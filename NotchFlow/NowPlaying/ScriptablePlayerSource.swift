import AppKit

/// Official, Apple-supported Now Playing for the Music app and Spotify.
///
/// Both apps broadcast a notification whenever playback changes, which needs no
/// permission. Details like artwork and position, and the play/pause/skip controls,
/// go through AppleScript, which macOS asks permission for once per app.
@MainActor
final class ScriptablePlayerSource {
    struct Player {
        let bundleID: String
        let scriptName: String
        let notification: String
    }

    static let players = [
        Player(bundleID: "com.apple.Music", scriptName: "Music", notification: "com.apple.Music.playerInfo"),
        Player(bundleID: "com.spotify.client", scriptName: "Spotify", notification: "com.spotify.client.PlaybackStateChanged"),
    ]

    /// Called with the most relevant player's info, or nil when nothing is playing or paused.
    var onUpdate: ((NowPlayingInfo?) -> Void)?

    private var infoByPlayer: [String: NowPlayingInfo] = [:]
    private var lastChanged: [String: Date] = [:]
    private var observers: [NSObjectProtocol] = []
    private var artworkURLs: [String: String] = [:]

    func start() {
        for player in Self.players {
            observers.append(DistributedNotificationCenter.default().addObserver(
                forName: Notification.Name(player.notification),
                object: nil,
                queue: .main
            ) { [weak self] notification in
                let userInfo = notification.userInfo ?? [:]
                let state = (userInfo["Player State"] as? String) ?? ""
                MainActor.assumeIsolated {
                    self?.playerChanged(player, reportedState: state)
                }
            })
        }

        observers.append(NSWorkspace.shared.notificationCenter.addObserver(
            forName: NSWorkspace.didTerminateApplicationNotification,
            object: nil,
            queue: .main
        ) { [weak self] notification in
            let bundleID = (notification.userInfo?[NSWorkspace.applicationUserInfoKey] as? NSRunningApplication)?.bundleIdentifier
            MainActor.assumeIsolated {
                guard let self, let bundleID, self.infoByPlayer[bundleID] != nil else { return }
                self.infoByPlayer[bundleID] = nil
                self.publish()
            }
        })

        // Pick up anything already playing when NotchFlow starts.
        for player in Self.players where Self.isRunning(player) {
            refresh(player)
        }
    }

    func stop() {
        for observer in observers {
            DistributedNotificationCenter.default().removeObserver(observer)
            NSWorkspace.shared.notificationCenter.removeObserver(observer)
        }
        observers.removeAll()
    }

    func send(_ command: MediaCommand, to bundleID: String) {
        guard let player = Self.players.first(where: { $0.bundleID == bundleID }), Self.isRunning(player) else { return }
        let verb = switch command {
        case .togglePlayPause: "playpause"
        case .nextTrack: "next track"
        case .previousTrack: "previous track"
        }
        Task {
            _ = await AppleScriptRunner.run("tell application \"\(player.scriptName)\" to \(verb)")
            refresh(player)
        }
    }

    // MARK: - Updates

    private func playerChanged(_ player: Player, reportedState: String) {
        if reportedState == "Stopped" {
            infoByPlayer[player.bundleID] = nil
            publish()
            return
        }
        refresh(player)
    }

    private func refresh(_ player: Player) {
        Task {
            // Never ask a player that isn't open: AppleScript would launch it.
            guard Self.isRunning(player) else { return }
            let script = player.bundleID == "com.apple.Music" ? Self.musicScript : Self.spotifyScript
            guard let output = await AppleScriptRunner.run(script) else { return }
            await apply(output, from: player)
        }
    }

    private func apply(_ output: String, from player: Player) async {
        let lines = output.components(separatedBy: "\n")
        guard lines.count >= 6, lines[0] != "stopped" else {
            infoByPlayer[player.bundleID] = nil
            publish()
            return
        }

        let previous = infoByPlayer[player.bundleID]
        let artworkReference = lines.count > 6 ? lines[6] : ""
        var info = NowPlayingInfo(
            title: lines[1],
            artist: lines[2],
            album: lines[3],
            isPlaying: lines[0] == "playing",
            duration: Self.number(lines[4]),
            elapsed: Self.number(lines[5]),
            elapsedUpdatedAt: Date(),
            artwork: previous?.title == lines[1] ? previous?.artwork : nil,
            appBundleID: player.bundleID,
            appName: player.scriptName
        )

        if info.artwork == nil || artworkURLs[player.bundleID] != artworkReference {
            artworkURLs[player.bundleID] = artworkReference
            info.artwork = await Self.loadArtwork(artworkReference)
        }

        infoByPlayer[player.bundleID] = info
        lastChanged[player.bundleID] = Date()
        publish()
    }

    /// Prefers a playing player; otherwise the one that changed most recently.
    private func publish() {
        let best = infoByPlayer.values.max { lhs, rhs in
            if lhs.isPlaying != rhs.isPlaying { return !lhs.isPlaying }
            return (lastChanged[lhs.appBundleID] ?? .distantPast) < (lastChanged[rhs.appBundleID] ?? .distantPast)
        }
        onUpdate?(best)
    }

    // MARK: - Helpers

    private static func isRunning(_ player: Player) -> Bool {
        !NSRunningApplication.runningApplications(withBundleIdentifier: player.bundleID).isEmpty
    }

    /// AppleScript prints numbers with the system's decimal separator, which may be a comma.
    private static func number(_ text: String) -> TimeInterval? {
        TimeInterval(text.replacingOccurrences(of: ",", with: "."))
    }

    private static func loadArtwork(_ reference: String) async -> NSImage? {
        guard !reference.isEmpty else { return nil }
        if reference.hasPrefix("http"), let url = URL(string: reference) {
            guard let (data, _) = try? await URLSession.shared.data(from: url) else { return nil }
            return NSImage(data: data)
        }
        return NSImage(contentsOfFile: reference)
    }

    private static let artworkFile = AppPaths.thumbnailsDirectory.appendingPathComponent("music-artwork").path

    // Each script prints: state, title, artist, album, duration (s), position (s), artwork.

    private static let spotifyScript = """
    tell application "Spotify"
        set s to player state as string
        if s is "stopped" then return "stopped"
        set t to current track
        return s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & ((duration of t) / 1000) & linefeed & player position & linefeed & (artwork url of t)
    end tell
    """

    private static let musicScript = """
    tell application "Music"
        set s to player state as string
        if s is "stopped" then return "stopped"
        set t to current track
        set out to s & linefeed & (name of t) & linefeed & (artist of t) & linefeed & (album of t) & linefeed & (duration of t) & linefeed & player position
    end tell
    try
        tell application "Music" to set d to data of artwork 1 of current track
        set f to open for access (POSIX file "\(artworkFile)") with write permission
        set eof f to 0
        write d to f
        close access f
        set out to out & linefeed & "\(artworkFile)"
    end try
    return out
    """
}
