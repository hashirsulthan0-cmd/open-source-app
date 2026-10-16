import AppKit

/// Owns the notch window and decides when it opens and closes.
///
/// The notch opens when the cursor comes within `NotchMetrics.hoverMargin` of it,
/// or when something is being dragged toward it. It closes shortly after the cursor
/// leaves, or right away on a click outside.
@MainActor
final class NotchController: NSObject {
    private let viewModel = NotchViewModel(geometry: .zero)
    private let clipboard: ClipboardManager
    private let shelf: FileTrayManager
    private var panel: NotchPanel?
    private var eventMonitors: [Any] = []

    private var closeTask: Task<Void, Never>?
    private var collapseTask: Task<Void, Never>?

    /// `NSPasteboard(name: .drag)` gets a new change count each time a drag starts.
    /// Comparing it with the value at mouse-down tells a real file or text drag apart
    /// from an ordinary click-and-drag such as selecting text or moving a window.
    private var dragChangeCountAtMouseDown = NSPasteboard(name: .drag).changeCount
    private var isDraggingContent = false

    /// Set when the notch is opened from the menu bar icon. It then stays open until
    /// the cursor has visited it and left, or the user clicks elsewhere.
    private var openedManually = false
    private var cursorVisitedSinceManualOpen = false

    init(clipboard: ClipboardManager, shelf: FileTrayManager) {
        self.clipboard = clipboard
        self.shelf = shelf
        super.init()
    }

    // MARK: - Lifecycle

    func start() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        viewModel.geometry = NotchGeometry(screen: screen)

        let panel = NotchPanel(contentRect: viewModel.geometry.closedPanelFrame)
        let container = NotchContainerView(
            frame: NSRect(origin: .zero, size: panel.frame.size),
            rootView: NotchRootView(viewModel: viewModel, clipboard: clipboard, shelf: shelf)
        )
        container.delegate = self
        panel.contentView = container
        panel.orderFrontRegardless()
        self.panel = panel

        installEventMonitors()

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
        NotificationCenter.default.removeObserver(self)
        NSWorkspace.shared.notificationCenter.removeObserver(self)
        closeTask?.cancel()
        collapseTask?.cancel()
        panel?.orderOut(nil)
    }

    // MARK: - Opening and closing

    func open(manually: Bool = false) {
        cancelScheduledClose()
        collapseTask?.cancel()
        collapseTask = nil

        if manually {
            openedManually = true
            cursorVisitedSinceManualOpen = false
        }

        guard !viewModel.isOpen, let panel else { return }

        // Grow the window first, then animate the shape inside it. The closed shape
        // stays centred at the top, so it doesn't jump when the window resizes.
        panel.setFrame(viewModel.geometry.openPanelFrame, display: true)
        NSHapticFeedbackManager.defaultPerformer.perform(.alignment, performanceTime: .now)
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
            panel.setFrame(self.viewModel.geometry.closedPanelFrame, display: true)
            // If the search field had keyboard focus, typing would keep going to the
            // hidden notch. Re-ordering the window hands focus back to the app underneath.
            if panel.isKeyWindow {
                panel.makeFirstResponder(nil)
                panel.orderOut(nil)
                panel.orderFrontRegardless()
            }
        }
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

    // MARK: - Cursor and drag tracking

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

        // Escape closes the notch while it has keyboard focus.
        if let keys = NSEvent.addLocalMonitorForEvents(matching: .keyDown, handler: { [weak self] event in
            let escapeKeyCode: UInt16 = 53
            guard event.keyCode == escapeKeyCode else { return event }
            let didClose = MainActor.assumeIsolated { () -> Bool in
                guard let self, self.viewModel.isOpen else { return false }
                self.close()
                return true
            }
            return didClose ? nil : event
        }) {
            eventMonitors.append(keys)
        }
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
            // Don't pop open while the user is dragging a window or selecting text
            // across the top of the screen. Only real content drags count.
            let mouseIsDown = NSEvent.pressedMouseButtons != 0
            if geometry.hoverZone.contains(location) && (!mouseIsDown || isDraggingContent) {
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
            // Opened from the menu bar and the cursor hasn't come over yet: stay open.
        } else {
            scheduleClose()
        }
    }

    // MARK: - System changes

    @objc private func screenParametersChanged() {
        guard let screen = NotchGeometry.preferredScreen() else { return }
        viewModel.geometry = NotchGeometry(screen: screen)
        let frame = viewModel.isOpen ? viewModel.geometry.openPanelFrame : viewModel.geometry.closedPanelFrame
        panel?.setFrame(frame, display: true)
    }

    @objc private func activeSpaceChanged() {
        panel?.orderFrontRegardless()
    }
}

// MARK: - NotchContainerViewDelegate

extension NotchController: NotchContainerViewDelegate {
    func containerMouseEntered() {
        // Hovering the notch itself always opens it, even if the cursor jumped straight in.
        if NSEvent.pressedMouseButtons == 0 {
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
