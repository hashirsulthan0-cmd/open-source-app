import Foundation

/// Where NotchFlow keeps its data: ~/Library/Application Support/NotchFlow.
enum AppPaths {
    static let supportDirectory: URL = {
        let base = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        return makeDirectory(base.appendingPathComponent("NotchFlow", isDirectory: true))
    }()

    static let clipboardImagesDirectory = makeDirectory(
        supportDirectory.appendingPathComponent("ClipboardImages", isDirectory: true)
    )

    static let thumbnailsDirectory = makeDirectory(
        supportDirectory.appendingPathComponent("Thumbnails", isDirectory: true)
    )

    private static func makeDirectory(_ url: URL) -> URL {
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }
}

/// Reads and writes one Codable value as a JSON file.
struct JSONFileStore<Value: Codable> {
    let url: URL

    func load() -> Value? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(Value.self, from: data)
    }

    func save(_ value: Value) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        do {
            try encoder.encode(value).write(to: url, options: .atomic)
        } catch {
            NSLog("NotchFlow: could not save \(url.lastPathComponent): \(error.localizedDescription)")
        }
    }
}

extension URL {
    /// Turns a copied or dropped string into a web link, if it is one.
    static func webLink(from string: String) -> URL? {
        let trimmed = string.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty,
              trimmed.rangeOfCharacter(from: .whitespacesAndNewlines) == nil,
              let url = URL(string: trimmed),
              let scheme = url.scheme?.lowercased(),
              scheme == "http" || scheme == "https",
              url.host != nil
        else { return nil }
        return url
    }
}
