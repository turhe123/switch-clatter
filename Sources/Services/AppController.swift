import AppKit
import CoreGraphics
import Combine

/// UserDefaults keys and defaults shared by `@AppStorage` views and the controller.
enum Prefs {
    static let enabled = "enabled"
    static let profile = "profile"
    static let volume = "volume"
    static let pitchVariance = "pitchVariance"
    static let stereoSpread = "stereoSpread"
    static let playRelease = "playRelease"
    static let playModifiers = "playModifiers"
    static let mutedApps = "mutedApps"

    static func register() {
        UserDefaults.standard.register(defaults: [
            enabled: true, profile: SwitchProfile.linear.rawValue, volume: 0.6,
            pitchVariance: 0.5, stereoSpread: true, playRelease: true,
            playModifiers: false, mutedApps: "",
        ])
    }

    /// Muted bundle identifiers, stored as a newline-separated string for `@AppStorage`.
    static func decodeApps(_ raw: String) -> [String] {
        raw.split(separator: "\n").map(String.init).filter { !$0.isEmpty }
    }
}

/// Central coordinator: owns the key listener and sound engine, tracks Input Monitoring
/// permission, screen lock and the frontmost app, and decides whether each key makes a sound.
final class AppController: ObservableObject {
    static let shared = AppController()

    @Published private(set) var hasPermission = false
    @Published private(set) var tapFailed = false
    @Published private(set) var engineError: String?
    @Published private(set) var screenLocked = false
    @Published private(set) var frontmostBundleID: String?

    private let sound = SoundEngine()
    private let listener = KeyListener()
    private var pollTimer: Timer?
    private var observers: [NSObjectProtocol] = []
    private let defaults = UserDefaults.standard

    private init() {
        Prefs.register()
        sound.onStateChange = { [weak self] in self?.engineError = self?.sound.lastError }
        sound.prepare(currentProfile)
        sound.start()
        listener.onKey = { [weak self] in self?.handle($0) }
        frontmostBundleID = NSWorkspace.shared.frontmostApplication?.bundleIdentifier
        observeSystem()
        refreshPermission()
    }

    private var currentProfile: SwitchProfile {
        SwitchProfile(rawValue: defaults.string(forKey: Prefs.profile) ?? "") ?? .linear
    }

    // MARK: Permission

    func refreshPermission() {
        hasPermission = CGPreflightListenEventAccess()
        if hasPermission, !listener.isRunning {
            tapFailed = !listener.start()
        }
    }

    /// Prompts for Input Monitoring, opens the privacy pane and polls until access is granted.
    func requestPermission() {
        if !CGRequestListenEventAccess(),
           let url = URL(string: "x-apple.systempreferences:com.apple.preference.security?Privacy_ListenEvent") {
            NSWorkspace.shared.open(url)
        }
        pollTimer?.invalidate()
        var ticks = 0
        pollTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] timer in
            ticks += 1
            self?.refreshPermission()
            if self?.hasPermission != false || ticks > 120 { timer.invalidate() }
        }
    }

    func retryAudio() {
        sound.start()
    }

    // MARK: Muting

    /// Human-readable reason sounds are currently suppressed, or nil.
    func muteReason(mutedApps: String) -> String? {
        if screenLocked { return "Muted while the screen is locked" }
        if let id = frontmostBundleID, Prefs.decodeApps(mutedApps).contains(id) {
            let name = NSRunningApplication.runningApplications(withBundleIdentifier: id).first?.localizedName ?? id
            return "Muted while \(name) is frontmost"
        }
        return nil
    }

    private func observeSystem() {
        let workspace = NSWorkspace.shared.notificationCenter
        observers.append(workspace.addObserver(forName: NSWorkspace.didActivateApplicationNotification,
                                               object: nil, queue: .main) { [weak self] note in
            let app = note.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication
            self?.frontmostBundleID = app?.bundleIdentifier
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidResignActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
        })
        observers.append(workspace.addObserver(forName: NSWorkspace.sessionDidBecomeActiveNotification,
                                               object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
        })
        let distributed = DistributedNotificationCenter.default()
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsLocked"),
                                                 object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = true
        })
        observers.append(distributed.addObserver(forName: Notification.Name("com.apple.screenIsUnlocked"),
                                                 object: nil, queue: .main) { [weak self] _ in
            self?.screenLocked = false
        })
    }

    // MARK: Playback

    private func handle(_ event: KeyEventInfo) {
        guard defaults.bool(forKey: Prefs.enabled),
              muteReason(mutedApps: defaults.string(forKey: Prefs.mutedApps) ?? "") == nil else { return }
        if event.isModifier, !defaults.bool(forKey: Prefs.playModifiers) { return }
        if !event.isDown, !defaults.bool(forKey: Prefs.playRelease) { return }
        play(event)
    }

    private func play(_ event: KeyEventInfo) {
        let spread = defaults.bool(forKey: Prefs.stereoSpread)
        let pan = spread ? (KeyLayout.position(for: event.keyCode) * 2 - 1) * 0.8 : 0
        sound.play(KeyClass.from(event), isDown: event.isDown, profile: currentProfile,
                   volume: defaults.double(forKey: Prefs.volume),
                   variance: defaults.double(forKey: Prefs.pitchVariance), pan: pan)
    }

    /// Plays a short sample so the user can hear the current settings.
    func preview() {
        for (i, code) in [Int64(0), 1, 2, 49].enumerated() {
            DispatchQueue.main.asyncAfter(deadline: .now() + Double(i) * 0.14) { [weak self] in
                self?.play(KeyEventInfo(keyCode: code, isDown: true, isModifier: false))
            }
        }
    }
}
