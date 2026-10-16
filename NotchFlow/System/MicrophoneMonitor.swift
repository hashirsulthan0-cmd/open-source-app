import AppKit
import CoreAudio

/// Watches whether any app is recording from a microphone.
///
/// Everything here runs on one private serial queue, never the main thread: CoreAudio
/// queries are calls into the audio server and can be slow when the Mac is busy.
///
/// Only input devices are watched (usually one or two), not every app that uses audio.
/// Apps like Blender and browsers create and remove audio connections constantly, and
/// watching each of those flooded NotchFlow with updates. Bursts of changes are also
/// combined into a single check.
final class MicrophoneMonitor: @unchecked Sendable {
    /// Combine changes that arrive within this window into one check.
    private static let coalescingDelay: TimeInterval = 0.3
    /// While recording, recheck at this interval so the list of recording apps stays current.
    private static let activeRecheckInterval: TimeInterval = 3

    private let queue = DispatchQueue(label: "io.github.hashirsulthan0.NotchFlow.microphone", qos: .utility)

    // Only touched on `queue`.
    private var onChange: (@Sendable (MicrophoneStatus) -> Void)?
    private var deviceListeners: [AudioObjectID: AudioObjectPropertyListenerBlock] = [:]
    private var deviceListListener: AudioObjectPropertyListenerBlock?
    private var isCheckScheduled = false
    private var lastStatus: MicrophoneStatus?
    private var isRunning = false

    /// `onChange` is called on the main thread, only when the status changes.
    func start(onChange: @escaping @Sendable (MicrophoneStatus) -> Void) {
        queue.async {
            guard !self.isRunning else { return }
            self.isRunning = true
            self.onChange = onChange
            self.installDeviceListListener()
            self.syncDeviceListeners()
            self.scheduleCheck(after: 0)
        }
    }

    func stop() {
        queue.async {
            self.isRunning = false
            self.onChange = nil
            for (device, block) in self.deviceListeners {
                var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
                AudioObjectRemovePropertyListenerBlock(device, &address, self.queue, block)
            }
            self.deviceListeners.removeAll()
            if let block = self.deviceListListener {
                var address = Self.address(kAudioHardwarePropertyDevices)
                AudioObjectRemovePropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, self.queue, block)
            }
            self.deviceListListener = nil
        }
    }

    // MARK: - Listeners (on `queue`)

    private func installDeviceListListener() {
        var address = Self.address(kAudioHardwarePropertyDevices)
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
            // Runs on `queue`: a microphone was plugged in or removed.
            self?.syncDeviceListeners()
            self?.scheduleCheck(after: Self.coalescingDelay)
        }
        if AudioObjectAddPropertyListenerBlock(AudioObjectID(kAudioObjectSystemObject), &address, queue, block) == noErr {
            deviceListListener = block
        }
    }

    /// Adds listeners for new input devices and removes them for devices that are gone,
    /// leaving existing ones untouched.
    private func syncDeviceListeners() {
        let current = Set(Self.inputDevices())

        for (device, block) in deviceListeners where !current.contains(device) {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectRemovePropertyListenerBlock(device, &address, queue, block)
            deviceListeners[device] = nil
        }

        for device in current where deviceListeners[device] == nil {
            var address = Self.address(kAudioDevicePropertyDeviceIsRunningSomewhere)
            let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in
                self?.scheduleCheck(after: Self.coalescingDelay)
            }
            if AudioObjectAddPropertyListenerBlock(device, &address, queue, block) == noErr {
                deviceListeners[device] = block
            }
        }
    }

    // MARK: - Checking (on `queue`)

    private func scheduleCheck(after delay: TimeInterval) {
        guard isRunning, !isCheckScheduled else { return }
        isCheckScheduled = true
        queue.asyncAfter(deadline: .now() + delay) { [weak self] in
            guard let self else { return }
            self.isCheckScheduled = false
            self.check()
        }
    }

    private func check() {
        guard isRunning else { return }
        let status = Self.currentStatus()

        if status != lastStatus {
            lastStatus = status
            if let onChange {
                DispatchQueue.main.async { onChange(status) }
            }
        }
        // Device-level changes don't say when a second app starts recording, so while the
        // mic is in use, look again every few seconds to keep the app names right.
        if status.isActive {
            scheduleCheck(after: Self.activeRecheckInterval)
        }
    }

    private static func currentStatus() -> MicrophoneStatus {
        // Cheap first check: if no microphone is running at all, nothing is recording.
        let anyDeviceRunning = inputDevices().contains {
            uint32Property(kAudioDevicePropertyDeviceIsRunningSomewhere, of: $0) == 1
        }
        guard anyDeviceRunning else { return MicrophoneStatus() }

        // A headset that's playing music also counts as "running", so ask which apps are
        // actually recording (macOS 14.2+). Older systems fall back to the device answer.
        let processes = objectList(kAudioHardwarePropertyProcessObjectList)
        guard !processes.isEmpty else { return MicrophoneStatus(isActive: true) }

        let ownPID = ProcessInfo.processInfo.processIdentifier
        let recordingPIDs = processes
            .filter { uint32Property(kAudioProcessPropertyIsRunningInput, of: $0) == 1 }
            .compactMap(pid(of:))
            .filter { $0 != ownPID }
        guard !recordingPIDs.isEmpty else { return MicrophoneStatus() }

        // macOS services such as corespeechd ("Hey Siri") always report recording input, so
        // leave them out of the names. If only system services are recording while the mic
        // is running, it's macOS itself (like Dictation), which still counts as in use.
        let appPIDs = recordingPIDs.filter { !isSystemProcess($0) }
        let names = appPIDs.compactMap { NSRunningApplication(processIdentifier: $0)?.localizedName }
        return MicrophoneStatus(isActive: true, appNames: Array(Set(names)).sorted())
    }

    private static func isSystemProcess(_ pid: pid_t) -> Bool {
        var buffer = [CChar](repeating: 0, count: Int(MAXPATHLEN) * 4)
        guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else { return false }
        let path = String(cString: buffer)
        return path.hasPrefix("/System/") || path.hasPrefix("/usr/")
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
