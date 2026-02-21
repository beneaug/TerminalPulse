import SwiftUI
import WatchKit

struct WatchTerminalView: View {
    @Bindable var bridge: PhoneBridge
    @State private var showTextInput = false

    var body: some View {
        ZStack(alignment: .top) {
            TerminalColors.defaultBackground
                .ignoresSafeArea()

            WatchTerminalContent(bridge: bridge)

            WatchStatusOverlay(bridge: bridge)

            if bridge.isProUnlocked {
                VStack {
                    Spacer()
                    WatchInputToolbar(bridge: bridge, showTextInput: $showTextInput)
                }
            }
        }
        .ignoresSafeArea()
        .onAppear { bridge.startAutoRefresh() }
        .onDisappear { bridge.stopAutoRefresh() }
        .sheet(isPresented: $showTextInput) {
            WatchTextInputView(bridge: bridge)
        }
    }
}

// MARK: - Terminal Content (observes ONLY renderedLines)

private struct WatchTerminalContent: View {
    let bridge: PhoneBridge

    var body: some View {
        if bridge.renderedLines.isEmpty {
            VStack(spacing: 6) {
                Spacer()
                Image(systemName: "terminal")
                    .font(.system(size: 24))
                    .foregroundStyle(.white.opacity(0.2))
                Text("Waiting for data...")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.3))
                Spacer()
            }
        } else {
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 0) {
                    ForEach(Array(bridge.renderedLines.enumerated()), id: \.offset) { _, line in
                        Text(line)
                            .frame(maxWidth: .infinity, alignment: .leading)
                    }
                }
                .padding(.top, 14)
                .padding(.horizontal, 2)
                .padding(.bottom, 40)
            }
            .defaultScrollAnchor(.bottom)
            .ignoresSafeArea()
        }
    }
}

// MARK: - Status Overlay (observes isConnected, sessionLabel, lastUpdate)

private struct WatchStatusOverlay: View {
    let bridge: PhoneBridge

    var body: some View {
        HStack(spacing: 3) {
            Circle()
                .fill(bridge.isConnected ? .green : .red)
                .frame(width: 4, height: 4)
                .accessibilityLabel(bridge.isConnected ? "Connected" : "Disconnected")

            if !bridge.sessionLabel.isEmpty {
                Text(bridge.sessionLabel)
                    .font(.system(size: 8, weight: .medium, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.7))
                    .lineLimit(1)
            }

            Spacer()

            if let lastUpdate = bridge.lastUpdate {
                Text(lastUpdate, style: .relative)
                    .font(.system(size: 7, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.35))
                    .lineLimit(1)
            }

            Button {
                bridge.requestRefresh()
            } label: {
                Image(systemName: "arrow.clockwise")
                    .font(.system(size: 8, weight: .medium))
                    .foregroundStyle(.white.opacity(0.4))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Refresh")
        }
        .padding(.horizontal, 2)
        .padding(.top, 1)
        .background(
            LinearGradient(
                colors: [
                    TerminalColors.defaultBackground,
                    TerminalColors.defaultBackground.opacity(0.6),
                    .clear
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
    }
}

// MARK: - Input Toolbar

private struct ToolbarKey: Identifiable {
    let id: String
    let label: String
    let special: String
    let supportsHold: Bool
}

private let primaryKeys: [ToolbarKey] = [
    .init(id: "up", label: "▲", special: "Up", supportsHold: false),
    .init(id: "down", label: "▼", special: "Down", supportsHold: false),
    .init(id: "enter", label: "Enter", special: "Enter", supportsHold: false),
    .init(id: "esc", label: "Esc", special: "Escape", supportsHold: true),
    .init(id: "kbd", label: "⌨", special: "", supportsHold: false),
]

private let secondaryKeys: [ToolbarKey] = [
    .init(id: "ctrlc", label: "^C", special: "C-c", supportsHold: true),
    .init(id: "tab", label: "Tab", special: "Tab", supportsHold: true),
    .init(id: "ctrld", label: "^D", special: "C-d", supportsHold: true),
    .init(id: "ctrlz", label: "^Z", special: "C-z", supportsHold: true),
    .init(id: "ctrll", label: "^L", special: "C-l", supportsHold: true),
    .init(id: "left", label: "◄", special: "Left", supportsHold: false),
    .init(id: "right", label: "►", special: "Right", supportsHold: false),
]

private struct WatchInputToolbar: View {
    let bridge: PhoneBridge
    @Binding var showTextInput: Bool
    @State private var holdingKey: String?
    @State private var holdTimer: Timer?

    var body: some View {
        VStack(spacing: 0) {
            // Send status flash
            if case .sent(let label) = bridge.sendStatus {
                Text("sent: \(label)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.green.opacity(0.7))
                    .transition(.opacity)
            } else if case .error(let msg) = bridge.sendStatus {
                Text(msg)
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(.red.opacity(0.8))
                    .lineLimit(1)
                    .transition(.opacity)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(primaryKeys) { key in
                        if key.id == "kbd" {
                            ToolbarButton(label: key.label, isHolding: false) {
                                showTextInput = true
                            }
                        } else {
                            toolbarButton(for: key)
                        }
                    }

                    Divider()
                        .frame(height: 20)
                        .background(Color.white.opacity(0.1))

                    ForEach(secondaryKeys) { key in
                        toolbarButton(for: key)
                    }
                }
                .padding(.horizontal, 4)
            }
        }
        .padding(.bottom, 2)
        .background(
            LinearGradient(
                colors: [
                    .clear,
                    TerminalColors.defaultBackground.opacity(0.8),
                    TerminalColors.defaultBackground
                ],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .animation(.easeInOut(duration: 0.2), value: bridge.sendStatus)
    }

    @ViewBuilder
    private func toolbarButton(for key: ToolbarKey) -> some View {
        if key.supportsHold {
            ToolbarButton(label: key.label, isHolding: holdingKey == key.id) {
                bridge.sendKeys(special: key.special)
            }
            .onTapGesture(count: 2) {
                toggleHold(for: key)
            }
            .onTapGesture(count: 1) {
                bridge.sendKeys(special: key.special)
            }
        } else {
            ToolbarButton(label: key.label, isHolding: false) {
                bridge.sendKeys(special: key.special)
            }
        }
    }

    private func toggleHold(for key: ToolbarKey) {
        if holdingKey == key.id {
            // Stop holding
            stopHold()
            WKInterfaceDevice.current().play(.failure)
        } else {
            // Start holding
            stopHold()
            holdingKey = key.id
            WKInterfaceDevice.current().play(.success)
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                Task { @MainActor in
                    bridge.sendKeys(special: key.special)
                }
            }
        }
    }

    private func stopHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdingKey = nil
    }
}

private struct ToolbarButton: View {
    let label: String
    let isHolding: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Text(label)
                .font(.system(size: 11, weight: .medium, design: .monospaced))
                .foregroundStyle(isHolding ? .black : .white.opacity(0.85))
                .padding(.horizontal, 6)
                .padding(.vertical, 5)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHolding ? Color.green : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text Input Sheet

private struct WatchTextInputView: View {
    let bridge: PhoneBridge
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""

    var body: some View {
        VStack(spacing: 12) {
            Text("Send Text")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))

            TextField("Type or dictate", text: $text)
                .font(.system(size: 14, design: .monospaced))

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.5))

                Button("Done") {
                    if !text.isEmpty {
                        bridge.sendKeys(text: text)
                    }
                    dismiss()
                }
                .foregroundStyle(.green)
                .fontWeight(.semibold)
            }
        }
        .padding()
    }
}
