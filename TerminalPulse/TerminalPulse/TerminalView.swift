import SwiftUI
import UIKit

private struct ReadingSnapshot: Identifiable {
    let id = UUID()
    let title: String
    let lines: [AttributedString]
    let text: String
    let date: Date
}

private struct InputTarget: Identifiable {
    let id = UUID()
    let paneID: String?
    let label: String
    let inputContextID: String?
}

struct TerminalView: View {
    @Bindable var polling: PollingService
    var watchReachable: Bool
    @State private var showSessionPicker = false
    @State private var inputTarget: InputTarget?
    @State private var readingSnapshot: ReadingSnapshot?
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 2))
            : AnyLayout(HStackLayout(spacing: 8))
    }

    var body: some View {
        VStack(spacing: 0) {
            WorkspaceHeader(polling: polling, watchReachable: watchReachable) {
                polling.refreshSessions()
                showSessionPicker = true
            }
            TerminalContentView(polling: polling)
            if let error = polling.errorMessage, !DemoData.isDemo {
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "wifi.exclamationmark")
                    Text(error).font(.footnote).lineLimit(3)
                    Spacer(minLength: 0)
                    Button("Retry") { polling.fetchNow() }.font(.footnote.weight(.semibold))
                }
                .foregroundStyle(.orange)
                .padding(16)
                .background(.orange.opacity(0.08))
            }
            actionLayout {
                action("Read & Find", icon: "text.magnifyingglass", enabled: !polling.renderedLines.isEmpty) {
                    readingSnapshot = ReadingSnapshot(title: polling.sessionLabel, lines: polling.renderedLines,
                                                       text: polling.plainOutput, date: polling.lastUpdate ?? Date())
                }
                action("Refresh", icon: "arrow.clockwise", enabled: !polling.isRefreshing) { polling.fetchNow() }
                action("Input", icon: "keyboard") {
                    inputTarget = InputTarget(paneID: polling.currentPayload?.paneId, label: polling.sessionLabel,
                                              inputContextID: polling.currentPayloadInputContextID)
                }
            }
            .padding(.horizontal, 18)
            .padding(.vertical, 5)
            .background(TerminalColors.chromeSurface)
            .overlay(alignment: .top) { Divider().opacity(0.35) }
        }
        .background(TerminalColors.defaultBackground)
        .onChange(of: dynamicTypeSize) { polling.rerender() }
        .sheet(isPresented: $showSessionPicker) {
            SessionPickerView(sessions: polling.sessions, windowsBySession: polling.windowsBySession,
                              selectedTarget: polling.selectedTarget) { target in
                polling.selectTarget(target)
                showSessionPicker = false
            }
            .presentationDetents([.medium, .large])
            .presentationDragIndicator(.visible)
        }
        .sheet(item: $readingSnapshot) { snapshot in ReadingView(snapshot: snapshot) }
        .sheet(item: $inputTarget) { target in
            PhoneInputView(polling: polling, paneID: target.paneID, paneLabel: target.label, inputContextID: target.inputContextID)
        }
    }

    private func action(_ title: LocalizedStringKey, icon: String, enabled: Bool = true,
                        perform: @escaping () -> Void) -> some View {
        Button(action: perform) {
            Label(title, systemImage: icon)
                .font(.subheadline.weight(.medium))
                .frame(maxWidth: .infinity, alignment: dynamicTypeSize.isAccessibilitySize ? .leading : .center)
                .frame(minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(enabled ? TerminalColors.productAccent : .secondary)
        .disabled(!enabled)
    }
}

private struct WorkspaceHeader: View {
    let polling: PollingService
    let watchReachable: Bool
    let selectTarget: () -> Void
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var statusLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize ? AnyLayout(VStackLayout(alignment: .leading, spacing: 6))
            : AnyLayout(HStackLayout(spacing: 12))
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 6) {
                    Text(polling.hostLabel.isEmpty ? String(localized: "YOUR WORKSPACE") : polling.hostLabel.uppercased())
                        .font(.caption2.weight(.semibold)).tracking(1.5)
                        .foregroundStyle(.secondary)
                    Button(action: selectTarget) {
                        HStack(spacing: 9) {
                            Text(polling.sessionLabel.isEmpty ? String(localized: "Choose a session") : polling.sessionLabel)
                                .font(.title2.weight(.semibold)).lineLimit(1)
                            Image(systemName: "chevron.down").font(.caption.weight(.bold))
                                .foregroundStyle(.secondary)
                        }
                        .frame(minHeight: 32, alignment: .leading)
                        .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(Text("Switch session, currently \(polling.sessionLabel)"))
                }
                Spacer(minLength: 0)
                Image(systemName: polling.selectedTarget == nil ? "scope" : "pin")
                    .font(.title3.weight(.medium))
                    .foregroundStyle(TerminalColors.productAccent)
                    .frame(width: 44, height: 44)
                    .background(TerminalColors.productAccent.opacity(0.09), in: RoundedRectangle(cornerRadius: 14))
                    .accessibilityLabel(polling.selectedTarget == nil ? "Following tmux focus" : "Pinned target")
            }
            statusLayout {
                Label {
                    Text(DemoData.isDemo ? "Preview" : (polling.isConnected ? "Live" : "Reconnecting"))
                } icon: {
                    Circle().fill(DemoData.isDemo ? Color.secondary : (polling.isConnected ? TerminalColors.productAccent : .orange))
                        .frame(width: 6, height: 6)
                }
                .font(.caption.weight(.medium))
                .foregroundStyle(.primary)
                if !dynamicTypeSize.isAccessibilitySize {
                    Rectangle().fill(.quaternary).frame(width: 1, height: 12)
                }
                Label(watchReachable ? "Watch connected" : "Watch on standby", systemImage: "applewatch")
                    .font(.caption).foregroundStyle(.secondary).lineLimit(1)
                if !dynamicTypeSize.isAccessibilitySize { Spacer(minLength: 0) }
                if let date = polling.lastUpdate {
                    Text(date, format: .dateTime.hour().minute())
                        .font(.caption.monospacedDigit()).foregroundStyle(.secondary)
                        .accessibilityLabel(Text("Last checked \(date.formatted(date: .omitted, time: .shortened))"))
                }
            }
        }
        .padding(20)
        .background(TerminalColors.chromeSurface)
        .overlay(alignment: .bottom) { Divider().opacity(0.35) }
    }
}

private struct TerminalContentView: View {
    let polling: PollingService

    var body: some View {
        // Capture one value for this render transaction; a live array can shrink
        // before SwiftUI evaluates a retained lazy row.
        let lines = polling.renderedLines
        Group {
            if lines.isEmpty {
                ContentUnavailableView {
                    Label("Your terminal, within reach", systemImage: "terminal")
                } description: {
                    Text("Connect your Mac in Settings, or explore the demo. Your watch will follow along.")
                } actions: {
                    Button("Try the demo") {
                        DemoData.activate()
                        polling.startDemoAnimation()
                    }
                    .buttonStyle(.bordered)
                }
            } else {
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 2) {
                        ForEach(lines.indices, id: \.self) { index in
                            Text(lines[index])
                                .frame(maxWidth: .infinity, alignment: .leading)
                        }
                    }
                    .padding(.horizontal, 16)
                    .padding(.vertical, 18)
                    .accessibilityLabel("Terminal output")
                }
                .defaultScrollAnchor(.bottom)
                .refreshable { await polling.fetchAndWait() }
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}

private struct ReadingView: View {
    let snapshot: ReadingSnapshot
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var copied = false

    private var matches: [Int] {
        snapshot.lines.indices.filter { query.isEmpty || String(snapshot.lines[$0].characters).localizedStandardContains(query) }
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                HStack {
                    Label("Reading snapshot", systemImage: "pause.circle")
                    Spacer()
                    Text(snapshot.date, format: .dateTime.hour().minute())
                }
                .font(.caption).foregroundStyle(.secondary).padding(16)
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(matches, id: \.self) { index in
                            HStack(alignment: .top, spacing: 12) {
                                Text("\(index + 1)").font(.caption2.monospacedDigit())
                                    .foregroundStyle(.tertiary).frame(width: 26, alignment: .trailing)
                                Text(snapshot.lines[index]).textSelection(.enabled)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }
                        }
                    }.padding(.horizontal, 16)
                }
                if !query.isEmpty {
                    Text("\(matches.count) matching lines").font(.caption).foregroundStyle(.secondary).padding(12)
                }
                Text("The live stream continues on your watch.")
                    .font(.footnote).foregroundStyle(.secondary).padding(16)
            }
            .background(TerminalColors.defaultBackground)
            .navigationTitle(snapshot.title.isEmpty ? String(localized: "Read & Find") : snapshot.title)
            .navigationBarTitleDisplayMode(.inline)
            .searchable(text: $query, prompt: "Find in output")
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } }
                ToolbarItemGroup(placement: .primaryAction) {
                    Button {
                        UIPasteboard.general.string = snapshot.text
                        copied = true
                    } label: { Image(systemName: copied ? "checkmark" : "doc.on.doc") }
                    .accessibilityLabel(copied ? "Copied" : "Copy output")
                    ShareLink(item: snapshot.text).accessibilityLabel("Share snapshot")
                }
            }
        }
        .tint(TerminalColors.productAccent)
    }
}

private struct PhoneInputView: View {
    let polling: PollingService
    let paneID: String?
    let paneLabel: String
    let inputContextID: String?
    @Environment(\.dismiss) private var dismiss
    @State private var text = ""
    @State private var sending = false
    @State private var result: String?
    @State private var failed = false
    @State private var shortcuts = UserDefaults.standard.stringArray(forKey: "savedInputShortcuts") ?? []

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Label(paneLabel.isEmpty ? String(localized: "No terminal connected") : paneLabel, systemImage: "terminal")
                        .font(.headline)
                    Text("Send text to this pane, then press Return when you’re ready to run it.")
                        .font(.subheadline).foregroundStyle(.secondary)
                }
                if StoreManager.shared.isProUnlocked || DemoData.isDemo {
                    if DemoData.isDemo {
                        Section {
                            Label("Input preview", systemImage: "sparkle")
                            Text("Explore the composer. Connect a terminal and unlock Pro to send input.")
                                .font(.footnote).foregroundStyle(.secondary)
                        }
                    }
                    Section("Compose") {
                        TextField("Type a command or reply", text: $text, axis: .vertical)
                            .font(.system(.body, design: .monospaced))
                            .autocorrectionDisabled().textInputAutocapitalization(.never)
                            .lineLimit(3...6)
                            .onChange(of: text) { _, value in
                                if value.count > 512 { text = String(value.prefix(512)) }
                            }
                        Button { send(text: text) } label: {
                            Label(sending ? "Sending…" : "Send text", systemImage: "arrow.up.circle.fill")
                        }
                        .disabled(text.isEmpty || sending || paneID == nil || DemoData.isDemo)
                        HStack {
                            Button("Return") { send(special: "Enter") }
                            Spacer()
                            Button("Escape") { send(special: "Escape") }
                            Spacer()
                            Button("Ctrl-C") { send(special: "C-c") }
                        }
                        .buttonStyle(.borderless)
                        .disabled(sending || paneID == nil || DemoData.isDemo)
                    }
                    if text.contains(where: { $0.isNewline }) {
                        Section {
                            Label("Line breaks can run commands immediately. Send one line at a time.", systemImage: "exclamationmark.triangle")
                                .font(.footnote).foregroundStyle(.orange)
                        }
                    }
                    if let result {
                        Section { Text(result).font(.footnote).foregroundStyle(failed ? Color.orange : TerminalColors.productAccent) }
                    }
                    Section {
                        ForEach(shortcuts, id: \.self) { shortcut in
                            Button { text = shortcut } label: {
                                Text(shortcut).font(.system(.subheadline, design: .monospaced)).lineLimit(2)
                            }
                        }
                        .onDelete { offsets in
                            shortcuts.remove(atOffsets: offsets)
                            saveShortcuts()
                        }
                        Button("Save as shortcut") {
                            shortcuts.append(text)
                            saveShortcuts()
                        }
                        .disabled(text.isEmpty || shortcuts.contains(text) || shortcuts.count >= 8)
                    } header: { Text("Your shortcuts") }
                    footer: { Text("Saved on this iPhone. Choosing a shortcut fills the composer; it never runs automatically.") }
                } else {
                    Section {
                        Label("Reply from either screen", systemImage: "keyboard")
                            .font(.title3.weight(.semibold))
                        Text("Keep an eye on your work for free. With Pro, send input from your wrist or iPhone and keep your frequently used commands close.")
                            .foregroundStyle(.secondary)
                        SettingsView.ProUpgradeRow()
                    }
                }
            }
            .navigationTitle("Terminal input")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .cancellationAction) { Button("Done") { dismiss() } } }
        }
        .tint(TerminalColors.productAccent)
    }

    private func saveShortcuts() { UserDefaults.standard.set(shortcuts, forKey: "savedInputShortcuts") }

    private func send(text: String? = nil, special: String? = nil) {
        guard !sending, let paneID else { return }
        if text?.contains(where: { $0.isNewline }) == true {
            result = String(localized: "Line breaks can run commands immediately. Send one line at a time.")
            failed = true
            return
        }
        sending = true
        result = nil
        Task { @MainActor in
            do {
                try await polling.sendInput(text: text, special: special, paneID: paneID, inputContextID: inputContextID)
                result = text != nil ? String(localized: "Text sent. Press Return to run.") : String(localized: "Key sent.")
                failed = false
                if text != nil { self.text = "" }
            } catch {
                result = error.localizedDescription
                failed = true
            }
            sending = false
        }
    }
}

struct SessionPickerView: View {
    let sessions: [SessionInfo]
    let windowsBySession: [String: [WindowInfoResponse]]
    let selectedTarget: String?
    let onSelect: (String?) -> Void

    var body: some View {
        NavigationStack {
            List {
                Section {
                    targetRow(String(localized: "Follow tmux focus"), detail: "Always show the active pane", icon: "scope", target: nil)
                } footer: { Text("Pin a session or window to keep it on your phone and watch.") }
                ForEach(sessions, id: \.name) { session in
                    Section(session.name) {
                        targetRow(session.name, detail: session.attached ? "Attached" : "Running", icon: "rectangle.stack", target: session.name)
                        ForEach(windowsBySession[session.name] ?? [], id: \.index) { window in
                            targetRow("\(window.index) · \(window.name)", detail: window.active ? "Active window" : "Window",
                                      icon: "terminal", target: "\(session.name):\(window.index)")
                        }
                    }
                }
            }
            .navigationTitle("Sessions")
            .navigationBarTitleDisplayMode(.inline)
        }
        .tint(TerminalColors.productAccent)
    }

    private func targetRow(_ title: String, detail: LocalizedStringKey, icon: String, target: String?) -> some View {
        Button { onSelect(target) } label: {
            HStack(spacing: 12) {
                Image(systemName: icon).foregroundStyle(TerminalColors.productAccent).frame(width: 24)
                VStack(alignment: .leading, spacing: 4) {
                    Text(title).font(.system(.body, design: .monospaced)).foregroundStyle(.primary)
                    Text(detail).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                if selectedTarget == target { Image(systemName: "checkmark").foregroundStyle(TerminalColors.productAccent) }
            }.padding(.vertical, 4)
        }
        .buttonStyle(.plain)
    }
}
