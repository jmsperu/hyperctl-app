import SwiftUI

@main
struct HyperCtlApp: App {
    @StateObject private var appState = AppState()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(appState)
                .frame(minWidth: 1000, minHeight: 600)
        }
        .windowStyle(.titleBar)
        .defaultSize(width: 1200, height: 750)
        .commands {
            CommandGroup(after: .newItem) {
                Button("New Profile...") {
                    appState.showAddProfile = true
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])

                Button("Refresh") {
                    Task { await appState.refresh() }
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }

        Settings {
            SettingsView()
                .environmentObject(appState)
        }

        WindowGroup("VM Console", for: String.self) { $vmID in
            if let vmID = vmID, let vm = appState.vms.first(where: { $0.id == vmID }) {
                VMConsoleView(vm: vm)
                    .environmentObject(appState)
            } else {
                Text("VM not found")
            }
        }
        .defaultSize(width: 900, height: 600)
    }
}
