# SwiftBiff

SwiftBiff is a macOS menu bar app that shows the number of unread conversations in a Gmail inbox, lists their senders and subjects, and opens the inbox in the default browser. It asks Google for `gmail.metadata` only, so it can never read a message body.

## Code standards

- Code must be readable and simple. Prefer a plain function over a protocol, a struct over a class, and a `switch` over a clever abstraction. No layers or generics added "for later".
- Comments are sparse. Write one only when the code cannot say why something is done, for example a Google API quirk or a macOS workaround. Never restate what the code does. No doc comments on obvious members.
- Each file has one job, and types stay small. If a file passes about 200 lines, it is probably doing two jobs.
- Follow the Swift API Design Guidelines. Swift 6 language mode, strict concurrency, no warnings.
- No third-party dependencies.
- No force unwraps outside tests, except for URL literals that are known to be valid.
- Logging goes through `os.Logger` and never includes subjects, senders or email addresses.

## Commit rules

- Work on `main`.
- Each commit is one coherent change that builds and passes its tests on its own.
- Subject lines are concise, imperative and at most 50 characters. Add a body only when the reason for the change is not obvious from the diff.
- No "WIP", "fix typo" or "address review" commits in the final history.

## Decisions

| Area | Decision |
|---|---|
| Name | Display name `SwiftBiff`. Repo, Xcode project and target `swiftbiff`. Bundle ID `dk.thrysoee.swiftbiff`. |
| Platform | macOS 27 minimum. Swift 6. SwiftUI `MenuBarExtra` (menu style) and a `Settings` scene. |
| Google access | Scope `gmail.metadata`. Each user creates their own Google Cloud project and Desktop OAuth client. |
| OAuth | Own code, no SDK. Authorization code flow with PKCE and a loopback redirect to `127.0.0.1`. |
| Secrets | Client ID, client secret and refresh token in the login keychain, service `dk.thrysoee.swiftbiff`. Access token only in memory. |
| Count | `threadsUnread` of the `INBOX` label, which matches the Gmail web UI. |
| Polling | A fixed interval (1, 2, 5, 10, 15 or 30 minutes, default 5) plus Check Now. First check at launch. |
| Open Inbox | `NSWorkspace.shared.open` with `https://mail.google.com/mail/?authuser=<email>#inbox`. |
| Signing | Automatic signing with the Personal Team. The team ID lives in the gitignored `Config/Local.xcconfig`. |
| Sandbox | App Sandbox with `network.client` and `network.server` (the server entitlement is for the loopback listener). |
| License | MIT. |

Out of scope for now: notifications and sounds, several accounts, importing the client JSON file, checking on wake or network change, and a custom app icon.

## Architecture

`MailChecker` calls `OAuthClient` for an access token and `GmailClient` for data, then publishes plain values. The views read those values and call methods on `MailChecker`. The views never talk to `OAuthClient`, `GmailClient` or `Keychain` directly.

## Build and test

```sh
xcodebuild -project swiftbiff.xcodeproj -scheme swiftbiff -destination 'platform=macOS' -allowProvisioningUpdates test
```
