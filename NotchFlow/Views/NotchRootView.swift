import SwiftUI

/// Everything drawn inside the notch window: the black notch shape, which morphs
/// between closed and open, and the expanded content.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    @ObservedObject var settings: SettingsStore
    let clipboard: ClipboardManager
    let shelf: FileTrayManager
    let hud: SystemHUDManager
    let nowPlaying: NowPlayingManager
    let drawer: DrawerContext
    let openSettings: () -> Void

    var body: some View {
        let isOpen = viewModel.isOpen
        let shape = NotchShape(
            topCornerRadius: isOpen ? NotchMetrics.openTopRadius : NotchMetrics.closedTopRadius,
            bottomCornerRadius: isOpen ? NotchMetrics.openBottomRadius : NotchMetrics.closedBottomRadius
        )

        ZStack(alignment: .top) {
            if isOpen {
                NotchExpandedView(
                    viewModel: viewModel,
                    clipboard: clipboard,
                    shelf: shelf,
                    hud: hud,
                    nowPlaying: nowPlaying,
                    drawer: drawer,
                    openSettings: openSettings
                )
                .transition(
                    .asymmetric(
                        insertion: .opacity
                            .combined(with: .scale(scale: 0.94, anchor: .top))
                            .animation(NotchMetrics.spring.delay(0.05)),
                        removal: .opacity.animation(.easeOut(duration: 0.12))
                    )
                )
            } else if viewModel.hasClosedIndicator {
                ClosedNotchIndicators(viewModel: viewModel)
                    .frame(height: viewModel.geometry.notchRect.height)
            }
        }
        .frame(
            width: viewModel.currentSize.width,
            height: viewModel.currentSize.height,
            alignment: .top
        )
        .background {
            NotchGlassBackground(
                isOpen: isOpen,
                topBandHeight: max(viewModel.geometry.notchRect.height, 32)
            )
        }
        .clipShape(shape)
        .overlay {
            // A glossy rim: brighter along the bottom curve, where light catches the edge.
            shape.stroke(
                LinearGradient(
                    colors: [
                        Color.white.opacity(isOpen ? 0.04 : 0),
                        Color.white.opacity(isOpen ? 0.08 + 0.22 * settings.glassIntensity : 0),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                ),
                lineWidth: 1
            )
        }
        .background {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(isOpen ? 0.5 : 0), radius: 18, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
        .environment(\.glassIntensity, settings.glassIntensity)
        .animation(.easeOut(duration: 0.2), value: settings.glassIntensity)
    }
}

/// What the menu bar drawer needs, bundled so it can be passed down in one piece.
struct DrawerContext {
    let scanner: MenuBarScanner
    let quickLaunch: [QuickLaunchItem]
    let onQuickLaunch: (QuickLaunchItem) -> Void
    let onPressItem: (MenuBarItem) -> Void
}

/// The open notch: a top band split around the camera (tabs on the left, clock and
/// settings on the right), with the selected tab's content below.
struct NotchExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    let clipboard: ClipboardManager
    let shelf: FileTrayManager
    let hud: SystemHUDManager
    let nowPlaying: NowPlayingManager
    let drawer: DrawerContext
    let openSettings: () -> Void

    var body: some View {
        let geometry = viewModel.geometry
        let topBandHeight = max(geometry.notchRect.height, 32)

        VStack(spacing: 10) {
            HStack(spacing: 0) {
                NotchTabBar(selection: $viewModel.selectedTab)
                // Leave the camera area clear.
                Spacer(minLength: geometry.hasNotch ? geometry.notchRect.width + 16 : 16)
                HStack(spacing: 10) {
                    NotchClock()
                    Button(action: openSettings) {
                        Image(systemName: "gearshape.fill")
                            .font(.system(size: 12, weight: .semibold))
                            .foregroundStyle(.white.opacity(0.6))
                            .frame(width: 24, height: 24)
                            .contentShape(Rectangle())
                    }
                    .buttonStyle(.plain)
                    .help("Settings")
                    .accessibilityLabel("Settings")
                }
            }
            .frame(height: topBandHeight)

            Group {
                switch viewModel.selectedTab {
                case .clipboard:
                    ClipboardView(clipboard: clipboard, focusRequest: viewModel.searchFocusRequest)
                case .shelf:
                    ShelfView(shelf: shelf, isDropTargeted: viewModel.isDropTargeted)
                case .status:
                    StatusView(hud: hud, nowPlaying: nowPlaying)
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)

            if geometry.includesDrawer {
                MenuBarDrawerView(
                    scanner: drawer.scanner,
                    quickLaunch: drawer.quickLaunch,
                    onQuickLaunch: drawer.onQuickLaunch,
                    onPressItem: drawer.onPressItem
                )
            }
        }
        .padding(.horizontal, NotchMetrics.openTopRadius + 14)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }
}

private struct NotchTabBar: View {
    @Binding var selection: NotchViewModel.Tab

    @Namespace private var highlight
    @Environment(\.glassIntensity) private var intensity

    var body: some View {
        HStack(spacing: 4) {
            ForEach(Array(NotchViewModel.Tab.allCases.enumerated()), id: \.element) { index, tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.spring(response: 0.3, dampingFraction: 0.8)) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .background {
                            if isSelected {
                                Capsule()
                                    .fill(Color.white.opacity(0.16 + 0.74 * intensity))
                                    .shadow(color: .white.opacity(0.25 * intensity), radius: 4)
                                    .matchedGeometryEffect(id: "selectedTab", in: highlight)
                            }
                        }
                        .foregroundStyle(isSelected ? (intensity > 0.45 ? Color.black : Color.white) : Color.white.opacity(0.55))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help("\(tab.title) (⌘\(index + 1))")
                .accessibilityLabel(tab.title)
            }
        }
    }
}

private struct NotchClock: View {
    var body: some View {
        TimelineView(.everyMinute) { context in
            Text(context.date, format: .dateTime.hour().minute())
                .font(.system(size: 13, weight: .semibold).monospacedDigit())
                .foregroundStyle(.white.opacity(0.85))
        }
    }
}
