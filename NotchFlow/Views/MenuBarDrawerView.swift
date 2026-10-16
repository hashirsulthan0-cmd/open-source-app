import SwiftUI

/// The row along the bottom of the open notch: pinned apps on the left, then the
/// menu bar's icons, including ones hidden behind the notch.
struct MenuBarDrawerView: View {
    @ObservedObject var scanner: MenuBarScanner
    let quickLaunch: [QuickLaunchItem]
    let onQuickLaunch: (QuickLaunchItem) -> Void
    let onPressItem: (MenuBarItem) -> Void

    var body: some View {
        HStack(spacing: 6) {
            ForEach(quickLaunch) { item in
                DrawerButton(help: item.title, action: { onQuickLaunch(item) }) {
                    if case .spotlight = item.action {
                        Image(nsImage: item.icon)
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.85))
                    } else {
                        Image(nsImage: item.icon)
                            .resizable()
                            .scaledToFit()
                            .frame(width: 22, height: 22)
                    }
                }
            }

            if !quickLaunch.isEmpty {
                Rectangle()
                    .fill(Color.white.opacity(0.15))
                    .frame(width: 1, height: 20)
                    .padding(.horizontal, 2)
            }

            if scanner.hasAccessibility {
                menuBarItems
            } else {
                permissionButton(
                    "Allow Accessibility to show your menu bar icons here",
                    systemImage: "hand.raised.fill",
                    action: scanner.requestAccessibility
                )
            }
        }
        .padding(.horizontal, 8)
        .frame(height: NotchMetrics.drawerHeight - 8)
        .frame(maxWidth: .infinity, alignment: .leading)
        .glossySurface(cornerRadius: 19)
    }

    @ViewBuilder
    private var menuBarItems: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 4) {
                ForEach(scanner.items) { item in
                    DrawerButton(help: item.isHidden ? "\(item.appName) (hidden behind the notch)" : item.appName) {
                        onPressItem(item)
                    } label: {
                        MenuBarItemIcon(item: item)
                    }
                }
                if scanner.items.isEmpty {
                    Text("Looking for menu bar icons…")
                        .font(.system(size: 11))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }

        if !scanner.hasScreenRecording {
            Button(action: scanner.requestScreenRecording) {
                Image(systemName: "eye")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                    .frame(width: 24, height: 24)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .help("Allow Screen Recording to show the real menu bar icons instead of app icons")
        }
    }

    private func permissionButton(_ title: String, systemImage: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Label(title, systemImage: systemImage)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(.white.opacity(0.8))
                .padding(.horizontal, 10)
                .frame(height: 26)
                .glossySurface(cornerRadius: 13)
        }
        .buttonStyle(.plain)
    }
}

private struct MenuBarItemIcon: View {
    let item: MenuBarItem

    var body: some View {
        Group {
            if let image = item.image {
                let size = Self.fittedSize(image.size)
                if item.drawsAsTemplate {
                    Image(nsImage: image)
                        .renderingMode(.template)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                        .foregroundStyle(.white.opacity(0.9))
                } else {
                    Image(nsImage: image)
                        .resizable()
                        .frame(width: size.width, height: size.height)
                }
            } else if let icon = NSRunningApplication(processIdentifier: item.pid)?.icon {
                Image(nsImage: icon)
                    .resizable()
                    .scaledToFit()
                    .frame(width: 20, height: 20)
            } else {
                Image(systemName: "app.dashed")
                    .foregroundStyle(.white.opacity(0.6))
            }
        }
        .overlay(alignment: .bottomTrailing) {
            if item.isHidden {
                // Marks icons that are hidden behind the notch in the real menu bar.
                Circle()
                    .fill(Color.orange)
                    .frame(width: 5, height: 5)
                    .offset(x: 2, y: 2)
            }
        }
    }

    /// Menu bar icons are about 24 points tall; keep their shape but cap the width.
    private static func fittedSize(_ size: CGSize) -> CGSize {
        guard size.height > 0 else { return CGSize(width: 20, height: 20) }
        let height: CGFloat = 22
        let width = min(size.width * height / size.height, 90)
        return CGSize(width: width, height: height)
    }
}

private struct DrawerButton<Label: View>: View {
    let help: String
    let action: () -> Void
    @ViewBuilder var label: () -> Label

    @State private var isHovering = false

    var body: some View {
        Button(action: action) {
            label()
                .frame(minWidth: 30, minHeight: 30)
                .padding(.horizontal, 2)
                .background {
                    RoundedRectangle(cornerRadius: 8, style: .continuous)
                        .fill(Color.white.opacity(isHovering ? 0.14 : 0))
                }
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { isHovering = $0 }
        .help(help)
        .accessibilityLabel(help)
    }
}
