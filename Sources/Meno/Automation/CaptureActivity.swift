import CoreAudio
import CoreMediaIO
import Foundation

/// Tells whether any app is using a microphone or a camera.
///
/// Meno records nothing itself: CoreAudio and CoreMediaIO report which
/// devices and processes are running, which needs no permission. Watching
/// starts only while a rule asks for it, and stopping removes every
/// listener again. Change notifications are not delivered reliably on every
/// macOS version, so the state is also polled.
final class CaptureActivity: @unchecked Sendable {
    struct State: Equatable, Sendable {
        var microphone = false
        var camera = false
        /// Apps recording from a microphone, when macOS reports them.
        var microphoneUsers: [String] = []
    }

    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).capture")
    /// Where CoreAudio and CoreMediaIO call the listeners. Removing a
    /// listener waits for its calls to finish, so they are not called on
    /// `queue`, where listeners are removed.
    private let listenerQueue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).capture.listeners")
    private let onChange: @Sendable (State) -> Void

    /// A property of a CoreAudio or CoreMediaIO object that Meno listens to.
    private struct Listened: Hashable {
        let object: UInt32
        let selector: UInt32
    }

    // Only used on `queue`.
    private var watchesMicrophones = false
    private var watchesCameras = false
    /// The listeners Meno added, kept so that they can be removed again:
    /// removing one takes the same block.
    private var audioListeners: [Listened: AudioObjectPropertyListenerBlock] = [:]
    private var cameraListeners: [Listened: CMIOObjectPropertyListenerBlock] = [:]
    private var timer: DispatchSourceTimer?
    private var state = State()

    /// `onChange` runs on the main queue.
    init(onChange: @escaping @Sendable (State) -> Void) {
        self.onChange = onChange
    }

    /// Starts or stops watching microphones and cameras.
    func watch(microphones: Bool, cameras: Bool) {
        queue.async { [self] in
            watchesMicrophones = microphones
            watchesCameras = cameras
            if microphones || cameras {
                startPolling()
            } else {
                timer?.cancel()
                timer = nil
            }
            check()
        }
    }

    /// How many listeners Meno has added to CoreAudio and CoreMediaIO, for
    /// the diagnostic report.
    var listenerCount: Int {
        queue.sync { audioListeners.count + cameraListeners.count }
    }

    // MARK: - Checking

    private func check() {
        updateListeners()
        var new = State()
        if watchesMicrophones {
            let users = Microphones.recordingProcesses()
            new.microphoneUsers = users?.sorted() ?? []
            new.microphone = users.map { !$0.isEmpty } ?? false
            if !new.microphone {
                // A device that also plays sound (a headset) runs for music as
                // well, so only devices that just record count here.
                new.microphone = Microphones.devices().contains { !$0.hasOutput && Microphones.isRunning($0.id) }
            }
        }
        if watchesCameras {
            new.camera = Cameras.devices().contains(where: Cameras.isRunning)
        }
        guard new != state else { return }
        state = new
        DispatchQueue.main.async { [onChange] in onChange(new) }
    }

    private func startPolling() {
        guard timer == nil else { return }
        let timer = DispatchSource.makeTimerSource(queue: queue)
        timer.schedule(deadline: .now() + 5, repeating: 5, leeway: .seconds(1))
        timer.setEventHandler { [weak self] in self?.check() }
        timer.resume()
        self.timer = timer
    }

    // MARK: - Listeners

    /// Listens to the lists of devices and processes and to each one that
    /// can record, as far as they are watched, and removes the listeners of
    /// objects that are gone or no longer watched.
    private func updateListeners() {
        var audio: Set<Listened> = []
        if watchesMicrophones {
            let system = AudioObjectID(kAudioObjectSystemObject)
            audio.insert(Listened(object: system, selector: kAudioHardwarePropertyDevices))
            for device in Microphones.devices() {
                audio.insert(Listened(object: device.id, selector: kAudioDevicePropertyDeviceIsRunningSomewhere))
            }
            if #available(macOS 14.2, *) {
                audio.insert(Listened(object: system, selector: kAudioHardwarePropertyProcessObjectList))
                for process in Microphones.processObjects() {
                    audio.insert(Listened(object: process, selector: kAudioProcessPropertyIsRunningInput))
                }
            }
        }
        var cameras: Set<Listened> = []
        if watchesCameras {
            cameras.insert(Listened(object: CMIOObjectID(kCMIOObjectSystemObject), selector: CMIOObjectPropertySelector(kCMIOHardwarePropertyDevices)))
            for camera in Cameras.devices() {
                cameras.insert(Listened(object: camera, selector: CMIOObjectPropertySelector(kCMIODevicePropertyDeviceIsRunningSomewhere)))
            }
        }
        for listened in Array(audioListeners.keys) where !audio.contains(listened) {
            removeAudioListener(listened)
        }
        for listened in audio where audioListeners[listened] == nil {
            addAudioListener(listened)
        }
        for listened in Array(cameraListeners.keys) where !cameras.contains(listened) {
            removeCameraListener(listened)
        }
        for listened in cameras where cameraListeners[listened] == nil {
            addCameraListener(listened)
        }
    }

    /// Checks again on `queue` when a listener is called.
    private func scheduleCheck() {
        queue.async { [weak self] in self?.check() }
    }

    private func addAudioListener(_ listened: Listened) {
        let block: AudioObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleCheck() }
        var address = Microphones.property(listened.selector)
        guard AudioObjectAddPropertyListenerBlock(listened.object, &address, listenerQueue, block) == noErr else { return }
        audioListeners[listened] = block
    }

    /// Removes a listener; for an object that is gone, macOS has dropped it
    /// already and only Meno's copy goes.
    private func removeAudioListener(_ listened: Listened) {
        guard let block = audioListeners.removeValue(forKey: listened) else { return }
        var address = Microphones.property(listened.selector)
        _ = AudioObjectRemovePropertyListenerBlock(listened.object, &address, listenerQueue, block)
    }

    private func addCameraListener(_ listened: Listened) {
        let block: CMIOObjectPropertyListenerBlock = { [weak self] _, _ in self?.scheduleCheck() }
        var address = Cameras.property(listened.selector)
        guard CMIOObjectAddPropertyListenerBlock(listened.object, &address, listenerQueue, block) == noErr else { return }
        cameraListeners[listened] = block
    }

    private func removeCameraListener(_ listened: Listened) {
        guard let block = cameraListeners.removeValue(forKey: listened) else { return }
        var address = Cameras.property(listened.selector)
        _ = CMIOObjectRemovePropertyListenerBlock(listened.object, &address, listenerQueue, block)
    }
}

// MARK: - CoreAudio

private enum Microphones {
    struct Device {
        let id: AudioObjectID
        let hasOutput: Bool
    }

    static func property(_ selector: AudioObjectPropertySelector, scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: kAudioObjectPropertyElementMain)
    }

    /// Devices that can record.
    static func devices() -> [Device] {
        objects(of: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyDevices).compactMap { id in
            guard hasStreams(id, scope: kAudioObjectPropertyScopeInput) else { return nil }
            return Device(id: id, hasOutput: hasStreams(id, scope: kAudioObjectPropertyScopeOutput))
        }
    }

    /// Whether any process uses the device, for input or output.
    static func isRunning(_ device: AudioObjectID) -> Bool {
        var address = property(kAudioDevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        return AudioObjectGetPropertyData(device, &address, 0, nil, &size, &running) == noErr && running != 0
    }

    @available(macOS 14.2, *)
    static func processObjects() -> [AudioObjectID] {
        objects(of: AudioObjectID(kAudioObjectSystemObject), selector: kAudioHardwarePropertyProcessObjectList)
    }

    /// The apps that record right now, or `nil` when macOS cannot tell
    /// (before macOS 14.2).
    static func recordingProcesses() -> [String]? {
        guard #available(macOS 14.2, *) else { return nil }
        let processes = processObjects()
        guard !processes.isEmpty else { return nil }
        return processes.compactMap { process in
            var address = property(kAudioProcessPropertyIsRunningInput)
            var running: UInt32 = 0
            var size = UInt32(MemoryLayout<UInt32>.size)
            guard AudioObjectGetPropertyData(process, &address, 0, nil, &size, &running) == noErr, running != 0 else { return nil }
            return name(ofProcess: process)
        }
    }

    @available(macOS 14.2, *)
    private static func name(ofProcess process: AudioObjectID) -> String {
        var address = property(kAudioProcessPropertyBundleID)
        var bundleID: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        if AudioObjectGetPropertyData(process, &address, 0, nil, &size, &bundleID) == noErr,
           let value = bundleID?.takeRetainedValue() {
            let text = value as String
            if !text.isEmpty { return text }
        }
        address = property(kAudioProcessPropertyPID)
        var pid: pid_t = 0
        size = UInt32(MemoryLayout<pid_t>.size)
        _ = AudioObjectGetPropertyData(process, &address, 0, nil, &size, &pid)
        return "PID \(pid)"
    }

    private static func hasStreams(_ device: AudioObjectID, scope: AudioObjectPropertyScope) -> Bool {
        var address = property(kAudioDevicePropertyStreams, scope: scope)
        var size: UInt32 = 0
        return AudioObjectGetPropertyDataSize(device, &address, 0, nil, &size) == noErr && size > 0
    }

    private static func objects(of object: AudioObjectID, selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var address = property(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(object, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        guard AudioObjectGetPropertyData(object, &address, 0, nil, &size, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(size) / MemoryLayout<AudioObjectID>.size))
    }
}

// MARK: - CoreMediaIO

private enum Cameras {
    static func property<Selector: BinaryInteger>(_ selector: Selector) -> CMIOObjectPropertyAddress {
        CMIOObjectPropertyAddress(
            mSelector: CMIOObjectPropertySelector(selector),
            mScope: CMIOObjectPropertyScope(kCMIOObjectPropertyScopeGlobal),
            mElement: CMIOObjectPropertyElement(kCMIOObjectPropertyElementMain)
        )
    }

    static func devices() -> [CMIOObjectID] {
        var address = property(kCMIOHardwarePropertyDevices)
        let system = CMIOObjectID(kCMIOObjectSystemObject)
        var size: UInt32 = 0
        guard CMIOObjectGetPropertyDataSize(system, &address, 0, nil, &size) == noErr, size > 0 else { return [] }
        var ids = [CMIOObjectID](repeating: 0, count: Int(size) / MemoryLayout<CMIOObjectID>.size)
        var used: UInt32 = 0
        guard CMIOObjectGetPropertyData(system, &address, 0, nil, size, &used, &ids) == noErr else { return [] }
        return Array(ids.prefix(Int(used) / MemoryLayout<CMIOObjectID>.size))
    }

    static func isRunning(_ camera: CMIOObjectID) -> Bool {
        var address = property(kCMIODevicePropertyDeviceIsRunningSomewhere)
        var running: UInt32 = 0
        var used: UInt32 = 0
        let status = CMIOObjectGetPropertyData(camera, &address, 0, nil, UInt32(MemoryLayout<UInt32>.size), &used, &running)
        return status == noErr && running != 0
    }
}
