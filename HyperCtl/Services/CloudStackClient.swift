import Foundation
import CryptoKit

actor CloudStackClient {
    private let baseURL: String
    private let apiKey: String
    private let apiSecret: String
    private let username: String
    private let password: String
    private let profileID: UUID
    private let session: URLSession
    private var sessionKey: String?
    private let usePasswordAuth: Bool

    init(profile: HyperProfile) {
        self.baseURL = profile.url.trimmingCharacters(in: .init(charactersIn: "/"))
        self.apiKey = profile.apiKey
        self.apiSecret = profile.apiSecret
        self.username = profile.username
        self.password = profile.password
        self.profileID = profile.id
        self.usePasswordAuth = profile.apiKey.isEmpty && !profile.username.isEmpty

        let config = URLSessionConfiguration.default
        config.timeoutIntervalForRequest = 30
        config.httpCookieAcceptPolicy = .always
        config.httpCookieStorage = HTTPCookieStorage.shared
        config.httpShouldSetCookies = true

        if profile.insecure {
            self.session = URLSession(configuration: config, delegate: InsecureDelegate.shared, delegateQueue: nil)
        } else {
            self.session = URLSession(configuration: config)
        }
    }

    // MARK: - Username/Password Login

    private func login() async throws {
        let loginURL = "\(baseURL)/api"
        var request = URLRequest(url: URL(string: loginURL)!)
        request.httpMethod = "POST"
        request.setValue("application/x-www-form-urlencoded", forHTTPHeaderField: "Content-Type")

        let body = "command=login&username=\(percentEncode(username))&password=\(percentEncode(password))&domain=%2F&response=json"
        request.httpBody = body.data(using: .utf8)

        let (data, response) = try await session.data(for: request)

        guard let httpResp = response as? HTTPURLResponse, httpResp.statusCode == 200 else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            throw HyperCtlError.apiError("Login failed (HTTP \(statusCode))")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
              let loginResp = json["loginresponse"] as? [String: Any],
              let key = loginResp["sessionkey"] as? String else {
            throw HyperCtlError.apiError("Login failed: invalid response")
        }

        sessionKey = key
    }

    // MARK: - Signing

    private func signedURL(command: String, params: [String: String] = [:]) -> URL {
        var allParams = params
        allParams["command"] = command
        allParams["apikey"] = apiKey
        allParams["response"] = "json"

        // Sort params by key (case-insensitive), lowercase keys and values for signing
        let sortedForSigning = allParams
            .map { (key: $0.key.lowercased(), value: $0.value.lowercased()) }
            .sorted { $0.key < $1.key }

        let queryForSigning = sortedForSigning
            .map { "\($0.key)=\(percentEncode($0.value))" }
            .joined(separator: "&")

        // HMAC-SHA1 signature
        let key = SymmetricKey(data: Data(apiSecret.utf8))
        let signature = HMAC<Insecure.SHA1>.authenticationCode(
            for: Data(queryForSigning.utf8),
            using: key
        )
        let signatureBase64 = Data(signature).base64EncodedString()

        // Build the actual URL with original-case params
        let apiBase = baseURL.hasSuffix("/client") ? "\(baseURL)/api" : "\(baseURL)/client/api"
        var components = URLComponents(string: apiBase)!
        var queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
        queryItems.append(URLQueryItem(name: "signature", value: signatureBase64))
        components.queryItems = queryItems

        return components.url!
    }

    private func percentEncode(_ string: String) -> String {
        var allowed = CharacterSet.alphanumerics
        allowed.insert(charactersIn: "-_.~")
        return string.addingPercentEncoding(withAllowedCharacters: allowed) ?? string
    }

    // MARK: - Request Helper

    private func request(_ command: String, params: [String: String] = [:]) async throws -> [String: Any] {
        let url: URL

        if usePasswordAuth {
            // Session-based auth
            if sessionKey == nil {
                try await login()
            }
            var allParams = params
            allParams["command"] = command
            allParams["sessionkey"] = sessionKey ?? ""
            allParams["response"] = "json"

            var components = URLComponents(string: "\(baseURL)/api")!
            components.queryItems = allParams.map { URLQueryItem(name: $0.key, value: $0.value) }
            url = components.url!
        } else {
            // API key auth
            url = signedURL(command: command, params: params)
        }

        let (data, response) = try await session.data(from: url)

        guard let httpResponse = response as? HTTPURLResponse,
              (200...299).contains(httpResponse.statusCode) else {
            let statusCode = (response as? HTTPURLResponse)?.statusCode ?? 0
            let body = String(data: data, encoding: .utf8) ?? ""
            throw HyperCtlError.apiError("CloudStack HTTP \(statusCode): \(body)")
        }

        guard let json = try JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            throw HyperCtlError.parseError("Invalid JSON response")
        }

        // Check for error response
        if let errorResponse = json["errorresponse"] as? [String: Any],
           let errorText = errorResponse["errortext"] as? String {
            throw HyperCtlError.apiError(errorText)
        }

        return json
    }

    // MARK: - VM Operations

    func listVMs() async throws -> [VirtualMachine] {
        let json = try await request("listVirtualMachines", params: ["listall": "true"])

        guard let response = json["listvirtualmachinesresponse"] as? [String: Any],
              let vmList = response["virtualmachine"] as? [[String: Any]] else {
            return []
        }

        return vmList.map { vm in
            let nics = vm["nic"] as? [[String: Any]] ?? []
            let ip = nics.first?["ipaddress"] as? String ?? ""

            return VirtualMachine(
                id: vm["id"] as? String ?? "",
                name: vm["name"] as? String ?? "",
                instanceName: vm["instancename"] as? String ?? "",
                state: parseVMState(vm["state"] as? String ?? ""),
                cpus: vm["cpunumber"] as? Int ?? 0,
                memoryMB: (vm["memory"] as? Int ?? 0),
                ipAddress: ip,
                hostName: vm["hostname"] as? String ?? "",
                zone: vm["zonename"] as? String ?? "",
                template: vm["templatename"] as? String ?? "",
                created: vm["created"] as? String ?? "",
                profileID: profileID
            )
        }
    }

    func startVM(id: String) async throws {
        _ = try await request("startVirtualMachine", params: ["id": id])
    }

    func stopVM(id: String) async throws {
        _ = try await request("stopVirtualMachine", params: ["id": id])
    }

    func rebootVM(id: String) async throws {
        _ = try await request("rebootVirtualMachine", params: ["id": id])
    }

    func destroyVM(id: String, expunge: Bool = false) async throws {
        var params = ["id": id]
        if expunge { params["expunge"] = "true" }
        _ = try await request("destroyVirtualMachine", params: params)
    }

    func recoverVM(id: String) async throws {
        _ = try await request("recoverVirtualMachine", params: ["id": id])
    }

    // MARK: - Deploy VM

    func deployVM(name: String, serviceOfferingId: String, templateId: String, zoneId: String, networkIds: String = "", diskOfferingId: String = "", startVM: Bool = true) async throws -> String {
        var params: [String: String] = [
            "name": name,
            "displayname": name,
            "serviceofferingid": serviceOfferingId,
            "templateid": templateId,
            "zoneid": zoneId,
            "startvm": startVM ? "true" : "false",
        ]
        if !networkIds.isEmpty { params["networkids"] = networkIds }
        if !diskOfferingId.isEmpty { params["diskofferingid"] = diskOfferingId }

        let json = try await request("deployVirtualMachine", params: params)
        if let resp = json["deployvirtualmachineresponse"] as? [String: Any],
           let id = resp["id"] as? String {
            return id
        }
        return ""
    }

    // MARK: - Resize / Scale VM

    func scaleVM(id: String, serviceOfferingId: String) async throws {
        _ = try await request("scaleVirtualMachine", params: [
            "id": id,
            "serviceofferingid": serviceOfferingId,
        ])
    }

    func changeServiceForVM(id: String, serviceOfferingId: String) async throws {
        _ = try await request("changeServiceForVirtualMachine", params: [
            "id": id,
            "serviceofferingid": serviceOfferingId,
        ])
    }

    // MARK: - Migrate VM

    func migrateVM(vmId: String, hostId: String) async throws {
        _ = try await request("migrateVirtualMachine", params: [
            "virtualmachineid": vmId,
            "hostid": hostId,
        ])
    }

    // MARK: - Snapshots

    func createSnapshot(volumeId: String, name: String = "") async throws {
        var params = ["volumeid": volumeId]
        if !name.isEmpty { params["name"] = name }
        _ = try await request("createSnapshot", params: params)
    }

    func createVMSnapshot(vmId: String, name: String = "", snapshotMemory: Bool = false) async throws {
        var params = ["virtualmachineid": vmId]
        if !name.isEmpty { params["name"] = name }
        if snapshotMemory { params["snapshotmemory"] = "true" }
        _ = try await request("createVMSnapshot", params: params)
    }

    func listVMSnapshots(vmId: String) async throws -> [[String: Any]] {
        let json = try await request("listVMSnapshot", params: ["virtualmachineid": vmId])
        if let resp = json["listvmsnapshotresponse"] as? [String: Any],
           let snaps = resp["vmSnapshot"] as? [[String: Any]] {
            return snaps
        }
        return []
    }

    func deleteVMSnapshot(id: String) async throws {
        _ = try await request("deleteVMSnapshot", params: ["vmsnapshotid": id])
    }

    func revertVMSnapshot(id: String) async throws {
        _ = try await request("revertToVMSnapshot", params: ["vmsnapshotid": id])
    }

    // MARK: - Volumes

    func listVolumes(vmId: String = "") async throws -> [[String: Any]] {
        var params = ["listall": "true"]
        if !vmId.isEmpty { params["virtualmachineid"] = vmId }
        let json = try await request("listVolumes", params: params)
        if let resp = json["listvolumesresponse"] as? [String: Any],
           let vols = resp["volume"] as? [[String: Any]] {
            return vols
        }
        return []
    }

    func createVolume(name: String, diskOfferingId: String, zoneId: String, size: Int = 0) async throws {
        var params: [String: String] = [
            "name": name,
            "diskofferingid": diskOfferingId,
            "zoneid": zoneId,
        ]
        if size > 0 { params["size"] = "\(size)" }
        _ = try await request("createVolume", params: params)
    }

    func attachVolume(id: String, vmId: String) async throws {
        _ = try await request("attachVolume", params: ["id": id, "virtualmachineid": vmId])
    }

    func detachVolume(id: String) async throws {
        _ = try await request("detachVolume", params: ["id": id])
    }

    func deleteVolume(id: String) async throws {
        _ = try await request("deleteVolume", params: ["id": id])
    }

    func resizeVolume(id: String, size: Int) async throws {
        _ = try await request("resizeVolume", params: ["id": id, "size": "\(size)"])
    }

    // MARK: - NICs

    func addNicToVM(vmId: String, networkId: String) async throws {
        _ = try await request("addNicToVirtualMachine", params: [
            "virtualmachineid": vmId,
            "networkid": networkId,
        ])
    }

    func removeNicFromVM(vmId: String, nicId: String) async throws {
        _ = try await request("removeNicFromVirtualMachine", params: [
            "virtualmachineid": vmId,
            "nicid": nicId,
        ])
    }

    func updateDefaultNic(vmId: String, nicId: String) async throws {
        _ = try await request("updateDefaultNicForVirtualMachine", params: [
            "virtualmachineid": vmId,
            "nicid": nicId,
        ])
    }

    // MARK: - ISO

    func attachISO(id: String, vmId: String) async throws {
        _ = try await request("attachIso", params: ["id": id, "virtualmachineid": vmId])
    }

    func detachISO(vmId: String) async throws {
        _ = try await request("detachIso", params: ["virtualmachineid": vmId])
    }

    // MARK: - Console / VNC

    func getConsoleURL(vmId: String) -> String {
        let base = baseURL.hasSuffix("/client") ? baseURL : "\(baseURL)/client"
        return "\(base)/console?cmd=access&vm=\(vmId)"
    }

    // MARK: - Service Offerings

    func listServiceOfferings() async throws -> [[String: Any]] {
        let json = try await request("listServiceOfferings")
        if let resp = json["listserviceofferingsresponse"] as? [String: Any],
           let offerings = resp["serviceoffering"] as? [[String: Any]] {
            return offerings
        }
        return []
    }

    // MARK: - Disk Offerings

    func listDiskOfferings() async throws -> [[String: Any]] {
        let json = try await request("listDiskOfferings")
        if let resp = json["listdiskofferingsresponse"] as? [String: Any],
           let offerings = resp["diskoffering"] as? [[String: Any]] {
            return offerings
        }
        return []
    }

    // MARK: - Templates

    func listTemplates(filter: String = "all") async throws -> [[String: Any]] {
        let json = try await request("listTemplates", params: ["templatefilter": filter])
        if let resp = json["listtemplatesresponse"] as? [String: Any],
           let templates = resp["template"] as? [[String: Any]] {
            return templates
        }
        return []
    }

    // MARK: - ISOs

    func listISOs(filter: String = "all") async throws -> [[String: Any]] {
        let json = try await request("listIsos", params: ["isofilter": filter])
        if let resp = json["listisosresponse"] as? [String: Any],
           let isos = resp["iso"] as? [[String: Any]] {
            return isos
        }
        return []
    }

    // MARK: - Zones

    func listZones() async throws -> [[String: Any]] {
        let json = try await request("listZones")
        if let resp = json["listzonesresponse"] as? [String: Any],
           let zones = resp["zone"] as? [[String: Any]] {
            return zones
        }
        return []
    }

    // MARK: - Hosts

    func listHosts() async throws -> [HyperHost] {
        let json = try await request("listHosts", params: ["type": "Routing"])

        guard let response = json["listhostsresponse"] as? [String: Any],
              let hostList = response["host"] as? [[String: Any]] else {
            return []
        }

        return hostList.map { h in
            HyperHost(
                id: h["id"] as? String ?? "",
                name: h["name"] as? String ?? "",
                state: h["state"] as? String ?? "",
                hypervisor: h["hypervisor"] as? String ?? "",
                cpus: h["cpunumber"] as? Int ?? 0,
                cpuUsed: h["cpuused"] as? String ?? "0%",
                memoryTotal: h["memorytotal"] as? Int64 ?? 0,
                memoryUsed: h["memoryused"] as? Int64 ?? 0,
                zone: h["zonename"] as? String ?? "",
                cluster: h["clustername"] as? String ?? "",
                profileID: profileID
            )
        }
    }

    // MARK: - Storage

    func listStoragePools() async throws -> [StoragePool] {
        let json = try await request("listStoragePools")

        guard let response = json["liststoragepoolsresponse"] as? [String: Any],
              let poolList = response["storagepool"] as? [[String: Any]] else {
            return []
        }

        return poolList.map { p in
            StoragePool(
                id: p["id"] as? String ?? "",
                name: p["name"] as? String ?? "",
                state: p["state"] as? String ?? "",
                type: p["type"] as? String ?? "",
                totalBytes: p["disksizetotal"] as? Int64 ?? 0,
                usedBytes: p["disksizeused"] as? Int64 ?? 0,
                allocBytes: p["disksizeallocated"] as? Int64 ?? 0,
                zone: p["zonename"] as? String ?? "",
                cluster: p["clustername"] as? String ?? "",
                profileID: profileID
            )
        }
    }

    // MARK: - Networks

    func listNetworks() async throws -> [HyperNetwork] {
        let json = try await request("listNetworks", params: ["listall": "true"])

        guard let response = json["listnetworksresponse"] as? [String: Any],
              let netList = response["network"] as? [[String: Any]] else {
            return []
        }

        return netList.map { n in
            HyperNetwork(
                id: n["id"] as? String ?? "",
                name: n["name"] as? String ?? "",
                state: n["state"] as? String ?? "",
                type: n["type"] as? String ?? "",
                cidr: n["cidr"] as? String ?? "",
                gateway: n["gateway"] as? String ?? "",
                vlan: n["vlan"] as? String ?? "",
                zone: n["zonename"] as? String ?? "",
                profileID: profileID
            )
        }
    }

    // MARK: - Helpers

    private func parseVMState(_ state: String) -> VMState {
        switch state.lowercased() {
        case "running": return .running
        case "stopped": return .stopped
        case "starting": return .starting
        case "stopping": return .stopping
        case "suspended": return .suspended
        case "error": return .error
        default: return .unknown
        }
    }
}
