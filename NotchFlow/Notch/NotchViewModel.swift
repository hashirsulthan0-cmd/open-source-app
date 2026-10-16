import SwiftUI

/// Shared state between `NotchController` (AppKit) and the SwiftUI views.
@MainActor
final class NotchViewModel: ObservableObject {
    enum State {
        case closed
        case open
    }

    enum Tab: String, CaseIterable, Identifiable {
        case clipboard
        case shelf
        case status

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clipboard: "Clipboard"
            case .shelf: "Shelf"
            case .status: "Status"
            }
        }

        var symbol: String {
            switch self {
            case .clipboard: "doc.on.clipboard"
            case .shelf: "tray.full"
            case .status: "bolt.horizontal.circle"
            }
        }
    }

    @Published private(set) var state: State = .closed
    @Published var selectedTab: Tab = .clipboard
    @Published var geometry: NotchGeometry
    /// True while something is being dragged over the notch.
    @Published var isDropTargeted = false

    // Indicators beside the closed notch.
    @Published var showsMicrophoneIndicator = false
    /// Battery percentage shown briefly after the charger is connected.
    @Published var chargingIndicatorPercentage: Int?
    /// The track shown beside the closed notch while music plays.
    @Published var nowPlayingIndicator: NowPlayingInfo?

    /// Incremented to ask the clipboard search field to take keyboard focus.
    @Published private(set) var searchFocusRequest = 0

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    var isOpen: Bool { state == .open }

    var hasClosedIndicator: Bool {
        showsMicrophoneIndicator || chargingIndicatorPercentage != nil || nowPlayingIndicator != nil
    }

    var closedExtraWidth: CGFloat {
        hasClosedIndicator ? NotchMetrics.indicatorWidth : 0
    }

    var currentSize: CGSize {
        isOpen ? geometry.openSize : geometry.closedSize(extraWidth: closedExtraWidth)
    }

    func setState(_ newState: State) {
        guard newState != state else { return }
        withAnimation(NotchMetrics.spring) {
            state = newState
        }
    }

    func requestSearchFocus() {
        searchFocusRequest += 1
    }
}
