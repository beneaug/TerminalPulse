import SwiftUI
import WatchKit

struct WatchTerminalView: View {
    @Bindable var bridge: PhoneBridge
    @State private var showTextInput = false
    @State private var inputDraft = ""
    @State private var inputPaneID: String?
    @State private var inputContextID: String?
    @State private var readingSnapshot: WatchReadingSnapshot<AttributedString>?
    @State private var visibleLine: Int?
    @AppStorage("protectScreenPreviews") private var protectScreenPreviews = true
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.scenePhase) private var scenePhase

    private var concealed: Bool {
        WatchDisplayPolicy.shouldConceal(
            protectScreenPreviews: protectScreenPreviews,
            isActive: scenePhase == .active,
            isLuminanceReduced: isLuminanceReduced
        )
    }

    var body: some View {
        ZStack(alignment: .top) {
            TerminalColors.defaultBackground.ignoresSafeArea()
            // Do not use an opacity overlay: private text must leave accessibility too.
            if concealed {
                VStack(spacing: 8) {
                    Image(systemName: "lock.fill")
                        .font(.title3)
                        .accessibilityHidden(true)
                    Text("Terminal hidden")
                        .font(.caption)
                    Text("Raise your wrist to view")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
            } else {
                VStack(spacing: 0) {
                    WatchStatusOverlay(bridge: bridge, sessionLabel: readingSnapshot?.sessionLabel ?? bridge.sessionLabel,
                                       isReading: readingSnapshot != nil)
                    HStack(spacing: 4) {
                        Text(LocalizedStringKey(readingSnapshot == nil ? "Live" : "Reading"))
                            .font(.caption2)
                            .foregroundStyle(.secondary)
                        Spacer(minLength: 0)
                        Button {
                            if readingSnapshot == nil {
                                readingSnapshot = WatchReadingSnapshot(lines: bridge.renderedLines, sessionLabel: bridge.sessionLabel)
                            } else {
                                readingSnapshot = nil
                            }
                        } label: {
                            Label(LocalizedStringKey(readingSnapshot == nil ? "Read" : "Latest"),
                                  systemImage: readingSnapshot == nil ? "pause.fill" : "arrow.down.to.line")
                                .font(.caption2)
                                .frame(minHeight: 32)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(Text(LocalizedStringKey(readingSnapshot == nil ? "Pause to read" : "Show latest output")))
                    }
                    .padding(.horizontal, 8)
                    WatchTerminalContent(bridge: bridge, snapshot: readingSnapshot, visibleLine: $visibleLine) { direction in
                        guard readingSnapshot == nil else { return }
                        bridge.switchSession(direction: direction)
                    }
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .clipped()
                    if bridge.isProUnlocked && !isLuminanceReduced && readingSnapshot == nil {
                        WatchInputToolbar(bridge: bridge) {
                            inputPaneID = bridge.currentPaneId
                            inputContextID = bridge.currentInputContextID
                            showTextInput = true
                        }
                    }
                }
                if readingSnapshot == nil {
                    WatchWindowSwitchOverlay(bridge: bridge)
                }
            }
        }
        .sheet(isPresented: $showTextInput) {
            // Remove sheet contents immediately, even during dismissal animation.
            if !concealed {
                WatchTextInputView(bridge: bridge, text: $inputDraft, paneID: inputPaneID, contextID: inputContextID)
            }
        }
        .onChange(of: concealed) { _, hidden in
            if hidden { showTextInput = false }
        }
        .onAppear {
            bridge.setLuminanceReduced(isLuminanceReduced)
        }
        .onChange(of: isLuminanceReduced) { _, reduced in
            bridge.setLuminanceReduced(reduced)
        }
    }
}

// MARK: - Terminal Content (observes ONLY renderedLines)

private struct WatchTerminalContent: View {
    let bridge: PhoneBridge
    let snapshot: WatchReadingSnapshot<AttributedString>?
    @Binding var visibleLine: Int?
    var onSessionSwipe: ((Int) -> Void)?
    private var isReading: Bool { snapshot != nil }
    @Environment(\.isLuminanceReduced) private var isLuminanceReduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var switchOffsetX: CGFloat = 0
    @State private var switchOpacity: Double = 1
    @State private var pendingScrollTask: Task<Void, Never>?
    private let swipeMinDistance: CGFloat = 14
    private let swipeAxisRatio: CGFloat = 1.05

    var body: some View {
        terminalBody
            .offset(x: switchOffsetX)
            .opacity(switchOpacity)
        .onDisappear {
            pendingScrollTask?.cancel()
            pendingScrollTask = nil
        }
        .onChange(of: bridge.sessionTransitionToken) {
            guard !isReading, !reduceMotion, !isLuminanceReduced else { return }
            let direction = bridge.sessionTransitionDirection >= 0 ? 1 : -1
            let startOffset: CGFloat = direction > 0 ? 12 : -12
            switchOffsetX = startOffset
            switchOpacity = 0.84
            withAnimation(.easeOut(duration: 0.18)) {
                switchOffsetX = 0
                switchOpacity = 1
            }
        }
        .onChange(of: isReading) { _, reading in
            if reading {
                pendingScrollTask?.cancel()
                pendingScrollTask = nil
                switchOffsetX = 0
                switchOpacity = 1
            }
        }
        .simultaneousGesture(
            DragGesture(minimumDistance: swipeMinDistance, coordinateSpace: .local)
                .onEnded { value in
                    let actualDx = value.translation.width
                    let actualDy = value.translation.height
                    let predictedDx = value.predictedEndTranslation.width
                    let predictedDy = value.predictedEndTranslation.height

                    // Use the larger of actual/predicted movement to catch short flicks.
                    let dx = abs(predictedDx) > abs(actualDx) ? predictedDx : actualDx
                    let dy = abs(predictedDy) > abs(actualDy) ? predictedDy : actualDy

                    guard abs(dx) >= swipeMinDistance else { return }
                    guard abs(dx) > abs(dy) * swipeAxisRatio else { return }
                    if dx < 0 {
                        onSessionSwipe?(1)
                    } else {
                        onSessionSwipe?(-1)
                    }
                }
        )
    }

    @ViewBuilder
    private var terminalBody: some View {
        let lines = snapshot?.lines ?? bridge.renderedLines
        if lines.isEmpty {
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
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 0) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text(lines[index])
                                .frame(maxWidth: .infinity, alignment: .leading)
                                .id(index)
                        }
                        Color.clear
                            .frame(height: 1)
                            .id("bottom")
                    }
                    .scrollTargetLayout()
                    .padding(.vertical, 6)
                    .padding(.horizontal, 6)
                }
                .defaultScrollAnchor(isReading ? .top : .bottom)
                .scrollPosition(id: $visibleLine)
                .onAppear {
                    if isReading, let visibleLine {
                        proxy.scrollTo(visibleLine, anchor: .top)
                    } else {
                        scrollToBottom(proxy)
                    }
                }
                .onChange(of: isReading) { _, reading in
                    if !reading { scrollToBottom(proxy) }
                }
                .onChange(of: bridge.renderedLines) {
                    scrollToBottom(proxy)
                }
                .onChange(of: bridge.sessionTransitionToken) {
                    scrollToBottom(proxy, settleDelayMs: 40)
                }
                .onChange(of: isLuminanceReduced) { _, reduced in
                    if !reduced {
                        scrollToBottom(proxy)
                    }
                }
            }
        }
    }

    private func scrollToBottom(_ proxy: ScrollViewProxy, settleDelayMs: Int = 0) {
        guard !isReading, !isLuminanceReduced else { return }
        pendingScrollTask?.cancel()
        pendingScrollTask = Task { @MainActor in
            await Task.yield()
            guard !Task.isCancelled else { return }
            if settleDelayMs > 0 {
                try? await Task.sleep(for: .milliseconds(settleDelayMs))
                guard !Task.isCancelled else { return }
            }
            proxy.scrollTo("bottom", anchor: .bottom)
        }
    }
}

private struct WatchWindowSwitchOverlay: View {
    let bridge: PhoneBridge
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if let label = bridge.switchedWindowLabel {
                Text(label)
                    .font(.system(size: 20, weight: .semibold, design: .monospaced))
                    .foregroundStyle(.white.opacity(0.95))
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
                    .background(Color.black.opacity(0.55))
                    .clipShape(Capsule())
                    .overlay(
                        Capsule()
                            .stroke(Color.white.opacity(0.2), lineWidth: 1)
                    )
                    .transition(.scale(scale: 0.9).combined(with: .opacity))
                    .id(bridge.switchedWindowFlashToken)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .center)
        .allowsHitTesting(false)
        .animation(reduceMotion ? nil : .easeOut(duration: 0.2), value: bridge.switchedWindowFlashToken)
    }
}

// MARK: - Status Overlay (observes isConnected, sessionLabel, lastUpdate)

private struct WatchStatusOverlay: View {
    let bridge: PhoneBridge
    let sessionLabel: String
    let isReading: Bool

    var body: some View {
        ZStack {
            HStack(spacing: 3) {
                Circle()
                    .fill(bridge.isConnected ? TerminalColors.productAccent : .red)
                    .frame(width: 4, height: 4)
                    .accessibilityLabel(bridge.isConnected ? "Connected" : "Disconnected")

                if !sessionLabel.isEmpty {
                    Text(sessionLabel)
                        .font(.system(size: 10, weight: .medium, design: .monospaced))
                        .foregroundStyle(TerminalColors.productAccent.opacity(0.72))
                        .lineLimit(1)
                }

                Spacer()

                Button {
                    bridge.requestRefresh()
                } label: {
                    Image(systemName: "arrow.clockwise")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(.secondary)
                        .frame(width: 28, height: 28)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Refresh")
                .disabled(isReading)
            }
        }
        .padding(.horizontal, 6)
        .padding(.top, 1)
        .background(TerminalColors.defaultBackground)
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
    .init(id: "up", label: "\u{25B2}\u{FE0E}", special: "Up", supportsHold: false),
    .init(id: "down", label: "\u{25BC}\u{FE0E}", special: "Down", supportsHold: false),
    .init(id: "enter", label: "Ret", special: "Enter", supportsHold: false),
    .init(id: "esc", label: "Esc", special: "Escape", supportsHold: true),
    .init(id: "kbd", label: "\u{2328}\u{FE0E}", special: "", supportsHold: false),
]

private let secondaryKeys: [ToolbarKey] = [
    .init(id: "ctrlc", label: "^C", special: "C-c", supportsHold: true),
    .init(id: "tab", label: "Tab", special: "Tab", supportsHold: true),
    .init(id: "ctrld", label: "^D", special: "C-d", supportsHold: true),
    .init(id: "ctrlz", label: "^Z", special: "C-z", supportsHold: true),
    .init(id: "ctrll", label: "^L", special: "C-l", supportsHold: true),
    .init(id: "left", label: "\u{25C4}\u{FE0E}", special: "Left", supportsHold: false),
    .init(id: "right", label: "\u{25BA}\u{FE0E}", special: "Right", supportsHold: false),
]

private struct WatchInputToolbar: View {
    let bridge: PhoneBridge
    let presentTextInput: () -> Void
    @State private var holdingKey: String?
    @State private var holdTimer: Timer?
    @State private var holdStartTime: Date?
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.isLuminanceReduced) private var reduced
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    private let holdMaxDuration: TimeInterval = 30

    var body: some View {
        VStack(spacing: 0) {
            // Send status flash
            if case .sent(let label) = bridge.sendStatus {
                Text("sent: \(label)")
                    .font(.system(size: 8, design: .monospaced))
                    .foregroundStyle(TerminalColors.productAccent.opacity(0.72))
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
                                presentTextInput()
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
        .background(TerminalColors.defaultBackground)
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: bridge.sendStatus)
        .onDisappear { stopHold() }
        .onChange(of: scenePhase) { _, phase in if phase != .active { stopHold() } }
        .onChange(of: reduced) { _, value in if value { stopHold() } }
    }

    @ViewBuilder
    private func toolbarButton(for key: ToolbarKey) -> some View {
        if key.supportsHold {
            ToolbarButton(label: key.label, isHolding: holdingKey == key.id) {
                bridge.sendKeys(special: key.special, expectedPaneID: bridge.currentPaneId, expectedContextID: bridge.currentInputContextID)
            }
            .onTapGesture(count: 2) {
                toggleHold(for: key)
            }
        } else {
            ToolbarButton(label: key.label, isHolding: false) {
                bridge.sendKeys(special: key.special, expectedPaneID: bridge.currentPaneId, expectedContextID: bridge.currentInputContextID)
            }
        }
    }

    private func toggleHold(for key: ToolbarKey) {
        if holdingKey == key.id {
            // Stop holding
            stopHold()
            WKInterfaceDevice.current().play(.failure)
        } else {
            // Bind repeat input to the same capture context and pane for its lifetime.
            stopHold()
            guard let contextID = bridge.currentInputContextID, let paneID = bridge.currentPaneId else { return }
            holdingKey = key.id
            holdStartTime = Date()
            WKInterfaceDevice.current().play(.success)
            holdTimer = Timer.scheduledTimer(withTimeInterval: 0.2, repeats: true) { _ in
                Task { @MainActor in
                    // A timer tick may already be queued when privacy/Reading removes the toolbar.
                    guard holdingKey == key.id, scenePhase == .active, !reduced else { return }
                    guard bridge.currentInputContextID == contextID, bridge.currentPaneId == paneID else {
                        stopHold()
                        return
                    }
                    // Auto-cancel after 30s to prevent runaway timer
                    if let start = holdStartTime, Date().timeIntervalSince(start) > holdMaxDuration {
                        stopHold()
                        WKInterfaceDevice.current().play(.failure)
                        return
                    }
                    bridge.sendKeys(special: key.special, expectedPaneID: paneID, expectedContextID: contextID)
                }
            }
        }
    }

    private func stopHold() {
        holdTimer?.invalidate()
        holdTimer = nil
        holdingKey = nil
        holdStartTime = nil
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
                .frame(minWidth: 20, minHeight: 32)
                .background(
                    RoundedRectangle(cornerRadius: 6)
                        .fill(isHolding ? TerminalColors.productAccent : Color.white.opacity(0.12))
                )
        }
        .buttonStyle(.plain)
    }
}

// MARK: - Text Input Sheet

private struct WatchTextInputView: View {
    let bridge: PhoneBridge
    @Environment(\.dismiss) private var dismiss
    @Binding var text: String
    let paneID: String?
    let contextID: String?

    var body: some View {
        VStack(spacing: 12) {
            Text("Send Text")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(.white.opacity(0.7))

            TextField("Type or dictate", text: $text)
                .font(.system(size: 14, design: .monospaced))

            if contextID == nil || contextID != bridge.currentInputContextID {
                Text("Refresh on iPhone to enable input.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                if contextID == nil {
                    Text("Update both apps if needed.")
                        .font(.caption2)
                        .foregroundStyle(.secondary)
                }
            } else if paneID != bridge.currentPaneId {
                Text("Pane changed. Reopen input.")
                    .font(.caption2)
                    .foregroundStyle(.secondary)
            }

            if case .error(let message) = bridge.sendStatus {
                Text(message)
                    .font(.caption2)
                    .foregroundStyle(.red)
            }

            HStack(spacing: 12) {
                Button("Cancel") {
                    dismiss()
                }
                .foregroundStyle(.white.opacity(0.5))

                Button("Send text") {
                    guard !text.isEmpty, let paneID, let contextID,
                          paneID == bridge.currentPaneId, contextID == bridge.currentInputContextID else { return }
                    let submittedText = text
                    bridge.sendKeys(text: submittedText, expectedPaneID: paneID, expectedContextID: contextID) { sent in
                        guard sent else { return }
                        if text == submittedText { text = "" }
                        dismiss()
                    }
                }
                .foregroundStyle(TerminalColors.productAccent)
                .fontWeight(.semibold)
                .disabled(text.isEmpty || paneID == nil || paneID != bridge.currentPaneId || contextID == nil || contextID != bridge.currentInputContextID || bridge.sendStatus == .sending)
            }
        }
        .padding()
    }
}
