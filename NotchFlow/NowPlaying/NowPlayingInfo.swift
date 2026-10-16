import AppKit

/// What's currently playing, from whichever source reported it.
struct NowPlayingInfo: Equatable {
    var title: String
    var artist: String
    var album: String
    var isPlaying: Bool
    var duration: TimeInterval?
    /// Playback position at `elapsedUpdatedAt`. The live position is derived from both.
    var elapsed: TimeInterval?
    var elapsedUpdatedAt = Date()
    var artwork: NSImage?
    var appBundleID: String
    var appName: String

    /// Position right now, assuming playback continued since the last update.
    func position(at date: Date) -> TimeInterval? {
        guard let elapsed else { return nil }
        let live = isPlaying ? elapsed + date.timeIntervalSince(elapsedUpdatedAt) : elapsed
        if let duration { return min(max(live, 0), duration) }
        return max(live, 0)
    }
}

enum MediaCommand {
    case togglePlayPause
    case nextTrack
    case previousTrack
}

/// Runs AppleScript through `/usr/bin/osascript` off the main thread.
enum AppleScriptRunner {
    static func run(_ source: String) async -> String? {
        await withCheckedContinuation { continuation in
            let process = Process()
            process.executableURL = URL(fileURLWithPath: "/usr/bin/osascript")
            process.arguments = ["-e", source]
            let output = Pipe()
            process.standardOutput = output
            process.standardError = FileHandle.nullDevice
            process.terminationHandler = { finished in
                let data = output.fileHandleForReading.readDataToEndOfFile()
                let text = String(decoding: data, as: UTF8.self).trimmingCharacters(in: .whitespacesAndNewlines)
                continuation.resume(returning: finished.terminationStatus == 0 ? text : nil)
            }
            do {
                try process.run()
            } catch {
                continuation.resume(returning: nil)
            }
        }
    }
}
