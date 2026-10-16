import AppKit
import CoreAudio
import IOKit.ps

struct BatteryStatus: Equatable {
    var hasBattery = false
    var percentage = 0
    var isCharging = false
    var isPluggedIn = false
    /// Minutes until full while charging, or until empty on battery. Nil while macOS is still estimating.
    var minutesRemaining: Int?
}

struct MicrophoneStatus: Equatable {
    var isActive = false
    /// Names of the apps recording, when macOS can tell us (macOS 14.2 and later).
    var appNames: [String] = []
}

/// Live battery and microphone state. Battery is event-driven; the microphone is
/// watched by `MicrophoneMonitor` on its own background queue.
@MainActor
final class SystemHUDManager: ObservableObject {
    @Published private(set) var battery = BatteryStatus()
    @Published private(set) var microphone = MicrophoneStatus()

    private var powerSource: CFRunLoopSource?
    private let microphoneMonitor = MicrophoneMonitor()

    func start() {
        refreshBattery()
        startBatteryNotifications()
        microphoneMonitor.start { [weak self] status in
            MainActor.assumeIsolated {
                guard let self, status != self.microphone else { return }
                self.microphone = status
            }
        }
    }

    func stop() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil
        microphoneMonitor.stop()
    }

    // MARK: - Battery (IOKit power sources)

    private func startBatteryNotifications() {
        let context = Unmanaged.passUnretained(self).toOpaque()
        let source = IOPSNotificationCreateRunLoopSource({ context in
            guard let context else { return }
            let manager = Unmanaged<SystemHUDManager>.fromOpaque(context).takeUnretainedValue()
            MainActor.assumeIsolated {
                manager.refreshBattery()
            }
        }, context)?.takeRetainedValue()

        if let source {
            CFRunLoopAddSource(CFRunLoopGetMain(), source, .defaultMode)
            powerSource = source
        }
    }

    func refreshBattery() {
        let status = Self.readBattery()
        if status != battery {
            battery = status
        }
    }

    private static func readBattery() -> BatteryStatus {
        guard let info = IOPSCopyPowerSourcesInfo()?.takeRetainedValue(),
              let sources = IOPSCopyPowerSourcesList(info)?.takeRetainedValue() as? [CFTypeRef]
        else { return BatteryStatus() }

        for source in sources {
            guard let description = IOPSGetPowerSourceDescription(info, source)?.takeUnretainedValue() as? [String: Any],
                  description[kIOPSTypeKey] as? String == kIOPSInternalBatteryType
            else { continue }

            let current = description[kIOPSCurrentCapacityKey] as? Int ?? 0
            let maximum = max(description[kIOPSMaxCapacityKey] as? Int ?? 100, 1)
            let isCharging = description[kIOPSIsChargingKey] as? Bool ?? false
            let isPluggedIn = description[kIOPSPowerSourceStateKey] as? String == kIOPSACPowerValue
            let minutesKey = isCharging ? kIOPSTimeToFullChargeKey : kIOPSTimeToEmptyKey
            let minutes = description[minutesKey] as? Int

            return BatteryStatus(
                hasBattery: true,
                percentage: Int((Double(current) / Double(maximum) * 100).rounded()),
                isCharging: isCharging,
                isPluggedIn: isPluggedIn,
                minutesRemaining: (minutes ?? -1) > 0 ? minutes : nil
            )
        }
        return BatteryStatus()
    }
}
