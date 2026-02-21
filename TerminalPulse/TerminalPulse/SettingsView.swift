import SwiftUI

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

    var watchReachable: Bool
    var onPollIntervalChanged: (() -> Void)?
    var onAppearanceChanged: (() -> Void)?

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
                }

                VStack(alignment: .leading, spacing: 4) {
                    Text("AUTH TOKEN")
                        .font(.system(size: 10, weight: .semibold, design: .monospaced))
                        .foregroundStyle(.secondary)
                    SecureField("Token", text: $authToken)
                        .font(.system(size: 14, design: .monospaced))
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
        }
        .navigationTitle("Settings")
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
}
