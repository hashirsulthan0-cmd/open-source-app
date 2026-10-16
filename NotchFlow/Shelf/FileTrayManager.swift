import AppKit

/// One thing parked on the shelf.
struct ShelfItem: Codable, Identifiable, Equatable {
    enum Kind: String, Codable {
        case file
        case link
        case text
    }

    let id: UUID
    let kind: Kind
    var filePath: String?
    var urlString: String?
    var text: String?
    var youTube: YouTubeMetadata?
    var addedAt: Date

    init(kind: Kind, filePath: String? = nil, urlString: String? = nil, text: String? = nil, youTube: YouTubeMetadata? = nil) {
        id = UUID()
        self.kind = kind
        self.filePath = filePath
        self.urlString = urlString
        self.text = text
        self.youTube = youTube
        addedAt = Date()
    }

    var fileURL: URL? { filePath.map { URL(fileURLWithPath: $0) } }
    var link: URL? { urlString.flatMap(URL.init(string:)) }

    var fileExists: Bool {
        guard let filePath else { return false }
        return FileManager.default.fileExists(atPath: filePath)
    }

    var displayName: String {
        switch kind {
        case .file: (filePath as NSString?)?.lastPathComponent ?? "File"
        case .link: youTube?.title ?? link?.host ?? urlString ?? "Link"
        case .text: text ?? ""
        }
    }
}

/// The shelf: a place to drop files, links and text for later.
///
/// Files are kept as references to where they already are; nothing is copied or moved.
/// The shelf is saved to Application Support so it survives restarts.
@MainActor
final class FileTrayManager: ObservableObject {
    enum DownloadState: Equatable {
        case downloading
        case finished
        case failed(String)
    }

    @Published private(set) var items: [ShelfItem]
    @Published private(set) var downloads: [UUID: DownloadState] = [:]

    private let store = JSONFileStore<[ShelfItem]>(
        url: AppPaths.supportDirectory.appendingPathComponent("shelf.json")
    )

    init() {
        items = store.load() ?? []
    }

    func save() {
        store.save(items)
    }

    // MARK: - Adding

    /// Adds whatever was dropped. Returns false if nothing usable was found.
    @discardableResult
    func add(from pasteboard: NSPasteboard) -> Bool {
        var added: [ShelfItem] = []

        if let fileURLs = pasteboard.readObjects(
            forClasses: [NSURL.self],
            options: [.urlReadingFileURLsOnly: true]
        ) as? [URL], !fileURLs.isEmpty {
            for url in fileURLs where !items.contains(where: { $0.filePath == url.path }) {
                added.append(ShelfItem(kind: .file, filePath: url.path))
            }
        } else if let links = pasteboard.readObjects(forClasses: [NSURL.self]) as? [URL],
                  let link = links.first(where: { !$0.isFileURL }) {
            added.append(makeLinkItem(link))
        } else if let string = pasteboard.string(forType: .string),
                  !string.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            if let link = URL.webLink(from: string) {
                added.append(makeLinkItem(link))
            } else {
                added.append(ShelfItem(kind: .text, text: string))
            }
        }

        guard !added.isEmpty else { return false }
        items.insert(contentsOf: added, at: 0)
        save()

        for item in added {
            if let videoID = item.youTube?.videoID, let link = item.link {
                loadYouTubeMetadata(for: item.id, videoID: videoID, url: link)
            }
        }
        return true
    }

    private func makeLinkItem(_ url: URL) -> ShelfItem {
        ShelfItem(
            kind: .link,
            urlString: url.absoluteString,
            youTube: YouTubeLink.videoID(in: url).map { YouTubeMetadata(videoID: $0) }
        )
    }

    private func loadYouTubeMetadata(for id: UUID, videoID: String, url: URL) {
        Task {
            let metadata = await YouTubeMetadataLoader.load(videoID: videoID, url: url)
            guard let index = items.firstIndex(where: { $0.id == id }) else { return }
            items[index].youTube = metadata
            save()
        }
    }

    // MARK: - Actions

    func open(_ item: ShelfItem) {
        switch item.kind {
        case .file:
            if let url = item.fileURL, item.fileExists {
                NSWorkspace.shared.open(url)
            }
        case .link:
            if let url = item.link {
                NSWorkspace.shared.open(url)
            }
        case .text:
            copy(item)
        }
    }

    func revealInFinder(_ item: ShelfItem) {
        guard let url = item.fileURL, item.fileExists else { return }
        NSWorkspace.shared.activateFileViewerSelecting([url])
    }

    func copy(_ item: ShelfItem) {
        let pasteboard = NSPasteboard.general
        pasteboard.clearContents()
        switch item.kind {
        case .file:
            if let url = item.fileURL {
                pasteboard.writeObjects([url as NSURL])
            }
        case .link:
            pasteboard.setString(item.urlString ?? "", forType: .string)
        case .text:
            pasteboard.setString(item.text ?? "", forType: .string)
        }
    }

    func remove(_ item: ShelfItem) {
        items.removeAll { $0.id == item.id }
        downloads[item.id] = nil
        save()
    }

    func removeAll() {
        items.removeAll()
        downloads.removeAll()
        save()
    }

    /// Drag data used when dragging an item out of the shelf into another app.
    func itemProvider(for item: ShelfItem) -> NSItemProvider {
        switch item.kind {
        case .file:
            if let url = item.fileURL, let provider = NSItemProvider(contentsOf: url) {
                return provider
            }
            return NSItemProvider()
        case .link:
            if let url = item.link {
                return NSItemProvider(object: url as NSURL)
            }
            return NSItemProvider()
        case .text:
            return NSItemProvider(object: (item.text ?? "") as NSString)
        }
    }

    // MARK: - yt-dlp

    var canDownloadVideos: Bool { YTDLPDownloader.isInstalled }

    func download(_ item: ShelfItem) {
        guard let url = item.link, item.youTube != nil, downloads[item.id] != .downloading else { return }
        downloads[item.id] = .downloading
        Task {
            do {
                try await YTDLPDownloader.download(url)
                downloads[item.id] = .finished
            } catch {
                downloads[item.id] = .failed(error.localizedDescription)
            }
        }
    }
}
