import Foundation
import Testing
@testable import SwiftBiff

struct GmailClientTests {
    private func decode<T: Decodable>(_ json: String) throws -> T {
        try JSONDecoder().decode(T.self, from: Data(json.utf8))
    }

    @Test func decodesInboxLabel() throws {
        let label: Label = try decode("""
            {
              "id": "INBOX",
              "name": "INBOX",
              "type": "system",
              "messagesTotal": 1834,
              "messagesUnread": 4,
              "threadsTotal": 1502,
              "threadsUnread": 3
            }
            """)
        #expect(label.threadsUnread == 3)
    }

    @Test func decodesThreadList() throws {
        let list: ThreadList = try decode("""
            {
              "threads": [
                {"id": "18f1", "snippet": "", "historyId": "991"},
                {"id": "18e7", "snippet": "", "historyId": "985"}
              ],
              "resultSizeEstimate": 2
            }
            """)
        #expect(list.threads?.map(\.id) == ["18f1", "18e7"])
    }

    @Test func decodesEmptyThreadList() throws {
        let list: ThreadList = try decode(#"{"resultSizeEstimate": 0}"#)
        #expect(list.threads == nil)
    }

    @Test func decodesThread() throws {
        let thread: GmailThread = try decode("""
            {
              "id": "18f1",
              "historyId": "991",
              "messages": [
                {
                  "id": "18f1",
                  "threadId": "18f1",
                  "labelIds": ["INBOX", "UNREAD", "CATEGORY_PERSONAL"],
                  "internalDate": "1790000000000",
                  "payload": {
                    "headers": [
                      {"name": "From", "value": "\\"Jane Doe\\" <jane@example.com>"},
                      {"name": "Subject", "value": "Q3 budget review"}
                    ]
                  }
                }
              ]
            }
            """)
        #expect(thread.unreadThread == UnreadThread(id: "18f1", sender: "Jane Doe", subject: "Q3 budget review"))
    }

    @Test func picksNewestUnreadMessage() {
        let thread = GmailThread(id: "18f1", messages: [
            message(subject: "First", labels: ["INBOX", "UNREAD"]),
            message(subject: "Second", labels: ["INBOX", "UNREAD"]),
            message(subject: "My reply", labels: ["SENT"]),
        ])
        #expect(thread.unreadThread?.subject == "Second")
    }

    @Test func fallsBackToNewestMessage() {
        let thread = GmailThread(id: "18f1", messages: [
            message(subject: "First", labels: ["INBOX"]),
            message(subject: "Second", labels: nil),
        ])
        #expect(thread.unreadThread?.subject == "Second")
    }

    @Test func parsesSenderName() {
        #expect(senderName(fromHeader: #""Jane Doe" <jane@example.com>"#) == "Jane Doe")
        #expect(senderName(fromHeader: "Jane Doe <jane@example.com>") == "Jane Doe")
        #expect(senderName(fromHeader: "jane@example.com") == "jane@example.com")
        #expect(senderName(fromHeader: "<jane@example.com>") == "jane@example.com")
    }

    private func message(subject: String, labels: [String]?) -> GmailThread.Message {
        GmailThread.Message(
            labelIds: labels,
            payload: .init(headers: [.init(name: "From", value: "a@example.com"), .init(name: "Subject", value: subject)])
        )
    }
}
