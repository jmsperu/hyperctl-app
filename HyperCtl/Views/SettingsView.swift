import SwiftUI

struct SettingsView: View {
    @EnvironmentObject var appState: AppState
    @AppStorage("hyperctl.autoRefreshInterval") private var autoRefreshInterval: Int = 30
    @AppStorage("hyperctl.defaultProfileID") private var defaultProfileID: String = ""

    var body: some View {
        Form {
            Section("Refresh") {
                Picker("Auto-refresh interval", selection: $autoRefreshInterval) {
                    Text("Disabled").tag(0)
                    Text("15 seconds").tag(15)
                    Text("30 seconds").tag(30)
                    Text("1 minute").tag(60)
                    Text("5 minutes").tag(300)
                }
            }

            Section("Default Profile") {
                Picker("Default profile on launch", selection: $defaultProfileID) {
                    Text("None").tag("")
                    ForEach(appState.profiles) { profile in
                        Label(profile.name, systemImage: profile.type.icon)
                            .tag(profile.id.uuidString)
                    }
                }
            }

            Section("Profiles") {
                if appState.profiles.isEmpty {
                    Text("No profiles configured.")
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(appState.profiles) { profile in
                        HStack {
                            Image(systemName: profile.type.icon)
                                .foregroundStyle(profile.type.color)
                            VStack(alignment: .leading) {
                                Text(profile.name)
                                    .font(.body)
                                Text(profile.url)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            Button(role: .destructive) {
                                appState.removeProfile(profile)
                            } label: {
                                Image(systemName: "trash")
                            }
                            .buttonStyle(.borderless)
                        }
                    }
                }
            }
        }
        .formStyle(.grouped)
        .frame(width: 450, height: 350)
        .navigationTitle("Settings")
    }
}
