import SwiftUI

/// Every size, radius and timing the notch uses, in one place so they're easy to tune.
enum NotchMetrics {
    /// How close (in points) the cursor must get to the notch before it expands.
    static let hoverMargin: CGFloat = 15

    /// Size of the expanded notch, including its small top "ears".
    static let openSize = CGSize(width: 620, height: 240)

    /// Transparent room around the expanded notch so its shadow isn't cut off.
    static let shadowPadding: CGFloat = 24

    /// Width of the virtual notch drawn on screens without a camera notch.
    static let fallbackPillWidth: CGFloat = 200
    static let fallbackPillMinHeight: CGFloat = 24

    // Corner radii. The top radius is the small outward curve where the notch
    // meets the top edge of the screen; the bottom radius rounds its lower corners.
    static let closedTopRadius: CGFloat = 6
    static let closedBottomRadius: CGFloat = 12
    static let openTopRadius: CGFloat = 16
    static let openBottomRadius: CGFloat = 26

    /// Grace period after the cursor leaves before the notch closes.
    static let closeDelay: Duration = .milliseconds(250)

    /// How long the close animation takes before the window shrinks back to notch size.
    static let collapseDuration: Duration = .milliseconds(420)

    static var spring: Animation {
        .spring(response: 0.32, dampingFraction: 0.78)
    }
}
