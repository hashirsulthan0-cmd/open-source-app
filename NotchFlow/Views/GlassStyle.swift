import AppKit
import SwiftUI

// The glossy, Control Center-like look. One value, `glassIntensity` (0–1, set by the
// slider in Settings), drives everything: 0 is the original solid black, 1 is the most
// see-through glass with the strongest highlights.

private struct GlassIntensityKey: EnvironmentKey {
    static let defaultValue = 0.6
}

extension EnvironmentValues {
    var glassIntensity: Double {
        get { self[GlassIntensityKey.self] }
        set { self[GlassIntensityKey.self] = newValue }
    }
}

/// Blurs whatever is behind the notch window, like Control Center does.
struct BehindWindowBlur: NSViewRepresentable {
    func makeNSView(context: Context) -> NSVisualEffectView {
        let view = NSVisualEffectView()
        view.material = .hudWindow
        view.blendingMode = .behindWindow
        // NotchFlow is never the active app, so keep the blur on regardless.
        view.state = .active
        view.appearance = NSAppearance(named: .darkAqua)
        return view
    }

    func updateNSView(_ nsView: NSVisualEffectView, context: Context) {}
}

/// Background of the notch shape. Closed, it's pure black so it blends with the camera
/// notch. Open, it's frosted glass that stays black along the top edge for the same reason.
///
/// The live blur is the most expensive part: macOS re-blurs everything behind the notch
/// on every frame. Without it, the glass is drawn as an opaque dark tint with the same
/// highlights, which looks close and costs almost nothing.
struct NotchGlassBackground: View {
    let isOpen: Bool
    let topBandHeight: CGFloat
    let usesLiveBlur: Bool
    @Environment(\.glassIntensity) private var intensity

    var body: some View {
        ZStack(alignment: .top) {
            if isOpen && intensity > 0.01 {
                if usesLiveBlur {
                    BehindWindowBlur()
                    // A dark tint keeps text readable; less tint means more glass.
                    Color.black.opacity(1 - 0.55 * intensity)
                } else {
                    // Opaque smoky glass: lifts from black toward a soft grey as glossiness rises.
                    LinearGradient(
                        colors: [Color(white: 0.04 + 0.06 * intensity), Color(white: 0.08 + 0.10 * intensity)],
                        startPoint: .top,
                        endPoint: .bottom
                    )
                }
                // Soft sheen across the top half, like light hitting glass.
                LinearGradient(
                    colors: [Color.white.opacity(0.07 * intensity), .clear],
                    startPoint: .top,
                    endPoint: .center
                )
                // Solid black behind the camera, fading into the glass below it.
                LinearGradient(
                    stops: [
                        .init(color: .black, location: 0),
                        .init(color: .black, location: 0.55),
                        .init(color: .black.opacity(0), location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
                .frame(height: topBandHeight + 14)
            } else {
                Color.black
            }
        }
    }
}

/// A glossy rounded surface for cards, pills and buttons inside the notch.
struct GlossySurface: ViewModifier {
    let cornerRadius: CGFloat
    var isHighlighted = false
    @Environment(\.glassIntensity) private var intensity

    func body(content: Content) -> some View {
        let shape = RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
        let fill = 0.06 + 0.06 * intensity + (isHighlighted ? 0.08 : 0)

        content
            .background {
                ZStack {
                    shape.fill(Color.white.opacity(fill))
                    // Light from above: brighter at the top edge, like the Control Center tiles.
                    shape.fill(
                        LinearGradient(
                            colors: [Color.white.opacity(0.10 * intensity), .clear],
                            startPoint: .top,
                            endPoint: .center
                        )
                    )
                }
            }
            .overlay {
                shape.strokeBorder(
                    LinearGradient(
                        colors: [
                            Color.white.opacity(0.08 + 0.32 * intensity),
                            Color.white.opacity(0.03 + 0.05 * intensity),
                        ],
                        startPoint: .top,
                        endPoint: .bottom
                    ),
                    lineWidth: 1
                )
            }
    }
}

extension View {
    func glossySurface(cornerRadius: CGFloat = 14, highlighted: Bool = false) -> some View {
        modifier(GlossySurface(cornerRadius: cornerRadius, isHighlighted: highlighted))
    }
}
