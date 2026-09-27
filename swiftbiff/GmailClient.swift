import Foundation
import os

struct UnreadThread: Identifiable, Equatable, Sendable {
    let id: String
    let sender: String
    let subject: String
}

enum GmailError: Error, Equatable {
    case unauthorized
    case http(Int)
}

private let logger = Logger(subsystem: "dk.thrysoee.swiftbiff", category: "gmail")

struct GmailClient: Sendable {
    let accessToken: String

    private static let baseURL = URL(string: "https://gmail.googleapis.com/gmail/v1/users/me")!

    func emailAddress() async throws -> String {
        let profile: Profile = try await get("profile")
        return profile.emailAddress
    }

    func unreadCount() async throws -> Int {
        let label: Label = try await get("labels/INBOX")
        return label.threadsUnread
    }

    func unreadThreadIDs(limit: Int) async throws -> [String] {
        let list: ThreadList = try await get("threads", query: [
            URLQueryItem(name: "labelIds", value: "INBOX"),
            URLQueryItem(name: "labelIds", value: "UNREAD"),
            URLQueryItem(name: "maxResults", value: String(limit)),
        ])
        return list.threads?.map(\.id) ?? []
    }

    func thread(id: String) async throws -> GmailThread {
        try await get("threads/\(id)", query: [
            URLQueryItem(name: "format", value: "metadata"),
            URLQueryItem(name: "metadataHeaders", value: "From"),
            URLQueryItem(name: "metadataHeaders", value: "Subject"),
        ])
    }

    func unreadThreads(limit: Int = 15) async throws -> [UnreadThread] {
        let ids = try await unreadThreadIDs(limit: limit)
        return try await withThrowingTaskGroup(of: (Int, UnreadThread?).self) { group in
            for (index, id) in ids.enumerated() {
                group.addTask { (index, try await thread(id: id).unreadThread) }
            }
            var threads = [UnreadThread?](repeating: nil, count: ids.count)
            for try await (index, thread) in group {
                threads[index] = thread
            }
            return threads.compactMap { $0 }
        }
    }

    private func get<Response: Decodable>(_ path: String, query: [URLQueryItem] = []) async throws -> Response {
        var request = URLRequest(url: Self.baseURL.appending(path: path).appending(queryItems: query))
        request.setValue("Bearer \(accessToken)", forHTTPHeaderField: "Authorization")

        let (data, response) = try await URLSession.shared.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        switch status {
        case 200..<300:
            return try JSONDecoder().decode(Response.self, from: data)
        case 401:
            throw GmailError.unauthorized
        default:
            logger.error("Gmail request failed with status \(status)")
            throw GmailError.http(status)
        }
    }
}

struct Profile: Decodable {
    let emailAddress: String
}

struct Label: Decodable {
    let threadsUnread: Int
}

struct ThreadList: Decodable {
    struct Entry: Decodable {
        let id: String
    }

    let threads: [Entry]?
}

struct GmailThread: Decodable {
    struct Message: Decodable {
        struct Payload: Decodable {
            let headers: [Header]?
        }

        struct Header: Decodable {
            let name: String
            let value: String
        }

        let labelIds: [String]?
        let payload: Payload

        func header(_ name: String) -> String? {
            payload.headers?.first { $0.name.lowercased() == name.lowercased() }?.value
        }
    }

    let id: String
    let messages: [Message]

    // Gmail lists the messages of a thread oldest first.
    var unreadThread: UnreadThread? {
        let unread = messages.last { $0.labelIds?.contains("UNREAD") == true }
        guard let message = unread ?? messages.last else { return nil }
        return UnreadThread(
            id: id,
            sender: senderName(fromHeader: message.header("From") ?? ""),
            subject: message.header("Subject") ?? ""
        )
    }
}

func senderName(fromHeader from: String) -> String {
    guard let open = from.lastIndex(of: "<") else {
        return from.trimmingCharacters(in: .whitespaces)
    }
    let name = from[..<open].trimmingCharacters(in: CharacterSet.whitespaces.union(["\""]))
    if !name.isEmpty {
        return name
    }
    return from[from.index(after: open)...].trimmingCharacters(in: CharacterSet.whitespaces.union([">"]))
}
