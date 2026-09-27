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
            if unreadCount > checker.threads.count {
                Text("…and \(unreadCount - checker.threads.count) more")
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
            String(localized: "Check Now - last check: error")
        case (.ok, let lastCheck?):
            String(localized: "Check Now - last check \(lastCheck.formatted(date: .omitted, time: .shortened))")
        default:
            String(localized: "Check Now")
        }
    }
}

func menuTitle(for thread: UnreadThread, maxLength: Int = 60) -> String {
    let subject = thread.subject.isEmpty ? String(localized: "(no subject)") : thread.subject
    let title = "\(thread.sender) - \(subject)"
    guard title.count > maxLength else { return title }
    return title.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
}

struct MenuBarLabel: View {
    let checker: MailChecker

    var body: some View {
        Image(nsImage: image)
            .accessibilityLabel(count.map { String(localized: "\($0) unread") } ?? "SwiftBiff")
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
                Text(count, format: .number)
                    .font(.system(size: 13))
            }
        }
        .opacity(checker.status == .ok && checker.unreadCount != nil ? 1 : 0.4)

        let renderer = ImageRenderer(content: content)
        renderer.scale = NSScreen.main?.backingScaleFactor ?? 2
        let image = renderer.nsImage ?? NSImage()
        image.isTemplate = true
        return image
    }
}
