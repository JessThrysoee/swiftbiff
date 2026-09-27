import Foundation
import Network

func receiveCallback(
    state: String,
    timeout: Duration,
    onReady: @Sendable (_ redirectURI: String) async -> Void
) async throws -> (code: String, redirectURI: String) {
    let listener = try NetworkListener(
        using: .parameters { TCP() }.localEndpoint(.hostPort(host: "127.0.0.1", port: .any))
    )
    let (ports, portContinuation) = AsyncStream.makeStream(of: UInt16.self)
    listener.onStateUpdate { listener, listenerState in
        switch listenerState {
        case .ready:
            if let port = listener.port { portContinuation.yield(port.rawValue) }
            portContinuation.finish()
        case .failed, .cancelled:
            portContinuation.finish()
        default:
            break
        }
    }

    let (callbacks, callbackContinuation) = AsyncStream.makeStream(of: Result<String, OAuthError>.self)
    let server = Task {
        try await listener.run { connection in
            let requestLine = try await readRequestLine(from: connection)
            guard requestLine.hasPrefix("GET /?") else {
                try? await connection.send(Data(httpResponse(status: "404 Not Found", message: "").utf8), endOfStream: true)
                return
            }
            let result = Result { try parseCallback(requestLine, expectedState: state) }
                .mapError { $0 as? OAuthError ?? .badCallback }
            let message = switch result {
            case .success: String(localized: "Signed in to SwiftBiff. You can close this tab.")
            case .failure: String(localized: "SwiftBiff sign-in failed. You can close this tab.")
            }
            try? await connection.send(Data(httpResponse(status: "200 OK", message: message).utf8), endOfStream: true)
            // A stale consent tab or another local process must not be able to end the sign-in.
            if case .failure(.stateMismatch) = result { return }
            callbackContinuation.yield(result)
        }
    }
    defer { server.cancel() }

    guard let port = await ports.first(where: { _ in true }) else { throw OAuthError.listenerFailed }
    let redirectURI = "http://127.0.0.1:\(port)"
    await onReady(redirectURI)

    let code = try await withThrowingTaskGroup(of: Result<String, OAuthError>?.self) { group in
        group.addTask { await callbacks.first { _ in true } }
        group.addTask {
            try await Task.sleep(for: timeout)
            return .failure(.timedOut)
        }
        defer { group.cancelAll() }
        guard let result = try await group.next() ?? nil else { throw OAuthError.listenerFailed }
        return try result.get()
    }
    return (code, redirectURI)
}

private func readRequestLine(from connection: NetworkConnection<TCP>) async throws -> String {
    var request = ""
    while request.firstRange(of: "\r\n") == nil && request.utf8.count < 16_384 {
        let message = try await connection.receive(atMost: 4096)
        request += String(decoding: message.content, as: UTF8.self)
        if message.metadata.endOfStream { break }
    }
    guard let end = request.firstRange(of: "\r\n") else { return request }
    return String(request[..<end.lowerBound])
}

private func httpResponse(status: String, message: String) -> String {
    let body = "<!doctype html><title>SwiftBiff</title><p>\(message)</p>"
    return "HTTP/1.1 \(status)\r\nContent-Type: text/html; charset=utf-8\r\n"
        + "Content-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
}

func parseCallback(_ requestLine: String, expectedState: String) throws -> String {
    let parts = requestLine.split(separator: " ")
    guard parts.count == 3, parts[0] == "GET", let components = URLComponents(string: String(parts[1])) else {
        throw OAuthError.badCallback
    }
    let items = components.queryItems ?? []
    func value(_ name: String) -> String? { items.first { $0.name == name }?.value }

    guard value("state") == expectedState else { throw OAuthError.stateMismatch }
    if let error = value("error") { throw OAuthError.denied(error) }
    guard let code = value("code") else { throw OAuthError.badCallback }
    return code
}
