import SwiftUI

/// Artwork, track details, progress and playback controls.
struct NowPlayingCard: View {
    @ObservedObject var nowPlaying: NowPlayingManager

    var body: some View {
        StatusCard {
            if let info = nowPlaying.info {
                HStack(spacing: 10) {
                    ArtworkView(image: info.artwork, size: 52)
                    VStack(alignment: .leading, spacing: 2) {
                        Text(info.title)
                            .font(.system(size: 12.5, weight: .semibold))
                            .lineLimit(1)
                        Text(info.artist)
                            .font(.system(size: 11))
                            .foregroundStyle(.white.opacity(0.6))
                            .lineLimit(1)
                        HStack(spacing: 5) {
                            EqualizerView(isPlaying: info.isPlaying, barCount: 4, height: 10)
                            Text(info.appName)
                                .font(.system(size: 9.5, weight: .medium))
                                .foregroundStyle(.white.opacity(0.45))
                        }
                    }
                    Spacer(minLength: 0)
                }

                PlaybackProgress(info: info)

                HStack(spacing: 22) {
                    controlButton("backward.fill", label: "Previous track") { nowPlaying.send(.previousTrack) }
                    controlButton(info.isPlaying ? "pause.fill" : "play.fill", label: info.isPlaying ? "Pause" : "Play", size: 18) {
                        nowPlaying.send(.togglePlayPause)
                    }
                    controlButton("forward.fill", label: "Next track") { nowPlaying.send(.nextTrack) }
                }
                .frame(maxWidth: .infinity)
            } else {
                Label("Now Playing", systemImage: "music.note")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.white.opacity(0.6))
                Spacer(minLength: 0)
                Text("Nothing is playing.")
                    .font(.system(size: 13, weight: .semibold))
                Text("Play something in Music or Spotify, or turn on universal support in Settings.")
                    .font(.system(size: 10.5))
                    .foregroundStyle(.white.opacity(0.55))
                    .lineLimit(2)
            }
        }
    }

    private func controlButton(_ symbol: String, label: String, size: CGFloat = 14, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Image(systemName: symbol)
                .font(.system(size: size, weight: .semibold))
                .frame(width: 28, height: 24)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(label)
    }
}

private struct PlaybackProgress: View {
    let info: NowPlayingInfo

    var body: some View {
        TimelineView(.periodic(from: .now, by: 1)) { context in
            let position = info.position(at: context.date)
            VStack(spacing: 3) {
                GeometryReader { proxy in
                    let fraction = (position ?? 0) / max(info.duration ?? 1, 1)
                    ZStack(alignment: .leading) {
                        Capsule().fill(Color.white.opacity(0.15))
                        Capsule()
                            .fill(Color.white.opacity(0.85))
                            .frame(width: proxy.size.width * min(max(fraction, 0), 1))
                    }
                }
                .frame(height: 3)
                HStack {
                    Text(Self.format(position))
                    Spacer()
                    Text(Self.format(info.duration))
                }
                .font(.system(size: 9, weight: .medium).monospacedDigit())
                .foregroundStyle(.white.opacity(0.45))
            }
            .opacity(info.duration == nil ? 0 : 1)
        }
    }

    private static func format(_ seconds: TimeInterval?) -> String {
        guard let seconds, seconds.isFinite else { return "–:––" }
        let total = Int(seconds)
        return String(format: "%d:%02d", total / 60, total % 60)
    }
}

/// Album artwork with a rounded-corner placeholder when there is none.
struct ArtworkView: View {
    let image: NSImage?
    let size: CGFloat

    var body: some View {
        Group {
            if let image {
                Image(nsImage: image)
                    .resizable()
                    .scaledToFill()
            } else {
                ZStack {
                    Color.white.opacity(0.1)
                    Image(systemName: "music.note")
                        .font(.system(size: size * 0.4))
                        .foregroundStyle(.white.opacity(0.5))
                }
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: size * 0.18, style: .continuous))
    }
}

/// Bouncing bars that move while music plays and settle when paused.
struct EqualizerView: View {
    let isPlaying: Bool
    var barCount = 4
    var height: CGFloat = 12
    var color: Color = .white.opacity(0.8)

    var body: some View {
        TimelineView(.animation(minimumInterval: 1 / 20, paused: !isPlaying)) { context in
            let time = context.date.timeIntervalSinceReferenceDate
            HStack(alignment: .bottom, spacing: max(1, height / 8)) {
                ForEach(0..<barCount, id: \.self) { index in
                    Capsule()
                        .fill(color)
                        .frame(width: max(2, height / 5), height: barHeight(index: index, time: time))
                }
            }
            .frame(height: height, alignment: .bottom)
        }
        .animation(.easeOut(duration: 0.25), value: isPlaying)
    }

    private func barHeight(index: Int, time: TimeInterval) -> CGFloat {
        guard isPlaying else { return height * 0.25 }
        // Two sine waves at different speeds per bar look less mechanical than one.
        let speed = 5.0 + Double(index) * 1.7
        let wave = (sin(time * speed + Double(index)) + sin(time * speed * 0.53 + Double(index) * 2.1)) / 2
        return height * (0.3 + 0.7 * CGFloat((wave + 1) / 2))
    }
}
