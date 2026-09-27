import SwiftUI

struct SettingsView: View {
    @Bindable var checker: MailChecker

    @State private var clientID = ""
    @State private var clientSecret = ""
    @State private var signInTask: Task<Void, Never>?
    @State private var errorMessage: String?

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
        LabeledContent("Account") {
            HStack {
                if checker.status != .signedOut {
                    Text(checker.email ?? "")
                        .textSelection(.enabled)
                    Button("Sign Out") { checker.signOut() }
                } else if signInTask != nil {
                    Text("Waiting for the browser…")
                    Button("Cancel") { signInTask?.cancel() }
                } else {
                    Text(errorMessage ?? "Not signed in")
                        .foregroundStyle(errorMessage == nil ? Color.secondary : Color.red)
                    Button("Sign In…", action: signIn)
                        .disabled(clientID.isEmpty || clientSecret.isEmpty)
                }
            }
        }
    }

    @ViewBuilder
    private var checkFields: some View {
        Picker("Check every", selection: $checker.interval) {
            ForEach(MailChecker.intervals, id: \.self) { minutes in
                Text("\(minutes) min").tag(minutes)
            }
        }
    }

    private func signIn() {
        errorMessage = nil
        signInTask = Task {
            do {
                try await checker.signIn(clientID: clientID, clientSecret: clientSecret)
            } catch {
                if !Task.isCancelled {
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
        "Access was not granted."
    case .timedOut:
        "Timed out waiting for the browser."
    case .invalidGrant, .http(400), .http(401):
        "Google rejected the sign-in. Check the client ID and secret."
    case .missingRefreshToken:
        "Google did not return a refresh token."
    default:
        error.localizedDescription
    }
}
