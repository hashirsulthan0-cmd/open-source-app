import AppKit

/// App entry point. NotchFlow is an "agent" app: it has no Dock icon and no
/// app menus (`LSUIElement` in the generated Info.plist). The only always-visible
/// pieces are the notch panel and a small menu bar icon used to open or quit the app.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let clipboard = ClipboardManager()
    private let shelf = FileTrayManager()
    private var notchController: NotchController?
    private var statusItem: NSStatusItem?

    static func main() {
        let app = NSApplication.shared
        let delegate = AppDelegate()
        app.delegate = delegate
        // `NSApplication.delegate` is weak, so keep the delegate alive while the app runs.
        withExtendedLifetime(delegate) {
            app.run()
        }
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.accessory)

        clipboard.start()

        let controller = NotchController(clipboard: clipboard, shelf: shelf)
        controller.start()
        notchController = controller

        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        notchController?.stop()
        clipboard.stop()
        shelf.save()
    }

    // MARK: - Menu bar icon

    private func installStatusItem() {
        let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.squareLength)
        item.button?.image = NSImage(
            systemSymbolName: "rectangle.topthird.inset.filled",
            accessibilityDescription: "NotchFlow"
        )

        let menu = NSMenu()

        let openItem = NSMenuItem(title: "Open Notch", action: #selector(openNotch), keyEquivalent: "")
        openItem.target = self
        menu.addItem(openItem)

        menu.addItem(.separator())

        let quitItem = NSMenuItem(
            title: "Quit NotchFlow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        )
        menu.addItem(quitItem)

        item.menu = menu
        statusItem = item
    }

    @objc private func openNotch() {
        notchController?.open(manually: true)
    }
}
