import AppKit
import SwiftUI

/// Shows the Settings window, creating it the first time.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let clipboard: ClipboardManager
    private let scanner: MenuBarScanner
    private let previewNotch: () -> Void
    private var window: NSWindow?

    init(settings: SettingsStore, clipboard: ClipboardManager, scanner: MenuBarScanner, previewNotch: @escaping () -> Void) {
        self.settings = settings
        self.clipboard = clipboard
        self.scanner = scanner
        self.previewNotch = previewNotch
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(
                settings: settings,
                clipboard: clipboard,
                scanner: scanner,
                previewNotch: previewNotch
            ))
            // Size the window from the view's ideal size, not its full content height,
            // so long pages scroll instead of growing past the screen.
            hosting.sizingOptions = [.minSize]

            let window = NSWindow(contentViewController: hosting)
            window.title = "NotchFlow Settings"
            window.styleMask = [.titled, .closable, .miniaturizable, .resizable]
            window.setContentSize(NSSize(width: 580, height: 480))
            window.isReleasedWhenClosed = false
            window.setFrameAutosaveName("NotchFlowSettings")
            window.center()
            self.window = window
        }
        // NotchFlow has no Dock icon, so bring it forward explicitly or the window opens behind others.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
