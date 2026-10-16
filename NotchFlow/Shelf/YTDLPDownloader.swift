import Foundation

/// Hands a video link to a locally installed `yt-dlp`.
///
/// NotchFlow never bundles or installs yt-dlp. The download option only appears when
/// the user has installed it themselves (for example with `brew install yt-dlp`).
/// Only download videos you have the right to save.
enum YTDLPDownloader {
    private static let searchPaths = [
        "/opt/homebrew/bin/yt-dlp",
        "/usr/local/bin/yt-dlp",
        NSHomeDirectory() + "/.local/bin/yt-dlp",
    ]

    static var executableURL: URL? {
        searchPaths
            .first { FileManager.default.isExecutableFile(atPath: $0) }
            .map { URL(fileURLWithPath: $0) }
    }

    static var isInstalled: Bool { executableURL != nil }

    static var downloadsDirectory: URL {
        FileManager.default.urls(for: .downloadsDirectory, in: .userDomainMask)[0]
    }

    enum DownloadError: LocalizedError {
        case notInstalled
        case failed(String)

        var errorDescription: String? {
            switch self {
            case .notInstalled: "yt-dlp is not installed."
            case .failed(let message): message
            }
        }
    }

    /// Downloads one video into the Downloads folder.
    static func download(_ url: URL) async throws {
        guard let executable = executableURL else { throw DownloadError.notInstalled }

        let process = Process()
        process.executableURL = executable
        process.arguments = [
            "--no-playlist",
            // Keep output small: only errors are written, and they're read when yt-dlp exits.
            "--quiet",
            "--no-warnings",
            "-o", downloadsDirectory.path + "/%(title)s [%(id)s].%(ext)s",
            url.absoluteString,
        ]
        // Apps launched from Finder get a minimal PATH. Add Homebrew so yt-dlp can find ffmpeg.
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = "/opt/homebrew/bin:/usr/local/bin:" + (environment["PATH"] ?? "/usr/bin:/bin")
        process.environment = environment

        let errorPipe = Pipe()
        process.standardError = errorPipe
        process.standardOutput = FileHandle.nullDevice

        try await withCheckedThrowingContinuation { (continuation: CheckedContinuation<Void, Error>) in
            process.terminationHandler = { finished in
                if finished.terminationStatus == 0 {
                    continuation.resume()
                } else {
                    let data = errorPipe.fileHandleForReading.readDataToEndOfFile()
                    let lastLine = String(decoding: data, as: UTF8.self)
                        .split(separator: "\n")
                        .last
                        .map(String.init) ?? "yt-dlp exited with code \(finished.terminationStatus)."
                    continuation.resume(throwing: DownloadError.failed(lastLine))
                }
            }
            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}
