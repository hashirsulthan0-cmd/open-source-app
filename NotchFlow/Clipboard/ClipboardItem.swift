import Foundation

/// One entry in the clipboard history.
struct ClipboardItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case text
        case link
        case image
        case files
    }

    let id: UUID
    let kind: Kind
    /// The copied text, or the link for `.link` items.
    var text: String?
    /// Paths of copied files, for `.files` items.
    var filePaths: [String]
    /// File name inside `AppPaths.clipboardImagesDirectory`, for `.image` items.
    var imageFileName: String?
    /// Text found in the image by OCR, used for search.
    var recognizedText: String?
    /// Title and thumbnail when the link is a YouTube video.
    var youTube: YouTubeMetadata?
    var sourceAppName: String?
    var copiedAt: Date
    var isPinned: Bool
    /// Identifies identical content, so copying the same thing twice moves it to the top
    /// instead of adding a duplicate.
    let contentKey: String

    init(
        kind: Kind,
        text: String? = nil,
        filePaths: [String] = [],
        imageFileName: String? = nil,
        youTube: YouTubeMetadata? = nil,
        sourceAppName: String?,
        contentKey: String
    ) {
        id = UUID()
        self.kind = kind
        self.text = text
        self.filePaths = filePaths
        self.imageFileName = imageFileName
        self.youTube = youTube
        self.sourceAppName = sourceAppName
        self.contentKey = contentKey
        copiedAt = Date()
        isPinned = false
    }

    var imageURL: URL? {
        imageFileName.map { AppPaths.clipboardImagesDirectory.appendingPathComponent($0) }
    }

    var fileURLs: [URL] {
        filePaths.map { URL(fileURLWithPath: $0) }
    }

    /// Everything search should match against.
    var searchableText: String {
        [
            text,
            recognizedText,
            youTube?.title,
            filePaths.map { ($0 as NSString).lastPathComponent }.joined(separator: " "),
            sourceAppName,
        ]
        .compactMap { $0 }
        .joined(separator: "\n")
    }
}
