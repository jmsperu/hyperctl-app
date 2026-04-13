import Foundation
import SwiftUI

// MARK: - Profile

struct HyperProfile: Identifiable, Codable, Hashable {
    var id = UUID()
    var name: String
    var type: HypervisorType
    var url: String
    var apiKey: String = ""
    var apiSecret: String = ""
    var username: String = ""
    var password: String = ""
    var insecure: Bool = false
}

enum HypervisorType: String, Codable, CaseIterable {
    case cloudstack = "CloudStack"
    case xcpng = "XCP-ng"
    case hyperv = "Hyper-V"

    var icon: String {
        switch self {
        case .cloudstack: return "cloud"
        case .xcpng: return "server.rack"
        case .hyperv: return "desktopcomputer"
        }
    }

    var color: Color {
        switch self {
        case .cloudstack: return .orange
        case .xcpng: return .green
        case .hyperv: return .blue
        }
    }
}

// MARK: - VM

struct VirtualMachine: Identifiable, Hashable {
    var id: String
    var name: String
    var instanceName: String = "" // virsh domain name e.g. i-2-1814-VM
    var state: VMState
    var cpus: Int
    var memoryMB: Int
    var ipAddress: String
    var hostName: String
    var zone: String
    var template: String
    var created: String
    var profileID: UUID
}

enum VMState: String, Hashable {
    case running = "Running"
    case stopped = "Stopped"
    case starting = "Starting"
    case stopping = "Stopping"
    case suspended = "Suspended"
    case error = "Error"
    case unknown = "Unknown"

    var color: Color {
        switch self {
        case .running: return .green
        case .stopped: return .red
        case .starting, .stopping: return .orange
        case .suspended: return .yellow
        case .error: return .red
        case .unknown: return .gray
        }
    }

    var icon: String {
        switch self {
        case .running: return "play.circle.fill"
        case .stopped: return "stop.circle.fill"
        case .starting: return "arrow.clockwise.circle"
        case .stopping: return "arrow.clockwise.circle"
        case .suspended: return "pause.circle.fill"
        case .error: return "exclamationmark.circle.fill"
        case .unknown: return "questionmark.circle"
        }
    }
}

// MARK: - Host

struct HyperHost: Identifiable, Hashable {
    var id: String
    var name: String
    var state: String
    var hypervisor: String
    var cpus: Int
    var cpuUsed: String
    var memoryTotal: Int64
    var memoryUsed: Int64
    var zone: String
    var cluster: String
    var profileID: UUID
}

// MARK: - Storage

struct StoragePool: Identifiable, Hashable {
    var id: String
    var name: String
    var state: String
    var type: String
    var totalBytes: Int64
    var usedBytes: Int64
    var allocBytes: Int64
    var zone: String
    var cluster: String
    var profileID: UUID

    var usedPercent: Double {
        guard totalBytes > 0 else { return 0 }
        return Double(usedBytes) / Double(totalBytes) * 100
    }
}

// MARK: - Network

struct HyperNetwork: Identifiable, Hashable {
    var id: String
    var name: String
    var state: String
    var type: String
    var cidr: String
    var gateway: String
    var vlan: String
    var zone: String
    var profileID: UUID
}

// MARK: - Sidebar

enum SidebarItem: String, CaseIterable {
    case dashboard = "Dashboard"
    case vms = "Virtual Machines"
    case hosts = "Hosts"
    case storage = "Storage"
    case networks = "Networks"
    case snapshots = "Snapshots"
    case templates = "Templates"

    var icon: String {
        switch self {
        case .dashboard: return "gauge.with.dots.needle.33percent"
        case .vms: return "desktopcomputer"
        case .hosts: return "server.rack"
        case .storage: return "externaldrive"
        case .networks: return "network"
        case .snapshots: return "camera"
        case .templates: return "doc.on.doc"
        }
    }
}

// MARK: - App State

@MainActor
class AppState: ObservableObject {
    @Published var profiles: [HyperProfile] = []
    @Published var activeProfile: HyperProfile?
    @Published var selectedItem: SidebarItem = .dashboard
    @Published var showAddProfile = false
    @Published var isLoading = false
    @Published var errorMessage: String?

    // Data
    @Published var vms: [VirtualMachine] = []
    @Published var hosts: [HyperHost] = []
    @Published var storagePools: [StoragePool] = []
    @Published var networks: [HyperNetwork] = []

    private let profilesKey = "hyperctl.profiles"
    private let logFile = FileManager.default.homeDirectoryForCurrentUser.appendingPathComponent("hyperctl-debug.log")

    private func log(_ msg: String) {
        let line = "\(Date()): \(msg)\n"
        print(line, terminator: "")
        if let data = line.data(using: .utf8) {
            if FileManager.default.fileExists(atPath: logFile.path) {
                if let fh = try? FileHandle(forWritingTo: logFile) {
                    fh.seekToEndOfFile()
                    fh.write(data)
                    fh.closeFile()
                }
            } else {
                try? data.write(to: logFile)
            }
        }
    }

    init() {
        loadProfiles()
    }

    func loadProfiles() {
        if let data = UserDefaults.standard.data(forKey: profilesKey),
           let profiles = try? JSONDecoder().decode([HyperProfile].self, from: data) {
            self.profiles = profiles
            self.activeProfile = profiles.first
        }
    }

    func saveProfiles() {
        if let data = try? JSONEncoder().encode(profiles) {
            UserDefaults.standard.set(data, forKey: profilesKey)
        }
    }

    func addProfile(_ profile: HyperProfile) {
        profiles.append(profile)
        if activeProfile == nil {
            activeProfile = profile
        }
        saveProfiles()
    }

    func removeProfile(_ profile: HyperProfile) {
        profiles.removeAll { $0.id == profile.id }
        if activeProfile?.id == profile.id {
            activeProfile = profiles.first
        }
        saveProfiles()
    }

    func updateProfile(_ profile: HyperProfile) {
        if let idx = profiles.firstIndex(where: { $0.id == profile.id }) {
            profiles[idx] = profile
            if activeProfile?.id == profile.id {
                activeProfile = profile
            }
            saveProfiles()
        }
    }

    func testProfile(_ profile: HyperProfile) async {
        isLoading = true
        errorMessage = nil

        do {
            switch profile.type {
            case .cloudstack:
                let client = CloudStackClient(profile: profile)
                let vms = try await client.listVMs()
                errorMessage = nil
                // Show success as a non-error message (reusing the alert)
                let msg = "Connection successful! Found \(vms.count) VMs."
                errorMessage = msg
            case .xcpng:
                let client = XCPngClient(profile: profile)
                try await client.login()
                let vms = try await client.listVMs()
                await client.logout()
                errorMessage = "Connection successful! Found \(vms.count) VMs."
            case .hyperv:
                errorMessage = "Hyper-V test not yet implemented."
            }
        } catch {
            errorMessage = "Connection FAILED: \(error.localizedDescription)"
        }

        isLoading = false
    }

    func refresh() async {
        guard let profile = activeProfile else {
            log("[HyperCtl] No active profile")
            return
        }
        isLoading = true
        errorMessage = nil
        log("[HyperCtl] Refreshing profile: \(profile.name) type=\(profile.type.rawValue) url=\(profile.url) insecure=\(profile.insecure) hasApiKey=\(!profile.apiKey.isEmpty) hasUser=\(!profile.username.isEmpty)")

        do {
            switch profile.type {
            case .cloudstack:
                let client = CloudStackClient(profile: profile)
                log("[HyperCtl] Fetching VMs...")
                async let fetchVMs = client.listVMs()
                async let fetchHosts = client.listHosts()
                async let fetchStorage = client.listStoragePools()
                async let fetchNets = client.listNetworks()

                let (v, h, s, n) = try await (fetchVMs, fetchHosts, fetchStorage, fetchNets)
                log("[HyperCtl] Got \(v.count) VMs, \(h.count) hosts, \(s.count) pools, \(n.count) networks")
                vms = v
                hosts = h
                storagePools = s
                networks = n

            case .xcpng:
                let client = XCPngClient(profile: profile)
                try await client.login()
                defer { Task { await client.logout() } }

                vms = try await client.listVMs()
                hosts = try await client.listHosts()
                storagePools = try await client.listSRs()
                networks = try await client.listNetworks()

            case .hyperv:
                let client = HyperVClient(profile: profile)
                vms = try await client.listVMs()
                hosts = try await client.listHosts()
            }
        } catch {
            log("[HyperCtl] REFRESH ERROR: \(error)")
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }

    func vmAction(_ action: String, vm: VirtualMachine) async {
        guard let profile = activeProfile else {
            errorMessage = "No active profile selected"
            return
        }
        isLoading = true
        errorMessage = nil

        do {
            switch profile.type {
            case .cloudstack:
                let client = CloudStackClient(profile: profile)
                switch action {
                case "start": try await client.startVM(id: vm.id)
                case "stop": try await client.stopVM(id: vm.id)
                case "reboot": try await client.rebootVM(id: vm.id)
                default: break
                }
            case .xcpng:
                let client = XCPngClient(profile: profile)
                try await client.login()
                defer { Task { await client.logout() } }
                switch action {
                case "start": try await client.startVM(ref: vm.id)
                case "stop": try await client.stopVM(ref: vm.id)
                case "reboot": try await client.rebootVM(ref: vm.id)
                default: break
                }
            case .hyperv:
                let client = HyperVClient(profile: profile)
                switch action {
                case "start": try await client.startVM(name: vm.name)
                case "stop": try await client.stopVM(name: vm.name)
                case "reboot": try await client.rebootVM(name: vm.name)
                default: break
                }
            }
            // Refresh after action
            try? await Task.sleep(for: .seconds(2))
            await refresh()
        } catch {
            errorMessage = error.localizedDescription
        }

        isLoading = false
    }
}
