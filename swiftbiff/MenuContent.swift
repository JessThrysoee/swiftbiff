import SwiftUI

struct MenuContent: View {
    let checker: MailChecker
    @Environment(\.openSettings) private var openSettings

    var body: some View {
        Button("Open Inbox") {
            checker.openInbox()
        }
        .disabled(checker.status == .signedOut)

        Button("Check Now") {
            Task { await checker.check(userInitiated: true) }
        }
        .disabled(checker.status == .signedOut)
        if let lastCheckRow {
            Text(lastCheckRow)
        }

        if checker.status == .signedOut {
            Divider()
            Button("Sign In…", action: showSettings)
        } else if let unreadCount = checker.unreadCount {
            Divider()
            if checker.threads.isEmpty {
                Text("No unread mail")
            }
            ForEach(checker.threads) { thread in
                Button(menuTitle(for: thread)) { checker.openThread(thread) }
            }
            if unreadCount > checker.threads.count {
                Text("…and \(unreadCount - checker.threads.count) more", comment: "Menu row after the listed conversations, N not shown")
            }
        }

        Divider()
        Button("Settings…", action: showSettings)
            .keyboardShortcut(",")
        Button("Quit SwiftBiff") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    // Picking a menu bar item does not activate the app, so the window would open behind the frontmost app.
    private func showSettings() {
        openSettings()
        NSApp.activate()
        Task { @MainActor in
            NSApp.windows.first { $0.styleMask.contains(.titled) }?.orderFrontRegardless()
        }
    }

    private var lastCheckRow: String? {
        let time = checker.lastCheck?.formatted(date: .omitted, time: .shortened)
        return switch (checker.status, time) {
        case (.ok, let time?):
            String(localized: "Last checked \(time)")
        case (.failed, let time?):
            String(localized: "Last check failed. Showing mail from \(time)")
        case (.failed, nil):
            String(localized: "Last check failed")
        default:
            nil
        }
    }
}

func menuTitle(for thread: UnreadThread, maxLength: Int = 60) -> String {
    let subject = thread.subject.isEmpty
        ? String(localized: "(no subject)", comment: "Menu row subject when the mail has none")
        : thread.subject
    let title = String(localized: "\(thread.sender) - \(subject)", comment: "A menu row: the sender, then the subject")
    guard title.count > maxLength else { return title }
    return title.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
}

struct MenuBarLabel: View {
    let checker: MailChecker

    var body: some View {
        Image(nsImage: image)
            .accessibilityLabel(accessibilityLabel)
    }

    private var count: Int? {
        guard let unreadCount = checker.unreadCount, unreadCount > 0 else { return nil }
        return unreadCount
    }

    private var symbol: String {
        if checker.status == .signedOut { return "envelope.badge.person.crop" }
        return count == nil ? "envelope" : "envelope.fill"
    }

    // Dimmed means the data is stale or missing. Signed out has no data to be stale.
    private var isDimmed: Bool {
        checker.status == .failed || (checker.status == .ok && checker.unreadCount == nil)
    }

    private var accessibilityLabel: String {
        switch (checker.status, checker.unreadCount) {
        case (.signedOut, _):
            String(localized: "SwiftBiff, signed out")
        case (.ok, nil):
            String(localized: "SwiftBiff, checking")
        case (.ok, 0):
            String(localized: "No unread mail")
        case (.ok, let count?):
            String(localized: "\(count) unread", comment: "Menu bar accessibility label, N unread conversations")
        case (.failed, nil):
            String(localized: "SwiftBiff, last check failed")
        case (.failed, let count?):
            String(
                localized: "\(count) unread, last check failed",
                comment: "Menu bar accessibility label, N unread conversations and the last check failed"
            )
        }
    }

    // MenuBarExtra ignores opacity, so the label is drawn into a template image, which keeps its alpha.
    private var image: NSImage {
        let content = HStack(spacing: 3) {
            Image(systemName: symbol)
                .font(.system(size: 15, weight: .medium))
            if let count {
                Text(count, format: .number)
                    .font(.system(size: 13))
            }
        }
        .opacity(isDimmed ? 0.4 : 1)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
