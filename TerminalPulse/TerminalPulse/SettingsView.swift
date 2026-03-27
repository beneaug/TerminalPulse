import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://127.0.0.1:8787"
    @AppStorage("pollInterval") private var pollInterval = 2
    @AppStorage("remotePushEnabled") private var remotePushEnabled = false
    @AppStorage("fontSize") private var fontSize = 11
    @AppStorage("watchFontSize") private var watchFontSize = 10
    @AppStorage("colorTheme") private var colorTheme = "default"

    @State private var authToken = KeychainService.load(key: "authToken") ?? ""
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var isTesting = false

    @State private var showResetConfirm = false
    @State private var isScanning = false
    @State private var showCameraDeniedAlert = false
    @State private var remotePushStatus: String?
    @State private var isTestingRemotePush = false

    var watchReachable: Bool
    var onPollIntervalChanged: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var onDemoLoaded: (() -> Void)?
    var onServerConnected: (() -> Void)?

    var body: some View {
        Form {
            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERVER URL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:8787", text: $serverURL)
                        .font(.system(size: 14, design: .monospaced))
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .accessibilityLabel("Server URL")
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUTH TOKEN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    SecureField("Token", text: $authToken)
                        .font(.system(size: 14, design: .monospaced))
                        .accessibilityLabel("Authentication token")
                        .onChange(of: authToken) {
                            _ = KeychainService.save(key: "authToken", value: authToken)
                        }
                }

                Button {
                    testConnection()
                } label: {
                    HStack {
                        if isTesting {
                            ProgressView()
                                .scaleEffect(0.8)
                        }
                        Text(isTesting ? "Testing..." : "Test Connection")
                    }
                }
                .disabled(isTesting)

                if let result = testResult {
                    Text(result)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(testSuccess ? .green : .red)
                        .accessibilityLabel("Connection test result: \(result)")
                }

                Button {
                    checkCameraAndScan()
                } label: {
                    HStack {
                        Image(systemName: "qrcode")
                        Text("Scan QR Code")
                    }
                }
                .sheet(isPresented: $isScanning) {
                    QRScannerView { result in
                        isScanning = false
                        handleQRResult(result)
                    }
                }
                .alert("Camera Access Required", isPresented: $showCameraDeniedAlert) {
                    Button("Open Settings") {
                        if let url = URL(string: UIApplication.openSettingsURLString) {
                            UIApplication.shared.open(url)
                        }
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("Camera access is needed to scan the QR code. Enable it in Settings.")
                }
            } header: {
                Text("Connection")
            }

            Section {
                Stepper("Poll every \(pollInterval)s", value: $pollInterval, in: 1...120, step: 1)
                    .onChange(of: pollInterval) {
                        onPollIntervalChanged?()
                    }
            } header: {
                Text("Polling")
            }

            Section {
                Text("Optional. Enables cloud relay delivery for webhook-triggered push alerts.")
                    .font(.caption)
                    .foregroundStyle(.secondary)

                Toggle("Enable Remote Push", isOn: $remotePushEnabled)
                    .onChange(of: remotePushEnabled) { _, on in
                        if on {
                            NotificationService.requestPermission()
                            Task { await NotificationService.registerDeviceWithRelayIfPossible(force: true) }
                        } else {
                            Task { await NotificationService.unregisterDeviceFromRelayIfPossible() }
                        }
                    }

                if let token = NotificationService.notifyToken() {
                    VStack(alignment: .leading, spacing: 6) {
                        Text("WEBHOOK URL")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(NotificationService.webhookURLString())
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                    }

                    VStack(alignment: .leading, spacing: 6) {
                        Text("TOKEN")
                            .font(.system(size: 10, weight: .semibold, design: .monospaced))
                            .foregroundStyle(.secondary)
                        Text(token)
                            .font(.system(size: 12, design: .monospaced))
                            .textSelection(.enabled)
                            .lineLimit(2)
                            .minimumScaleFactor(0.8)
                    }

                    if let curlExample = NotificationService.curlExample() {
                        ScrollView(.horizontal, showsIndicators: false) {
                            Text(curlExample)
                                .font(.system(size: 12, design: .monospaced))
                                .textSelection(.enabled)
                                .padding(10)
                                .background(Color.secondary.opacity(0.12))
                                .clipShape(RoundedRectangle(cornerRadius: 8))
                        }

                        Button {
                            UIPasteboard.general.string = curlExample
                            remotePushStatus = "cURL example copied."
                        } label: {
                            Label("Copy cURL Example", systemImage: "doc.on.doc")
                        }
                    }

                    Button {
                        runRemotePushTest()
                    } label: {
                        HStack {
                            if isTestingRemotePush {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Text(isTestingRemotePush ? "Sending..." : "Send Test Push")
                        }
                    }
                    .disabled(isTestingRemotePush)
                } else {
                    Text("No webhook token configured yet. Re-run installer and scan the QR code to auto-configure remote push.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }

                if let remotePushStatus {
                    Text(remotePushStatus)
                        .font(.system(size: 12, design: .monospaced))
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Remote Push (Webhook)")
            } footer: {
                Text("Use this endpoint from scripts, hooks, or CI to deliver reliable APNs alerts.")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("iPhone Font Size: \(fontSize)pt")
                    Slider(value: .init(
                        get: { Double(fontSize) },
                        set: { fontSize = Int($0) }
                    ), in: 8...16, step: 1)
                }
                .onChange(of: fontSize) { onAppearanceChanged?() }

                VStack(alignment: .leading, spacing: 4) {
                    Text("Watch Font Size: \(watchFontSize)pt")
                    Slider(value: .init(
                        get: { Double(watchFontSize) },
                        set: { watchFontSize = Int($0) }
                    ), in: 7...12, step: 1)
                }
                .onChange(of: watchFontSize) { onAppearanceChanged?() }
            } header: {
                Text("Font Size")
            }

            Section {
                Picker("Theme", selection: $colorTheme) {
                    Text("Default").tag("default")
                    Text("Solarized Dark").tag("solarized")
                    Text("Dracula").tag("dracula")
                    Text("Gruvbox").tag("gruvbox")
                }
                .onChange(of: colorTheme) {
                    TerminalColors.invalidateCache()
                    onAppearanceChanged?()
                }
            } header: {
                Text("Color Theme")
            }

            Section {
                HStack {
                    Text("Watch")
                    Spacer()
                    HStack(spacing: 4) {
                        Circle()
                            .fill(watchReachable ? .green : .gray)
                            .frame(width: 6, height: 6)
                            .accessibilityHidden(true)
                        Text(watchReachable ? "Connected" : "Not reachable")
                            .foregroundStyle(.secondary)
                    }
                    .accessibilityElement(children: .combine)
                    .accessibilityLabel("Watch status: \(watchReachable ? "Connected" : "Not reachable")")
                }
            } header: {
                Text("Apple Watch")
            }

            Section {
                ProUpgradeRow()
            } header: {
                Text("Watch Input")
            }

            Section {
                Button(role: .destructive) {
                    showResetConfirm = true
                } label: {
                    HStack {
                        Image(systemName: "play.circle")
                        Text("Load Demo Data")
                    }
                }
                .confirmationDialog("Load Demo Data?", isPresented: $showResetConfirm) {
                    Button("Load Demo", role: .destructive) {
                        DemoData.activate()
                        serverURL = "http://127.0.0.1:8787"
                        authToken = ""
                        KeychainService.delete(key: "authToken")
                        onDemoLoaded?()
                    }
                    Button("Cancel", role: .cancel) {}
                } message: {
                    Text("This clears your server connection and loads sample terminal output. You can reconnect anytime.")
                }
            } header: {
                Text("Demo")
            } footer: {
                Text("Load sample data for testing without a server.")
            }

            Section {
                HStack {
                    Text("Version")
                    Spacer()
                    Text(displayVersion)
                        .foregroundStyle(.secondary)
                        .font(.system(size: 14, design: .monospaced))
                }

                Link("Privacy Policy", destination: URL(string: "https://tmuxonwatch.com/privacy")!)
                Link("Terms of Service", destination: URL(string: "https://tmuxonwatch.com/terms")!)
                Link("Support", destination: URL(string: "https://tmuxonwatch.com/support")!)
            } header: {
                Text("About")
            }
        }
        .navigationTitle("Settings")
    }

    private var displayVersion: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info?["CFBundleVersion"] as? String ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)

        let parts = short.split(separator: ".")
        if parts.count >= 3 {
            var replaced = parts.map(String.init)
            replaced[replaced.count - 1] = build
            return replaced.joined(separator: ".")
        }
        if parts.count >= 1 {
            return "\(short).\(build)"
        }
        return short
    }

    // MARK: - Pro Upgrade

    struct ProUpgradeRow: View {
        private var store = StoreManager.shared

        var body: some View {
            if store.isProUnlocked {
                HStack {
                    Label("Watch Input", systemImage: "applewatch")
                    Spacer()
                    Text("Unlocked")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            } else {
                VStack(alignment: .leading, spacing: 8) {
                    Text("Send keys to tmux from your Apple Watch — dictation, scribble, and a full key toolbar.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await store.purchase() }
                    } label: {
                        HStack {
                            Text("Unlock Watch Input")
                            Spacer()
                            if let product = store.proProduct {
                                Text(product.displayPrice)
                                    .fontWeight(.semibold)
                            }
                        }
                    }
                    .disabled(store.purchaseState == .purchasing)

                    if case .failed(let msg) = store.purchaseState {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Button("Restore Purchase") {
                        Task { await store.restore() }
                    }
                    .font(.caption)
                }
            }
        }
    }

    private func testConnection() {
        isTesting = true
        testResult = nil
        Task {
            do {
                let api = APIClient()
                let health = try await api.fetchHealth()
                var authLabel = "auth: ok"
                do {
                    _ = try await api.fetchSessions()
                } catch let apiError as APIError {
                    if apiError.statusCode == 401 {
                        throw apiError
                    }
                    // Non-auth API failures still indicate the token passed auth.
                    authLabel = "auth: ok (tmux unavailable)"
                }
                await refreshRemoteConfigFromServer(api: api)
                testResult = "\(health.hostname) — tmux: \(health.tmux ? "yes" : "no") — \(authLabel)"
                testSuccess = true
                if DemoData.isDemo {
                    DemoData.deactivate()
                    CaptureCache.clear()
                }
                onServerConnected?()
            } catch {
                testResult = error.localizedDescription
                testSuccess = false
            }
            isTesting = false
        }
    }

    private func checkCameraAndScan() {
        switch AVCaptureDevice.authorizationStatus(for: .video) {
        case .authorized:
            isScanning = true
        case .notDetermined:
            AVCaptureDevice.requestAccess(for: .video) { granted in
                DispatchQueue.main.async {
                    if granted { isScanning = true }
                    else { showCameraDeniedAlert = true }
                }
            }
        case .denied, .restricted:
            showCameraDeniedAlert = true
        @unknown default:
            isScanning = true
        }
    }

    private func handleQRResult(_ json: String) {
        guard let data = json.data(using: .utf8),
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let url = dict["url"] as? String,
              let token = dict["token"] as? String else {
            testResult = "QR code not recognized"
            testSuccess = false
            return
        }
        serverURL = url
        authToken = token
        _ = KeychainService.save(key: "authToken", value: token)
        NotificationService.applyRemoteConfig(NotificationService.remoteConfig(from: dict))
        testResult = "Credentials loaded from QR. Testing..."
        testSuccess = true
        testConnection()
    }

    private func runRemotePushTest() {
        isTestingRemotePush = true
        remotePushStatus = nil
        Task {
            do {
                do {
                    try await NotificationService.sendTestWebhook()
                } catch {
                    // Token may be stale/missing after older QR flows; refresh once and retry.
                    await refreshRemoteConfigFromServer(api: APIClient())
                    try await NotificationService.sendTestWebhook()
                }
                remotePushStatus = "Test push sent."
            } catch {
                remotePushStatus = error.localizedDescription
            }
            isTestingRemotePush = false
        }
    }

    private func refreshRemoteConfigFromServer(api: APIClient) async {
        do {
            let config = try await api.fetchNotifyConfig()
            NotificationService.applyRemoteConfig(
                .init(
                    notifyToken: config.notifyToken,
                    notifyWebhookURL: config.notifyWebhookURL,
                    notifyRegisterURL: config.notifyRegisterURL,
                    notifyUnregisterURL: config.notifyUnregisterURL
                )
            )
        } catch {
            // Ignore missing/stale server support; QR/manual config may still provide values.
        }
    }
}
