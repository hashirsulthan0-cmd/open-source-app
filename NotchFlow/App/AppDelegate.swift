import AppKit
import Combine

/// App entry point. NotchFlow is an "agent" app: it has no Dock icon and no
/// app menus (`LSUIElement` in the generated Info.plist). The only always-visible
/// pieces are the notch panel and a small menu bar icon used to open settings or quit.
@main
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    private let settings = SettingsStore()
    private let clipboard = ClipboardManager()
    private let shelf = FileTrayManager()
    private let hud = SystemHUDManager()
    private let nowPlaying = NowPlayingManager()
    private let scanner = MenuBarScanner()
    private lazy var settingsWindow = SettingsWindowController(
        settings: settings,
        clipboard: clipboard,
        scanner: scanner,
        previewNotch: { [weak self] in self?.notchController?.preview() }
    )

    private var notchController: NotchController?
    private var statusItem: NSStatusItem?
    private var subscriptions: Set<AnyCancellable> = []

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

        settings.$saveClipboardHistory
            .sink { [weak self] isOn in
                MainActor.assumeIsolated {
                    self?.clipboard.isRecording = isOn
                }
            }
            .store(in: &subscriptions)

        clipboard.start()
        hud.start()
        nowPlaying.start(settings: settings)

        let controller = NotchController(
            clipboard: clipboard,
            shelf: shelf,
            hud: hud,
            nowPlaying: nowPlaying,
            scanner: scanner,
            settings: settings,
            openSettings: { [weak self] in self?.settingsWindow.show() }
        )
        controller.start()
        notchController = controller

        HotKeyCenter.shared.register(HotKeyCenter.toggleNotch) { [weak controller] in
            controller?.toggle()
        }
        HotKeyCenter.shared.register(HotKeyCenter.openClipboard) { [weak controller] in
            controller?.openClipboardSearch()
        }

        installStatusItem()
    }

    func applicationWillTerminate(_ notification: Notification) {
        HotKeyCenter.shared.unregisterAll()
        notchController?.stop()
        hud.stop()
        nowPlaying.stop()
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
        menu.addItem(menuItem("Open Notch", action: #selector(openNotch)))
        menu.addItem(menuItem("Search Clipboard", action: #selector(openClipboardSearch)))
        menu.addItem(.separator())
        menu.addItem(menuItem("Settings…", action: #selector(openSettings), key: ","))
        menu.addItem(.separator())
        menu.addItem(NSMenuItem(
            title: "Quit NotchFlow",
            action: #selector(NSApplication.terminate(_:)),
            keyEquivalent: "q"
        ))

        item.menu = menu
        statusItem = item
    }

    private func menuItem(_ title: String, action: Selector, key: String = "") -> NSMenuItem {
        let item = NSMenuItem(title: title, action: action, keyEquivalent: key)
        item.target = self
        return item
    }

    @objc private func openNotch() {
        notchController?.open(manually: true)
    }

    @objc private func openClipboardSearch() {
        notchController?.openClipboardSearch()
    }

    @objc private func openSettings() {
        settingsWindow.show()
    }
}
