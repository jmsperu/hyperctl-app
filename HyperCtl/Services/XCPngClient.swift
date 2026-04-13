import Foundation

actor XCPngClient {
    private let baseURL: String
    private let username: String
    private let password: String
    private let profileID: UUID
    private let session: URLSession
    private var sessionRef: String = ""

    init(profile: HyperProfile) {
        var url = profile.url.trimmingCharacters(in: .init(charactersIn: "/"))
        if !url.hasSuffix("/jsonrpc") {
            url += "/jsonrpc"
        }
        self.baseURL = url
        self.username = profile.username
        self.password = profile.password
        self.profileID = profile.id

        if profile.insecure {
            let config = URLSessionConfiguration.default
            config.timeoutIntervalForRequest = 30
            self.session = URLSession(configuration: config, delegate: InsecureDelegate.shared, delegateQueue: nil)
        } else {
            self.session = URLSession.shared
        }
    }

    // MARK: - JSON-RPC

    private func rpc(_ method: String, params: [Any]) async throws -> Any {
        let body: [String: Any] = [
            "jsonrpc": "2.0",
            "method": method,
            "params": params,
            "id": 1
        ]

        var request = URLRequest(url: URL(string: baseURL)!)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await session.data(for: request)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw HyperCtlError.apiError("XCP-ng HTTP \(statusCode)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HyperCtlError.parseError("Invalid JSON-RPC response")
        }

        if let error = json["error"] as? [String: Any] {
            let message = error["message"] as? String ?? "Unknown XAPI error"
            throw HyperCtlError.apiError(message)
        }

        return json["result"] as Any
    }

    // MARK: - Session

    func login() async throws {
        let result = try await rpc("session.login_with_password", params: [username, password, "1.0", "HyperCtl"])
        guard let ref = result as? String else {
            throw HyperCtlError.apiError("Login failed: no session reference")
        }
        sessionRef = ref
    }

    func logout() async {
        _ = try? await rpc("session.logout", params: [sessionRef])
        sessionRef = ""
    }

    // MARK: - VMs

    func listVMs() async throws -> [VirtualMachine] {
        let result = try await rpc("VM.get_all_records", params: [sessionRef])
        guard let records = result as? [String: [String: Any]] else { return [] }

        var machines: [VirtualMachine] = []
        for (ref, rec) in records {
            let isTemplate = rec["is_a_template"] as? Bool ?? true
            let isControlDomain = rec["is_control_domain"] as? Bool ?? true
            let isSnapshot = rec["is_a_snapshot"] as? Bool ?? false
            if isTemplate || isControlDomain || isSnapshot { continue }

            let powerState = rec["power_state"] as? String ?? "Unknown"
            let metrics = rec["metrics"] as? String ?? ""
            let cpus = Int(rec["VCPUs_max"] as? String ?? "0") ?? 0
            let memoryBytes = Int64(rec["memory_target"] as? String ?? "0") ?? 0

            // Try to get guest metrics for IP
            var ip = ""
            if let guestMetricsRef = rec["guest_metrics"] as? String,
               guestMetricsRef != "OpaqueRef:NULL" {
                if let gmResult = try? await rpc("VM_guest_metrics.get_networks", params: [sessionRef, guestMetricsRef]),
                   let networks = gmResult as? [String: String] {
                    ip = networks["0/ip"] ?? networks.values.first ?? ""
                }
            }

            // Get host name
            var hostName = ""
            if let residentOn = rec["resident_on"] as? String,
               residentOn != "OpaqueRef:NULL" {
                if let nameResult = try? await rpc("host.get_name_label", params: [sessionRef, residentOn]) {
                    hostName = nameResult as? String ?? ""
                }
            }

            let vm = VirtualMachine(
                id: ref,
                name: rec["name_label"] as? String ?? "",
                state: parseXCPState(powerState),
                cpus: cpus,
                memoryMB: Int(memoryBytes / (1024 * 1024)),
                ipAddress: ip,
                hostName: hostName,
                zone: "",
                template: "",
                created: "",
                profileID: profileID
            )
            machines.append(vm)
        }

        return machines.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    func startVM(ref: String) async throws {
        _ = try await rpc("VM.start", params: [sessionRef, ref, false, true])
    }

    func stopVM(ref: String) async throws {
        _ = try await rpc("VM.clean_shutdown", params: [sessionRef, ref])
    }

    func rebootVM(ref: String) async throws {
        _ = try await rpc("VM.clean_reboot", params: [sessionRef, ref])
    }

    // MARK: - Hosts

    func listHosts() async throws -> [HyperHost] {
        let result = try await rpc("host.get_all_records", params: [sessionRef])
        guard let records = result as? [String: [String: Any]] else { return [] }

        var hosts: [HyperHost] = []
        for (_, rec) in records {
            let cpuInfo = rec["cpu_info"] as? [String: String] ?? [:]
            let cpuCount = Int(cpuInfo["cpu_count"] ?? "0") ?? 0
            let metricsRef = rec["metrics"] as? String ?? ""

            var memTotal: Int64 = 0
            var memUsed: Int64 = 0
            if metricsRef != "OpaqueRef:NULL",
               let metricsResult = try? await rpc("host_metrics.get_record", params: [sessionRef, metricsRef]),
               let metrics = metricsResult as? [String: Any] {
                memTotal = Int64(metrics["memory_total"] as? String ?? "0") ?? 0
                let memFree = Int64(metrics["memory_free"] as? String ?? "0") ?? 0
                memUsed = memTotal - memFree
            }

            let host = HyperHost(
                id: rec["uuid"] as? String ?? "",
                name: rec["name_label"] as? String ?? "",
                state: rec["enabled"] as? Bool == true ? "Up" : "Down",
                hypervisor: "XCP-ng",
                cpus: cpuCount,
                cpuUsed: "",
                memoryTotal: memTotal,
                memoryUsed: memUsed,
                zone: "",
                cluster: "",
                profileID: profileID
            )
            hosts.append(host)
        }
        return hosts
    }

    // MARK: - Storage Repositories

    func listSRs() async throws -> [StoragePool] {
        let result = try await rpc("SR.get_all_records", params: [sessionRef])
        guard let records = result as? [String: [String: Any]] else { return [] }

        var pools: [StoragePool] = []
        for (_, rec) in records {
            let srType = rec["type"] as? String ?? ""
            // Skip non-visible/internal SRs
            if ["udev", "iso"].contains(srType) { continue }

            let physSize = Int64(rec["physical_size"] as? String ?? "0") ?? 0
            let physUtil = Int64(rec["physical_utilisation"] as? String ?? "0") ?? 0
            let virtAlloc = Int64(rec["virtual_allocation"] as? String ?? "0") ?? 0

            if physSize == 0 { continue }

            let pool = StoragePool(
                id: rec["uuid"] as? String ?? "",
                name: rec["name_label"] as? String ?? "",
                state: rec["current_operations"] as? [String: String] != nil ? "Active" : "Ready",
                type: srType,
                totalBytes: physSize,
                usedBytes: physUtil,
                allocBytes: virtAlloc,
                zone: "",
                cluster: "",
                profileID: profileID
            )
            pools.append(pool)
        }
        return pools
    }

    // MARK: - Networks

    func listNetworks() async throws -> [HyperNetwork] {
        let result = try await rpc("network.get_all_records", params: [sessionRef])
        guard let records = result as? [String: [String: Any]] else { return [] }

        var nets: [HyperNetwork] = []
        for (_, rec) in records {
            let otherConfig = rec["other_config"] as? [String: String] ?? [:]
            let nameLabel = rec["name_label"] as? String ?? ""

            // Skip internal networks
            if otherConfig["is_host_internal_management_network"] == "true" { continue }

            let net = HyperNetwork(
                id: rec["uuid"] as? String ?? "",
                name: nameLabel,
                state: "Active",
                type: rec["bridge"] as? String ?? "",
                cidr: "",
                gateway: "",
                vlan: otherConfig["vlan"] ?? "",
                zone: "",
                profileID: profileID
            )
            nets.append(net)
        }
        return nets.sorted { $0.name.localizedCaseInsensitiveCompare($1.name) == .orderedAscending }
    }

    // MARK: - Helpers

    private func parseXCPState(_ state: String) -> VMState {
        switch state.lowercased() {
        case "running": return .running
        case "halted": return .stopped
        case "paused": return .suspended
        case "suspended": return .suspended
        default: return .unknown
        }
    }
}
