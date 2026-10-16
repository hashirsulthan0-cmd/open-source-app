import AppKit
import Combine

/// Combines the Now Playing sources and exposes one current track plus controls.
///
/// Music and Spotify support (official AppleScript) is always on. Universal support
/// (the bundled mediaremote-adapter) is optional; when it's on and reports a track,
/// that track wins because it covers every app, browsers included.
@MainActor
final class NowPlayingManager: ObservableObject {
    @Published private(set) var info: NowPlayingInfo?

    private let scriptable = ScriptablePlayerSource()
    private let universal = MediaRemoteAdapterSource()
    private var scriptableInfo: NowPlayingInfo?
    private var universalInfo: NowPlayingInfo?
    private var isUniversalRunning = false
    private var subscriptions: Set<AnyCancellable> = []

    static var isUniversalSupportAvailable: Bool { MediaRemoteAdapterSource.isAvailable }

    func start(settings: SettingsStore) {
        scriptable.onUpdate = { [weak self] info in
            self?.scriptableInfo = info
            self?.publish()
        }
        universal.onUpdate = { [weak self] info in
            self?.universalInfo = info
            self?.publish()
        }
        scriptable.start()

        settings.$universalMediaSupport
            .removeDuplicates()
            .sink { [weak self] isOn in
                MainActor.assumeIsolated {
                    self?.setUniversalSupport(isOn)
                }
            }
            .store(in: &subscriptions)
    }

    func stop() {
        subscriptions.removeAll()
        scriptable.stop()
        universal.stop()
    }

    func send(_ command: MediaCommand) {
        guard let info else { return }
        if info == universalInfo {
            universal.send(command)
        } else {
            scriptable.send(command, to: info.appBundleID)
        }
    }

    private func setUniversalSupport(_ isOn: Bool) {
        if isOn, !isUniversalRunning, MediaRemoteAdapterSource.isAvailable {
            universal.start()
            isUniversalRunning = true
        } else if !isOn, isUniversalRunning {
            universal.stop()
            isUniversalRunning = false
            universalInfo = nil
            publish()
        }
    }

    private func publish() {
        let newInfo = universalInfo ?? scriptableInfo
        if newInfo != info {
            info = newInfo
        }
    }
}
