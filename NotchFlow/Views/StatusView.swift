import SwiftUI

/// Status tab: battery and microphone at a glance.
struct StatusView: View {
    @ObservedObject var hud: SystemHUDManager
    @ObservedObject var nowPlaying: NowPlayingManager

    var body: some View {
        HStack(spacing: 8) {
            NowPlayingCard(nowPlaying: nowPlaying)
                .frame(width: 250)
            if hud.battery.hasBattery {
                BatteryCard(battery: hud.battery)
            }
            MicrophoneCard(microphone: hud.microphone)
        }
    }
}

struct StatusCard<Content: View>: View {
    @ViewBuilder var content: () -> Content

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            content()
        }
        .padding(12)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .glossySurface(cornerRadius: 18)
    }
}

private struct BatteryCard: View {
    let battery: BatteryStatus

    var body: some View {
        StatusCard {
            Label("Battery", systemImage: battery.isCharging ? "battery.100.bolt" : batterySymbol)
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            Text("\(battery.percentage)%")
                .font(.system(size: 30, weight: .semibold, design: .rounded).monospacedDigit())
                .foregroundStyle(tint)

            BatteryBar(fraction: Double(battery.percentage) / 100, tint: tint)

            Spacer(minLength: 0)

            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
    }

    private var tint: Color {
        if battery.isCharging || battery.isPluggedIn { return .green }
        if battery.percentage <= 10 { return .red }
        if battery.percentage <= 20 { return .orange }
        return .white
    }

    private var batterySymbol: String {
        switch battery.percentage {
        case ..<13: "battery.0"
        case ..<38: "battery.25"
        case ..<63: "battery.50"
        case ..<88: "battery.75"
        default: "battery.100"
        }
    }

    private var detail: String {
        let time = battery.minutesRemaining.map { minutes in
            minutes >= 60 ? "\(minutes / 60) h \(minutes % 60) min" : "\(minutes) min"
        }
        if battery.isCharging {
            return time.map { "Charging · full in \($0)" } ?? "Charging"
        }
        if battery.isPluggedIn {
            return "Plugged in, not charging"
        }
        return time.map { "\($0) remaining" } ?? "On battery"
    }
}

private struct BatteryBar: View {
    let fraction: Double
    let tint: Color

    var body: some View {
        GeometryReader { proxy in
            ZStack(alignment: .leading) {
                Capsule().fill(Color.white.opacity(0.12))
                Capsule()
                    .fill(tint)
                    .frame(width: max(4, proxy.size.width * min(max(fraction, 0), 1)))
            }
        }
        .frame(height: 5)
        .animation(.easeOut(duration: 0.3), value: fraction)
    }
}

private struct MicrophoneCard: View {
    let microphone: MicrophoneStatus

    var body: some View {
        StatusCard {
            Label("Microphone", systemImage: microphone.isActive ? "mic.fill" : "mic.slash")
                .font(.system(size: 11, weight: .semibold))
                .foregroundStyle(.white.opacity(0.6))

            HStack(spacing: 8) {
                Circle()
                    .fill(microphone.isActive ? Color.orange : Color.white.opacity(0.25))
                    .frame(width: 10, height: 10)
                    .shadow(color: microphone.isActive ? .orange : .clear, radius: 5)
                Text(microphone.isActive ? "In use" : "Not in use")
                    .font(.system(size: 18, weight: .semibold, design: .rounded))
                    .foregroundStyle(microphone.isActive ? Color.orange : Color.white)
            }
            .animation(.easeOut(duration: 0.2), value: microphone.isActive)

            Spacer(minLength: 0)

            Text(detail)
                .font(.system(size: 10.5))
                .foregroundStyle(.white.opacity(0.55))
                .lineLimit(2)
        }
    }

    private var detail: String {
        guard microphone.isActive else { return "No app is recording." }
        guard !microphone.appNames.isEmpty else { return "An app is recording." }
        return microphone.appNames.joined(separator: ", ")
    }
}

/// Icons shown on each side of the closed notch.
struct ClosedNotchIndicators: View {
    @ObservedObject var viewModel: NotchViewModel

    var body: some View {
        HStack(spacing: 0) {
            leading
                .frame(width: NotchMetrics.indicatorWidth)
            Spacer(minLength: 0)
            trailing
                .frame(width: NotchMetrics.indicatorWidth)
        }
        .padding(.horizontal, NotchMetrics.closedTopRadius)
        .font(.system(size: 11, weight: .semibold))
        .transition(.opacity)
    }

    @ViewBuilder
    private var leading: some View {
        if viewModel.chargingIndicatorPercentage != nil {
            Image(systemName: "bolt.fill")
                .foregroundStyle(.green)
        } else if viewModel.showsMicrophoneIndicator {
            Image(systemName: "waveform")
                .foregroundStyle(.orange)
                .symbolEffect(.variableColor.iterative, options: .repeating)
        } else if let nowPlaying = viewModel.nowPlayingIndicator {
            ArtworkView(image: nowPlaying.artwork, size: 18)
        }
    }

    @ViewBuilder
    private var trailing: some View {
        if viewModel.showsMicrophoneIndicator {
            Image(systemName: "mic.fill")
                .foregroundStyle(.orange)
        } else if let percentage = viewModel.chargingIndicatorPercentage {
            Text("\(percentage)%")
                .font(.system(size: 10.5, weight: .semibold).monospacedDigit())
                .foregroundStyle(.green)
        } else if let nowPlaying = viewModel.nowPlayingIndicator {
            EqualizerView(isPlaying: nowPlaying.isPlaying, barCount: 4, height: 12, color: .white.opacity(0.85))
        }
    }
}
