import AppKit

/// The borderless, see-through window that sits over the notch.
///
/// It floats above the menu bar, shows on every Space and over full-screen apps,
/// and never steals focus from the app you're working in.
final class NotchPanel: NSPanel {
    init(contentRect: NSRect) {
        super.init(
            contentRect: contentRect,
            styleMask: [.borderless, .nonactivatingPanel, .utilityWindow],
            backing: .buffered,
            defer: false
        )

        isFloatingPanel = true
        // Above the menu bar (and its menus) so the notch is always on top.
        level = NSWindow.Level(rawValue: NSWindow.Level.mainMenu.rawValue + 3)
        collectionBehavior = [.canJoinAllSpaces, .stationary, .fullScreenAuxiliary, .ignoresCycle]

        isOpaque = false
        backgroundColor = .clear
        hasShadow = false // SwiftUI draws its own shadow around the notch shape.

        isMovable = false
        isMovableByWindowBackground = false
        hidesOnDeactivate = false
        isReleasedWhenClosed = false
        animationBehavior = .none
        acceptsMouseMovedEvents = true
        becomesKeyOnlyIfNeeded = true
    }

    // Allows text fields inside the notch (like the clipboard search in Phase 2) to take typing.
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }

    // AppKit normally pushes windows down so they don't overlap the menu bar.
    // The notch window must sit at the very top of the screen, so keep the frame as given.
    override func constrainFrameRect(_ frameRect: NSRect, to screen: NSScreen?) -> NSRect {
        frameRect
    }
}
