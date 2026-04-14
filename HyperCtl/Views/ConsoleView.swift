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
            if challenge.protectionSpace.authenticationMethod == NSURLAuthenticationMethodServerTrust,
               let trust = challenge.protectionSpace.serverTrust {
                completionHandler(.useCredential, URLCredential(trust: trust))
            } else {
                completionHandler(.performDefaultHandling, nil)
            }
        }
    }
}

// MARK: - Interactive Terminal Text View

class InteractiveTextView: NSTextView {
    var inputHandler: ((String) -> Void)?
    var keyMonitor: Any?

    override var acceptsFirstResponder: Bool { true }
    override var canBecomeKeyView: Bool { true }

    override func viewDidMoveToWindow() {
        super.viewDidMoveToWindow()
        if window != nil {
            setupKeyMonitor()
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.3) { [weak self] in
                self?.window?.makeFirstResponder(self)
            }
        } else {
            removeKeyMonitor()
        }
    }

    private func setupKeyMonitor() {
        removeKeyMonitor()
        keyMonitor = NSEvent.addLocalMonitorForEvents(matching: [.keyDown]) { [weak self] event in
            guard let self = self, self.window != nil, self.window == event.window else {
                return event
            }
            self.handleKeyEvent(event)
            return nil // consume the event
        }
    }

    private func removeKeyMonitor() {
        if let monitor = keyMonitor {
            NSEvent.removeMonitor(monitor)
            keyMonitor = nil
        }
    }

    private func handleKeyEvent(_ event: NSEvent) {
        // Handle Ctrl+key combinations
        if event.modifierFlags.contains(.control), let chars = event.charactersIgnoringModifiers {
            for ch in chars.unicodeScalars {
                let code = ch.value
                if code >= 0x61 && code <= 0x7A {
                    let ctrlChar = String(UnicodeScalar(code - 0x60)!)
                    inputHandler?(ctrlChar)
                    return
                }
            }
        }
        // Handle Cmd+V paste
        if event.modifierFlags.contains(.command), event.charactersIgnoringModifiers == "v" {
            if let str = NSPasteboard.general.string(forType: .string) {
                inputHandler?(str)
            }
            return
        }
        // Arrow keys (no characters, just key codes)
        switch event.keyCode {
        case 126: inputHandler?("\u{1b}[A"); return // up
        case 125: inputHandler?("\u{1b}[B"); return // down
        case 124: inputHandler?("\u{1b}[C"); return // right
        case 123: inputHandler?("\u{1b}[D"); return // left
        default: break
        }
        // Regular characters
        if let chars = event.characters, !chars.isEmpty {
            inputHandler?(chars)
        }
    }

    override func becomeFirstResponder() -> Bool {
        return true
    }

    override func mouseDown(with event: NSEvent) {
        window?.makeFirstResponder(self)
        super.mouseDown(with: event)
    }

    override func keyDown(with event: NSEvent) {
        handleKeyEvent(event)
    }

    override func insertText(_ string: Any, replacementRange: NSRange) {
        if let str = string as? String {
            inputHandler?(str)
        }
    }

    override func insertNewline(_ sender: Any?) {
        inputHandler?("\n")
    }

    override func insertTab(_ sender: Any?) {
        inputHandler?("\t")
    }

    override func deleteBackward(_ sender: Any?) {
        inputHandler?("\u{7f}")
    }

    override func moveUp(_ sender: Any?) {
        inputHandler?("\u{1b}[A")
    }

    override func moveDown(_ sender: Any?) {
        inputHandler?("\u{1b}[B")
    }

    override func moveRight(_ sender: Any?) {
        inputHandler?("\u{1b}[C")
    }

    override func moveLeft(_ sender: Any?) {
        inputHandler?("\u{1b}[D")
    }

    override func cancelOperation(_ sender: Any?) {
        inputHandler?("\u{03}")
    }

    override func paste(_ sender: Any?) {
        if let str = NSPasteboard.general.string(forType: .string) {
            inputHandler?(str)
        }
    }

    deinit {
        removeKeyMonitor()
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
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)

        let contentSize = scrollView.contentSize

        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true
        textContainer.lineFragmentPadding = 4

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = InteractiveTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isEditable = true
        textView.isSelectable = true
        textView.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        textView.insertionPointColor = .white
        textView.textColor = .white
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isAutomaticQuoteSubstitutionEnabled = false
        textView.isAutomaticDashSubstitutionEnabled = false
        textView.isAutomaticTextReplacementEnabled = false
        textView.isAutomaticSpellingCorrectionEnabled = false
        textView.isAutomaticTextCompletionEnabled = false
        textView.isRichText = false
        textView.allowsUndo = false
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 4, height: 4)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView

        context.coordinator.textView = textView
        textView.inputHandler = { [weak coordinator = context.coordinator] text in
            NSLog("[HyperCtl] KEY INPUT: %d bytes: %@", text.count, text.debugDescription)
            coordinator?.sendInput(text)
        }
        context.coordinator.startSSH(host: host, port: port, username: username, password: password, initialCommand: initialCommand)

        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        if let textView = nsView.documentView as? NSTextView {
            let width = nsView.contentSize.width
            textView.minSize = NSSize(width: width, height: nsView.contentSize.height)
            textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
            textView.frame.size.width = width
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
            NSLog("[HyperCtl] sendInput called: %d bytes, pipe exists: %@", text.count, inputPipe != nil ? "YES" : "NO")
            if let data = text.data(using: .utf8) {
                inputPipe?.fileHandleForWriting.write(data)
            }
        }

        deinit {
            process?.terminate()
        }
    }
}

// MARK: - Guest Agent Output View

struct GuestOutputView: NSViewRepresentable {
    let text: String

    func makeNSView(context: Context) -> NSScrollView {
        let scrollView = NSScrollView()
        scrollView.hasVerticalScroller = true
        scrollView.hasHorizontalScroller = false
        scrollView.autoresizingMask = [.width, .height]
        scrollView.borderType = .noBorder
        scrollView.drawsBackground = true
        scrollView.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)

        let contentSize = scrollView.contentSize
        let textContainer = NSTextContainer(size: NSSize(width: contentSize.width, height: CGFloat.greatestFiniteMagnitude))
        textContainer.widthTracksTextView = true

        let layoutManager = NSLayoutManager()
        layoutManager.addTextContainer(textContainer)

        let textStorage = NSTextStorage()
        textStorage.addLayoutManager(layoutManager)

        let textView = NSTextView(frame: NSRect(origin: .zero, size: contentSize), textContainer: textContainer)
        textView.isEditable = false
        textView.isSelectable = true
        textView.backgroundColor = NSColor(red: 0.1, green: 0.1, blue: 0.12, alpha: 1.0)
        textView.textColor = .white
        textView.font = NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        textView.isVerticallyResizable = true
        textView.isHorizontallyResizable = false
        textView.autoresizingMask = [.width]
        textView.textContainerInset = NSSize(width: 8, height: 8)
        textView.minSize = NSSize(width: 0, height: contentSize.height)
        textView.maxSize = NSSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)

        scrollView.documentView = textView
        return scrollView
    }

    func updateNSView(_ nsView: NSScrollView, context: Context) {
        guard let textView = nsView.documentView as? NSTextView else { return }
        let width = nsView.contentSize.width
        textView.minSize = NSSize(width: width, height: nsView.contentSize.height)
        textView.maxSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.textContainer?.containerSize = NSSize(width: width, height: CGFloat.greatestFiniteMagnitude)
        textView.frame.size.width = width

        let attrStr = NSAttributedString(string: text, attributes: [
            .foregroundColor: NSColor.white,
            .font: NSFont.monospacedSystemFont(ofSize: 13, weight: .regular)
        ])
        textView.textStorage?.setAttributedString(attrStr)
    }
}

// MARK: - Console Window View

struct VMConsoleView: View {
    @EnvironmentObject var appState: AppState
    @Environment(\.dismiss) private var dismiss
    let vm: VirtualMachine
    @State private var consoleType: ConsoleType = .vnc
    @State private var sshUser: String = "root"
    @State private var sshPass: String = ""
    @State private var sshPort: String = "22"
    @State private var isConnected = false
    @State private var sshQuickInfo = false

    @State private var kvmHost: String = ""
    @State private var kvmUser: String = "xcobean"
    @State private var kvmPass: String = "Wafula2023"
    @State private var vncDisplay: String = ""
    @State private var vncStatus: String = ""
    @State private var isDiscovering = false

    @State private var guestInfo: String = ""
    @State private var isLoadingGuest = false
    @State private var showGuestCommand = false
    @State private var guestCommand = ""

    enum ConsoleType: String, CaseIterable {
        case vnc = "VNC"
        case serial = "Serial"
        case ssh = "SSH"
        case guest = "Guest Agent"
        case web = "Web"
    }

    var body: some View {
        VStack(spacing: 0) {
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
                .frame(width: 340)

                Button { dismiss() } label: {
                    Image(systemName: "xmark.circle.fill")
                        .font(.title2)
                        .foregroundStyle(.secondary)
                }
                .buttonStyle(.plain)
                .keyboardShortcut(.cancelAction)
            }
            .padding(.horizontal)
            .padding(.vertical, 8)

            Divider()

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
        .frame(minWidth: 900, minHeight: 600)
        .frame(width: 1100, height: 750)
        .onAppear {
            discoverVNCDisplay()
        }
    }

    // MARK: - VNC Console

    @ViewBuilder
    private var vncConsole: some View {
        if isDiscovering {
            VStack(spacing: 12) {
                ProgressView()
                    .controlSize(.large)
                Text("Discovering VNC display...")
                    .font(.headline)
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

                let vncParts = vncDisplay.split(separator: ":")
                let vncHost = String(vncParts.first ?? "")
                let displayNum = vncParts.count >= 2 ? (Int(String(vncParts.last ?? "0")) ?? 0) : 0
                let vncPort = 5900 + displayNum

                Text(verbatim: "\(vncHost):\(vncPort)")
                    .font(.title3.monospaced())
                    .foregroundStyle(.secondary)
                    .padding(.top, 4)

                Button {
                    openScreenSharing(host: vncHost, port: vncPort)
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
                        .font(.callout)
                        .padding(8)
                        .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 6))
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

    // MARK: - Serial Console

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
            } else if !vm.hostName.isEmpty {
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
                        self.vncStatus = "VNC not available for \(instanceName.isEmpty ? "this VM" : instanceName)\nResponse: \(rawOutput.prefix(200))"
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
                VStack(spacing: 12) {
                    Spacer()
                    ProgressView()
                        .controlSize(.large)
                    Text("Querying guest agent...")
                        .foregroundStyle(.secondary)
                    Spacer()
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else if guestInfo.isEmpty {
                VStack(spacing: 16) {
                    Spacer()
                    Image(systemName: "cpu")
                        .font(.system(size: 48))
                        .foregroundStyle(.secondary)
                    Text("QEMU Guest Agent")
                        .font(.title3)
                    Text("Query VM info and run commands via the QEMU guest agent.\nNo SSH credentials needed -- uses the hypervisor's agent channel.")
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
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                GuestOutputView(text: guestInfo)
            }
        }
        .sheet(isPresented: $showGuestCommand) {
            guestCommandSheet
        }
    }

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

        let capturedHost = kvmHost
        let capturedUser = kvmUser
        let capturedPass = kvmPass
        let capturedVM = vm

        Task.detached {
            let vmName = await Self.findVirshName(host: capturedHost, user: capturedUser, pass: capturedPass, vmIP: capturedVM.ipAddress)

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

            var result = "=== Guest Agent Info for \(capturedVM.name) ===\n"
            result += "KVM Host: \(capturedHost)\n"
            result += "virsh name: \(vmName)\n\n"

            for (label, _, cmd) in commands {
                let cmdResult = await Self.runOnGuest(host: capturedHost, user: capturedUser, pass: capturedPass, vmName: vmName, command: cmd)
                result += "-- \(label) --\n\(cmdResult)\n\n"
            }

            let finalResult = result
            await MainActor.run {
                self.guestInfo = finalResult
                self.isLoadingGuest = false
            }
        }
    }

    private func runGuestCommand(_ command: String) {
        guard !kvmHost.isEmpty else { return }
        isLoadingGuest = true

        let capturedHost = kvmHost
        let capturedUser = kvmUser
        let capturedPass = kvmPass
        let capturedVM = vm

        Task.detached {
            let vmName = await Self.findVirshName(host: capturedHost, user: capturedUser, pass: capturedPass, vmIP: capturedVM.ipAddress)
            let cmdResult = await Self.runOnGuest(host: capturedHost, user: capturedUser, pass: capturedPass, vmName: vmName, command: command)

            let appendStr = "\n-- \(command) --\n\(cmdResult)\n"
            await MainActor.run {
                self.guestInfo += appendStr
                self.isLoadingGuest = false
            }
        }
    }

    private nonisolated static func runOnGuest(host: String, user: String, pass: String, vmName: String, command: String) async -> String {
        let sshpassPath = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/sshpass"

        let escapedCommand = command.replacingOccurrences(of: "\"", with: "\\\\\"")
        let script = "RESULT=$(virsh -c qemu:///system qemu-agent-command '\(vmName)' '{\"execute\":\"guest-exec\",\"arguments\":{\"path\":\"/bin/sh\",\"arg\":[\"-c\",\"\(escapedCommand)\"],\"capture-output\":true}}' 2>/dev/null); if [ $? -eq 0 ]; then PID=$(echo \"$RESULT\" | python3 -c \"import sys,json; print(json.load(sys.stdin)['return']['pid'])\" 2>/dev/null); if [ -n \"$PID\" ]; then sleep 1; STATUS=$(virsh -c qemu:///system qemu-agent-command '\(vmName)' \"{\\\\\"execute\\\\\":\\\\\"guest-exec-status\\\\\",\\\\\"arguments\\\\\":{\\\\\"pid\\\\\":$PID}}\" 2>/dev/null); echo \"$STATUS\" | python3 -c \"import sys,json,base64; d=json.load(sys.stdin)['return']; print(base64.b64decode(d.get('out-data','')).decode('utf-8',errors='replace'),end='') if 'out-data' in d else None; print(base64.b64decode(d.get('err-data','')).decode('utf-8',errors='replace'),end='') if 'err-data' in d else None\" 2>/dev/null; fi; else echo 'Guest agent not available or command failed'; fi"

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

    private nonisolated static func findVirshName(host: String, user: String, pass: String, vmIP: String) async -> String {
        let sshpassPath = ["/opt/homebrew/bin/sshpass", "/usr/local/bin/sshpass"]
            .first { FileManager.default.fileExists(atPath: $0) } ?? "/opt/homebrew/bin/sshpass"

        let script = "for vm in $(virsh -c qemu:///system list --name 2>/dev/null); do IP=$(virsh -c qemu:///system qemu-agent-command \"$vm\" '{\"execute\":\"guest-network-get-interfaces\"}' 2>/dev/null | python3 -c \"import sys,json; [print(a['ip-address']) for i in json.load(sys.stdin)['return'] for a in i.get('ip-addresses',[]) if a['ip-address-type']=='ipv4' and a['ip-address']!='127.0.0.1']\" 2>/dev/null); if echo \"$IP\" | grep -q \"\(vmIP)\"; then echo \"$vm\"; exit 0; fi; done"

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
                initialCommand: sshQuickInfo ? "echo '=== System Info ===' && hostname && echo '' && echo '-- OS --' && cat /etc/os-release 2>/dev/null | grep PRETTY_NAME | cut -d= -f2 && echo '' && echo '-- Uptime --' && uptime && echo '' && echo '-- Memory --' && free -h 2>/dev/null && echo '' && echo '-- Disk --' && df -h | grep -v tmpfs && echo '' && echo '-- CPU --' && nproc && echo '' && echo '-- Network --' && ip -br addr 2>/dev/null || ifconfig 2>/dev/null && echo '' && echo '-- Top Processes --' && ps aux --sort=-%mem 2>/dev/null | head -10" : nil
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
