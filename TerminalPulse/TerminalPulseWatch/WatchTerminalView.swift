import SwiftUI
import WatchKit

struct WatchTerminalView: View {
    @Bindable var bridge: PhoneBridge

    var body: some View {
        ZStack(alignment: .top) {
            TerminalColors.defaultBackground
                .ignoresSafeArea()

            WatchTerminalContent(bridge: bridge)

            WatchStatusOverlay(bridge: bridge)
        }
        .ignoresSafeArea()
        .onAppear { bridge.startAutoRefresh() }
        .onDisappear { bridge.stopAutoRefresh() }
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
                .padding(.bottom, 2)
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
