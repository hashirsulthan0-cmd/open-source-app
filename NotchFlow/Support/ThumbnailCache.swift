import AppKit

/// Keeps recently shown images in memory so scrolling the notch doesn't reload them from disk.
@MainActor
enum ThumbnailCache {
    private static let cache: NSCache<NSURL, NSImage> = {
        let cache = NSCache<NSURL, NSImage>()
        cache.countLimit = 150
        return cache
    }()

    static func image(at url: URL) -> NSImage? {
        if let cached = cache.object(forKey: url as NSURL) {
            return cached
        }
        guard let image = NSImage(contentsOf: url) else { return nil }
        cache.setObject(image, forKey: url as NSURL)
        return image
    }

    static func remove(_ url: URL) {
        cache.removeObject(forKey: url as NSURL)
    }
}
