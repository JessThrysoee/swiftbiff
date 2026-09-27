import Testing
@testable import SwiftBiff

struct MenuContentTests {
    @Test func formatsRow() {
        let thread = UnreadThread(id: "t", sender: "Jane Doe", subject: "Re: Q3 budget review")
        #expect(menuTitle(for: thread) == "Jane Doe - Re: Q3 budget review")
    }

    @Test func truncatesLongRow() {
        let thread = UnreadThread(id: "t", sender: "Jane Doe", subject: String(repeating: "word ", count: 20))
        #expect(menuTitle(for: thread) == "Jane Doe - " + String(repeating: "word ", count: 9) + "wor…")
    }

    @Test func keepsRowAtExactLimit() {
        let thread = UnreadThread(id: "t", sender: "A", subject: String(repeating: "x", count: 56))
        #expect(menuTitle(for: thread).count == 60)
        #expect(!menuTitle(for: thread).hasSuffix("…"))
    }

    @Test func showsPlaceholderForEmptySubject() {
        #expect(menuTitle(for: UnreadThread(id: "t", sender: "Jane Doe", subject: "")) == "Jane Doe - (no subject)")
    }
}
