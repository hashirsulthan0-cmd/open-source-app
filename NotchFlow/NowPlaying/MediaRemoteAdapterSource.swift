import AppKit

/// Universal Now Playing through the bundled open-source mediaremote-adapter
/// (BSD 3-Clause, github.com/ungive/mediaremote-adapter).
///
/// Since macOS 15.4, only Apple-entitled programs may read the system's Now Playing
/// information. The adapter runs its small framework inside `/usr/bin/perl`, which is
/// entitled, and streams changes as JSON lines. This covers every player, browsers
/// included. It is unofficial, so a macOS update may break it; NotchFlow then falls
/// back to the Music and Spotify support.
@MainActor
final class MediaRemoteAdapterSource {
    var onUpdate: ((NowPlayingInfo?) -> Void)?

    private var process: Process?
    private var restartAttempts = 0
    private var isStopping = false

    private static let perlURL = URL(fileURLWithPath: "/usr/bin/perl")

    private static var scriptURL: URL? {
        Bundle.main.url(forResource: "mediaremote-adapter", withExtension: "pl")
    }

    private static var frameworkURL: URL? {
        guard let url = Bundle.main.privateFrameworksURL?.appendingPathComponent("MediaRemoteAdapter.framework"),
              FileManager.default.fileExists(atPath: url.path)
        else { return nil }
        return url
    }

    static var isAvailable: Bool { scriptURL != nil && frameworkURL != nil }

    func start() {
        isStopping = false
        launchStream()
    }

    func stop() {
        isStopping = true
        process?.terminate()
        process = nil
    }

    func send(_ command: MediaCommand) {
        // MRCommand numbers from MediaRemote: 2 toggles play/pause, 4 next, 5 previous.
        let id = switch command {
        case .togglePlayPause: "2"
        case .nextTrack: "4"
        case .previousTrack: "5"
        }
        guard let script = Self.scriptURL, let framework = Self.frameworkURL else { return }
        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = [script.path, framework.path, "send", id]
        process.standardOutput = FileHandle.nullDevice
        process.standardError = FileHandle.nullDevice
        try? process.run()
    }

    // MARK: - Streaming

    private func launchStream() {
        guard process == nil, let script = Self.scriptURL, let framework = Self.frameworkURL else { return }

        let process = Process()
        process.executableURL = Self.perlURL
        process.arguments = [script.path, framework.path, "stream", "--no-diff", "--debounce=100"]
        process.standardError = FileHandle.nullDevice

        let output = Pipe()
        process.standardOutput = output
        let reader = JSONLineReader { [weak self] payload in
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.handle(payload)
                }
            }
        }
        output.fileHandleForReading.readabilityHandler = { handle in
            reader.append(handle.availableData)
        }

        process.terminationHandler = { [weak self] _ in
            output.fileHandleForReading.readabilityHandler = nil
            DispatchQueue.main.async {
                MainActor.assumeIsolated {
                    self?.streamEnded()
                }
            }
        }

        do {
            try process.run()
            self.process = process
        } catch {
            NSLog("NotchFlow: could not start media helper: \(error.localizedDescription)")
        }
    }

    /// Restarts the helper a few times if it quits unexpectedly, waiting longer each time.
    private func streamEnded() {
        process = nil
        onUpdate?(nil)
        guard !isStopping, restartAttempts < 5 else { return }
        restartAttempts += 1
        let delay = Double(restartAttempts * restartAttempts)
        Task { [weak self] in
            try? await Task.sleep(for: .seconds(delay))
            guard let self, !self.isStopping else { return }
            self.launchStream()
        }
    }

    private func handle(_ payload: [String: Any]) {
        restartAttempts = 0
        onUpdate?(Self.info(from: payload))
    }

    private static func info(from payload: [String: Any]) -> NowPlayingInfo? {
        guard let title = payload["title"] as? String, !title.isEmpty else { return nil }

        let bundleID = payload["bundleIdentifier"] as? String ?? ""
        let pid = (payload["processIdentifier"] as? NSNumber)?.int32Value
        let appName = pid.flatMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            ?? NSRunningApplication.runningApplications(withBundleIdentifier: bundleID).first?.localizedName
            ?? bundleID

        var artwork: NSImage?
        if let base64 = payload["artworkData"] as? String, let data = Data(base64Encoded: base64) {
            artwork = NSImage(data: data)
        }

        let timestamp = (payload["timestamp"] as? String).flatMap { ISO8601DateFormatter().date(from: $0) }

        return NowPlayingInfo(
            title: title,
            artist: payload["artist"] as? String ?? "",
            album: payload["album"] as? String ?? "",
            isPlaying: payload["playing"] as? Bool ?? false,
            duration: (payload["duration"] as? NSNumber)?.doubleValue,
            elapsed: (payload["elapsedTime"] as? NSNumber)?.doubleValue,
            elapsedUpdatedAt: timestamp ?? Date(),
            artwork: artwork,
            appBundleID: bundleID,
            appName: appName
        )
    }
}

/// Splits the helper's output into lines and decodes each `{"type":"data","payload":…}` line.
/// Used only from the pipe's own serial reading queue.
private final class JSONLineReader: @unchecked Sendable {
    private var buffer = Data()
    private let onPayload: ([String: Any]) -> Void

    init(onPayload: @escaping ([String: Any]) -> Void) {
        self.onPayload = onPayload
    }

    func append(_ data: Data) {
        buffer.append(data)
        while let newline = buffer.firstIndex(of: UInt8(ascii: "\n")) {
            let line = buffer[buffer.startIndex..<newline]
            buffer.removeSubrange(buffer.startIndex...newline)
            guard let object = try? JSONSerialization.jsonObject(with: line) as? [String: Any],
                  object["type"] as? String == "data",
                  let payload = object["payload"] as? [String: Any]
            else { continue }
            onPayload(payload)
        }
    }
}
