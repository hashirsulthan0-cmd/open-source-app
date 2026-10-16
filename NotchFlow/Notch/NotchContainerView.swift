import AppKit
import SwiftUI

@MainActor
protocol NotchContainerViewDelegate: AnyObject {
    func containerMouseEntered()
    func containerMouseExited()
    func containerDragEntered()
    func containerDragExited()
}

/// The panel's root view. It hosts the SwiftUI interface and reports hover and
/// drag-and-drop activity over the notch back to `NotchController`.
final class NotchContainerView: NSView {
    weak var delegate: NotchContainerViewDelegate?

    private let hostingView: NSHostingView<NotchRootView>

    init(frame: NSRect, rootView: NotchRootView) {
        hostingView = NSHostingView(rootView: rootView)
        super.init(frame: frame)

        wantsLayer = true
        layer?.backgroundColor = NSColor.clear.cgColor

        // The window size is managed by NotchController, not by the SwiftUI content.
        hostingView.sizingOptions = []
        hostingView.translatesAutoresizingMaskIntoConstraints = false
        addSubview(hostingView)
        NSLayoutConstraint.activate([
            hostingView.leadingAnchor.constraint(equalTo: leadingAnchor),
            hostingView.trailingAnchor.constraint(equalTo: trailingAnchor),
            hostingView.topAnchor.constraint(equalTo: topAnchor),
            hostingView.bottomAnchor.constraint(equalTo: bottomAnchor),
        ])

        registerForDraggedTypes([.fileURL, .URL, .string, .tiff, .png])
    }

    @available(*, unavailable)
    required init?(coder: NSCoder) {
        fatalError("init(coder:) is not supported")
    }

    // MARK: - Hover tracking

    override func updateTrackingAreas() {
        super.updateTrackingAreas()
        for area in trackingAreas {
            removeTrackingArea(area)
        }
        addTrackingArea(NSTrackingArea(
            rect: bounds,
            options: [.mouseEnteredAndExited, .activeAlways, .inVisibleRect],
            owner: self,
            userInfo: nil
        ))
    }

    override func mouseEntered(with event: NSEvent) {
        delegate?.containerMouseEntered()
    }

    override func mouseExited(with event: NSEvent) {
        delegate?.containerMouseExited()
    }

    // MARK: - Drag and drop

    override func draggingEntered(_ sender: NSDraggingInfo) -> NSDragOperation {
        delegate?.containerDragEntered()
        return .copy
    }

    override func draggingUpdated(_ sender: NSDraggingInfo) -> NSDragOperation {
        .copy
    }

    override func draggingExited(_ sender: NSDraggingInfo?) {
        delegate?.containerDragExited()
    }

    override func draggingEnded(_ sender: NSDraggingInfo) {
        delegate?.containerDragExited()
    }

    // Dropped items are stored by the shelf, which arrives in Phase 2.
    // Until then the drop is declined and the item returns to where it came from.
    override func performDragOperation(_ sender: NSDraggingInfo) -> Bool {
        false
    }
}
