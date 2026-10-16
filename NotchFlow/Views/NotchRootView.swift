import SwiftUI

/// Everything drawn inside the notch window: the black notch shape, which morphs
/// between closed and open, and the expanded content.
struct NotchRootView: View {
    @ObservedObject var viewModel: NotchViewModel
    let clipboard: ClipboardManager
    let shelf: FileTrayManager

    var body: some View {
        let isOpen = viewModel.isOpen
        let shape = NotchShape(
            topCornerRadius: isOpen ? NotchMetrics.openTopRadius : NotchMetrics.closedTopRadius,
            bottomCornerRadius: isOpen ? NotchMetrics.openBottomRadius : NotchMetrics.closedBottomRadius
        )

        ZStack(alignment: .top) {
            if isOpen {
                NotchExpandedView(viewModel: viewModel, clipboard: clipboard, shelf: shelf)
                    .transition(
                        .asymmetric(
                            insertion: .opacity
                                .combined(with: .scale(scale: 0.94, anchor: .top))
                                .animation(NotchMetrics.spring.delay(0.05)),
                            removal: .opacity.animation(.easeOut(duration: 0.12))
                        )
                    )
            }
        }
        .frame(
            width: viewModel.currentSize.width,
            height: viewModel.currentSize.height,
            alignment: .top
        )
        .clipShape(shape)
        .background {
            shape
                .fill(Color.black)
                .shadow(color: .black.opacity(isOpen ? 0.45 : 0), radius: 18, y: 8)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .environment(\.colorScheme, .dark)
    }
}

/// The open notch: a top band split around the camera (tabs on the left, clock on
/// the right), with the selected tab's content below.
struct NotchExpandedView: View {
    @ObservedObject var viewModel: NotchViewModel
    let clipboard: ClipboardManager
    let shelf: FileTrayManager

    var body: some View {
        let geometry = viewModel.geometry
        let topBandHeight = max(geometry.notchRect.height, 32)

        VStack(spacing: 10) {
            HStack(spacing: 0) {
                NotchTabBar(selection: $viewModel.selectedTab)
                // Leave the camera area clear.
                Spacer(minLength: geometry.hasNotch ? geometry.notchRect.width + 16 : 16)
                NotchClock()
            }
            .frame(height: topBandHeight)

            Group {
                switch viewModel.selectedTab {
                case .clipboard:
                    ClipboardView(clipboard: clipboard)
                case .shelf:
                    ShelfView(shelf: shelf, isDropTargeted: viewModel.isDropTargeted)
                case .nowPlaying:
                    NotchEmptyState(
                        symbol: "music.note",
                        title: "Now Playing",
                        message: "Music, battery and microphone status will appear here."
                    )
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .transition(.opacity)
        }
        .padding(.horizontal, NotchMetrics.openTopRadius + 14)
        .padding(.bottom, 16)
        .foregroundStyle(.white)
    }
}

private struct NotchTabBar: View {
    @Binding var selection: NotchViewModel.Tab

    var body: some View {
        HStack(spacing: 4) {
            ForEach(NotchViewModel.Tab.allCases) { tab in
                let isSelected = tab == selection
                Button {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        selection = tab
                    }
                } label: {
                    Image(systemName: tab.symbol)
                        .font(.system(size: 12, weight: .semibold))
                        .frame(width: 30, height: 24)
                        .background {
                            Capsule().fill(Color.white.opacity(isSelected ? 0.16 : 0))
                        }
                        .foregroundStyle(isSelected ? Color.white : Color.white.opacity(0.55))
                        .contentShape(Capsule())
                }
                .buttonStyle(.plain)
                .help(tab.title)
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
