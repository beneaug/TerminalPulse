import SwiftUI
import AVFoundation

struct OnboardingView: View {
    @Binding var isComplete: Bool
    @State private var currentStep = 0

    var body: some View {
        ZStack {
            TerminalColors.defaultBackground
                .ignoresSafeArea()

            VStack(spacing: 0) {
                // Progress dots
                HStack(spacing: 8) {
                    ForEach(0..<3) { index in
                        Circle()
                            .fill(index <= currentStep ? Color.green : Color.white.opacity(0.2))
                            .frame(width: 8, height: 8)
                    }
                }
                .padding(.top, 20)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Step \(currentStep + 1) of 3")

                Spacer()

                switch currentStep {
                case 0:
                    installStep
                case 1:
                    connectStep
                case 2:
                    doneStep
                default:
                    EmptyView()
                }

                Spacer()

                // Navigation
                HStack {
                    if currentStep > 0 {
                        Button("Back") {
                            withAnimation { currentStep -= 1 }
                        }
                        .foregroundStyle(.white.opacity(0.5))
                    }

                    Spacer()

                    if currentStep < 2 {
                        Button("Skip") {
                            completeOnboarding()
                        }
                        .foregroundStyle(.white.opacity(0.3))
                        .font(.system(size: 13))
                    }
                }
                .padding(.horizontal, 24)
                .padding(.bottom, 20)
            }
        }
    }

    // MARK: - Step 1: Install

    private var installStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "terminal")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("Install the Server")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Run this on the Mac where tmux is running:")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))

            HStack {
                Text("bash <(curl -sSL https://tmuxonwatch.com/install)")
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.green)
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)

                Button {
                    UIPasteboard.general.string = "bash <(curl -sSL https://tmuxonwatch.com/install)"
                } label: {
                    Image(systemName: "doc.on.doc")
                        .font(.system(size: 14))
                        .foregroundStyle(.white.opacity(0.5))
                }
                .accessibilityLabel("Copy install command")
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
                .font(.system(size: 12))
                .foregroundStyle(.white.opacity(0.4))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                withAnimation { currentStep = 1 }
            } label: {
                Text("Next: Connect")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.white)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)

            Button {
                activateDemo()
            } label: {
                Text("Try Demo")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(.green)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
                    .background(Color.green.opacity(0.1))
                    .clipShape(RoundedRectangle(cornerRadius: 10))
                    .overlay(
                        RoundedRectangle(cornerRadius: 10)
                            .stroke(Color.green.opacity(0.3), lineWidth: 1)
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
                .foregroundStyle(.green)

            Text("Connect to Server")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("Scan the QR code from the install script, or enter details manually.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            Button {
                checkCameraAndScan()
            } label: {
                HStack {
                    Image(systemName: "qrcode")
                    Text("Scan QR Code")
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(.black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(.white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
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
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    TextField("http://127.0.0.1:8787", text: $serverURL)
                        .font(.system(size: 14, design: .monospaced))
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

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUTH TOKEN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.white.opacity(0.4))
                    SecureField("Paste token here", text: $authToken)
                        .font(.system(size: 14, design: .monospaced))
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
                        Text("Connected!")
                    case .failure:
                        Image(systemName: "exclamationmark.triangle.fill")
                        Text("Retry")
                    case .idle:
                        Text("Test Connection")
                    }
                }
                .font(.system(size: 16, weight: .semibold))
                .foregroundStyle(connectionStatus.isSuccess ? .white : .black)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 14)
                .background(connectionStatus.isSuccess ? .green : .white)
                .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .disabled(serverURL.isEmpty || authToken.isEmpty || connectionStatus.isTesting)
            .padding(.horizontal, 24)

            if let msg = connectionStatus.failureMessage {
                Text(msg)
                    .font(.system(size: 12, design: .monospaced))
                    .foregroundStyle(.red)
                    .padding(.horizontal, 24)
                    .accessibilityLabel("Connection error: \(msg)")
            }
        }
    }

    // MARK: - Step 3: Done

    private var doneStep: some View {
        VStack(spacing: 24) {
            Image(systemName: "checkmark.circle")
                .font(.system(size: 48))
                .foregroundStyle(.green)

            Text("You're Connected!")
                .font(.system(size: 24, weight: .bold))
                .foregroundStyle(.white)

            Text("tmuxonwatch will poll your tmux session and push live output to your Apple Watch.")
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.6))
                .multilineTextAlignment(.center)
                .padding(.horizontal, 32)

            VStack(alignment: .leading, spacing: 12) {
                featureRow(icon: "applewatch", text: "Live terminal on your wrist")
                featureRow(icon: "bell.badge", text: "Notifications when commands finish")
                featureRow(icon: "arrow.clockwise", text: "Auto-refreshes in background")
            }
            .padding(20)
            .background(Color.white.opacity(0.03))
            .clipShape(RoundedRectangle(cornerRadius: 12))
            .padding(.horizontal, 24)

            Button {
                completeOnboarding()
            } label: {
                Text("Start Watching")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(.black)
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 14)
                    .background(.green)
                    .clipShape(RoundedRectangle(cornerRadius: 10))
            }
            .padding(.horizontal, 24)
        }
    }

    private func featureRow(icon: String, text: String) -> some View {
        HStack(spacing: 12) {
            Image(systemName: icon)
                .font(.system(size: 16))
                .foregroundStyle(.green)
                .frame(width: 24)
            Text(text)
                .font(.system(size: 14))
                .foregroundStyle(.white.opacity(0.8))
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
              let dict = try? JSONSerialization.jsonObject(with: data) as? [String: String],
              let url = dict["url"],
              let token = dict["token"] else {
            connectionStatus = .failure("QR code not recognized. Scan the code from the install script.")
            return
        }
        serverURL = url
        authToken = token
        testAndConnect()
    }

    private func testAndConnect() {
        guard !serverURL.isEmpty, !authToken.isEmpty else { return }
        connectionStatus = .testing

        // Save credentials so APIClient can read them for the test
        UserDefaults.standard.set(serverURL, forKey: "serverURL")
        _ = KeychainService.save(key: "authToken", value: authToken)

        Task {
            do {
                let api = APIClient()
                _ = try await api.fetchHealth()
                do {
                    _ = try await api.fetchSessions()
                } catch let apiError as APIError {
                    if apiError.statusCode == 401 {
                        throw apiError
                    }
                    // Non-auth API failures (for example no tmux sessions yet) still
                    // prove token acceptance by the server.
                }
                connectionStatus = .success
                try? await Task.sleep(for: .milliseconds(800))
                withAnimation { currentStep = 2 }
            } catch {
                // Clear invalid credentials so they don't persist
                UserDefaults.standard.removeObject(forKey: "serverURL")
                KeychainService.delete(key: "authToken")
                connectionStatus = .failure(error.localizedDescription)
            }
        }
    }

    private func completeOnboarding() {
        // Save whatever is entered even if not tested
        if !serverURL.isEmpty {
            UserDefaults.standard.set(serverURL, forKey: "serverURL")
        }
        if !authToken.isEmpty {
            _ = KeychainService.save(key: "authToken", value: authToken)
        }
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        NotificationService.requestPermission()
        withAnimation { isComplete = true }
    }

    private func activateDemo() {
        DemoData.activate()
        UserDefaults.standard.set("http://127.0.0.1:8787", forKey: "serverURL")
        UserDefaults.standard.set(true, forKey: "onboardingComplete")
        withAnimation { isComplete = true }
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

        captureSession = session
        Task.detached { session.startRunning() }
    }

    func metadataOutput(_ output: AVCaptureMetadataOutput, didOutput metadataObjects: [AVMetadataObject], from connection: AVCaptureConnection) {
        guard let obj = metadataObjects.first as? AVMetadataMachineReadableCodeObject,
              let value = obj.stringValue else { return }
        captureSession?.stopRunning()
        dismiss(animated: true) { [weak self] in
            self?.onResult?(value)
        }
    }

    override func viewWillDisappear(_ animated: Bool) {
        super.viewWillDisappear(animated)
        captureSession?.stopRunning()
    }
}
