import AppKit
import Carbon.HIToolbox

/// Pinned buttons in the drawer for apps you open often.
struct QuickLaunchItem: Identifiable {
    enum Action {
        case openApp(URL)
        case spotlight
    }

    let id: String
    let title: String
    let icon: NSImage
    let action: Action

    /// Claude, Wispr Flow, Spotlight and Siri, skipping any app that isn't installed.
    static func defaults() -> [QuickLaunchItem] {
        var items: [QuickLaunchItem] = []
        let apps: [(id: String, title: String)] = [
            ("com.anthropic.claudefordesktop", "Claude"),
            ("com.electron.wispr-flow", "Wispr Flow"),
        ]
        for app in apps {
            if let item = appItem(bundleID: app.id, title: app.title) {
                items.append(item)
            }
        }

        if let icon = NSImage(systemSymbolName: "magnifyingglass", accessibilityDescription: "Spotlight") {
            items.append(QuickLaunchItem(id: "spotlight", title: "Spotlight Search", icon: icon, action: .spotlight))
        }
        if let siri = appItem(bundleID: "com.apple.siri.launcher", title: "Siri") {
            items.append(siri)
        }
        return items
    }

    private static func appItem(bundleID: String, title: String) -> QuickLaunchItem? {
        guard let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleID) else { return nil }
        return QuickLaunchItem(id: bundleID, title: title, icon: NSWorkspace.shared.icon(forFile: url.path), action: .openApp(url))
    }

    /// Opens the app, or shows Spotlight. Spotlight has no public API, so it's opened with its
    /// shortcut (⌘Space), which needs Accessibility. Returns false when that permission is missing.
    @MainActor
    @discardableResult
    func perform() -> Bool {
        switch action {
        case .openApp(let url):
            NSWorkspace.shared.openApplication(at: url, configuration: NSWorkspace.OpenConfiguration())
            return true
        case .spotlight:
            guard AXIsProcessTrusted() else { return false }
            let space = CGKeyCode(kVK_Space)
            for isDown in [true, false] {
                let event = CGEvent(keyboardEventSource: nil, virtualKey: space, keyDown: isDown)
                event?.flags = .maskCommand
                event?.post(tap: .cghidEventTap)
            }
            return true
        }
    }
}
