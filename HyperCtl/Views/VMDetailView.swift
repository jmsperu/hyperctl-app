import SwiftUI

struct VMDetailView: View {
    @EnvironmentObject var appState: AppState
    let vm: VirtualMachine
    @Environment(\.dismiss) private var dismiss
    @State private var showConsole = false
    @State private var showMigrate = false
    @State private var showResize = false
    @State private var showDeployVM = false
    @State private var showSnapshot = false
    @State private var showAttachVolume = false
    @State private var showAddNIC = false
    @State private var showConfirmDestroy = false
    @State private var actionResult: String?

    // Data loaded on appear
    @State private var vmVolumes: [[String: Any]] = []
    @State private var vmSnapshots: [[String: Any]] = []
    @State private var hosts: [[String: Any]] = []
    @State private var serviceOfferings: [[String: Any]] = []
    @State private var networks: [[String: Any]] = []
    @State private var isLoadingDetails = false

    var body: some View {
        VStack(spacing: 0) {
            // Header with close button
            HStack {
                headerSection
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .padding(.trailing)
            }

            Divider()

            if isLoadingDetails {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading VM details...")
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            }

            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    // Info cards
                    LazyVGrid(columns: [
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                        GridItem(.flexible(), spacing: 12),
                    ], spacing: 12) {
                        infoCard("Status", icon: vm.state.icon, color: vm.state.color) {
                            HStack(spacing: 6) {
                                Circle().fill(vm.state.color).frame(width: 10, height: 10)
                                Text(vm.state.rawValue).font(.headline).foregroundStyle(vm.state.color)
                            }
                        }
                        infoCard("CPU", icon: "cpu", color: .blue) {
                            Text("\(vm.cpus) vCPUs").font(.headline)
                        }
                        infoCard("Memory", icon: "memorychip", color: .purple) {
                            Text(formatMemory(vm.memoryMB)).font(.headline)
                        }
                        infoCard("IP Address", icon: "network", color: .green) {
                            HStack {
                                Text(vm.ipAddress.isEmpty ? "None" : vm.ipAddress).font(.headline.monospaced())
                                if !vm.ipAddress.isEmpty {
                                    copyButton(vm.ipAddress)
                                }
                            }
                        }
                        infoCard("Host", icon: "server.rack", color: .orange) {
                            Text(vm.hostName.isEmpty ? "Unassigned" : vm.hostName).font(.callout)
                        }
                        infoCard("Zone", icon: "globe", color: .teal) {
                            Text(vm.zone.isEmpty ? "-" : vm.zone).font(.callout)
                        }
                    }

                    // Template & ID
                    GroupBox("Details") {
                        LabeledContent("Template", value: vm.template.isEmpty ? "N/A" : vm.template)
                        LabeledContent("VM ID") {
                            HStack {
                                Text(vm.id).font(.caption.monospaced()).lineLimit(1)
                                copyButton(vm.id)
                            }
                        }
                        if !vm.created.isEmpty {
                            LabeledContent("Created", value: vm.created)
                        }
                    }

                    // Volumes
                    GroupBox {
                        HStack {
                            Label("Volumes", systemImage: "externaldrive")
                                .font(.headline)
                            Spacer()
                            Button("Attach Volume") { showAttachVolume = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        if vmVolumes.isEmpty {
                            Text("No volumes loaded").foregroundStyle(.secondary).font(.caption)
                        } else {
                            ForEach(Array(vmVolumes.enumerated()), id: \.offset) { _, vol in
                                HStack {
                                    Image(systemName: vol["type"] as? String == "ROOT" ? "internaldrive" : "externaldrive")
                                        .foregroundStyle(vol["type"] as? String == "ROOT" ? .blue : .orange)
                                    VStack(alignment: .leading) {
                                        Text(vol["name"] as? String ?? "Unknown").font(.callout.bold())
                                        Text("\(vol["type"] as? String ?? "") • \(formatBytesI64(vol["size"] as? Int64 ?? 0)) • \(vol["state"] as? String ?? "")")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    if vol["type"] as? String != "ROOT" {
                                        Button("Detach") {
                                            Task { await detachVolume(id: vol["id"] as? String ?? "") }
                                        }
                                        .buttonStyle(.bordered)
                                        .controlSize(.mini)
                                        .tint(.orange)
                                    }
                                }
                                .padding(.vertical, 2)
                                if vol["id"] as? String != vmVolumes.last?["id"] as? String {
                                    Divider()
                                }
                            }
                        }
                    }

                    // Snapshots
                    GroupBox {
                        HStack {
                            Label("Snapshots", systemImage: "camera")
                                .font(.headline)
                            Spacer()
                            Button("Create Snapshot") { showSnapshot = true }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                        }

                        if vmSnapshots.isEmpty {
                            Text("No snapshots").foregroundStyle(.secondary).font(.caption)
                        } else {
                            ForEach(Array(vmSnapshots.enumerated()), id: \.offset) { _, snap in
                                HStack {
                                    Image(systemName: "camera.fill")
                                        .foregroundStyle(.purple)
                                    VStack(alignment: .leading) {
                                        Text(snap["displayname"] as? String ?? snap["name"] as? String ?? "Snapshot")
                                            .font(.callout.bold())
                                        Text(snap["created"] as? String ?? "")
                                            .font(.caption).foregroundStyle(.secondary)
                                    }
                                    Spacer()
                                    Button("Revert") {
                                        Task { await revertSnapshot(id: snap["id"] as? String ?? "") }
                                    }
                                    .buttonStyle(.bordered).controlSize(.mini).tint(.blue)
                                    Button("Delete") {
                                        Task { await deleteSnapshot(id: snap["id"] as? String ?? "") }
                                    }
                                    .buttonStyle(.bordered).controlSize(.mini).tint(.red)
                                }
                                .padding(.vertical, 2)
                            }
                        }
                    }

                    // Advanced actions
                    GroupBox("Advanced") {
                        HStack(spacing: 12) {
                            Button { showResize = true } label: {
                                Label("Resize", systemImage: "arrow.up.left.and.arrow.down.right")
                            }
                            .buttonStyle(.bordered)

                            Button { showMigrate = true } label: {
                                Label("Migrate", systemImage: "arrow.triangle.swap")
                            }
                            .buttonStyle(.bordered)
                            .disabled(vm.state != .running)

                            Button { showAddNIC = true } label: {
                                Label("Add NIC", systemImage: "network.badge.shield.half.filled")
                            }
                            .buttonStyle(.bordered)

                            Spacer()

                            Button { showConfirmDestroy = true } label: {
                                Label("Destroy VM", systemImage: "trash")
                            }
                            .buttonStyle(.bordered)
                            .tint(.red)
                        }
                    }

                    // Action result
                    if let result = actionResult {
                        HStack {
                            Image(systemName: result.contains("Error") || result.contains("Failed") ? "xmark.circle.fill" : "checkmark.circle.fill")
                                .foregroundStyle(result.contains("Error") || result.contains("Failed") ? .red : .green)
                            Text(result)
                                .font(.callout)
                            Spacer()
                            Button("Dismiss") { actionResult = nil }
                                .buttonStyle(.borderless)
                        }
                        .padding(8)
                        .background(Color.accentColor.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
                    }
                }
                .padding()
            }
        }
        .frame(minWidth: 750, minHeight: 600)
        .onAppear { loadDetails() }
        .sheet(isPresented: $showConsole) {
            VMConsoleView(vm: vm).environmentObject(appState).frame(minWidth: 800, minHeight: 500)
        }
        .sheet(isPresented: $showResize) { resizeSheet }
        .sheet(isPresented: $showMigrate) { migrateSheet }
        .sheet(isPresented: $showSnapshot) { snapshotSheet }
        .alert("Destroy VM?", isPresented: $showConfirmDestroy) {
            Button("Cancel", role: .cancel) {}
            Button("Destroy", role: .destructive) {
                Task { await destroyVM() }
            }
            Button("Destroy & Expunge", role: .destructive) {
                Task { await destroyVM(expunge: true) }
            }
        } message: {
            Text("Are you sure you want to destroy \(vm.name)? This cannot be undone.")
        }
    }

    // MARK: - Header

    private var headerSection: some View {
        HStack(spacing: 12) {
            ZStack {
                RoundedRectangle(cornerRadius: 10).fill(vm.state.color.opacity(0.15)).frame(width: 48, height: 48)
                Image(systemName: "desktopcomputer").font(.title2).foregroundStyle(vm.state.color)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(vm.name).font(.title2.bold())
                HStack(spacing: 6) {
                    Image(systemName: vm.state.icon).foregroundStyle(vm.state.color)
                    Text(vm.state.rawValue).foregroundStyle(vm.state.color)
                    if !vm.ipAddress.isEmpty {
                        Text("•").foregroundStyle(.secondary)
                        Text(vm.ipAddress).font(.callout.monospaced()).foregroundStyle(.secondary)
                    }
                }
                .font(.callout)
            }

            Spacer()

            // Quick actions
            Button { Task { await appState.vmAction("start", vm: vm) } } label: {
                Image(systemName: "play.fill")
            }
            .disabled(vm.state == .running).buttonStyle(.bordered).tint(.green)

            Button { Task { await appState.vmAction("stop", vm: vm) } } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(vm.state == .stopped).buttonStyle(.bordered).tint(.red)

            Button { Task { await appState.vmAction("reboot", vm: vm) } } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(vm.state != .running).buttonStyle(.bordered).tint(.orange)

            Button { showConsole = true } label: {
                Label("Console", systemImage: "terminal")
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
    }

    // MARK: - Sheets

    @State private var selectedOffering = ""
    @State private var selectedHost = ""
    @State private var snapshotName = ""
    @State private var selectedNetwork = ""

    private var resizeSheet: some View {
        VStack(spacing: 16) {
            Text("Resize VM").font(.title2.bold())
            Text("VM must be stopped to change service offering").font(.caption).foregroundStyle(.secondary)
            Picker("Service Offering", selection: $selectedOffering) {
                Text("Select...").tag("")
                ForEach(Array(serviceOfferings.enumerated()), id: \.offset) { _, o in
                    let name = o["name"] as? String ?? ""
                    let cpus = o["cpunumber"] as? Int ?? 0
                    let mem = o["memory"] as? Int ?? 0
                    Text("\(name) (\(cpus) CPU, \(mem) MB)")
                        .tag(o["id"] as? String ?? "")
                }
            }
            .frame(width: 400)
            HStack {
                Button("Cancel") { showResize = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Apply") {
                    Task { await resizeVM() }
                    showResize = false
                }
                .buttonStyle(.borderedProminent).disabled(selectedOffering.isEmpty)
            }
        }
        .padding().frame(width: 500)
        .onAppear { loadOfferings() }
    }

    private var migrateSheet: some View {
        VStack(spacing: 16) {
            Text("Migrate VM").font(.title2.bold())
            Text("Live-migrate to another host").font(.caption).foregroundStyle(.secondary)
            Picker("Target Host", selection: $selectedHost) {
                Text("Select...").tag("")
                ForEach(Array(hosts.enumerated()), id: \.offset) { _, h in
                    let name = h["name"] as? String ?? ""
                    let state = h["state"] as? String ?? ""
                    Text("\(name) (\(state))").tag(h["id"] as? String ?? "")
                }
            }
            .frame(width: 400)
            HStack {
                Button("Cancel") { showMigrate = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Migrate") {
                    Task { await migrateVM() }
                    showMigrate = false
                }
                .buttonStyle(.borderedProminent).disabled(selectedHost.isEmpty)
            }
        }
        .padding().frame(width: 500)
        .onAppear { loadHosts() }
    }

    private var snapshotSheet: some View {
        VStack(spacing: 16) {
            Text("Create VM Snapshot").font(.title2.bold())
            TextField("Snapshot Name", text: $snapshotName, prompt: Text("\(vm.name)-snap"))
                .frame(width: 300)
            HStack {
                Button("Cancel") { showSnapshot = false }.keyboardShortcut(.cancelAction)
                Spacer()
                Button("Create") {
                    Task { await createSnapshot() }
                    showSnapshot = false
                }
                .buttonStyle(.borderedProminent)
            }
        }
        .padding().frame(width: 400)
    }

    // MARK: - Actions

    private func loadDetails() {
        guard let profile = appState.activeProfile, profile.type == .cloudstack else { return }
        isLoadingDetails = true
        Task {
            let client = CloudStackClient(profile: profile)
            vmVolumes = (try? await client.listVolumes(vmId: vm.id)) ?? []
            vmSnapshots = (try? await client.listVMSnapshots(vmId: vm.id)) ?? []
            isLoadingDetails = false
        }
    }

    private func loadOfferings() {
        guard let profile = appState.activeProfile else { return }
        Task {
            let client = CloudStackClient(profile: profile)
            serviceOfferings = (try? await client.listServiceOfferings()) ?? []
        }
    }

    private func loadHosts() {
        guard let profile = appState.activeProfile else { return }
        Task {
            let client = CloudStackClient(profile: profile)
            let hostList = try? await client.listHosts()
            hosts = (hostList ?? []).map { h in
                ["id": h.id, "name": h.name, "state": h.state] as [String: Any]
            }
        }
    }

    private func destroyVM(expunge: Bool = false) async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            try await client.destroyVM(id: vm.id, expunge: expunge)
            actionResult = "VM destroyed successfully"
            await appState.refresh()
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    private func resizeVM() async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            if vm.state == .stopped {
                try await client.changeServiceForVM(id: vm.id, serviceOfferingId: selectedOffering)
            } else {
                try await client.scaleVM(id: vm.id, serviceOfferingId: selectedOffering)
            }
            actionResult = "VM resized successfully"
            await appState.refresh()
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    private func migrateVM() async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            try await client.migrateVM(vmId: vm.id, hostId: selectedHost)
            actionResult = "Migration started"
            await appState.refresh()
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    private func createSnapshot() async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            let name = snapshotName.isEmpty ? "\(vm.name)-snap" : snapshotName
            try await client.createVMSnapshot(vmId: vm.id, name: name)
            actionResult = "Snapshot created"
            loadDetails()
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    private func revertSnapshot(id: String) async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            try await client.revertVMSnapshot(id: id)
            actionResult = "Reverted to snapshot"
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    private func deleteSnapshot(id: String) async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            try await client.deleteVMSnapshot(id: id)
            actionResult = "Snapshot deleted"
            loadDetails()
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    private func detachVolume(id: String) async {
        guard let profile = appState.activeProfile else { return }
        do {
            let client = CloudStackClient(profile: profile)
            try await client.detachVolume(id: id)
            actionResult = "Volume detached"
            loadDetails()
        } catch {
            actionResult = "Error: \(error.localizedDescription)"
        }
    }

    // MARK: - Helpers

    private func infoCard<Content: View>(_ title: String, icon: String, color: Color, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Image(systemName: icon).foregroundStyle(color).font(.caption)
                Text(title).font(.caption).foregroundStyle(.secondary)
            }
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(.background.secondary)
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }

    private func copyButton(_ text: String) -> some View {
        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(text, forType: .string)
        } label: {
            Image(systemName: "doc.on.doc").font(.caption2)
        }
        .buttonStyle(.borderless)
    }

    private func formatMemory(_ mb: Int) -> String {
        mb >= 1024 ? String(format: "%.1f GB", Double(mb) / 1024.0) : "\(mb) MB"
    }

    private func formatBytesI64(_ bytes: Int64) -> String {
        let gb = Double(bytes) / (1024 * 1024 * 1024)
        return gb >= 1024 ? String(format: "%.1f TB", gb / 1024) : String(format: "%.1f GB", gb)
    }
}
