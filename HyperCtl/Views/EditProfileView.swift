import SwiftUI

struct EditProfileView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss

    let profile: HyperProfile

    @State private var name: String = ""
    @State private var url: String = ""
    @State private var apiKey: String = ""
    @State private var apiSecret: String = ""
    @State private var username: String = ""
    @State private var password: String = ""
    @State private var insecure: Bool = false
    @State private var showSecrets: Bool = false

    @State private var isTesting = false
    @State private var testResult: TestResult?

    enum TestResult {
        case success(String)
        case failure(String)
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: profile.type.icon)
                    .foregroundStyle(profile.type.color)
                    .font(.title2)
                Text("Edit Profile — \(profile.type.rawValue)")
                    .font(.title2.bold())
                Spacer()
                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
            }
            .padding()

            Divider()

            Form {
                Section("General") {
                    TextField("Name", text: $name)
                    TextField("URL", text: $url)
                        .font(.body.monospaced())
                }

                Section("Credentials") {
                    switch profile.type {
                    case .cloudstack:
                        if !apiKey.isEmpty {
                            LabeledContent("API Key") {
                                HStack {
                                    if showSecrets {
                                        Text(apiKey)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    } else {
                                        Text(maskedString(apiKey))
                                            .font(.caption.monospaced())
                                    }
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(apiKey, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                            LabeledContent("API Secret") {
                                HStack {
                                    if showSecrets {
                                        Text(apiSecret)
                                            .font(.caption.monospaced())
                                            .textSelection(.enabled)
                                    } else {
                                        Text(maskedString(apiSecret))
                                            .font(.caption.monospaced())
                                    }
                                    Button {
                                        NSPasteboard.general.clearContents()
                                        NSPasteboard.general.setString(apiSecret, forType: .string)
                                    } label: {
                                        Image(systemName: "doc.on.doc")
                                    }
                                    .buttonStyle(.borderless)
                                }
                            }
                        }

                        if !username.isEmpty {
                            TextField("Username", text: $username)
                            SecureField("Password", text: $password)
                        }

                        if apiKey.isEmpty && username.isEmpty {
                            Text("No credentials saved")
                                .foregroundStyle(.secondary)
                            TextField("API Key", text: $apiKey)
                            SecureField("API Secret", text: $apiSecret)
                            Text("— or —").foregroundStyle(.secondary)
                            TextField("Username", text: $username)
                            SecureField("Password", text: $password)
                        }

                    case .xcpng, .hyperv:
                        TextField("Username", text: $username)
                        SecureField("Password", text: $password)
                        if showSecrets && !password.isEmpty {
                            LabeledContent("Current Password") {
                                Text(password)
                                    .font(.caption.monospaced())
                                    .textSelection(.enabled)
                            }
                        }
                    }

                    Toggle("Show secrets", isOn: $showSecrets)
                }

                Section("Security") {
                    Toggle("Allow insecure TLS", isOn: $insecure)
                }

                // Test result
                if let result = testResult {
                    Section("Connection Test") {
                        switch result {
                        case .success(let msg):
                            Label(msg, systemImage: "checkmark.circle.fill")
                                .foregroundStyle(.green)
                        case .failure(let msg):
                            VStack(alignment: .leading, spacing: 4) {
                                Label("Connection Failed", systemImage: "xmark.circle.fill")
                                    .foregroundStyle(.red)
                                Text(msg)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .textSelection(.enabled)
                            }
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
                .disabled(isTesting)

                if isTesting {
                    ProgressView()
                        .controlSize(.small)
                }

                Spacer()

                Button("Cancel") {
                    dismiss()
                }
                .keyboardShortcut(.cancelAction)

                Button("Save Changes") {
                    saveChanges()
                }
                .buttonStyle(.borderedProminent)
                .keyboardShortcut(.defaultAction)
            }
            .padding()
        }
        .frame(width: 550, height: 580)
        .onAppear {
            name = profile.name
            url = profile.url
            apiKey = profile.apiKey
            apiSecret = profile.apiSecret
            username = profile.username
            password = profile.password
            insecure = profile.insecure
        }
    }

    private func maskedString(_ s: String) -> String {
        guard s.count > 8 else { return String(repeating: "•", count: s.count) }
        let prefix = String(s.prefix(4))
        let suffix = String(s.suffix(4))
        return "\(prefix)•••••••\(suffix)"
    }

    private func testConnection() {
        isTesting = true
        testResult = nil

        let updatedProfile = buildProfile()

        Task {
            do {
                switch updatedProfile.type {
                case .cloudstack:
                    let client = CloudStackClient(profile: updatedProfile)
                    let vms = try await client.listVMs()
                    testResult = .success("Connected! Found \(vms.count) VMs.")
                case .xcpng:
                    let client = XCPngClient(profile: updatedProfile)
                    try await client.login()
                    let vms = try await client.listVMs()
                    await client.logout()
                    testResult = .success("Connected! Found \(vms.count) VMs.")
                case .hyperv:
                    testResult = .failure("Hyper-V WinRM not yet implemented.")
                }
            } catch {
                testResult = .failure(error.localizedDescription)
            }
            isTesting = false
        }
    }

    private func buildProfile() -> HyperProfile {
        var p = profile
        p.name = name
        p.url = url
        p.apiKey = apiKey
        p.apiSecret = apiSecret
        p.username = username
        p.password = password
        p.insecure = insecure
        return p
    }

    private func saveChanges() {
        let updated = buildProfile()
        appState.updateProfile(updated)
        dismiss()
    }
}
