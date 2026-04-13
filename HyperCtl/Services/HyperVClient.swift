import Foundation

actor HyperVClient {
    private let host: String
    private let username: String
    private let password: String
    private let profileID: UUID

    init(profile: HyperProfile) {
        self.host = profile.url
        self.username = profile.username
        self.password = profile.password
        self.profileID = profile.id
    }

    // MARK: - VM Operations (WinRM stub)

    func listVMs() async throws -> [VirtualMachine] {
        // WinRM integration requires WS-Management protocol.
        // This is a stub for future implementation.
        return []
    }

    func listHosts() async throws -> [HyperHost] {
        return []
    }

    func startVM(name: String) async throws {
        throw HyperCtlError.apiError("Hyper-V WinRM support not yet implemented")
    }

    func stopVM(name: String) async throws {
        throw HyperCtlError.apiError("Hyper-V WinRM support not yet implemented")
    }

    func rebootVM(name: String) async throws {
        throw HyperCtlError.apiError("Hyper-V WinRM support not yet implemented")
    }
}
