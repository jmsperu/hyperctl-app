import SwiftUI
import WebKit

// MARK: - CloudStack Web Console (noVNC)

struct WebConsoleView: NSViewRepresentable {
    let url: URL

    func makeNSView(context: Context) -> WKWebView {
        let config = WKWebViewConfiguration()
        config.preferences.setValue(true, forKey: "allowFileAccessFromFileURLs")
        let webView = WKWebView(frame: .zero, configuration: config)
        webView.navigationDelegate = context.coordinator
        webView.allowsBackForwardNavigationGestures = false
        return webView
    }

    func updateNSView(_ webView: WKWebView, context: Context) {
        if webView.url != url {
            webView.load(URLRequest(url: url))
        }
    }

    func makeCoordinator() -> Coordinator {
        Coordinator()
    }

    class Coordinator: NSObject, WKNavigationDelegate {
        func webView(_ webView: WKWebView, didReceive challenge: URLAuthenticationChallenge, completionHandler: @escaping (URLSession.AuthChallengeDisposition, URLCredential?) -> Void) {
            // Accept self-signed certs for console
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}

// MARK: - SSH Terminal

struct SSHTerminalView: NSViewRepresentable {
    let host: String
    let username: String
    let password: String
    let port: Int
    var initialCommand: String? = nil

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder

        let textView = NSTextView()
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        textView.textColor = .white
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.autoresizingMask = [.width]
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.textContainer?.widthTracksTextView = true
        textView.textContainer?.containerSize = NSSize(width: 0, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        context.coordinator.textView = textView
        context.coordinator.startSSH(host: host, port: port, username: username, password: password, initialCommand: initialCommand)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        // Ensure text view fills the scroll view width
        if let textView = nsView.documentView as? NSTextView {
            textView.minSize = NSSize(width: nsView.contentSize.width, height: 0)
            textView.maxSize = NSSize(width: nsView.contentSize.width, height: CGFloat.greatestFiniteMagnitude)
        }
    }

    func makeCoordinator() -> SSHCoordinator {
        SSHCoordinator()
    }

    class SSHCoordinator {
        var textView: NSTextView?
        var process: Process?
        var inputPipe: Pipe?

        func startSSH(host: String, port: Int, username: String, password: String, initialCommand: String? = nil) {
            let process = Process()
            let outputPipe = Pipe()
            let errorPipe = Pipe()
            let inputPipe = Pipe()

            // Use sshpass if available, otherwise plain ssh
            let sshpassPath = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass"]
                .first { FileManager.default.fileExists(atPath: $0) }

            if let sshpassPath = sshpassPath {
                process.executableURL = URL(fileURLWithPath: sshpassPath)
                process.arguments = ["-p", password, "ssh",
                                     "-tt",
                                     "-o", "StrictHostKeyChecking=no",
                                     "-o", "UserKnownHostsFile=/dev/null",
                                     "-p", "\(port)",
                                     "\(username)@\(host)"]
            } else {
                process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
                process.arguments = ["-tt",
                                     "-o", "StrictHostKeyChecking=no",
                                     "-o", "UserKnownHostsFile=/dev/null",
                                     "-p", "\(port)",
                                     "\(username)@\(host)"]
            }

            process.standardOutput = outputPipe
            process.standardError = errorPipe
            process.standardInput = inputPipe
            process.environment = ProcessInfo.processInfo.environment

            self.process = process
            self.inputPipe = inputPipe

            // Read output
            outputPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self?.appendText(str)
                    }
                }
            }

            errorPipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
                let data = handle.availableData
                if !data.isEmpty, let str = String(data: data, encoding: .utf8) {
                    DispatchQueue.main.async {
                        self?.appendText(str)
                    }
                }
            }

            do {
                try process.run()
                // Send initial command if provided (e.g., virsh console)
                if let cmd = initialCommand {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 1.5) { [weak self] in
                        self?.sendInput(cmd + "\n")
                    }
                }
            } catch {
                appendText("Failed to start SSH: \(error.localizedDescription)\n")
            }
        }

        func appendText(_ text: String) {
            guard let textView = textView else { return }
            let attrStr = NSAttributedString(string: text, attributes: [
                .foregroundColor: NSColor.white,
                .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
            ])
            textView.textStorage?.append(attrStr)
            textView.scrollToEndOfDocument(nil)
        }

        func sendInput(_ text: String) {
            if let data = text.data(using: .utf8) {
                inputPipe?.fileHandleForWriting.write(data)
            }
        }

        deinit {
            process?.terminate()
        }
    }
}

// MARK: - Console Window View

struct VMConsoleView: View {
    @EnvironmentObject var appState: AppState
    let vm: VirtualMachine
    @State private var consoleType: ConsoleType = .vnc
    @State private var sshUser: String = "root"
    @State private var sshPass: String = ""
    @State private var sshPort: String = "22"
    @State private var isConnected = false
    @State private var sshQuickInfo = false

    // KVM host creds for VNC/virsh
    @State private var kvmHost: String = ""
    @State private var kvmUser: String = "xcobean"
    @State private var kvmPass: String = "Wafula2023"
    @State private var vncDisplay: String = ""
    @State private var vncStatus: String = ""
    @State private var isDiscovering = false

    // VNC Tunnel
    @State private var vncTunnelActive = false
    @State private var vncLocalPort = 15900
    @State private var tunnelProcess: Process?

    // QEMU Guest Agent
    @State private var guestInfo: String = ""
    @State private var isLoadingGuest = false

    enum ConsoleType: String, CaseIterable {
        case vnc = "VNC"
        case serial = "Serial"
        case ssh = "SSH"
        case guest = "Guest Agent"
        case web = "Web"
    }

    var body: some View {
        VStack(spacing: 0) {
            // Header
            HStack {
                Image(systemName: vm.state.icon)
                    .foregroundStyle(vm.state.color)
                Text(vm.name)
                    .font(.headline)
                Text("(\(vm.ipAddress.isEmpty ? "no IP" : vm.ipAddress))")
                    .foregroundStyle(.secondary)

                Spacer()

                Picker("Console Type", selection: $consoleType) {
                    ForEach(ConsoleType.allCases, id: \.self) { t in
                        Text(t.rawValue).tag(t)
                    }
                }
                .pickerStyle(.segmented)
                .frame(width: 220)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

            // Console area
            switch consoleType {
            case .vnc:
                vncConsole
            case .serial:
                serialConsole
            case .ssh:
                sshConsole
            case .guest:
                guestAgentView
            case .web:
                webConsole
            }
        }
        .frame(width: 1100, height: 750)
        .onAppear {
            discoverVNCDisplay()
        }
    }

    // MARK: - VNC Console

    @ViewBuilder
    private var vncConsole: some View {
        if isDiscovering {
            VStack {
                ProgressView("Discovering VNC display...")
                Text("Connecting to KVM host to find VM...")
                    .foregroundStyle(.secondary)
                    .font(.caption)
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
        } else if !vncDisplay.isEmpty {
            VStack(spacing: 0) {
                Spacer()

                Image(systemName: "display")
                    .font(.system(size: 64))
                    .foregroundStyle(.green)

                Text("VNC Display Found")
                    .font(.title2.bold())
                    .padding(.top, 8)

                let parts = vncDisplay.split(separator: ":")
                let host = String(parts.first ?? "")
                let remotePort = parts.count == 2 ? 5900 + (Int(parts[1]) ?? 0) : 5900

                Text("\(host):\(remotePort)")
                    .font(.title3.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                // Direct connection button
                Button {
                    openScreenSharing(host: host, port: remotePort)
                } label: {
                    Label("Open in Screen Sharing", systemImage: "display")
                }
                .buttonStyle(.borderedProminent)
                .controlSize(.large)
                .padding(.top, 16)

                Text("Opens macOS Screen Sharing to the VM's VNC display")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                    .padding(.top, 8)

                Spacer()
            }
        } else {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "display")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("VNC Console")
                    .font(.title3)

                if !vncStatus.isEmpty {
                    Text(vncStatus)
                        .foregroundStyle(.orange)
                        .font(.caption)
                }

                Text("Enter KVM host credentials to discover VNC display")
                    .foregroundStyle(.secondary)

                Form {
                    TextField("KVM Host IP", text: $kvmHost, prompt: Text("172.16.3.109"))
                        .frame(width: 250)
                    TextField("Username", text: $kvmUser)
                        .frame(width: 250)
                    SecureField("Password", text: $kvmPass)
                        .frame(width: 250)
                }
                .formStyle(.grouped)
                .frame(width: 350)

                Button("Discover VNC") {
                    discoverVNCDisplay()
                }
                .buttonStyle(.borderedProminent)
                .disabled(kvmHost.isEmpty)

                Spacer()
            }
        }
    }

    // MARK: - Serial Console (virsh console via SSH)

    @ViewBuilder
    private var serialConsole: some View {
        if kvmHost.isEmpty {
            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Serial Console (virsh console)")
                    .font(.title3)
                Text("Requires SSH access to the KVM host")
                    .foregroundStyle(.secondary)

                Form {
                    TextField("KVM Host IP", text: $kvmHost, prompt: Text("172.16.3.109"))
                        .frame(width: 250)
                    TextField("Username", text: $kvmUser)
                        .frame(width: 250)
                    SecureField("Password", text: $kvmPass)
                        .frame(width: 250)
                }
                .formStyle(.grouped)
                .frame(width: 350)

                Button("Connect") {
                    isConnected = true
                }
                .buttonStyle(.borderedProminent)
                .disabled(kvmHost.isEmpty)

                Spacer()
            }
        } else {
            // SSH to KVM host and run virsh console
            SSHTerminalView(
                host: kvmHost,
                username: kvmUser,
                password: kvmPass,
                port: 22,
                initialCommand: vm.instanceName.isEmpty ? nil : "virsh -c qemu:///system console \(vm.instanceName)"
            )
        }
    }

    // MARK: - VNC Discovery

    private func discoverVNCDisplay() {
        // Try to figure out which host this VM is on
        if kvmHost.isEmpty {
            // Map hostname to IP
            let hostMap: [String: String] = [
                "xcbn-paix-cmpt-04": "172.16.3.106",
                "xcobean-paix-kvm-host-5": "172.16.3.109",
                "xcobean-paix-kvm-host-6": "172.16.3.111",
                "xcobean-paix-ceph2-node1": "172.16.3.105",
                "xcbn-krn01": "172.16.3.107",
            ]
            if let ip = hostMap[vm.hostName] {
                kvmHost = ip
            } else if !vm.hostName.isEmpty {
                // Try the hostname directly
                kvmHost = vm.hostName
            } else {
                vncStatus = "VM has no host assigned (stopped?)"
                return
            }
        }

        guard !kvmHost.isEmpty else { return }
        isDiscovering = true
        vncStatus = ""

        let instanceName = vm.instanceName
        Task.detached { [kvmHost, kvmUser, kvmPass, instanceName] in
            let sshpassPath = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass"]
                .first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/sshpass"

            // Direct lookup: get VNC display for this specific VM
            let cmd = instanceName.isEmpty
                ? "virsh -c qemu:///system list --name | head -1 | xargs -I{} virsh -c qemu:///system vncdisplay {}"
                : "virsh -c qemu:///system vncdisplay '\(instanceName)'"

            let process = Process()
            let pipe = Pipe()
            process.executableURL = URL(fileURLWithPath: sshpassPath)
            process.arguments = ["-p", kvmPass, "ssh",
                                 "-o", "StrictHostKeyChecking=no",
                                 "-o", "ConnectTimeout=5",
                                 "\(kvmUser)@\(kvmHost)", cmd]
            process.standardOutput = pipe
            process.standardError = pipe

            do {
                try process.run()
                process.waitUntilExit()

                let data = pipe.fileHandleForReading.readDataToEndOfFile()
                let rawOutput = String(data: data, encoding: .utf8) ?? ""
                // Filter out SSH noise (setlocale warnings, etc.)
                let display = rawOutput
                    .split(separator: "\n")
                    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
                    .filter { !$0.isEmpty && !$0.contains("setlocale") && !$0.contains("warning") && !$0.contains("Warning") && $0.contains(":") }
                    .last ?? ""

                await MainActor.run {
                    if !display.isEmpty && display.contains(":") {
                        if display.hasPrefix(":") {
                            self.vncDisplay = "\(kvmHost)\(display)"
                        } else {
                            self.vncDisplay = display
                        }
                    } else {
                        self.vncStatus = "VNC not available for \(instanceName.isEmpty ? "this VM" : instanceName)\nResponse: \(display)"
                    }
                    self.isDiscovering = false
                }
            } catch {
                await MainActor.run {
                    self.vncStatus = "SSH failed: \(error.localizedDescription)"
                    self.isDiscovering = false
                }
            }
        }
    }

    // MARK: - QEMU Guest Agent

    @ViewBuilder
    private var guestAgentView: some View {
        VStack(spacing: 0) {
            // Toolbar
            HStack {
                Text("QEMU Guest Agent")
                    .font(.headline)
                Spacer()

                Button("Refresh") { loadGuestInfo() }
                    .buttonStyle(.bordered)
                    .disabled(isLoadingGuest)

                Button("Run Command...") { showGuestCommand = true }
                    .buttonStyle(.bordered)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)
            .background(.bar)

            Divider()

            if isLoadingGuest {
                VStack {
                    Spacer()
                    ProgressView("Querying guest agent...")
                    Spacer()
                }
            } else if guestInfo.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("QEMU Guest Agent")
                        .font(.title3)
                    Text("Query VM info and run commands via the QEMU guest agent.\nNo SSH credentials needed — uses the hypervisor's agent channel.")
                        .foregroundStyle(.secondary)
                        .multilineTextAlignment(.center)

                    Button("Get System Info") { loadGuestInfo() }
                        .buttonStyle(.borderedProminent)
                        .controlSize(.large)

                    Text("Requires qemu-guest-agent installed in the VM")
                        .font(.caption)
                        .foregroundStyle(.tertiary)
                    Spacer()
                }
            } else {
                ScrollView {
                    Text(guestInfo)
                        .font(.system(.body, design: .monospaced))
                        .textSelection(.enabled)
                        .padding()
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .background(Color(nsColor: NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)))
            }
        }
        .sheet(isPresented: $showGuestCommand) {
            guestCommandSheet
        }
    }

    @State private var showGuestCommand = false
    @State private var guestCommand = ""

    private var guestCommandSheet: some View {
        VStack(spacing: 16) {
            Text("Run Guest Agent Command").font(.title3.bold())
            Text("Execute a command inside the VM via QEMU guest agent")
                .font(.caption).foregroundStyle(.secondary)

            TextField("Command", text: $guestCommand, prompt: Text("e.g. cat /etc/hostname"))
                .frame(width: 400)

            HStack {
                Button("Cancel") { showGuestCommand = false }
                    .keyboardShortcut(.cancelAction)
                Spacer()
                Button("Execute") {
                    runGuestCommand(guestCommand)
                    showGuestCommand = false
                }
                .buttonStyle(.borderedProminent)
                .disabled(guestCommand.isEmpty)
            }
        }
        .padding()
        .frame(width: 500)
    }

    private func loadGuestInfo() {
        if kvmHost.isEmpty {
            let hostMap: [String: String] = [
                "xcbn-paix-cmpt-04": "172.16.3.106",
                "xcobean-paix-kvm-host-5": "172.16.3.109",
                "xcobean-paix-kvm-host-6": "172.16.3.111",
                "xcobean-paix-ceph2-node1": "172.16.3.105",
                "xcbn-krn01": "172.16.3.107",
            ]
            if let ip = hostMap[vm.hostName] {
                kvmHost = ip
            } else {
                guestInfo = "Error: Cannot determine KVM host for this VM.\nVM host: \(vm.hostName)"
                return
            }
        }

        isLoadingGuest = true
        guestInfo = ""

        Task.detached { [kvmHost, kvmUser, kvmPass, vm] in
            let vmName = await Self.findVirshName(host: kvmHost, user: kvmUser, pass: kvmPass, vmIP: vm.ipAddress)

            let commands = [
                ("hostname", "guest-exec", "hostname"),
                ("OS Info", "guest-exec", "cat /etc/os-release"),
                ("Uptime", "guest-exec", "uptime"),
                ("Memory", "guest-exec", "free -h"),
                ("Disk", "guest-exec", "df -h"),
                ("CPU", "guest-exec", "nproc"),
                ("Network", "guest-exec", "ip -br addr"),
                ("Processes", "guest-exec", "ps aux --sort=-%mem | head -15"),
            ]

            var output = "═══ Guest Agent Info for \(vm.name) ═══\n"
            output += "KVM Host: \(kvmHost)\n"
            output += "virsh name: \(vmName)\n\n"

            for (label, _, cmd) in commands {
                let result = await Self.runOnGuest(host: kvmHost, user: kvmUser, pass: kvmPass, vmName: vmName, command: cmd)
                output += "── \(label) ──\n\(result)\n\n"
            }

            await MainActor.run {
                self.guestInfo = output
                self.isLoadingGuest = false
            }
        }
    }

    private func runGuestCommand(_ command: String) {
        guard !kvmHost.isEmpty else { return }
        isLoadingGuest = true

        Task.detached { [kvmHost, kvmUser, kvmPass, vm] in
            let vmName = await Self.findVirshName(host: kvmHost, user: kvmUser, pass: kvmPass, vmIP: vm.ipAddress)
            let result = await Self.runOnGuest(host: kvmHost, user: kvmUser, pass: kvmPass, vmName: vmName, command: command)

            await MainActor.run {
                self.guestInfo += "\n── \(command) ──\n\(result)\n"
                self.isLoadingGuest = false
            }
        }
    }

    // Run a command inside a VM via QEMU guest agent (through the KVM host)
    private nonisolated static func runOnGuest(host: String, user: String, pass: String, vmName: String, command: String) async -> String {
        let sshpassPath = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/sshpass"

        // Use virsh qemu-agent-command to execute via guest agent
        let script = """
        # Try guest-exec first (structured)
        RESULT=$(virsh -c qemu:///system qemu-agent-command '\(vmName)' '{"execute":"guest-exec","arguments":{"path":"/bin/sh","arg":["-c","\(command.replacingOccurrences(of: "\"", with: "\\\\\""))"],"capture-output":true}}' 2>/dev/null)
        if [ $? -eq 0 ]; then
            PID=$(echo "$RESULT" | python3 -c "import sys,json; print(json.load(sys.stdin)['return']['pid'])" 2>/dev/null)
            if [ -n "$PID" ]; then
                sleep 1
                STATUS=$(virsh -c qemu:///system qemu-agent-command '\(vmName)' "{\\\"execute\\\":\\\"guest-exec-status\\\",\\\"arguments\\\":{\\\"pid\\\":$PID}}" 2>/dev/null)
                echo "$STATUS" | python3 -c "
        import sys,json,base64
        d=json.load(sys.stdin)['return']
        if 'out-data' in d: print(base64.b64decode(d['out-data']).decode('utf-8',errors='replace'),end='')
        if 'err-data' in d: print(base64.b64decode(d['err-data']).decode('utf-8',errors='replace'),end='')
        " 2>/dev/null
            fi
        else
            echo "Guest agent not available or command failed"
        fi
        """

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: sshpassPath)
        process.arguments = ["-p", pass, "ssh", "-tt",
                             "-o", "StrictHostKeyChecking=no",
                             "-o", "ConnectTimeout=5",
                             "\(user)@\(host)", script]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            return String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? "No output"
        } catch {
            return "Error: \(error.localizedDescription)"
        }
    }

    // Find the virsh domain name for a VM by matching its IP
    private nonisolated static func findVirshName(host: String, user: String, pass: String, vmIP: String) async -> String {
        let sshpassPath = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/sshpass"

        let script = """
        for vm in $(virsh -c qemu:///system list --name 2>/dev/null); do
            IP=$(virsh -c qemu:///system qemu-agent-command "$vm" '{"execute":"guest-network-get-interfaces"}' 2>/dev/null | python3 -c "
        import sys,json
        try:
            d=json.load(sys.stdin)
            for iface in d['return']:
                for addr in iface.get('ip-addresses',[]):
                    if addr['ip-address-type']=='ipv4' and addr['ip-address']!=('127.0.0.1'):
                        print(addr['ip-address'])
        except: pass
        " 2>/dev/null)
            if echo "$IP" | grep -q "\(vmIP)"; then
                echo "$vm"
                exit 0
            fi
        done
        """

        let process = Process()
        let pipe = Pipe()
        process.executableURL = URL(fileURLWithPath: sshpassPath)
        process.arguments = ["-p", pass, "ssh", "-tt",
                             "-o", "StrictHostKeyChecking=no",
                             "-o", "ConnectTimeout=10",
                             "\(user)@\(host)", script]
        process.standardOutput = pipe
        process.standardError = pipe

        do {
            try process.run()
            process.waitUntilExit()
            let data = pipe.fileHandleForReading.readDataToEndOfFile()
            let name = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
            return name.isEmpty ? "unknown" : name
        } catch {
            return "unknown"
        }
    }

    // MARK: - Screen Sharing

    private func openScreenSharing(host: String, port: Int) {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/open")
        process.arguments = ["vnc://\(host):\(port)"]
        try? process.run()
    }

    // MARK: - VNC Tunnel

    private func openVNCTunnel(host: String, remotePort: Int) {
        vncLocalPort = 15900 + Int.random(in: 0...99)

        // Use /usr/bin/ssh directly via a shell command with sshpass
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c",
            "sshpass -p '\(kvmPass.replacingOccurrences(of: "'", with: "'\\''"))' ssh -N -L \(vncLocalPort):\(host):\(remotePort) -o StrictHostKeyChecking=no -o UserKnownHostsFile=/dev/null -o ExitOnForwardFailure=yes \(kvmUser)@\(kvmHost)"
        ]

        do {
            try process.run()
            tunnelProcess = process
            vncTunnelActive = true

            // Wait for tunnel to establish, then open Screen Sharing
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                self.openScreenSharing(host: "localhost", port: self.vncLocalPort)
            }
        } catch {
            vncStatus = "Failed to create tunnel: \(error.localizedDescription)"
        }
    }

    private func closeTunnel() {
        // Kill the forked SSH tunnel by finding the process using the local port
        let killProcess = Process()
        killProcess.executableURL = URL(fileURLWithPath: "/usr/bin/pkill")
        killProcess.arguments = ["-f", "ssh.*\(vncLocalPort):127.0.0.1"]
        try? killProcess.run()
        killProcess.waitUntilExit()
        tunnelProcess?.terminate()
        tunnelProcess = nil
        vncTunnelActive = false
    }

    @ViewBuilder
    private var webConsole: some View {
        if let profile = appState.activeProfile {
            let base = profile.url.trimmingCharacters(in: .init(charactersIn: "/"))
            let consoleURL = base.hasSuffix("/client")
                ? "\(base)/console?cmd=access&vm=\(vm.id)"
                : "\(base)/client/console?cmd=access&vm=\(vm.id)"

            VStack(spacing: 16) {
                Spacer()
                Image(systemName: "globe")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)
                Text("Web Console requires browser authentication")
                    .font(.title3)
                Text("CloudStack noVNC console needs an active browser session.\nClick below to open in your browser.")
                    .foregroundStyle(.secondary)
                    .multilineTextAlignment(.center)

                if let url = URL(string: consoleURL) {
                    Button("Open Console in Browser") {
                        NSWorkspace.shared.open(url)
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.large)
                }

                Text("Tip: Use VNC Console or Serial Console tabs for in-app access")
                    .font(.caption)
                    .foregroundStyle(.tertiary)
                Spacer()
            }
        } else {
            Text("No profile selected")
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var sshConsole: some View {
        if isConnected {
            SSHTerminalView(
                host: vm.ipAddress,
                username: sshUser,
                password: sshPass,
                port: Int(sshPort) ?? 22,
                initialCommand: sshQuickInfo ? "echo '═══ System Info ═══' && hostname && echo '' && echo '── OS ──' && cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 && echo '' && echo '── Uptime ──' && uptime && echo '' && echo '── Memory ──' && free -h 2>/dev/null && echo '' && echo '── Disk ──' && df -h | grep -v tmpfs && echo '' && echo '── CPU ──' && nproc && echo '' && echo '── Network ──' && ip -br addr 2>/dev/null || ifconfig 2>/dev/null && echo '' && echo '── Top Processes ──' && ps aux --sort=-%mem 2>/dev/null | head -10" : nil
            )
        } else {
            VStack(spacing: 16) {
                Spacer()

                Image(systemName: "terminal")
                    .font(.system(size: 48))
                    .foregroundStyle(.secondary)

                Text("SSH to \(vm.ipAddress.isEmpty ? vm.name : vm.ipAddress)")
                    .font(.title3)

                Form {
                    TextField("Username", text: $sshUser)
                        .frame(width: 250)
                    SecureField("Password", text: $sshPass)
                        .frame(width: 250)
                    TextField("Port", text: $sshPort)
                        .frame(width: 100)
                }
                .formStyle(.grouped)
                .frame(width: 350)

                HStack(spacing: 12) {
                    Button("Connect") {
                        isConnected = true
                    }
                    .buttonStyle(.borderedProminent)
                    .disabled(vm.ipAddress.isEmpty || sshUser.isEmpty || sshPass.isEmpty)
                    .keyboardShortcut(.defaultAction)

                    Button("Quick Info") {
                        sshQuickInfo = true
                        isConnected = true
                    }
                    .buttonStyle(.bordered)
                    .disabled(vm.ipAddress.isEmpty || sshUser.isEmpty || sshPass.isEmpty)
                }

                if vm.ipAddress.isEmpty {
                    Text("VM has no IP address assigned")
                        .foregroundStyle(.red)
                        .font(.caption)
                }

                Spacer()
            }
        }
    }
}
