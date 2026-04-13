import SwiftUI

struct ContentView: View {
    @EnvironmentObject var appState: AppState
    @State private var showEditProfile = false
    @State private var profileToEdit: HyperProfile?

    var body: some View {
        NavigationSplitView {
            VStack(spacing: 0) {
                // Profile selector
                profileSelector
                    .padding(.horizontal, 12)
                    .padding(.vertical, 8)

                Divider()

                // Sidebar items
                List(SidebarItem.allCases, id: \.self, selection: $appState.selectedItem) { item in
                    Label(item.rawValue, systemImage: item.icon)
                        .tag(item)
                }
                .listStyle(.sidebar)
            }
        } detail: {
            detailView
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
        .navigationSplitViewStyle(.balanced)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if appState.isLoading {
                    ProgressView()
                        .controlSize(.small)
                }

                Button {
                    Task { await appState.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
                .disabled(appState.activeProfile == nil)

                Button {
                    appState.showAddProfile = true
                } label: {
                    Label("Add Profile", systemImage: "plus")
                }
            }
        }
        .sheet(isPresented: $appState.showAddProfile) {
            AddProfileView()
                .environmentObject(appState)
        }
        .sheet(item: $profileToEdit) { profile in
            EditProfileView(profile: profile)
                .environmentObject(appState)
        }
        .alert("Error", isPresented: .init(
            get: { appState.errorMessage != nil },
            set: { if !$0 { appState.errorMessage = nil } }
        )) {
            Button("Retry") {
                Task { await appState.refresh() }
            }
            Button("Dismiss", role: .cancel) {}
        } message: {
            Text(appState.errorMessage ?? "")
        }
        .onAppear {
            if appState.activeProfile != nil {
                Task { await appState.refresh() }
            }
        }
    }

    // MARK: - Profile Selector

    private var profileSelector: some View {
        VStack(alignment: .leading, spacing: 4) {
            if appState.profiles.isEmpty {
                Button {
                    appState.showAddProfile = true
                } label: {
                    Label("Add Connection", systemImage: "plus.circle")
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .buttonStyle(.bordered)
            } else {
                Picker("Profile", selection: Binding(
                    get: { appState.activeProfile },
                    set: { newProfile in
                        appState.activeProfile = newProfile
                        Task { await appState.refresh() }
                    }
                )) {
                    ForEach(appState.profiles) { profile in
                        Label(profile.name, systemImage: profile.type.icon)
                            .tag(Optional(profile))
                            .contextMenu {
                                Button("Edit Profile...") {
                                    profileToEdit = profile
                                }
                                Button("Test Connection") {
                                    Task { await appState.testProfile(profile) }
                                }
                                Divider()
                                Button("Delete", role: .destructive) {
                                    appState.removeProfile(profile)
                                }
                            }
                    }
                }
                .labelsHidden()
                .pickerStyle(.menu)

                if let profile = appState.activeProfile {
                    HStack(spacing: 4) {
                        Image(systemName: profile.type.icon)
                            .foregroundStyle(profile.type.color)
                            .font(.caption2)
                        Text(profile.type.rawValue)
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                    }
                }
            }
        }
    }

    // MARK: - Detail

    @ViewBuilder
    private var detailView: some View {
        if appState.activeProfile == nil {
            VStack(spacing: 16) {
                Image(systemName: "server.rack")
                    .font(.system(size: 64))
                    .foregroundStyle(.tertiary)
                Text("No Connection")
                    .font(.title2)
                    .foregroundStyle(.secondary)
                Text("Add a hypervisor profile to get started.")
                    .foregroundStyle(.tertiary)
                Button("Add Profile") {
                    appState.showAddProfile = true
                }
                .buttonStyle(.borderedProminent)
            }
        } else {
            switch appState.selectedItem {
            case .dashboard:
                DashboardView()
            case .vms:
                VMListView()
            case .hosts:
                HostListView()
            case .storage:
                StorageView()
            case .networks:
                NetworkView()
            case .snapshots:
                PlaceholderView(title: "Snapshots", icon: "camera", message: "Snapshot management coming soon.")
            case .templates:
                PlaceholderView(title: "Templates", icon: "doc.on.doc", message: "Template management coming soon.")
            }
        }
    }
}

// MARK: - Placeholder

struct PlaceholderView: View {
    let title: String
    let icon: String
    let message: String

    var body: some View {
        VStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 48))
                .foregroundStyle(.tertiary)
            Text(title)
                .font(.title2)
                .foregroundStyle(.secondary)
            Text(message)
                .foregroundStyle(.tertiary)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
