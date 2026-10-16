import SwiftUI

/// Shared look for the cards in the clipboard and shelf rows.
struct NotchCard<Content: View>: View {
    var isHighlighted = false
    @ViewBuilder var content: () -> Content

    @State private var isHovering = false

    var body: some View {
        content()
            .frame(width: 128)
            .frame(maxHeight: .infinity)
            .background {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .fill(Color.white.opacity(isHovering || isHighlighted ? 0.13 : 0.07))
            }
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .strokeBorder(Color.white.opacity(isHighlighted ? 0.5 : 0), lineWidth: 1)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
            .onHover { isHovering = $0 }
            .animation(.easeOut(duration: 0.12), value: isHovering)
    }
}

/// An image file shown as a filled thumbnail.
struct ThumbnailImage: View {
    let url: URL?

    var body: some View {
        if let url, let image = ThumbnailCache.image(at: url) {
            Image(nsImage: image)
                .resizable()
                .scaledToFill()
        } else {
            Color.white.opacity(0.06)
        }
    }
}

/// Large faint icon with a short message, for empty tabs.
struct NotchEmptyState: View {
    let symbol: String
    let title: String
    let message: String

    var body: some View {
        VStack(spacing: 6) {
            Image(systemName: symbol)
                .font(.system(size: 24))
                .foregroundStyle(.white.opacity(0.35))
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            Text(message)
                .font(.system(size: 11))
                .foregroundStyle(.white.opacity(0.5))
                .multilineTextAlignment(.center)
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background {
            RoundedRectangle(cornerRadius: 14, style: .continuous)
                .fill(Color.white.opacity(0.05))
        }
    }
}

extension Date {
    /// "now", "5m", "2h", "3d": short enough for a small card.
    var shortAge: String {
        let seconds = Int(Date().timeIntervalSince(self))
        switch seconds {
        case ..<60: return "now"
        case ..<3600: return "\(seconds / 60)m"
        case ..<86_400: return "\(seconds / 3600)h"
        default: return "\(seconds / 86_400)d"
        }
    }
}
