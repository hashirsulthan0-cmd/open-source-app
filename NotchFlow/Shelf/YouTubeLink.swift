import AppKit
import LinkPresentation
import UniformTypeIdentifiers

/// Title and thumbnail of a YouTube video.
struct YouTubeMetadata: Codable, Equatable {
    let videoID: String
    var title: String?
    /// File name inside `AppPaths.thumbnailsDirectory`.
    var thumbnailFileName: String?

    var thumbnailURL: URL? {
        thumbnailFileName.map { AppPaths.thumbnailsDirectory.appendingPathComponent($0) }
    }
}

enum YouTubeLink {
    /// Returns the video ID for youtube.com/watch, youtu.be, /shorts, /live and /embed links.
    static func videoID(in url: URL) -> String? {
        guard var host = url.host?.lowercased() else { return nil }
        for prefix in ["www.", "m.", "music."] where host.hasPrefix(prefix) {
            host.removeFirst(prefix.count)
        }

        let pathParts = url.pathComponents.filter { $0 != "/" }
        var candidate: String?

        if host == "youtu.be" {
            candidate = pathParts.first
        } else if host == "youtube.com" || host == "youtube-nocookie.com" {
            if url.path == "/watch" {
                candidate = URLComponents(url: url, resolvingAgainstBaseURL: false)?
                    .queryItems?.first { $0.name == "v" }?.value
            } else if pathParts.count >= 2, ["shorts", "live", "embed"].contains(pathParts[0]) {
                candidate = pathParts[1]
            }
        }

        guard let id = candidate, isValidVideoID(id) else { return nil }
        return id
    }

    static func isYouTube(_ url: URL) -> Bool {
        videoID(in: url) != nil
    }

    private static func isValidVideoID(_ id: String) -> Bool {
        id.count == 11 && id.allSatisfy { $0.isLetter || $0.isNumber || $0 == "-" || $0 == "_" }
    }
}

/// Fetches a video's title with LinkPresentation and saves its thumbnail.
@MainActor
enum YouTubeMetadataLoader {
    static func load(videoID: String, url: URL) async -> YouTubeMetadata {
        var metadata = YouTubeMetadata(videoID: videoID)

        let provider = LPMetadataProvider()
        provider.timeout = 10
        let linkMetadata = try? await provider.startFetchingMetadata(for: url)
        metadata.title = linkMetadata?.title

        var imageData: Data?
        if let imageProvider = linkMetadata?.imageProvider {
            imageData = await loadImageData(from: imageProvider)
        }
        if imageData == nil {
            // YouTube's public thumbnail URL, used when the page preview has no image.
            if let fallback = URL(string: "https://i.ytimg.com/vi/\(videoID)/hqdefault.jpg") {
                imageData = try? await URLSession.shared.data(from: fallback).0
            }
        }

        if let imageData, NSImage(data: imageData) != nil {
            let fileName = "youtube-\(videoID).img"
            let fileURL = AppPaths.thumbnailsDirectory.appendingPathComponent(fileName)
            if (try? imageData.write(to: fileURL, options: .atomic)) != nil {
                ThumbnailCache.remove(fileURL)
                metadata.thumbnailFileName = fileName
            }
        }
        return metadata
    }

    private static func loadImageData(from provider: NSItemProvider) async -> Data? {
        await withCheckedContinuation { continuation in
            provider.loadDataRepresentation(forTypeIdentifier: UTType.image.identifier) { data, _ in
                continuation.resume(returning: data)
            }
        }
    }
}
