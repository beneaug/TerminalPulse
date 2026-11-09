import SwiftUI
import UIKit

struct ContentView: View {
    @AppStorage("protectScreenPreviews") private var protectScreenPreviews = true
    @State private var polling = PollingService.shared
    @State private var watchBridge = WatchBridge.shared
    @State private var onboardingComplete = UserDefaults.standard.bool(forKey: "onboardingComplete")
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        Group {
            if onboardingComplete {
                mainContent
            } else {
                OnboardingView(isComplete: $onboardingComplete)
            }
        }
        .accessibilityHidden(protectScreenPreviews && scenePhase != .active)
        .background(ScreenPreviewShield(enabled: protectScreenPreviews))
    }

    private var mainContent: some View {
        TabView {
            NavigationStack {
                TerminalView(polling: polling, watchReachable: watchBridge.isReachable)
                    .navigationTitle("tmuxonwatch")
                    .navigationBarTitleDisplayMode(.inline)
            }
            .tabItem {
                Label("Terminal", systemImage: "terminal")
            }

            NavigationStack {
                SettingsView(
                    watchReachable: watchBridge.isReachable,
                    onPollIntervalChanged: { polling.restartTimer(); polling.syncSettingsToWatch() },
                    onAppearanceChanged: {
                        polling.rerender()
                        polling.syncSettingsToWatch()
                    },
                    onDemoLoaded: {
                        polling.startDemoAnimation()
                    },
                    onServerConnected: {
                        if DemoData.isDemo {
                            DemoData.deactivate()
                            polling.stopDemoAnimation()
                        }
                        polling.fetchNow()
                    }
                )
            }
            .tabItem {
                Label("Settings", systemImage: "gear")
            }
        }
        .tint(TerminalColors.productAccent)
        .onAppear {
            polling.start()
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .background:
                polling.enterBackground()
            case .inactive:
                break
            case .active:
                polling.enterForeground()
            @unknown default:
                break
            }
        }
    }
}

/// Covers the whole scene's windows, not just the terminal's SwiftUI subtree.
/// A sheet (including credentials or a composer) is above that subtree. Keeping
/// the subtree mounted also preserves drafts and avoids repeated onAppear work.
private struct ScreenPreviewShield: UIViewRepresentable {
    let enabled: Bool

    func makeUIView(context: Context) -> ShieldAnchorView { ShieldAnchorView() }

    func updateUIView(_ uiView: ShieldAnchorView, context: Context) {
        uiView.protectionEnabled = enabled
        uiView.refresh()
    }

    static func dismantleUIView(_ uiView: ShieldAnchorView, coordinator: ()) {
        uiView.removeShields()
    }
}

private final class ShieldAnchorView: UIView {
    var protectionEnabled = true
    private var observers: [NSObjectProtocol] = []
    private var lifecycleInactive: Bool?
    private var shields: [(window: UIWindow, cover: UIView, hidden: [(UIView, Bool)])] = []

    override init(frame: CGRect) {
        super.init(frame: frame)
        isUserInteractionEnabled = false
        // willDeactivate is synchronous: install before iOS takes its snapshot.
        for name in [UIScene.willDeactivateNotification, UIScene.didEnterBackgroundNotification,
                     UIScene.willEnterForegroundNotification] {
            observers.append(NotificationCenter.default.addObserver(forName: name, object: nil, queue: .main) { [weak self] note in
                guard let self, let scene = note.object as? UIWindowScene,
                      scene === self.window?.windowScene else { return }
                self.refresh(forceInactive: true)
            })
        }
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didActivateNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let scene = note.object as? UIWindowScene,
                  scene === self.window?.windowScene else { return }
            self.lifecycleInactive = false
            self.removeShields()
        })
        observers.append(NotificationCenter.default.addObserver(forName: UIScene.didDisconnectNotification, object: nil, queue: .main) { [weak self] note in
            guard let self, let scene = note.object as? UIWindowScene,
                  scene === self.window?.windowScene else { return }
            self.removeShields()
        })
    }

    required init?(coder: NSCoder) { fatalError("init(coder:) has not been implemented") }

    deinit {
        observers.forEach(NotificationCenter.default.removeObserver)
    }

    override func didMoveToWindow() {
        super.didMoveToWindow()
        refresh()
    }

    func refresh(forceInactive: Bool = false) {
        if forceInactive { lifecycleInactive = true }
        guard protectionEnabled, let scene = window?.windowScene,
              lifecycleInactive ?? (scene.activationState != .foregroundActive) else {
            removeShields()
            return
        }
        for target in scene.windows where !target.isHidden {
            if let existing = shields.first(where: { $0.window === target }) {
                target.bringSubviewToFront(existing.cover)
                continue
            }
            let cover = UIView(frame: target.bounds)
            cover.autoresizingMask = [.flexibleWidth, .flexibleHeight]
            cover.backgroundColor = UIColor(white: 0.04, alpha: 1)
            cover.isOpaque = true
            cover.isUserInteractionEnabled = true
            cover.isAccessibilityElement = true
            cover.accessibilityLabel = String(localized: "Screen preview hidden")
            cover.accessibilityViewIsModal = true
            let icon = UIImageView(image: UIImage(systemName: "lock.shield"))
            icon.tintColor = .secondaryLabel
            icon.translatesAutoresizingMaskIntoConstraints = false
            icon.isAccessibilityElement = false
            cover.addSubview(icon)
            NSLayoutConstraint.activate([
                icon.centerXAnchor.constraint(equalTo: cover.centerXAnchor),
                icon.centerYAnchor.constraint(equalTo: cover.centerYAnchor),
                icon.widthAnchor.constraint(equalToConstant: 32),
                icon.heightAnchor.constraint(equalToConstant: 36)
            ])
            let original = target.subviews.map { ($0, $0.accessibilityElementsHidden) }
            original.forEach { $0.0.accessibilityElementsHidden = true }
            target.addSubview(cover)
            shields.append((target, cover, original))
        }
    }

    func removeShields() {
        for shield in shields {
            shield.cover.removeFromSuperview()
            shield.hidden.forEach { $0.0.accessibilityElementsHidden = $0.1 }
        }
        shields.removeAll()
    }
}
