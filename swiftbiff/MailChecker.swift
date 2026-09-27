import AppKit
import Foundation
import Observation
import os

private let logger = Logger(subsystem: "dk.thrysoee.swiftbiff", category: "checker")

@Observable @MainActor
final class MailChecker {
    enum Status {
        case signedOut
        case ok
        case failed
    }

    static let intervals = [1, 2, 5, 10, 15, 30]

    private(set) var status = Status.signedOut
    private(set) var unreadCount: Int?
    private(set) var threads: [UnreadThread] = []
    private(set) var lastCheck: Date?
    private(set) var email: String? {
        didSet { UserDefaults.standard.set(email, forKey: "email") }
    }

    var interval: Int {
        didSet {
            UserDefaults.standard.set(interval, forKey: "checkInterval")
            if status != .signedOut { startPolling(after: .seconds(interval * 60)) }
        }
    }

    var savedClientID: String { Keychain.string(for: .clientID) ?? "" }
    var savedClientSecret: String { Keychain.string(for: .clientSecret) ?? "" }

    private var accessToken: AccessToken?
    private var polling: Task<Void, Never>?
    private var isChecking = false
    private var isUserInitiated = false
    private var failedChecks = 0

    init() {
        let interval = UserDefaults.standard.integer(forKey: "checkInterval")
        self.interval = Self.intervals.contains(interval) ? interval : 5
        email = UserDefaults.standard.string(forKey: "email")
        if Keychain.string(for: .refreshToken) != nil {
            status = .ok
            startPolling()
        }
    }

    func check(userInitiated: Bool = false) async {
        // Check Now during a background check joins it instead of starting another.
        if userInitiated {
            isUserInitiated = true
        }
        guard !isChecking else { return }
        isChecking = true
        defer {
            isChecking = false
            isUserInitiated = false
        }
        guard let client = oauthClient(), let refreshToken = Keychain.string(for: .refreshToken) else {
            clearState()
            return
        }

        do {
            let mail: Mail
            do {
                mail = try await fetchMail(client: client, refreshToken: refreshToken)
            } catch GmailError.unauthorized {
                accessToken = nil
                mail = try await fetchMail(client: client, refreshToken: refreshToken)
            }
            guard isSignedIn(with: refreshToken) else { return }
            unreadCount = mail.unreadCount
            threads = mail.threads
            email = mail.email
            status = .ok
            failedChecks = 0
            lastCheck = .now
        } catch {
            guard !Task.isCancelled, isSignedIn(with: refreshToken) else { return }
            if error as? OAuthError == .invalidGrant {
                logger.notice("Refresh token was rejected, signing out")
                Keychain.delete(.refreshToken)
                clearState()
                return
            }
            logger.error("Check failed: \(error)")
            failedChecks += 1
            // A single background failure, e.g. right after wake before the network is up,
            // should not change the icon. Check Now always shows its result.
            if isUserInitiated || failedChecks >= 2 {
                status = .failed
                unreadCount = nil
                threads = []
            }
        }
    }

    func signIn(clientID: String, clientSecret: String) async throws {
        let client = OAuthClient(
            clientID: clientID.trimmingCharacters(in: .whitespacesAndNewlines),
            clientSecret: clientSecret.trimmingCharacters(in: .whitespacesAndNewlines)
        )
        try Keychain.set(client.clientID, for: .clientID)
        try Keychain.set(client.clientSecret, for: .clientSecret)

        let tokens = try await client.authorize()
        try Keychain.set(tokens.refreshToken, for: .refreshToken)
        accessToken = tokens.accessToken
        email = try? await GmailClient(accessToken: tokens.accessToken.value).emailAddress()
        status = .ok
        startPolling()
    }

    func signOut() {
        if let client = oauthClient(), let refreshToken = Keychain.string(for: .refreshToken) {
            Task { await client.revoke(refreshToken) }
        }
        Keychain.delete(.refreshToken)
        clearState()
    }

    func openInbox() {
        openGmail(fragment: "inbox")
    }

    func openThread(_ thread: UnreadThread) {
        openGmail(fragment: "inbox/\(thread.id)")
    }

    private func openGmail(fragment: String) {
        var components = URLComponents(string: "https://mail.google.com/mail/")!
        if let email {
            components.queryItems = [URLQueryItem(name: "authuser", value: email)]
        }
        components.fragment = fragment
        if let url = components.url {
            NSWorkspace.shared.open(url)
        }
    }

    private func startPolling(after delay: Duration = .zero) {
        polling?.cancel()
        polling = Task { [weak self] in
            try? await Task.sleep(for: delay)
            while !Task.isCancelled {
                await self?.check()
                guard let minutes = self?.interval else { return }
                try? await Task.sleep(for: .seconds(minutes * 60))
            }
        }
    }

    private struct Mail {
        let unreadCount: Int
        let threads: [UnreadThread]
        let email: String?
    }

    private func fetchMail(client: OAuthClient, refreshToken: String) async throws -> Mail {
        let gmail = GmailClient(accessToken: try await validAccessToken(client: client, refreshToken: refreshToken))
        async let count = gmail.unreadCount()
        async let threads = gmail.unreadThreads()
        var address = email
        if address == nil {
            address = try await gmail.emailAddress()
        }
        return Mail(unreadCount: try await count, threads: try await threads, email: address)
    }

    private func validAccessToken(client: OAuthClient, refreshToken: String) async throws -> String {
        if let accessToken, accessToken.expiresAt > .now.addingTimeInterval(60) {
            return accessToken.value
        }
        let token = try await client.refresh(refreshToken)
        accessToken = token
        return token.value
    }

    // A check that was running while the user signed out must not bring the old state back.
    private func isSignedIn(with refreshToken: String) -> Bool {
        Keychain.string(for: .refreshToken) == refreshToken
    }

    private func oauthClient() -> OAuthClient? {
        guard let id = Keychain.string(for: .clientID), let secret = Keychain.string(for: .clientSecret) else {
            return nil
        }
        return OAuthClient(clientID: id, clientSecret: secret)
    }

    private func clearState() {
        polling?.cancel()
        polling = nil
        accessToken = nil
        failedChecks = 0
        status = .signedOut
        unreadCount = nil
        threads = []
        lastCheck = nil
        email = nil
    }
}

func menuTitle(for thread: UnreadThread, maxLength: Int = 60) -> String {
    let subject = thread.subject.isEmpty ? String(localized: "(no subject)") : thread.subject
    let title = "\(thread.sender) - \(subject)"
    guard title.count > maxLength else { return title }
    return title.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
}

func moreRow(unreadCount: Int, shown: Int) -> String? {
    guard unreadCount > shown else { return nil }
    return String(localized: "…and \(unreadCount - shown) more")
}
