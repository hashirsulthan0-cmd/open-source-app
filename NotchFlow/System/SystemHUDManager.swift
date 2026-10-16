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

/// Live battery and microphone state. Both are event-driven: macOS calls back when
/// they change, so nothing is polled.
@MainActor
final class SystemHUDManager: ObservableObject {
    @Published private(set) var battery = BatteryStatus()
    @Published private(set) var microphone = MicrophoneStatus()

    private var powerSource: CFRunLoopSource?
    private var audioListeners: [(AudioObjectID, AudioObjectPropertyAddress, AudioObjectPropertyListenerBlock)] = []

    func start() {
        refreshBattery()
        startBatteryNotifications()
        rebuildAudioListeners()
    }

    func stop() {
        if let powerSource {
            CFRunLoopRemoveSource(CFRunLoopGetMain(), powerSource, .defaultMode)
        }
        powerSource = nil
        removeAudioListeners()
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

    // MARK: - Microphone (CoreAudio)

    /// Listens for "is this device recording?" on every input device, and for devices
    /// and recording apps coming and going.
    private func rebuildAudioListeners() {
        removeAudioListeners()

        let system = AudioObjectID(kAudioObjectSystemObject)
        addAudioListener(object: system, selector: kAudioHardwarePropertyDevices, rebuild: true)
        addAudioListener(object: system, selector: kAudioHardwarePropertyProcessObjectList, rebuild: false)

        for device in Self.inputDevices() {
            addAudioListener(object: device, selector: kAudioDevicePropertyDeviceIsRunningSomewhere, rebuild: false)
        }
        for process in Self.audioProcesses() {
            addAudioListener(object: process, selector: kAudioProcessPropertyIsRunningInput, rebuild: false)
        }

        refreshMicrophone()
    }

    private func addAudioListener(object: AudioObjectID, selector: AudioObjectPropertySelector, rebuild: Bool) {
        var address = Self.address(selector)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            MainActor.assumeIsolated {
                guard let self else { return }
                if rebuild || selector == kAudioHardwarePropertyProcessObjectList {
                    self.rebuildAudioListeners()
                } else {
                    self.refreshMicrophone()
                }
            }
        }
        if AudioObjectAddPropertyListenerBlock(object, &address, DispatchQueue.main, block) == noErr {
            audioListeners.append((object, address, block))
        }
    }

    private func removeAudioListeners() {
        for (object, address, block) in audioListeners {
            var address = address
            AudioObjectRemovePropertyListenerBlock(object, &address, DispatchQueue.main, block)
        }
        audioListeners.removeAll()
    }

    private func refreshMicrophone() {
        let status: MicrophoneStatus
        let processes = Self.audioProcesses()

        if !processes.isEmpty {
            // macOS 14.2+: ask each app whether it is recording, which also tells us who.
            let ownPID = ProcessInfo.processInfo.processIdentifier
            let recordingPIDs = processes
                .filter { Self.uint32Property(kAudioProcessPropertyIsRunningInput, of: $0) == 1 }
                .compactMap(Self.pid(of:))
                .filter { $0 != ownPID }
            let names = recordingPIDs.compactMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
            status = MicrophoneStatus(isActive: !recordingPIDs.isEmpty, appNames: Array(Set(names)).sorted())
        } else {
            // Older systems: a device is "running somewhere" when any app is using it.
            let isActive = Self.inputDevices().contains {
                Self.uint32Property(kAudioDevicePropertyDeviceIsRunningSomewhere, of: $0) == 1
            }
            status = MicrophoneStatus(isActive: isActive)
        }

        if status != microphone {
            microphone = status
        }
    }

    // MARK: - CoreAudio helpers

    private static func address(
        _ selector: AudioObjectPropertySelector,
        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal
    ) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    private static func objectList(_ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        let system = AudioObjectID(kAudioObjectSystemObject)
        var address = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var objects = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(system, &address, 0, nil, &size, &objects) == noErr else { return [] }
        return objects
    }

    private static func inputDevices() -> [AudioObjectID] {
        objectList(kAudioHardwarePropertyDevices).filter { device in
            var address = address(kAudioDevicePropertyStreams, scope: kAudioDevicePropertyScopeInput)
            var size: UInt32 = 0
            return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
        }
    }

    private static func audioProcesses() -> [AudioObjectID] {
        objectList(kAudioHardwarePropertyProcessObjectList)
    }

    private static func uint32Property(_ selector: AudioObjectPropertySelector, of object: AudioObjectID) -> UInt32? {
        var address = address(selector)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    private static func pid(of process: AudioObjectID) -> pid_t? {
        var address = address(kAudioProcessPropertyPID)
        var value: pid_t = 0
        var size = UInt32(MemoryLayout<pid_t>.size)
        guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }
}
