import SwiftUI

@main
struct SwiftbiffApp: App {
    @State private var checker = MailChecker()

    var body: some Scene {
        MenuBarExtra {
            MenuContent(checker: checker)
        } label: {
            MenuBarLabel(checker: checker)
        }
        .menuBarExtraStyle(.menu)

        Settings {
            SettingsView(checker: checker)
        }
        .windowResizability(.contentSize)
    }
}
