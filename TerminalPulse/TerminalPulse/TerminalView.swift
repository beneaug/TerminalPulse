import SwiftUI

struct TerminalView: View {
    @Bindable var polling: PollingService
    @State private var showSessionPicker = false

    var body: some View {
        VStack(spacing: 0) {
            TerminalStatusBar(polling: polling, onSessionTap: {
                polling.refreshSessions()
                showSessionPicker = true
            })

            TerminalContentView(polling: polling)

            TerminalErrorBanner(polling: polling)
        }
        .sheet(isPresented: $showSessionPicker) {
            SessionPickerView(
                sessions: polling.sessions,
                selectedTarget: polling.selectedTarget,
                onSelect: { target in
                    polling.selectTarget(target)
                    showSessionPicker = false
                }
            )
            .presentationDetents([.medium])
            .presentationDragIndicator(.visible)
        }
    }
}

// MARK: - Status Bar (observes isConnected, sessionLabel, lastUpdate)

private struct TerminalStatusBar: View {
    let polling: PollingService
    let onSessionTap: () -> Void

    var body: some View {
        HStack(spacing: 6) {
            Circle()
                .fill(polling.isConnected ? .green : .red)
                .frame(width: 6, height: 6)
                .accessibilityLabel(polling.isConnected ? "Connected" : "Disconnected")

            Button {
                onSessionTap()
            } label: {
                HStack(spacing: 4) {
                    if !polling.sessionLabel.isEmpty {
                        Text(polling.sessionLabel)
                            .font(.system(size: 11, weight: .medium, design: .monospaced))
                            .foregroundStyle(.green.opacity(0.8))
                    }
                    Image(systemName: "chevron.down")
                        .font(.system(size: 8, weight: .bold))
                        .foregroundStyle(.green.opacity(0.5))
                }
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Switch session, currently \(polling.sessionLabel)")

            Spacer()

            if let lastUpdate = polling.lastUpdate {
                Text(lastUpdate, style: .relative)
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.4))
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 6)
        .background(.black.opacity(0.8))
    }
}

// MARK: - Terminal Content (observes ONLY renderedLines — isolated from status bar updates)

private struct TerminalContentView: View {
    let polling: PollingService

    var body: some View {
        ScrollView {
            LazyVStack(alignment: .leading, spacing: 0) {
                ForEach(Array(polling.renderedLines.enumerated()), id: \.offset) { _, line in
                    Text(line)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            .padding(8)
            .accessibilityLabel("Terminal output")
        }
        .defaultScrollAnchor(.bottom)
        .refreshable {
            await polling.fetchAndWait()
        }
        .background(TerminalColors.defaultBackground)
    }
}

// MARK: - Error Banner (observes ONLY errorMessage)

private struct TerminalErrorBanner: View {
    let polling: PollingService

    var body: some View {
        if let error = polling.errorMessage {
            Text(error)
                .font(.system(size: 10, design: .monospaced))
                .foregroundStyle(.red)
                .padding(.horizontal, 12)
                .padding(.vertical, 4)
                .frame(maxWidth: .infinity)
                .background(.red.opacity(0.1))
        }
    }
}

// MARK: - Session Picker

struct SessionPickerView: View {
    let sessions: [SessionInfo]
    let selectedTarget: String?
    let onSelect: (String?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Button {
                    onSelect(nil)
                } label: {
                    HStack {
                        VStack(alignment: .leading) {
                            Text("Default")
                                .font(.system(size: 14, weight: .medium, design: .monospaced))
                            Text("Active pane")
                                .font(.system(size: 11))
                                .foregroundStyle(.secondary)
                        }
                        Spacer()
                        if selectedTarget == nil {
                            Image(systemName: "checkmark")
                                .foregroundStyle(.green)
                        }
                    }
                }
                .tint(.primary)

                ForEach(sessions, id: \.name) { session in
                    Button {
                        onSelect(session.name)
                    } label: {
                        HStack {
                            VStack(alignment: .leading) {
                                HStack(spacing: 6) {
                                    Text(session.name)
                                        .font(.system(size: 14, weight: .medium, design: .monospaced))
                                    if session.attached {
                                        Text("attached")
                                            .font(.system(size: 9, weight: .medium, design: .monospaced))
                                            .foregroundStyle(.green)
                                            .padding(.horizontal, 6)
                                            .padding(.vertical, 2)
                                            .background(.green.opacity(0.1))
                                            .clipShape(RoundedRectangle(cornerRadius: 4))
                                    }
                                }
                                Text("\(session.windows) window\(session.windows == 1 ? "" : "s")")
                                    .font(.system(size: 11))
                                    .foregroundStyle(.secondary)
                            }
                            Spacer()
                            if selectedTarget == session.name {
                                Image(systemName: "checkmark")
                                    .foregroundStyle(.green)
                            }
                        }
                    }
                    .tint(.primary)
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
        }
    }
}
