import SwiftUI

struct MenuContent: View {
    let checker: MailChecker

    var body: some View {
        Button("Open Inbox") {
            checker.openInbox()
        }
        .disabled(checker.status == .signedOut)

        Button(checkNowTitle) {
            Task { await checker.check(userInitiated: true) }
        }
        .disabled(checker.status == .signedOut)

        if checker.status == .signedOut {
            Divider()
            SettingsLink {
                Text("Sign In…")
            }
        } else if let unreadCount = checker.unreadCount {
            Divider()
            if checker.threads.isEmpty {
                Text("No unread mail")
            }
            ForEach(checker.threads) { thread in
                Button(menuTitle(for: thread)) { checker.openThread(thread) }
            }
            if let more = moreRow(unreadCount: unreadCount, shown: checker.threads.count) {
                Text(more)
            }
        }

        Divider()
        SettingsLink {
            Text("Settings…")
        }
        .keyboardShortcut(",")
        Button("Quit") {
            NSApp.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private var checkNowTitle: String {
        switch (checker.status, checker.lastCheck) {
        case (.failed, _):
            "Check Now - last check: error"
        case (.ok, let lastCheck?):
            "Check Now - last check \(lastCheck.formatted(date: .omitted, time: .shortened))"
        default:
            "Check Now"
        }
    }
}

struct MenuBarLabel: View {
    let checker: MailChecker

    var body: some View {
        Image(nsImage: image)
            .accessibilityLabel(count.map { "\($0) unread" } ?? "SwiftBiff")
    }

    private var count: Int? {
        guard let unreadCount = checker.unreadCount, unreadCount > 0 else { return nil }
        return unreadCount
    }

    // MenuBarExtra ignores opacity, so the label is drawn into a template image, which keeps its alpha.
    private var image: NSImage {
        let content = HStack(spacing: 3) {
            Image(systemName: count == nil ? "envelope" : "envelope.fill")
                .font(.system(size: 15, weight: .medium))
            if let count {
                Text("\(count)")
                    .font(.system(size: 13))
            }
        }
        .opacity(checker.status == .ok ? 1 : 0.4)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
