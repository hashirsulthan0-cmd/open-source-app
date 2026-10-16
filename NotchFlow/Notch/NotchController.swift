import AppKit
import Combine
import SwiftUI

/// Owns the notch window and decides when it opens and closes.
///
/// The notch opens when the cursor comes within `NotchMetrics.hoverMargin` of it (or on
/// click, if hover is turned off), when something is dragged toward it, or from a keyboard
/// shortcut. It closes shortly after the cursor leaves, on a click outside, or with Esc.
@MainActor
final class NotchController: NSObject {
    private let viewModel = NotchViewModel(geometry: .zero)
    private let clipboard: ClipboardManager
    private let shelf: FileTrayManager
    private let hud: SystemHUDManager
    private let nowPlaying: NowPlayingManager
    private let settings: SettingsStore
    private let openSettings: () -> Void

    private var panel: NotchPanel?
    private var eventMonitors: [Any] = []
    private var subscriptions: Set<AnyCancellable> = []

    private var closeTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?
    private var indicatorResizeTask: Task<Void, Never>?
    private var chargingIndicatorTask: Task<Void, Never>?

    /// `NSPasteboard(name: .drag)` gets a new change count each time a drag starts.
    /// Comparing it with the value at mouse-down tells a real file or text drag apart
    /// from an ordinary click-and-drag such as selecting text or moving a window.
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var isDraggingContent = false

    /// Set when the notch is opened from the menu bar icon or a shortcut. It then stays
    /// open until the cursor has visited it and left, or the user clicks elsewhere.
    private var openedManually = false
    private var cursorVisitedSinceManualOpen = false

    init(
        clipboard: ClipboardManager,
        shelf: FileTrayManager,
        hud: SystemHUDManager,
        nowPlaying: NowPlayingManager,
        settings: SettingsStore,
        openSettings: @escaping () -> Void
    ) {
        self.clipboard = clipboard
        self.shelf = shelf
        self.hud = hud
        self.nowPlaying = nowPlaying
        self.settings = settings
        self.openSettings = openSettings
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        viewModel.geometry = NotchGeometry(screen: screen)

        let panel = NotchPanel(contentRect: viewModel.geometry.closedPanelFrame())
        let container = NotchContainerView(
            frame: NSRect(origin: .zero, size: panel.frame.size),
            rootView: NotchRootView(
                viewModel: viewModel,
                clipboard: clipboard,
                shelf: shelf,
                hud: hud,
                nowPlaying: nowPlaying,
                openSettings: { [weak self] in
                    self?.close()
                    self?.openSettings()
                }
            )
        )
        container.delegate = self
        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        installEventMonitors()
        observeIndicators()

        NotificationCenter.default.addObserver(
            self,
            selector: #selector(screenParametersChanged),
            name: NSApplication.didChangeScreenParametersNotification,
            object: nil
        )
        NSWorkspace.shared.notificationCenter.addObserver(
            self,
            selector: #selector(activeSpaceChanged),
            name: NSWorkspace.activeSpaceDidChangeNotification,
            object: nil
        )
    }

    func stop() {
        for monitor in eventMonitors {
            NSEvent.removeMonitor(monitor)
        }
        eventMonitors.removeAll()
        subscriptions.removeAll()
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        for task in [closeTask, collapseTask, indicatorResizeTask, chargingIndicatorTask] {
            task?.cancel()
        }
        panel?.orderOut(nil)
    }

    // MARK: - Opening and closing

    func open(manually: Bool = false) {
        cancelScheduledClose()
        collapseTask?.cancel()
        collapseTask = nil
        indicatorResizeTask?.cancel()
        indicatorResizeTask = nil

        if manually {
            openedManually = true
            cursorVisitedSinceManualOpen = false
        }

        guard !viewModel.isOpen, let panel else { return }

        // Grow the window first, then animate the shape inside it. The closed shape
        // stays centred at the top, so it doesn't jump when the window resizes.
        panel.setFrame(viewModel.geometry.openPanelFrame, display: true)
        if settings.hapticsEnabled {
            NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
        }
        viewModel.setState(.open)
    }

    func close() {
        cancelScheduledClose()
        openedManually = false
        guard viewModel.isOpen else { return }

        viewModel.setState(.closed)
        viewModel.isDropTargeted = false

        // Shrink the window back to notch size once the close animation has played,
        // so the transparent area around it stops covering anything.
        collapseTask = Task { [weak self] in
            try? await Task.sleep(for: NotchMetrics.collapseDuration)
            guard let self, !Task.isCancelled, !self.viewModel.isOpen, let panel = self.panel else { return }
            panel.setFrame(self.viewModel.geometry.closedPanelFrame(extraWidth: self.viewModel.closedExtraWidth), display: true)
            // If the search field had keyboard focus, typing would keep going to the
            // hidden notch. Re-ordering the window hands focus back to the app underneath.
            if panel.isKeyWindow {
                panel.makeFirstResponder(nil)
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
    }

    /// Keyboard shortcut: open (and stay open) or close.
    func toggle() {
        if viewModel.isOpen {
            close()
        } else {
            open(manually: true)
        }
    }

    /// Keyboard shortcut: open the clipboard tab with the search field ready for typing.
    func openClipboardSearch() {
        viewModel.selectedTab = .clipboard
        open(manually: true)
        panel?.makeKey()
        viewModel.requestSearchFocus()
    }

    private func scheduleClose() {
        guard closeTask == nil else { return }
        closeTask = Task { [weak self] in
            try? await Task.sleep(for: NotchMetrics.closeDelay)
            guard let self, !Task.isCancelled else { return }
            self.closeTask = nil
            self.close()
        }
    }

    private func cancelScheduledClose() {
        closeTask?.cancel()
        closeTask = nil
    }

    // MARK: - Closed-notch indicators

    private func observeIndicators() {
        hud.$microphone
            .map(\.isActive)
            .combineLatest(settings.$showMicrophoneIndicator)
            .map { isActive, isEnabled in isActive && isEnabled }
            .removeDuplicates()
            .sink { [weak self] show in
                MainActor.assumeIsolated {
                    self?.updateIndicators { $0.showsMicrophoneIndicator = show }
                }
            }
            .store(in: &subscriptions)

        // Artwork and equalizer beside the notch while something plays. Paused tracks hide it.
        nowPlaying.$info
            .combineLatest(settings.$showNowPlayingIndicator)
            .map(Self.indicatorTrack)
            .removeDuplicates(by: Self.isSameIndicatorTrack)
            .sink { [weak self] (info: NowPlayingInfo?) in
                MainActor.assumeIsolated {
                    self?.updateIndicators { $0.nowPlayingIndicator = info }
                }
            }
            .store(in: &subscriptions)

        // Show the battery level for a few seconds when the charger is connected.
        hud.$battery
            .map(\.isPluggedIn)
            .removeDuplicates()
            .dropFirst()
            .filter { $0 }
            .sink { [weak self] _ in
                MainActor.assumeIsolated {
                    self?.flashChargingIndicator()
                }
            }
            .store(in: &subscriptions)
    }

    /// The track to show beside the closed notch: only while playing, and only if enabled.
    private nonisolated static func indicatorTrack(_ info: NowPlayingInfo?, isEnabled: Bool) -> NowPlayingInfo? {
        guard isEnabled, let info, info.isPlaying else { return nil }
        return info
    }

    /// Position updates arrive often; only a new track or new artwork should redraw the indicator.
    private nonisolated static func isSameIndicatorTrack(_ lhs: NowPlayingInfo?, _ rhs: NowPlayingInfo?) -> Bool {
        switch (lhs, rhs) {
        case (nil, nil):
            return true
        case let (lhs?, rhs?):
            return lhs.title == rhs.title && lhs.artist == rhs.artist && lhs.artwork === rhs.artwork
        default:
            return false
        }
    }

    private func flashChargingIndicator() {
        guard settings.showChargingIndicator, hud.battery.hasBattery else { return }
        updateIndicators { $0.chargingIndicatorPercentage = hud.battery.percentage }

        chargingIndicatorTask?.cancel()
        chargingIndicatorTask = Task { [weak self] in
            try? await Task.sleep(for: NotchMetrics.chargingIndicatorDuration)
            guard let self, !Task.isCancelled else { return }
            self.updateIndicators { $0.chargingIndicatorPercentage = nil }
        }
    }

    /// Changes which indicators are showing, resizing the closed window around them.
    /// The window grows before the shape animates wider, and shrinks after it animates narrower.
    private func updateIndicators(_ change: (NotchViewModel) -> Void) {
        let widthBefore = viewModel.closedExtraWidth
        withAnimation(NotchMetrics.spring) {
            change(viewModel)
        }
        let widthAfter = viewModel.closedExtraWidth

        guard !viewModel.isOpen, collapseTask == nil || collapseTask?.isCancelled == true, let panel else { return }
        let targetFrame = viewModel.geometry.closedPanelFrame(extraWidth: widthAfter)

        if widthAfter > widthBefore {
            indicatorResizeTask?.cancel()
            panel.setFrame(targetFrame, display: true)
        } else if widthAfter < widthBefore {
            indicatorResizeTask?.cancel()
            indicatorResizeTask = Task { [weak self] in
                try? await Task.sleep(for: NotchMetrics.collapseDuration)
                guard let self, !Task.isCancelled, !self.viewModel.isOpen else { return }
                self.panel?.setFrame(
                    self.viewModel.geometry.closedPanelFrame(extraWidth: self.viewModel.closedExtraWidth),
                    display: true
                )
            }
        }
    }

    // MARK: - Cursor, drag and keyboard tracking

    private func installEventMonitors() {
        let mouseEvents: NSEvent.EventTypeMask = [.mouseMoved, .leftMouseDragged, .leftMouseDown, .leftMouseUp]

        // Events sent to other apps. Watching mouse movement this way needs no extra permission.
        if let global = NSEvent.addGlobalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseEvent(event)
            }
        }) {
            eventMonitors.append(global)
        }

        // Events sent to NotchFlow's own windows.
        if let local = NSEvent.addLocalMonitorForEvents(matching: mouseEvents, handler: { [weak self] event in
            MainActor.assumeIsolated {
                self?.handleMouseEvent(event)
            }
            return event
        }) {
            eventMonitors.append(local)
        }

        // Keys while the notch has keyboard focus: Esc closes, ⌘1–⌘3 switch tabs.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let keyCode = event.keyCode
            let isCommand = event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            let characters = event.charactersIgnoringModifiers
            let handled = MainActor.assumeIsolated { () -> Bool in
                self?.handleKey(keyCode: keyCode, isCommand: isCommand, characters: characters) ?? false
            }
            return handled ? nil : event
        }) {
            eventMonitors.append(keys)
        }
    }

    private func handleKey(keyCode: UInt16, isCommand: Bool, characters: String?) -> Bool {
        guard viewModel.isOpen, panel?.isKeyWindow == true else { return false }

        let escapeKeyCode: UInt16 = 53
        if keyCode == escapeKeyCode {
            close()
            return true
        }
        if isCommand, let characters, let number = Int(characters),
           NotchViewModel.Tab.allCases.indices.contains(number - 1) {
            withAnimation(.easeInOut(duration: 0.15)) {
                viewModel.selectedTab = NotchViewModel.Tab.allCases[number - 1]
            }
            return true
        }
        return false
    }

    private func handleMouseEvent(_ event: NSEvent) {
        let location = NSEvent.mouseLocation

        switch event.type {
        case .leftMouseDown:
            dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
            if viewModel.isOpen && !viewModel.geometry.openShapeRect.contains(location) {
                close()
                return
            }
            // Clicking the closed notch always opens it, whether or not hover is on.
            if !viewModel.isOpen, event.window === panel {
                open()
                return
            }
        case .leftMouseDragged:
            if !isDraggingContent && NSPasteboard(name: .drag).changeCount != dragChangeCountAtMouseDown {
                isDraggingContent = true
            }
        case .leftMouseUp:
            isDraggingContent = false
        default:
            break
        }

        updateForCursor(at: location)
    }

    private func updateForCursor(at location: NSPoint) {
        let geometry = viewModel.geometry

        if !viewModel.isOpen {
            // Content drags always open the notch so there is somewhere to drop.
            // Plain hovering only does when the setting is on. Never pop open while the
            // user is dragging a window or selecting text across the top of the screen.
            let mouseIsDown = NSEvent.pressedMouseButtons != 0
            let wantsOpen = isDraggingContent || (settings.openOnHover && !mouseIsDown)
            if geometry.hoverZone.contains(location) && wantsOpen {
                if isDraggingContent {
                    viewModel.selectedTab = .shelf
                }
                open()
            }
            return
        }

        let cursorIsInside = geometry.openShapeRect.insetBy(dx: -4, dy: -4).contains(location)
            || geometry.hoverZone.contains(location)

        if cursorIsInside {
            cancelScheduledClose()
            if openedManually {
                cursorVisitedSinceManualOpen = true
            }
        } else if openedManually && !cursorVisitedSinceManualOpen {
            // Opened from the menu bar or a shortcut and the cursor hasn't come over yet: stay open.
        } else {
            scheduleClose()
        }
    }

    // MARK: - System changes

    @objc private func screenParametersChanged() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        viewModel.geometry = NotchGeometry(screen: screen)
        let frame = viewModel.isOpen
            ? viewModel.geometry.openPanelFrame
            : viewModel.geometry.closedPanelFrame(extraWidth: viewModel.closedExtraWidth)
        panel?.setFrame(frame, display: true)
    }

    @objc private func activeSpaceChanged() {
        panel?.orderFrontRegardless()
    }
}

// MARK: - NotchContainerViewDelegate

extension NotchController: NotchContainerViewDelegate {
    func containerMouseEntered() {
        // Hovering the notch itself opens it, even if the cursor jumped straight in.
        if settings.openOnHover && NSEvent.pressedMouseButtons == 0 {
            open()
        }
    }

    func containerMouseExited() {
        updateForCursor(at: NSEvent.mouseLocation)
    }

    func containerDragEntered() {
        isDraggingContent = true
        viewModel.selectedTab = .shelf
        viewModel.isDropTargeted = true
        open()
    }

    func containerDragExited() {
        viewModel.isDropTargeted = false
        updateForCursor(at: NSEvent.mouseLocation)
    }

    func containerPerformDrop(_ pasteboard: NSPasteboard) -> Bool {
        viewModel.isDropTargeted = false
        isDraggingContent = false
        viewModel.selectedTab = .shelf
        return shelf.add(from: pasteboard)
    }
}
