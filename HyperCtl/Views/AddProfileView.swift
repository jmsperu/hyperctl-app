import SwiftUI

struct AddProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var type: HypervisorType = .cloudstack
    @State private var url = ""
    @State private var apiKey = ""
    @State private var apiSecret = ""
    @State private var username = ""
    @State private var password = ""
    @State private var insecure = false
    @State private var usePasswordAuth = false

    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    private var isValid: Bool {
        guard !name.isEmpty, !url.isEmpty else { return false }
        switch type {
        case .cloudstack:
            if usePasswordAuth {
                return !username.isEmpty && !password.isEmpty
            }
            return !apiKey.isEmpty && !apiSecret.isEmpty
        case .xcpng, .hyperv:
            return !username.isEmpty && !password.isEmpty
        }
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Text("Add Connection")
                    .font(.title2.bold())
                Spacer()
                Button {
                    dismiss()
                } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            // Form
            Form {
                Section("General") {
                    TextField("Name", text: $name, prompt: Text("My CloudStack"))
                    Picker("Type", selection: $type) {
                        ForEach(HypervisorType.allCases, id: \.self) { t in
                            Label(t.rawValue, systemImage: t.icon)
                                .tag(t)
                        }
                    }
                    TextField("URL", text: $url, prompt: Text(urlPlaceholder))
                }

                switch type {
                case .cloudstack:
                    Section("CloudStack Authentication") {
                        Picker("Auth Method", selection: $usePasswordAuth) {
                            Text("API Key").tag(false)
                            Text("Username / Password").tag(true)
                        }
                        .pickerStyle(.segmented)

                        if usePasswordAuth {
                            TextField("Username", text: $username, prompt: Text("admin"))
                            SecureField("Password", text: $password)
                        } else {
                            TextField("API Key", text: $apiKey)
                            SecureField("API Secret", text: $apiSecret)
                        }
                    }
                case .xcpng:
                    Section("XCP-ng Credentials") {
                        TextField("Username", text: $username, prompt: Text("root"))
                        SecureField("Password", text: $password)
                    }
                case .hyperv:
                    Section("Hyper-V Credentials") {
                        TextField("Username", text: $username, prompt: Text("Administrator"))
                        SecureField("Password", text: $password)
                    }
                }

                Section("Security") {
                    Toggle("Allow insecure TLS (skip certificate verification)", isOn: $insecure)
                }

                // Test result
                if let result = testResult {
                    Section {
                        switch result {
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            Label(msg, systemImage: "xmark.circle.fill")
                                .foregroundStyle(.red)
                        }
                    }
                }
            }
            .formStyle(.grouped)

            Divider()

            // Actions
            HStack {
                Button("Test Connection") {
                    testConnection()
                }
                .disabled(!isValid || isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save") {
                    saveProfile()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
                .disabled(!isValid)
            }
            .padding()
        }
        .frame(width: 500, height: 520)
    }

    private var urlPlaceholder: String {
        switch type {
        case .cloudstack: return "http://cloudstack.example.com:8080"
        case .xcpng: return "https://xcpng-host.example.com"
        case .hyperv: return "https://hyperv-host.example.com:5986"
        }
    }

    private func buildProfile() -> HyperProfile {
        HyperProfile(
            name: name,
            type: type,
            url: url,
            apiKey: apiKey,
            apiSecret: apiSecret,
            username: username,
            password: password,
            insecure: insecure
        )
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        let profile = buildProfile()

        Task {
            do {
                switch profile.type {
                case .cloudstack:
                    let client = CloudStackClient(profile: profile)
                    let vms = try await client.listVMs()
                    testResult = .success("Connected. Found \(vms.count) VMs.")
                case .xcpng:
                    let client = XCPngClient(profile: profile)
                    try await client.login()
                    let vms = try await client.listVMs()
                    await client.logout()
                    testResult = .success("Connected. Found \(vms.count) VMs.")
                case .hyperv:
                    testResult = .failure("Hyper-V WinRM support not yet implemented.")
                }
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func saveProfile() {
        let profile = buildProfile()
        appState.addProfile(profile)
        dismiss()
    }
}
