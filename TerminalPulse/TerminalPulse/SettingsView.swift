import SwiftUI
import AVFoundation

struct SettingsView: View {
    @AppStorage("serverURL") private var serverURL = "http://127.0.0.1:8787"
    @AppStorage("pollInterval") private var pollInterval = 2
    @AppStorage("notificationsEnabled") private var notificationsEnabled = true
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

    var watchReachable: Bool
    var onPollIntervalChanged: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?
    var onDemoLoaded: (() -> Void)?

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
                Toggle("Command Finished Alerts", isOn: $notificationsEnabled)
                    .onChange(of: notificationsEnabled) { _, on in
                        if on { NotificationService.requestPermission() }
                    }

                if notificationsEnabled {
                    Text("Notifies when a command finishes (prompt reappears). Buzzes on Apple Watch.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            } header: {
                Text("Notifications")
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
                    Text("\(Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String ?? "?") (\(Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "?"))")
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
                let health = try await APIClient().fetchHealth()
                testResult = "\(health.hostname) — tmux: \(health.tmux ? "yes" : "no")"
                testSuccess = true
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
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let url = dict["url"],
              let token = dict["token"] else {
            testResult = "QR code not recognized"
            testSuccess = false
            return
        }
        serverURL = url
        authToken = token
        _ = KeychainService.save(key: "authToken", value: token)
        testResult = "Credentials loaded from QR"
        testSuccess = true
    }
}
