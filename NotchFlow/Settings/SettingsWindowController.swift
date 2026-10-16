import AppKit
import SwiftUI

/// Shows the Settings window, creating it the first time.
@MainActor
final class SettingsWindowController {
    private let settings: SettingsStore
    private let clipboard: ClipboardManager
    private let scanner: MenuBarScanner
    private var window: NSWindow?

    init(settings: SettingsStore, clipboard: ClipboardManager, scanner: MenuBarScanner) {
        self.settings = settings
        self.clipboard = clipboard
        self.scanner = scanner
    }

    func show() {
        if window == nil {
            let hosting = NSHostingController(rootView: SettingsView(settings: settings, clipboard: clipboard, scanner: scanner))
            let window = NSWindow(contentViewController: hosting)
            window.title = "NotchFlow Settings"
            window.styleMask = [.titled, .closable]
            window.isReleasedWhenClosed = false
            window.center()
            self.window = window
        }
        // NotchFlow has no Dock icon, so bring it forward explicitly or the window opens behind others.
        NSApp.activate()
        window?.makeKeyAndOrderFront(nil)
    }
}
