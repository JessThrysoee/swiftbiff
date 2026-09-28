import ServiceManagement
import SwiftUI
import os

private let logger = Logger(subsystem: "dk.thrysoee.swiftbiff", category: "settings")

struct SettingsView: View {
    @Bindable var checker: MailChecker

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var signInTask: Task<Void, Never>?
    @State private var errorMessage: String?
    @State private var opensAtLogin = false

    var body: some View {
        Form {
            Section {
                clientFields
            }
            Section {
                checkFields
            }
        }
        .formStyle(.grouped)
        .scrollDisabled(true)
        .frame(width: 480)
        .fixedSize(horizontal: false, vertical: true)
        .onAppear {
            // Menu bar apps open Settings behind the frontmost app.
            NSApp.activate()
            clientID = checker.savedClientID
            clientSecret = checker.savedClientSecret
            // The user can also change this in System Settings, so read it every time.
            opensAtLogin = SMAppService.mainApp.status == .enabled
        }
    }

    @ViewBuilder
    private var clientFields: some View {
        // The client ID is over 70 characters, so the field goes under its label.
        VStack(alignment: .leading) {
            Text("Client ID")
            TextField("Client ID", text: $clientID, prompt: Text("Paste from Google Cloud"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .disabled(checker.status != .signedOut)
        }
        VStack(alignment: .leading) {
            Text("Client Secret")
            SecureField("Client Secret", text: $clientSecret, prompt: Text("Paste from Google Cloud"))
                .labelsHidden()
                .textFieldStyle(.roundedBorder)
                .disabled(checker.status != .signedOut)
        }
        LabeledContent {
            HStack {
                if checker.status != .signedOut {
                    Text(checker.email ?? String(localized: "Signed in", comment: "Account row while the email address is still loading"))
                        .textSelection(.enabled)
                    Button("Sign Out") { checker.signOut() }
                } else if signInTask != nil {
                    Text("Waiting for the browser…")
                    Button("Cancel") { signInTask?.cancel() }
                } else {
                    Text("Not signed in")
                        .foregroundStyle(.secondary)
                    Button("Sign In…", action: signIn)
                        .disabled(!canSignIn)
                }
            }
        } label: {
            Text("Account", comment: "Settings label in front of the signed-in email address")
        }
        if let signedOutMessage {
            Text(signedOutMessage)
                .foregroundStyle(.red)
        }
    }

    private var canSignIn: Bool {
        let fields = [clientID, clientSecret].map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        return fields.allSatisfy { !$0.isEmpty }
    }

    private var signedOutMessage: String? {
        if let errorMessage { return errorMessage }
        if checker.sessionExpired { return String(localized: "Google signed you out. Sign in again.") }
        return nil
    }

    @ViewBuilder
    private var checkFields: some View {
        Picker(selection: $checker.interval) {
            ForEach(MailChecker.intervals, id: \.self) { minutes in
                Text(Duration.seconds(minutes * 60), format: .units(allowed: [.minutes], width: .abbreviated))
                    .tag(minutes)
            }
        } label: {
            Text("Check every", comment: "Settings label in front of the interval picker")
        }
        Toggle("Open at login", isOn: Binding(get: { opensAtLogin }, set: setOpensAtLogin))
    }

    private func setOpensAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            logger.error("Changing open at login failed: \(error)")
        }
        opensAtLogin = SMAppService.mainApp.status == .enabled
    }

    private func signIn() {
        errorMessage = nil
        signInTask = Task {
            do {
                try await checker.signIn(clientID: clientID, clientSecret: clientSecret)
            } catch {
                if !Task.isCancelled {
                    logger.error("Sign-in failed: \(error)")
                    errorMessage = signInErrorMessage(for: error)
                }
            }
            signInTask = nil
        }
    }
}

private func signInErrorMessage(for error: any Error) -> String {
    switch error as? OAuthError {
    case .denied:
        String(localized: "Access was not granted.")
    case .timedOut:
        String(localized: "Timed out waiting for the browser.")
    case .invalidGrant, .http(400), .http(401):
        String(localized: "Google rejected the sign-in. Check the client ID and secret.")
    case .missingRefreshToken:
        String(localized: "Google did not return a refresh token.")
    default:
        String(localized: "Sign-in failed.")
    }
}
