import AppKit
import ApplicationServices
import ScreenCaptureKit

/// One icon in the menu bar's right-hand side, owned by some app.
struct MenuBarItem: Identifiable, Equatable {
    let id: String
    let pid: pid_t
    let appName: String
    /// Position in global screen coordinates with the origin at the top-left, as
    /// CoreGraphics and Accessibility use.
    let frame: CGRect
    /// True when the icon sits behind the notch or off screen, so it can't be seen or clicked normally.
    let isHidden: Bool
    var image: NSImage?
    /// Draw the image in white: used for dark icons that would vanish on the black notch.
    var drawsAsTemplate = false
}

/// Finds the menu bar's status icons and clicks them on the user's behalf.
///
/// On macOS 26 every status icon is drawn by Control Center, so the window list
/// (`CGWindowListCopyWindowInfo`, layer 25) can't say which app an icon belongs to.
/// Accessibility can: each app's "extras menu bar" lists its icons with their positions,
/// and pressing them works even when they're hidden behind the notch.
///
/// - Accessibility permission: needed to list and press icons.
/// - Screen Recording permission (optional): needed to show the real icon pictures.
///   Without it, each app's regular icon is shown instead.
@MainActor
final class MenuBarScanner: ObservableObject {
    static let statusItemWindowLayer = 25

    @Published private(set) var items: [MenuBarItem] = []
    @Published private(set) var hasAccessibility = AXIsProcessTrusted()
    @Published private(set) var hasScreenRecording = CGPreflightScreenCaptureAccess()

    private var elements: [String: AXUIElement] = [:]
    private var imageCache: [String: (frame: CGRect, image: NSImage, template: Bool)] = [:]
    private var timer: Timer?
    private var isScanning = false

    // MARK: - Live updates while the drawer is visible

    func startLiveUpdates() {
        refresh()
        guard timer == nil else { return }
        let timer = Timer(timeInterval: 2, repeats: true) { [weak self] _ in
            MainActor.assumeIsolated {
                self?.refresh()
            }
        }
        RunLoop.main.add(timer, forMode: .common)
        self.timer = timer
    }

    func stopLiveUpdates() {
        timer?.invalidate()
        timer = nil
    }

    func refresh() {
        hasAccessibility = AXIsProcessTrusted()
        hasScreenRecording = CGPreflightScreenCaptureAccess()
        guard hasAccessibility, !isScanning else {
            if !hasAccessibility { items = [] }
            return
        }

        isScanning = true
        let notchRange = Self.notchXRange()
        let screenWidth = NSScreen.screens.map(\.frame.maxX).max() ?? .greatestFiniteMagnitude
        Task {
            // Accessibility calls can block on a busy app, so scan off the main thread.
            let found = await Task.detached(priority: .userInitiated) {
                Self.scanAccessibility(notchRange: notchRange, screenWidth: screenWidth)
            }.value
            isScanning = false
            apply(found)
        }
    }

    // MARK: - Permissions

    func requestAccessibility() {
        let options = [kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary
        hasAccessibility = AXIsProcessTrustedWithOptions(options)
    }

    func requestScreenRecording() {
        hasScreenRecording = CGRequestScreenCaptureAccess()
    }

    // MARK: - Clicking

    /// Opens the icon's menu, the same as clicking it in the menu bar.
    func press(_ item: MenuBarItem) {
        if let element = elements[item.id], AXUIElementPerformAction(element, kAXPressAction as CFString) == .success {
            return
        }
        // Fallback for icons that don't support the press action: a real click, if visible.
        guard !item.isHidden, hasAccessibility else { return }
        Self.click(at: CGPoint(x: item.frame.midX, y: item.frame.midY))
    }

    private static func click(at point: CGPoint) {
        let original = CGEvent(source: nil)?.location
        for type in [CGEventType.leftMouseDown, .leftMouseUp] {
            CGEvent(mouseEventSource: nil, mouseType: type, mouseCursorPosition: point, mouseButton: .left)?
                .post(tap: .cghidEventTap)
        }
        if let original {
            CGWarpMouseCursorPosition(original)
        }
    }

    // MARK: - Scanning

    private struct ScannedItem: @unchecked Sendable {
        let item: MenuBarItem
        let element: AXUIElement
    }

    private nonisolated static func scanAccessibility(
        notchRange: ClosedRange<CGFloat>?,
        screenWidth: CGFloat
    ) -> [ScannedItem] {
        let ownPID = ProcessInfo.processInfo.processIdentifier
        var results: [ScannedItem] = []

        for app in NSWorkspace.shared.runningApplications
        where app.processIdentifier != ownPID && app.activationPolicy != .prohibited {
            let appElement = AXUIElementCreateApplication(app.processIdentifier)
            AXUIElementSetMessagingTimeout(appElement, 0.25)

            guard let extras: AXUIElement = attribute(appElement, kAXExtrasMenuBarAttribute),
                  let children: [AXUIElement] = attribute(extras, kAXChildrenAttribute)
            else { continue }

            for (index, child) in children.enumerated() {
                guard let frame = frame(of: child), frame.width > 0 else { continue }
                let behindNotch = notchRange.map { $0.contains(frame.midX) } ?? false
                let offScreen = frame.maxX <= 0 || frame.minX >= screenWidth
                let item = MenuBarItem(
                    id: "\(app.processIdentifier)-\(index)",
                    pid: app.processIdentifier,
                    appName: app.localizedName ?? app.bundleIdentifier ?? "App",
                    frame: frame,
                    isHidden: behindNotch || offScreen
                )
                results.append(ScannedItem(item: item, element: child))
            }
        }
        return results.sorted { $0.item.frame.minX < $1.item.frame.minX }
    }

    private func apply(_ scanned: [ScannedItem]) {
        elements = Dictionary(scanned.map { ($0.item.id, $0.element) }, uniquingKeysWith: { first, _ in first })

        var newItems = scanned.map(\.item)
        for index in newItems.indices {
            if let cached = imageCache[newItems[index].id], cached.frame == newItems[index].frame {
                newItems[index].image = cached.image
                newItems[index].drawsAsTemplate = cached.template
            }
        }
        if newItems != items {
            items = newItems
        }

        if hasScreenRecording {
            captureMissingImages()
        }
    }

    // MARK: - Icon pictures (ScreenCaptureKit)

    private func captureMissingImages() {
        let missing = items.filter { $0.image == nil }
        guard !missing.isEmpty else { return }

        Task {
            guard let content = try? await SCShareableContent.excludingDesktopWindows(false, onScreenWindowsOnly: false) else { return }
            let statusWindows = content.windows.filter { $0.windowLayer == Self.statusItemWindowLayer }
            let scale = NSScreen.main?.backingScaleFactor ?? 2

            for item in missing {
                guard let window = statusWindows.first(where: { Self.matches($0.frame, item.frame) }) else { continue }
                let configuration = SCStreamConfiguration()
                configuration.width = Int(window.frame.width * scale)
                configuration.height = Int(window.frame.height * scale)
                configuration.showsCursor = false
                configuration.ignoreShadowsSingleWindow = true

                let filter = SCContentFilter(desktopIndependentWindow: window)
                guard let cgImage = try? await SCScreenshotManager.captureImage(
                    contentFilter: filter,
                    configuration: configuration
                ) else { continue }

                let image = NSImage(cgImage: cgImage, size: window.frame.size)
                let template = Self.isMostlyDark(cgImage)
                imageCache[item.id] = (item.frame, image, template)
                if let index = items.firstIndex(where: { $0.id == item.id }) {
                    items[index].image = image
                    items[index].drawsAsTemplate = template
                }
            }
        }
    }

    private nonisolated static func matches(_ lhs: CGRect, _ rhs: CGRect) -> Bool {
        abs(lhs.minX - rhs.minX) < 3 && abs(lhs.width - rhs.width) < 3
    }

    /// Menu bar icons are drawn black on a light menu bar. On the black notch they'd be
    /// invisible, so dark icons are redrawn in white.
    private nonisolated static func isMostlyDark(_ image: CGImage) -> Bool {
        let width = 24, height = 24
        var pixels = [UInt8](repeating: 0, count: width * height * 4)
        guard let context = CGContext(
            data: &pixels,
            width: width,
            height: height,
            bitsPerComponent: 8,
            bytesPerRow: width * 4,
            space: CGColorSpaceCreateDeviceRGB(),
            bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue
        ) else { return false }
        context.draw(image, in: CGRect(x: 0, y: 0, width: width, height: height))

        var total = 0.0
        var count = 0.0
        for offset in stride(from: 0, to: pixels.count, by: 4) {
            let alpha = Double(pixels[offset + 3]) / 255
            guard alpha > 0.5 else { continue }
            let red = Double(pixels[offset]) / 255 / alpha
            let green = Double(pixels[offset + 1]) / 255 / alpha
            let blue = Double(pixels[offset + 2]) / 255 / alpha
            total += 0.299 * red + 0.587 * green + 0.114 * blue
            count += 1
        }
        return count > 0 && total / count < 0.45
    }

    // MARK: - Helpers

    /// The horizontal span of the camera notch, where icons get hidden.
    private static func notchXRange() -> ClosedRange<CGFloat>? {
        guard let screen = NSScreen.screens.first(where: { $0.safeAreaInsets.top > 0 }) else { return nil }
        let notch = NotchGeometry(screen: screen).notchRect
        return notch.minX...notch.maxX
    }

    private nonisolated static func attribute<T>(_ element: AXUIElement, _ name: String) -> T? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, name as CFString, &value) == .success else { return nil }
        return value as? T
    }

    private nonisolated static func frame(of element: AXUIElement) -> CGRect? {
        var positionValue: CFTypeRef?
        var sizeValue: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXPositionAttribute as CFString, &positionValue) == .success,
              AXUIElementCopyAttributeValue(element, kAXSizeAttribute as CFString, &sizeValue) == .success,
              let positionValue, let sizeValue,
              CFGetTypeID(positionValue) == AXValueGetTypeID(),
              CFGetTypeID(sizeValue) == AXValueGetTypeID()
        else { return nil }

        var position = CGPoint.zero
        var size = CGSize.zero
        // The type IDs were checked above, so these casts can't fail.
        AXValueGetValue(positionValue as! AXValue, .cgPoint, &position)
        AXValueGetValue(sizeValue as! AXValue, .cgSize, &size)
        return CGRect(origin: position, size: size)
    }
}
