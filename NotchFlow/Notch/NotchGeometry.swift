import AppKit

/// Where the notch is on screen, and the window frames derived from it.
///
/// All rectangles use AppKit screen coordinates: the origin is the bottom-left of
/// the primary display and y grows upward, so the top of a screen is `frame.maxY`.
struct NotchGeometry: Equatable {
    /// Full frame of the screen the notch lives on.
    let screenFrame: NSRect

    /// The physical notch (or the virtual pill on screens without one).
    let notchRect: NSRect

    /// Whether `notchRect` is a real camera notch.
    let hasNotch: Bool

    static let zero = NotchGeometry(screenFrame: .zero, notchRect: .zero, hasNotch: false)

    init(screenFrame: NSRect, notchRect: NSRect, hasNotch: Bool) {
        self.screenFrame = screenFrame
        self.notchRect = notchRect
        self.hasNotch = hasNotch
    }

    init(screen: NSScreen) {
        let frame = screen.frame
        let topInset = screen.safeAreaInsets.top

        if topInset > 0,
           let leftArea = screen.auxiliaryTopLeftArea,
           let rightArea = screen.auxiliaryTopRightArea {
            // The menu bar is split into a usable area left and right of the camera.
            // Whatever width is left between them is the notch.
            let notchWidth = frame.width - leftArea.width - rightArea.width
            notchRect = NSRect(
                x: frame.minX + leftArea.width,
                y: frame.maxY - topInset,
                width: notchWidth,
                height: topInset
            )
            hasNotch = true
        } else {
            // External monitors and older Macs: draw a pill the height of the menu bar,
            // centred at the top. If the menu bar auto-hides, `visibleFrame` reaches the
            // top of the screen, so fall back to a sensible minimum height.
            let menuBarHeight = frame.maxY - screen.visibleFrame.maxY
            let height = max(menuBarHeight, NotchMetrics.fallbackPillMinHeight)
            notchRect = NSRect(
                x: frame.midX - NotchMetrics.fallbackPillWidth / 2,
                y: frame.maxY - height,
                width: NotchMetrics.fallbackPillWidth,
                height: height
            )
            hasNotch = false
        }
        screenFrame = frame
    }

    /// The built-in display with a notch if there is one, otherwise the main screen.
    static func preferredScreen() -> NSScreen? {
        NSScreen.screens.first { $0.safeAreaInsets.top > 0 } ?? NSScreen.main ?? NSScreen.screens.first
    }

    // MARK: - Sizes for the SwiftUI shape

    /// Closed shape: the notch plus its two small top ears.
    var closedSize: CGSize {
        CGSize(width: notchRect.width + NotchMetrics.closedTopRadius * 2, height: notchRect.height)
    }

    var openSize: CGSize { NotchMetrics.openSize }

    // MARK: - Window frames

    /// Window frame while closed. It hugs the notch so nothing around it is blocked.
    var closedPanelFrame: NSRect {
        let size = closedSize
        return NSRect(
            x: notchRect.midX - size.width / 2,
            y: screenFrame.maxY - size.height,
            width: size.width,
            height: size.height
        )
    }

    /// Window frame while open: the expanded shape plus room for its shadow.
    var openPanelFrame: NSRect {
        let width = openSize.width + NotchMetrics.shadowPadding * 2
        let height = openSize.height + NotchMetrics.shadowPadding
        return NSRect(
            x: notchRect.midX - width / 2,
            y: screenFrame.maxY - height,
            width: width,
            height: height
        )
    }

    /// The visible expanded shape, used to decide whether the cursor is "inside".
    var openShapeRect: NSRect {
        NSRect(
            x: notchRect.midX - openSize.width / 2,
            y: screenFrame.maxY - openSize.height,
            width: openSize.width,
            height: openSize.height
        )
    }

    /// Moving the cursor into this area opens the notch.
    var hoverZone: NSRect {
        notchRect.insetBy(dx: -NotchMetrics.hoverMargin, dy: -NotchMetrics.hoverMargin)
    }
}
