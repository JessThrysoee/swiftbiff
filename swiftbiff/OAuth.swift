import AppKit
import CryptoKit
import Foundation
import os

struct AccessToken: Sendable {
    let value: String
    let expiresAt: Date
}

struct Tokens: Sendable {
    let accessToken: AccessToken
    let refreshToken: String
}

enum OAuthError: Error, Equatable {
    case invalidGrant
    case denied(String)
    case stateMismatch
    case badCallback
    case listenerFailed
    case timedOut
    case missingRefreshToken
    case http(Int)
}

private let logger = Logger(subsystem: "dk.thrysoee.swiftbiff", category: "oauth")

struct OAuthClient: Sendable {
    let clientID: String
    let clientSecret: String

    func authorize() async throws -> Tokens {
        let verifier = randomToken()
        let state = randomToken()
        let (code, redirectURI) = try await receiveCallback(state: state, timeout: .seconds(5 * 60)) { redirectURI in
            let url = consentURL(
                clientID: clientID,
                redirectURI: redirectURI,
                challenge: codeChallenge(for: verifier),
                state: state
            )
            await MainActor.run { _ = NSWorkspace.shared.open(url) }
        }

        let response = try await requestToken([
            "grant_type": "authorization_code",
            "code": code,
            "code_verifier": verifier,
            "client_id": clientID,
            "client_secret": clientSecret,
            "redirect_uri": redirectURI,
        ])
        guard let refreshToken = response.refreshToken else { throw OAuthError.missingRefreshToken }
        return Tokens(accessToken: response.accessToken, refreshToken: refreshToken)
    }

    func refresh(_ refreshToken: String) async throws -> AccessToken {
        try await requestToken([
            "grant_type": "refresh_token",
            "refresh_token": refreshToken,
            "client_id": clientID,
            "client_secret": clientSecret,
        ]).accessToken
    }

    func revoke(_ token: String) async {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/revoke")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(["token": token])
        _ = try? await URLSession.shared.data(for: request)
    }

    private func requestToken(_ parameters: [String: String]) async throws -> TokenResponse {
        var request = URLRequest(url: URL(string: "https://oauth2.googleapis.com/token")!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")
        request.httpBody = formEncoded(parameters)

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        guard (200..<300).contains(status) else {
            logger.error("Token request failed with status \(status)")
            throw tokenError(status: status, body: data)
        }
        return try JSONDecoder().decode(TokenResponse.self, from: data)
    }
}

private struct TokenResponse: Decodable {
    let accessToken: AccessToken
    let refreshToken: String?

    enum CodingKeys: String, CodingKey {
        case accessToken = "access_token"
        case expiresIn = "expires_in"
        case refreshToken = "refresh_token"
    }

    init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        let expiresIn = try container.decode(Int.self, forKey: .expiresIn)
        accessToken = AccessToken(
            value: try container.decode(String.self, forKey: .accessToken),
            expiresAt: Date.now.addingTimeInterval(TimeInterval(expiresIn))
        )
        refreshToken = try container.decodeIfPresent(String.self, forKey: .refreshToken)
    }
}

func tokenError(status: Int, body: Data) -> OAuthError {
    struct ErrorResponse: Decodable { let error: String }
    let response = try? JSONDecoder().decode(ErrorResponse.self, from: body)
    return response?.error == "invalid_grant" ? .invalidGrant : .http(status)
}

func randomToken() -> String {
    base64URLEncoded(Data((0..<48).map { _ in UInt8.random(in: .min ... .max) }))
}

func codeChallenge(for verifier: String) -> String {
    base64URLEncoded(Data(SHA256.hash(data: Data(verifier.utf8))))
}

func consentURL(clientID: String, redirectURI: String, challenge: String, state: String) -> URL {
    var components = URLComponents(string: "https://accounts.google.com/o/oauth2/v2/auth")!
    components.queryItems = [
        URLQueryItem(name: "client_id", value: clientID),
        URLQueryItem(name: "redirect_uri", value: redirectURI),
        URLQueryItem(name: "response_type", value: "code"),
        URLQueryItem(name: "scope", value: "https://www.googleapis.com/auth/gmail.metadata"),
        URLQueryItem(name: "code_challenge", value: challenge),
        URLQueryItem(name: "code_challenge_method", value: "S256"),
        URLQueryItem(name: "state", value: state),
        URLQueryItem(name: "access_type", value: "offline"),
        // Without this, Google omits the refresh token when the user has signed in before.
        URLQueryItem(name: "prompt", value: "consent"),
    ]
    return components.url!
}

private func base64URLEncoded(_ data: Data) -> String {
    data.base64EncodedString()
        .replacingOccurrences(of: "+", with: "-")
        .replacingOccurrences(of: "/", with: "_")
        .replacingOccurrences(of: "=", with: "")
}

private func formEncoded(_ parameters: [String: String]) -> Data {
    let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~")
    func encode(_ string: String) -> String {
        string.addingPercentEncoding(withAllowedCharacters: unreserved) ?? string
    }
    let body = parameters.map { "\(encode($0.key))=\(encode($0.value))" }.joined(separator: "&")
    return Data(body.utf8)
}
