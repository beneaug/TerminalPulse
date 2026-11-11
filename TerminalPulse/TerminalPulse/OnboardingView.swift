import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var isComplete: Bool
    private let installCommand = "brew install beneaug/tmuxonwatch/tmuxonwatch && tmuxonwatch-install"
    @State private var currentStep = 0
    @State private var copiedInstallCommand = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @AppStorage(LanguageManager.preferredLanguageKey) private var preferredLanguage = ""
    @State private var showLanguageRestartAlert = false

    var body: some View {
        ZStack {
            TerminalColors.defaultBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                VStack(spacing: 10) {
                    HStack {
                        Text(String(format: "%02d / 03", currentStep + 1))
                            .font(.system(size: 11, weight: .bold, design: .monospaced))
                            .tracking(1)
                            .foregroundStyle(TerminalColors.productAccent)
                            .accessibilityLabel(Text("Step \(currentStep + 1) of 3"))

                        Spacer()

                        Text("TMUX ON WATCH")
                            .font(.system(size: 10, weight: .bold, design: .monospaced))
                            .tracking(1.2)
                            .foregroundStyle(.white.opacity(0.42))

                        if currentStep == 0 {
                            Menu {
                                Picker("Language", selection: $preferredLanguage) {
                                    Text("System").tag("")
                                    Text("English").tag("en")
                                    Text("日本語").tag("ja")
                                }
                            } label: {
                                Image(systemName: "ellipsis")
                                    .font(.system(size: 14, weight: .bold))
                                    .foregroundStyle(.white.opacity(0.55))
                                    .frame(width: 40, height: 40)
                                    .contentShape(Rectangle())
                            }
                            .accessibilityLabel(Text("More options"))
                            .onChange(of: preferredLanguage) { _, newValue in
                                LanguageManager.apply(newValue)
                                showLanguageRestartAlert = true
                            }
                        }
                    }

                    HStack(spacing: 5) {
                        ForEach(0..<3) { index in
                            Rectangle()
                                .fill(index <= currentStep ? TerminalColors.productAccent : Color.white.opacity(0.12))
                                .frame(height: 2)
                        }
                    }
                    .accessibilityHidden(true)
                }
                .padding(.horizontal, 20)
                .padding(.top, 12)
                GeometryReader { geometry in
                    ScrollView {
                        VStack(spacing: 0) {
                            Spacer(minLength: 24)
                            switch currentStep {
                            case 0: installStep
                            case 1: connectStep
                            case 2: doneStep
                            default: EmptyView()
                            }
                            Spacer(minLength: 24)
                        }
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height)
                    }
                    .scrollDismissesKeyboard(.interactively)
                    .id(currentStep)
                }

                // Navigation
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            cancelConnectionTest()
                            withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { currentStep -= 1 }
                        }
                        .foregroundStyle(.white.opacity(0.65))
                    }

                    Spacer()

                    if currentStep < 2 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .foregroundStyle(.white.opacity(0.65))
                        .font(.subheadline)
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
        .onDisappear { cancelConnectionTest() }
        .alert("Language Changed", isPresented: $showLanguageRestartAlert) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Language changed. Restart the app to apply.")
        }
    }

    // MARK: - Step 1: Install

    private var installStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(TerminalColors.productAccent)

            Text("Install the Server")
                .font(.largeTitle.weight(.black))
                .tracking(-1.2)
                .foregroundStyle(.white)

            Text("Run this on the Mac where tmux is running:")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))

            HStack {
                Text(installCommand)
                    .font(.caption.monospaced())
                    .foregroundStyle(TerminalColors.productAccent)
                    .fixedSize(horizontal: false, vertical: true)

                Button {
                    UIPasteboard.general.string = installCommand
                    copiedInstallCommand = true
                } label: {
                    Image(systemName: copiedInstallCommand ? "checkmark" : "doc.on.doc")
                        .font(.subheadline)
                        .foregroundStyle(.white.opacity(0.65))
                }
                .frame(minWidth: 44, minHeight: 44)
                .accessibilityLabel("Copy install command")
                .accessibilityValue(copiedInstallCommand ? Text("Copied") : Text(""))
            }
            .padding(16)
            .background(Color.white.opacity(0.05))
            .clipShape(RoundedRectangle(cornerRadius: 8))
            .overlay(
                RoundedRectangle(cornerRadius: 8)
                    .stroke(Color.white.opacity(0.1), lineWidth: 1)
            )
            .padding(.horizontal, 24)

            Text("The installer sets up Python, generates a secure token, and starts the server.")
                .font(.caption)
                .foregroundStyle(.white.opacity(0.65))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Button {
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { currentStep = 1 }
            } label: {
                Text("Next: Connect")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TerminalColors.productAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 24)

            Button {
                activateDemo()
            } label: {
                Text("Try Demo")
                    .font(.subheadline.weight(.medium))
                    .foregroundStyle(TerminalColors.productAccent)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(TerminalColors.productAccent.opacity(0.08))
                    .clipShape(RoundedRectangle(cornerRadius: 6))
                    .overlay(
                        RoundedRectangle(cornerRadius: 6)
                            .stroke(TerminalColors.productAccent.opacity(0.45), lineWidth: 1)
                    )
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Step 2: Connect

    @State private var serverURL = ""
    @State private var authToken = ""
    @State private var isScanning = false
    @State private var showCameraDeniedAlert = false
    @State private var connectionStatus: ConnectionStatus = .idle
    @State private var connectionTask: Task<Void, Never>?
    @State private var connectionAttempt = UUID()
    @State private var readiness: TerminalReadiness?
    @State private var pendingRemoteConfig: NotificationService.RemoteConfig?

    private enum ConnectionStatus {
        case idle, testing, success, failure(String)

        var isSuccess: Bool {
            if case .success = self { return true }
            return false
        }
        var isTesting: Bool {
            if case .testing = self { return true }
            return false
        }
        var failureMessage: String? {
            if case .failure(let msg) = self { return msg }
            return nil
        }
    }

    private var connectStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "qrcode.viewfinder")
                .font(.system(size: 48))
                .foregroundStyle(TerminalColors.productAccent)

            Text("Connect to Server")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text("Scan the QR code from the install script, or enter details manually.")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            Button {
                checkCameraAndScan()
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                    Text("Scan QR Code")
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TerminalColors.productAccent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 24)
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
                Text("tmuxonwatch needs camera access to scan the QR code. Enable it in Settings.")
            }

            // Manual entry
            VStack(spacing: 12) {
                VStack(alignment: .leading, spacing: 4) {
                    Text("SERVER URL")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    TextField("http://your-mac.local:8787", text: Binding(get: { serverURL }, set: { cancelConnectionTest(); pendingRemoteConfig = nil; serverURL = $0 }))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.white)
                        .textContentType(.URL)
                        .autocorrectionDisabled()
                        .textInputAutocapitalization(.never)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .accessibilityLabel("Server URL")
                }

                Text("Use your Mac’s LAN address or Tailscale hostname. 127.0.0.1 points to this iPhone.")
                    .font(.caption)
                    .foregroundStyle(.white.opacity(0.65))
                    .frame(maxWidth: .infinity, alignment: .leading)

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUTH TOKEN")
                        .font(.caption2.monospaced().weight(.semibold))
                        .foregroundStyle(.white.opacity(0.65))
                    SecureField("Paste token here", text: Binding(get: { authToken }, set: { cancelConnectionTest(); pendingRemoteConfig = nil; authToken = $0 }))
                        .font(.subheadline.monospaced())
                        .foregroundStyle(.white)
                        .padding(10)
                        .background(Color.white.opacity(0.05))
                        .clipShape(RoundedRectangle(cornerRadius: 6))
                        .overlay(
                            RoundedRectangle(cornerRadius: 6)
                                .stroke(Color.white.opacity(0.1), lineWidth: 1)
                        )
                        .accessibilityLabel("Authentication token")
                }
            }
            .padding(.horizontal, 24)

            Button {
                testAndConnect()
            } label: {
                HStack {
                    switch connectionStatus {
                    case .testing:
                        ProgressView()
                            .tint(.black)
                            .scaleEffect(0.8)
                        Text("Testing...")
                    case .success:
                        Image(systemName: "checkmark.circle.fill")
                        Text("Server saved")
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Retry")
                    case .idle:
                        Text("Test Connection")
                    }
                }
                .font(.headline)
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(TerminalColors.productAccent)
                .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .disabled(serverURL.isEmpty || authToken.isEmpty || connectionStatus.isTesting)
            .padding(.horizontal, 24)

            if let msg = connectionStatus.failureMessage {
                Text(msg)
                    .font(.caption.monospaced())
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .accessibilityLabel(Text("Connection error: \(msg)"))
            }
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(TerminalColors.productAccent)

            Text("Server saved")
                .font(.title2.bold())
                .foregroundStyle(.white)

            Text(readiness?.message ?? "")
                .font(.subheadline)
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                Text("Open the Watch app to check its connection. Remote notifications require separate setup in Settings.")
                    .font(.subheadline)
                    .foregroundStyle(.white.opacity(0.8))
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Button {
                completeOnboarding()
            } label: {
                Text("Continue")
                    .font(.headline)
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(TerminalColors.productAccent)
                    .clipShape(RoundedRectangle(cornerRadius: 6))
            }
            .padding(.horizontal, 24)
        }
    }

    // MARK: - Actions

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
            connectionStatus = .failure(String(localized: "QR code not recognized. Scan the code from the install script."))
            return
        }
        cancelConnectionTest()
        serverURL = url
        authToken = token
        pendingRemoteConfig = NotificationService.remoteConfig(from: dict)
        testAndConnect()
    }

    private func cancelConnectionTest() {
        connectionTask?.cancel()
        connectionAttempt = UUID()
        connectionStatus = .idle
        readiness = nil
    }

    private func testAndConnect() {
        guard !serverURL.isEmpty, !authToken.isEmpty else { return }
        connectionTask?.cancel()
        let attempt = UUID()
        connectionAttempt = attempt
        connectionStatus = .testing
        let testedURL = serverURL
        let testedToken = authToken
        let qrConfig = pendingRemoteConfig

        connectionTask = Task { @MainActor in
            do {
                let api = APIClient(serverURL: testedURL, authToken: testedToken)
                let result = try await api.checkReadiness()
                let config = try? await api.fetchNotifyConfig()
                try Task.checkCancellation()
                guard connectionAttempt == attempt, currentStep == 1,
                      serverURL == testedURL, authToken == testedToken else { return }
                guard KeychainService.save(key: "authToken", value: testedToken) else {
                    throw APIError.badStatus(0, String(localized: "Could not save the token securely. Please try again."))
                }
                UserDefaults.standard.set(testedURL, forKey: "serverURL")
                if let qrConfig { NotificationService.applyRemoteConfig(qrConfig) }
                pendingRemoteConfig = nil
                if let config {
                    NotificationService.applyRemoteConfig(.init(
                        notifyToken: config.notifyToken, notifyWebhookURL: config.notifyWebhookURL,
                        notifyRegisterURL: config.notifyRegisterURL, notifyUnregisterURL: config.notifyUnregisterURL))
                }
                if DemoData.isDemo {
                    DemoData.deactivate()
                    CaptureCache.clear()
                }
                readiness = result
                connectionStatus = .success
                withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { currentStep = 2 }
            } catch {
                guard !Task.isCancelled, connectionAttempt == attempt else { return }
                connectionStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func completeOnboarding() {
        // Skip never overwrites a working saved configuration with untested edits.
        connectionTask?.cancel()
        connectionAttempt = UUID()
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isComplete = true }
    }

    private func activateDemo() {
        DemoData.activate()
        UserDefaults.standard.set("http://127.0.0.1:8787", forKey: "serverURL")
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { isComplete = true }
    }


}

// MARK: - QR Scanner

struct QRScannerView: UIViewControllerRepresentable {
    var onResult: (String) -> Void

    func makeUIViewController(context: Context) -> QRScannerViewController {
        let vc = QRScannerViewController()
        vc.onResult = onResult
        return vc
    }

    func updateUIViewController(_ uiViewController: QRScannerViewController, context: Context) {}
}

class QRScannerViewController: UIViewController, AVCaptureMetadataOutputObjectsDelegate {
    var onResult: ((String) -> Void)?
    private var captureSession: AVCaptureSession?
    private let captureQueue = DispatchQueue(label: "com.tmuxonwatch.qr-camera", qos: .userInitiated)
    private var previewLayer: AVCaptureVideoPreviewLayer?
    private var handledResult = false

    override func viewDidLoad() {
        super.viewDidLoad()
        view.backgroundColor = .black

        let session = AVCaptureSession()
        guard let device = AVCaptureDevice.default(for: .video),
              let input = try? AVCaptureDeviceInput(device: device) else {
            dismiss(animated: true)
            return
        }

        session.addInput(input)
        let output = AVCaptureMetadataOutput()
        session.addOutput(output)
        output.setMetadataObjectsDelegate(self, queue: .main)
        output.metadataObjectTypes = [.qr]

        let preview = AVCaptureVideoPreviewLayer(session: session)
        preview.frame = view.bounds
        preview.videoGravity = .resizeAspectFill
        view.layer.addSublayer(preview)
        previewLayer = preview

        captureSession = session
        captureQueue.async { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard !handledResult, let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        handledResult = true
        if let session = captureSession { captureQueue.async { session.stopRunning() } }
        let callback = onResult
        dismiss(animated: true) {
            callback?(value)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        if let session = captureSession { captureQueue.async { session.stopRunning() } }
    }

    override func viewDidLayoutSubviews() {
        super.viewDidLayoutSubviews()
        previewLayer?.frame = view.bounds
    }
}
