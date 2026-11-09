import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://127.0.0.1:8787"
    @AppStorage("pollInterval") private var pollInterval = 2
    @AppStorage("remotePushEnabled") private var remotePushEnabled = false
    @AppStorage("protectScreenPreviews") private var protectScreenPreviews = true
    @AppStorage("hideNotificationDetails") private var hideNotificationDetails = true
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
    @AppStorage("fontSize") private var fontSize = 11
    @AppStorage("watchFontSize") private var watchFontSize = 10
    @AppStorage("colorTheme") private var colorTheme = "default"
    @AppStorage(LanguageManager.preferredLanguageKey) private var preferredLanguage = ""

    @State private var showLanguageRestartAlert = false
    @State private var authToken = KeychainService.load(key: "authToken") ?? ""
    @State private var testResult: String?
    @State private var testSuccess = false
    @State private var isTesting = false
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionAttempt = UUID()

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
                Picker("Language", selection: $preferredLanguage) {
                    Text("System").tag("")
                    Text("English").tag("en")
                    Text("日本語").tag("ja")
                }
                .onChange(of: preferredLanguage) { _, newValue in
                    LanguageManager.apply(newValue)
                    showLanguageRestartAlert = true
                }
            } header: {
                Text("Language")
            }

            Section {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERVER URL")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    TextField("http://127.0.0.1:8787", text: Binding(get: { serverURL }, set: { cancelConnectionTest(); serverURL = $0 }))
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
                    SecureField("Token", text: Binding(get: { authToken }, set: { cancelConnectionTest(); authToken = $0 }))
                        .font(.system(size: 14, design: .monospaced))
                        .accessibilityLabel("Authentication token")
                        .onChange(of: authToken) {
                            if !KeychainService.save(key: "authToken", value: authToken) {
                                testResult = String(localized: "Could not save the token securely. Please try again.")
                                testSuccess = false
                            }
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
                        .accessibilityLabel(Text("Connection test result: \(result)"))
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
                Text("Refresh pace")
            } footer: {
                Text("Updates quickly while output changes, then eases back when quiet. Raising your wrist requests fresh output.")
            }

            Section {
                Toggle("Protect screen previews", isOn: $protectScreenPreviews)
                    .onChange(of: protectScreenPreviews) { _, _ in
                        PollingService.shared.syncSettingsToWatch()
                    }
                Toggle("Hide notification details", isOn: $hideNotificationDetails)
            } header: {
                Text("Privacy")
            } footer: {
                Text("Screen protection hides the app when inactive, including app-switcher previews, and syncs to Apple Watch. New local completion alerts hide session names and output. Remote alerts are controlled at their source; this setting cannot redact remote notifications already sent to your phone.")
            }

            Section {
                Toggle("Command finished alerts", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, enabled in
                        if enabled { NotificationService.requestPermission() }
                    }
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
                            remotePushStatus = String(localized: "cURL example copied.")
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
                    .accessibilityLabel(Text("Watch status: \(watchReachable ? String(localized: "Connected") : String(localized: "Not reachable"))"))
                }
            } header: {
                Text("Apple Watch")
            }

            Section {
                ProUpgradeRow()
            } header: {
                Text("tmuxonwatch Pro")
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
        .onDisappear { cancelConnectionTest() }
        .navigationTitle("Settings")
        .scrollContentBackground(.hidden)
        .background(Color.black)
        .tint(TerminalColors.productAccent)
        .alert("Language Changed", isPresented: $showLanguageRestartAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Language changed. Restart the app to apply.")
        }
    }

    private var displayVersion: String {
        let info = Bundle.main.infoDictionary
        let short = (info?["CFBundleShortVersionString"] as? String ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)
        let build = (info?["CFBundleVersion"] as? String ?? "?").trimmingCharacters(in: .whitespacesAndNewlines)
        return "\(short) (\(build))"
    }

    // MARK: - Pro Upgrade

    struct ProUpgradeRow: View {
        private var store = StoreManager.shared

        var body: some View {
            if store.isProUnlocked {
                HStack {
                    Label("tmuxonwatch Pro", systemImage: "checkmark.seal")
                    Spacer()
                    Text("Unlocked")
                        .foregroundStyle(.green)
                        .font(.system(size: 13, weight: .medium, design: .monospaced))
                }
            } else {
                VStack(alignment: .leading, spacing: 10) {
                    Text("Reply from your Apple Watch or iPhone. Dictate, send keys, and save your frequently used commands on iPhone.")
                        .font(.caption)
                        .foregroundStyle(.secondary)

                    Button {
                        Task { await store.purchase() }
                    } label: {
                        HStack {
                            if store.purchaseState == .purchasing {
                                ProgressView()
                                    .scaleEffect(0.8)
                            }
                            Label(
                                store.purchaseState == .purchasing ? "Purchasing..." : "Unlock Pro",
                                systemImage: "applewatch.radiowaves.left.and.right"
                            )
                            Spacer()
                            if let product = store.proProduct {
                                Text(product.displayPrice)
                                    .fontWeight(.semibold)
                            }
                        }
                        .contentShape(Rectangle())
                    }
                    .disabled(store.purchaseState == .purchasing || store.purchaseState == .restoring)
                    .buttonStyle(.borderedProminent)
                    .controlSize(.regular)

                    Text("One purchase. Yours to keep. Live viewing, Read & Find, and sharing stay free.")
                        .font(.caption).foregroundStyle(.secondary)

                    if store.purchaseState == .restored {
                        Text("Purchase restored.")
                            .font(.caption2)
                            .foregroundStyle(.green)
                    }

                    if case .failed(let msg) = store.purchaseState {
                        Text(msg)
                            .font(.caption2)
                            .foregroundStyle(.red)
                    }

                    Button {
                        Task { await store.restore() }
                    } label: {
                        HStack(spacing: 6) {
                            if store.purchaseState == .restoring {
                                ProgressView()
                                    .scaleEffect(0.7)
                            }
                            Label(
                                store.purchaseState == .restoring ? "Restoring..." : "Restore Purchase",
                                systemImage: "arrow.clockwise"
                            )
                        }
                    }
                    .font(.caption)
                    .buttonStyle(.borderless)
                    .controlSize(.small)
                    .disabled(store.purchaseState == .purchasing || store.purchaseState == .restoring)
                }
            }
        }
    }

    private func cancelConnectionTest() {
        connectionTask?.cancel()
        connectionAttempt = UUID()
        isTesting = false
        testResult = nil
    }

    private func testConnection() {
        connectionTask?.cancel()
        let attempt = UUID()
        connectionAttempt = attempt
        isTesting = true
        testResult = nil
        let testedURL = serverURL
        let testedToken = authToken
        connectionTask = Task { @MainActor in
            defer { if connectionAttempt == attempt { isTesting = false } }
            do {
                let api = APIClient(serverURL: testedURL, authToken: testedToken)
                let readiness = try await api.checkReadiness()
                let config = try? await api.fetchNotifyConfig()
                try Task.checkCancellation()
                guard connectionAttempt == attempt,
                      serverURL == testedURL, authToken == testedToken else { return }
                guard KeychainService.save(key: "authToken", value: testedToken) else {
                    throw APIError.badStatus(0, String(localized: "Could not save the token securely. Please try again."))
                }
                if let config {
                    NotificationService.applyRemoteConfig(.init(
                        notifyToken: config.notifyToken, notifyWebhookURL: config.notifyWebhookURL,
                        notifyRegisterURL: config.notifyRegisterURL, notifyUnregisterURL: config.notifyUnregisterURL))
                }
                testResult = readiness.message
                testSuccess = readiness == .outputReceived
                if DemoData.isDemo {
                    DemoData.deactivate()
                    CaptureCache.clear()
                }
                onServerConnected?()
            } catch {
                guard !Task.isCancelled, connectionAttempt == attempt else { return }
                testResult = error.localizedDescription
                testSuccess = false
            }
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
            testResult = String(localized: "QR code not recognized")
            testSuccess = false
            return
        }
        guard KeychainService.save(key: "authToken", value: token) else {
            testResult = String(localized: "Could not save the token securely. Please try again.")
            testSuccess = false
            return
        }
        serverURL = url
        authToken = token
        NotificationService.applyRemoteConfig(NotificationService.remoteConfig(from: dict))
        testResult = String(localized: "Credentials loaded from QR. Testing...")
        testSuccess = true
        testConnection()
    }

    private func runRemotePushTest() {
        isTestingRemotePush = true
        remotePushStatus = nil
        Task {
            do {
                // Refresh only before a POST. A timeout may still have sent an alert.
                if NotificationService.notifyToken() == nil {
                    await refreshRemoteConfigFromServer(api: APIClient())
                }
                let receipt = try await NotificationService.sendTestWebhook()
                remotePushStatus = receipt.message
            } catch {
                remotePushStatus = error.localizedDescription + "\n" + String(localized: "The result is unconfirmed. Check your device before testing again.")
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
