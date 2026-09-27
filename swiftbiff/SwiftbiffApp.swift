import SwiftUI

@main
struct SwiftbiffApp: App {
    var body: some Scene {
        MenuBarExtra {
            Button("Quit") {
                NSApp.terminate(nil)
            }
            .keyboardShortcut("q")
        } label: {
            Image(systemName: "envelope")
        }
        .menuBarExtraStyle(.menu)
    }
}
