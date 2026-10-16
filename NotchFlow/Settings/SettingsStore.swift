import Foundation
import ServiceManagement

/// User preferences, saved in UserDefaults.
@MainActor
final class SettingsStore: ObservableObject {
    private enum Key {
        static let openOnHover = "openOnHover"
        static let hapticsEnabled = "hapticsEnabled"
        static let showMicrophoneIndicator = "showMicrophoneIndicator"
        static let showChargingIndicator = "showChargingIndicator"
        static let showNowPlayingIndicator = "showNowPlayingIndicator"
        static let saveClipboardHistory = "saveClipboardHistory"
        static let universalMediaSupport = "universalMediaSupport"
        static let showMenuBarDrawer = "showMenuBarDrawer"
    }

    private let defaults = UserDefaults.standard

    /// Open the notch when the cursor comes close. When off, click the notch to open it.
    @Published var openOnHover: Bool {
        didSet { defaults.set(openOnHover, forKey: Key.openOnHover) }
    }

    @Published var hapticsEnabled: Bool {
        didSet { defaults.set(hapticsEnabled, forKey: Key.hapticsEnabled) }
    }

    /// Show an orange microphone next to the closed notch while an app is recording.
    @Published var showMicrophoneIndicator: Bool {
        didSet { defaults.set(showMicrophoneIndicator, forKey: Key.showMicrophoneIndicator) }
    }

    /// Briefly show the battery level next to the notch when the charger is connected.
    @Published var showChargingIndicator: Bool {
        didSet { defaults.set(showChargingIndicator, forKey: Key.showChargingIndicator) }
    }

    /// Show the album artwork and an equalizer next to the closed notch while music plays.
    @Published var showNowPlayingIndicator: Bool {
        didSet { defaults.set(showNowPlayingIndicator, forKey: Key.showNowPlayingIndicator) }
    }

    /// When off, new copies are not recorded. Existing history is kept.
    @Published var saveClipboardHistory: Bool {
        didSet { defaults.set(saveClipboardHistory, forKey: Key.saveClipboardHistory) }
    }

    /// Use the bundled mediaremote-adapter to see media from every app, browsers included.
    @Published var universalMediaSupport: Bool {
        didSet { defaults.set(universalMediaSupport, forKey: Key.universalMediaSupport) }
    }

    /// Show pinned apps and the menu bar's icons along the bottom of the open notch.
    @Published var showMenuBarDrawer: Bool {
        didSet { defaults.set(showMenuBarDrawer, forKey: Key.showMenuBarDrawer) }
    }

    @Published private(set) var launchAtLogin: Bool
    @Published private(set) var launchAtLoginError: String?

    init() {
        defaults.register(defaults: [
            Key.openOnHover: true,
            Key.hapticsEnabled: true,
            Key.showMicrophoneIndicator: true,
            Key.showChargingIndicator: true,
            Key.showNowPlayingIndicator: true,
            Key.saveClipboardHistory: true,
            Key.universalMediaSupport: false,
            Key.showMenuBarDrawer: true,
        ])
        openOnHover = defaults.bool(forKey: Key.openOnHover)
        hapticsEnabled = defaults.bool(forKey: Key.hapticsEnabled)
        showMicrophoneIndicator = defaults.bool(forKey: Key.showMicrophoneIndicator)
        showChargingIndicator = defaults.bool(forKey: Key.showChargingIndicator)
        showNowPlayingIndicator = defaults.bool(forKey: Key.showNowPlayingIndicator)
        saveClipboardHistory = defaults.bool(forKey: Key.saveClipboardHistory)
        universalMediaSupport = defaults.bool(forKey: Key.universalMediaSupport)
        showMenuBarDrawer = defaults.bool(forKey: Key.showMenuBarDrawer)
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }

    func setLaunchAtLogin(_ enabled: Bool) {
        do {
            if enabled {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
            launchAtLoginError = nil
        } catch {
            launchAtLoginError = "Couldn’t change this: \(error.localizedDescription) "
                + "Moving NotchFlow to your Applications folder usually fixes it."
        }
        launchAtLogin = SMAppService.mainApp.status == .enabled
    }
}
