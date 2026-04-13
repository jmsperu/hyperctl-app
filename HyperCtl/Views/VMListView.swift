import SwiftUI
#if canImport(AppKit)
import AppKit
#endif

struct VMListView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.openWindow) private var openWindow
    @State private var searchText = ""
    @State private var sortOrder = [KeyPathComparator(\VirtualMachine.name)]
    @State private var selection = Set<String>()
    @State private var consoleVM: VirtualMachine?
    @State private var detailVM: VirtualMachine?

    private var filteredVMs: [VirtualMachine] {
        let vms: [VirtualMachine]
        if searchText.isEmpty {
            vms = appState.vms
        } else {
            let query = searchText.lowercased()
            vms = appState.vms.filter {
                $0.name.lowercased().contains(query) ||
                $0.ipAddress.lowercased().contains(query) ||
                $0.hostName.lowercased().contains(query) ||
                $0.zone.lowercased().contains(query) ||
                $0.state.rawValue.lowercased().contains(query)
            }
        }
        return vms.sorted(using: sortOrder)
    }

    var body: some View {
        Table(filteredVMs, selection: $selection, sortOrder: $sortOrder) {
            TableColumn("Name", value: \.name) { vm in
                HStack(spacing: 6) {
                    Image(systemName: "desktopcomputer")
                        .foregroundStyle(.secondary)
                        .font(.caption)
                    Text(vm.name)
                        .lineLimit(1)
                }
            }
            .width(min: 120, ideal: 200)

            TableColumn("State") { vm in
                HStack(spacing: 4) {
                    Image(systemName: vm.state.icon)
                        .foregroundStyle(vm.state.color)
                        .font(.caption)
                    Text(vm.state.rawValue)
                        .font(.callout)
                        .foregroundStyle(vm.state.color)
                }
                .padding(.horizontal, 6)
                .padding(.vertical, 2)
                .background(vm.state.color.opacity(0.1), in: Capsule())
            }
            .width(min: 80, ideal: 100)

            TableColumn("IP Address", value: \.ipAddress) { vm in
                Text(vm.ipAddress.isEmpty ? "-" : vm.ipAddress)
                    .font(.callout.monospaced())
            }
            .width(min: 100, ideal: 130)

            TableColumn("CPUs") { vm in
                Text("\(vm.cpus)")
                    .font(.callout)
            }
            .width(50)

            TableColumn("Memory") { vm in
                Text(formatMemory(vm.memoryMB))
                    .font(.callout)
            }
            .width(min: 60, ideal: 80)

            TableColumn("Host", value: \.hostName) { vm in
                Text(vm.hostName.isEmpty ? "-" : vm.hostName)
                    .font(.callout)
                    .lineLimit(1)
            }
            .width(min: 80, ideal: 120)

            TableColumn("Zone", value: \.zone) { vm in
                Text(vm.zone.isEmpty ? "-" : vm.zone)
                    .font(.callout)
                    .lineLimit(1)
            }
            .width(min: 60, ideal: 100)
        }
        .contextMenu(forSelectionType: VirtualMachine.ID.self) { ids in
            if let vmID = ids.first, let vm = appState.vms.first(where: { $0.id == vmID }) {
                Button {
                    detailVM = vm
                } label: {
                    Label("View Details", systemImage: "info.circle")
                }
                Divider()
                vmContextMenu(vm: vm)
            }
        }
        .searchable(text: $searchText, prompt: "Filter VMs")
        .navigationTitle("Virtual Machines (\(filteredVMs.count))")
        .toolbar {
            ToolbarItemGroup(placement: .automatic) {
                if let vmID = selection.first, let vm = appState.vms.first(where: { $0.id == vmID }) {
                    toolbarActions(vm: vm)
                }
            }
        }
        .overlay {
            if appState.isLoading && appState.vms.isEmpty {
                VStack(spacing: 12) {
                    ProgressView()
                        .controlSize(.large)
                    Text("Loading VMs...")
                        .foregroundStyle(.secondary)
                }
            } else if appState.vms.isEmpty {
                ContentUnavailableView(
                    "No Virtual Machines",
                    systemImage: "desktopcomputer",
                    description: Text("No VMs found in this environment.")
                )
            }
        }
        .safeAreaInset(edge: .bottom) {
            if let vmID = selection.first, let vm = appState.vms.first(where: { $0.id == vmID }) {
                vmDetailBar(vm: vm)
            }
        }
        .sheet(item: $consoleVM) { vm in
            VMConsoleView(vm: vm)
                .environmentObject(appState)
        }
        .sheet(item: $detailVM) { vm in
            VMDetailView(vm: vm)
                .environmentObject(appState)
                .frame(minWidth: 750, minHeight: 600)
        }
    }

    private func formatMemory(_ mb: Int) -> String {
        if mb >= 1024 {
            return String(format: "%.1f GB", Double(mb) / 1024.0)
        }
        return "\(mb) MB"
    }

    // MARK: - Context Menu

    @ViewBuilder
    private func vmContextMenu(vm: VirtualMachine) -> some View {
        Button {
            Task { await appState.vmAction("start", vm: vm) }
        } label: {
            Label("Start", systemImage: "play.fill")
        }
        .disabled(vm.state == .running)

        Button {
            Task { await appState.vmAction("stop", vm: vm) }
        } label: {
            Label("Stop", systemImage: "stop.fill")
        }
        .disabled(vm.state == .stopped)

        Button {
            Task { await appState.vmAction("reboot", vm: vm) }
        } label: {
            Label("Reboot", systemImage: "arrow.clockwise")
        }
        .disabled(vm.state != .running)

        Divider()

        Button {
            consoleVM = vm
        } label: {
            Label("Open Console", systemImage: "terminal")
        }

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(vm.ipAddress, forType: .string)
        } label: {
            Label("Copy IP", systemImage: "doc.on.doc")
        }
        .disabled(vm.ipAddress.isEmpty)

        Button {
            NSPasteboard.general.clearContents()
            NSPasteboard.general.setString(vm.id, forType: .string)
        } label: {
            Label("Copy VM ID", systemImage: "number")
        }
    }

    // MARK: - Toolbar Actions

    @ViewBuilder
    private func toolbarActions(vm: VirtualMachine) -> some View {
        HStack(spacing: 8) {
            Text(vm.name)
                .font(.callout.bold())
                .foregroundStyle(.secondary)

            Divider()
                .frame(height: 16)

            Button {
                Task { await appState.vmAction("start", vm: vm) }
            } label: {
                Label("Start", systemImage: "play.fill")
            }
            .disabled(vm.state == .running)
            .help("Start VM")

            Button {
                Task { await appState.vmAction("stop", vm: vm) }
            } label: {
                Label("Stop", systemImage: "stop.fill")
            }
            .disabled(vm.state == .stopped)
            .help("Stop VM")

            Button {
                Task { await appState.vmAction("reboot", vm: vm) }
            } label: {
                Label("Reboot", systemImage: "arrow.clockwise")
            }
            .disabled(vm.state != .running)
            .help("Reboot VM")

            if let profile = appState.activeProfile, profile.type == .cloudstack {
                Button {
                    let base = profile.url.trimmingCharacters(in: .init(charactersIn: "/"))
                    let consoleURL = base.hasSuffix("/client")
                        ? "\(base)/console?cmd=access&vm=\(vm.id)"
                        : "\(base)/client/console?cmd=access&vm=\(vm.id)"
                    if let url = URL(string: consoleURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Label("Console", systemImage: "terminal")
                }
                .help("Open Console in Browser")
            }
        }
    }

    // MARK: - VM Detail Bar

    private func vmDetailBar(vm: VirtualMachine) -> some View {
        HStack(spacing: 16) {
            HStack(spacing: 6) {
                Image(systemName: vm.state.icon)
                    .foregroundStyle(vm.state.color)
                Text(vm.name)
                    .font(.headline)
            }

            Divider().frame(height: 20)

            Label(vm.ipAddress.isEmpty ? "No IP" : vm.ipAddress, systemImage: "network")
                .font(.callout.monospaced())

            Label("\(vm.cpus) vCPU", systemImage: "cpu")
                .font(.callout)

            Label(formatMemory(vm.memoryMB), systemImage: "memorychip")
                .font(.callout)

            Label(vm.hostName.isEmpty ? "-" : vm.hostName, systemImage: "server.rack")
                .font(.callout)

            Spacer()

            // Action buttons
            Button {
                Task { await appState.vmAction("start", vm: vm) }
            } label: {
                Image(systemName: "play.fill")
            }
            .disabled(vm.state == .running)
            .buttonStyle(.bordered)
            .tint(.green)
            .help("Start")

            Button {
                Task { await appState.vmAction("stop", vm: vm) }
            } label: {
                Image(systemName: "stop.fill")
            }
            .disabled(vm.state == .stopped)
            .buttonStyle(.bordered)
            .tint(.red)
            .help("Stop")

            Button {
                Task { await appState.vmAction("reboot", vm: vm) }
            } label: {
                Image(systemName: "arrow.clockwise")
            }
            .disabled(vm.state != .running)
            .buttonStyle(.bordered)
            .tint(.orange)
            .help("Reboot")

            if let profile = appState.activeProfile, profile.type == .cloudstack {
                Button {
                    let base = profile.url.trimmingCharacters(in: .init(charactersIn: "/"))
                    let consoleURL = base.hasSuffix("/client")
                        ? "\(base)/console?cmd=access&vm=\(vm.id)"
                        : "\(base)/client/console?cmd=access&vm=\(vm.id)"
                    if let url = URL(string: consoleURL) {
                        NSWorkspace.shared.open(url)
                    }
                } label: {
                    Image(systemName: "terminal")
                }
                .buttonStyle(.bordered)
                .help("Console")
            }
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }
}
