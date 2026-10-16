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
        case nowPlaying

        var id: String { rawValue }

        var title: String {
            switch self {
            case .clipboard: "Clipboard"
            case .shelf: "Shelf"
            case .nowPlaying: "Now Playing"
            }
        }

        var symbol: String {
            switch self {
            case .clipboard: "doc.on.clipboard"
            case .shelf: "tray.full"
            case .nowPlaying: "music.note"
            }
        }
    }

    @Published private(set) var state: State = .closed
    @Published var selectedTab: Tab = .clipboard
    @Published var geometry: NotchGeometry

    init(geometry: NotchGeometry) {
        self.geometry = geometry
    }

    var isOpen: Bool { state == .open }

    var currentSize: CGSize {
        isOpen ? geometry.openSize : geometry.closedSize
    }

    func setState(_ newState: State) {
        guard newState != state else { return }
        withAnimation(NotchMetrics.spring) {
            state = newState
        }
    }
}
