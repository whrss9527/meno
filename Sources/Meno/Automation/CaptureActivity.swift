import CoreAudio
import CoreMediaIO
import Foundation

/// Tells whether any app is using a microphone or a camera.
///
/// Meno records nothing itself: CoreAudio and CoreMediaIO report which
/// devices and processes are running, which needs no permission. Watching
/// starts only while a rule asks for it. Change notifications are not
/// delivered reliably on every macOS version, so the state is also polled.
final class CaptureActivity: @unchecked Sendable {
    struct State: Equatable, Sendable {
        var microphone = false
        var camera = false
        /// Apps recording from a microphone, when macOS reports them.
        var microphoneUsers: [String] = []
    }

    private let queue = DispatchQueue(label: "\(AppInfo.bundleIdentifier).capture")
    private let onChange: @Sendable (State) -> Void

    // Only used on `queue`.
    private var watchesMicrophones = false
    private var watchesCameras = false
    private var installedMicrophoneListeners = false
    private var installedCameraListeners = false
    private var observedAudioObjects: Set<AudioObjectID> = []
    private var observedCameras: Set<CMIOObjectID> = []
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
            if microphones { installMicrophoneListeners() }
            if cameras { installCameraListeners() }
            if microphones || cameras {
                startPolling()
            } else {
                timer?.cancel()
                timer = nil
            }
            check()
        }
    }

    // MARK: - Checking

    private func check() {
        var new = State()
        if watchesMicrophones {
            observeNewAudioObjects()
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
            observeNewCameras()
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

    private func installMicrophoneListeners() {
        guard !installedMicrophoneListeners else { return }
        installedMicrophoneListeners = true
        let system = AudioObjectID(kAudioObjectSystemObject)
        var selectors = [kAudioHardwarePropertyDevices]
        if #available(macOS 14.2, *) {
            selectors.append(kAudioHardwarePropertyProcessObjectList)
        }
        for selector in selectors {
            var address = Microphones.property(selector)
            AudioObjectAddPropertyListenerBlock(system, &address, queue) { [weak self] _, _ in self?.check() }
        }
    }

    /// Listens to devices and processes that appeared since the last check.
    private func observeNewAudioObjects() {
        for device in Microphones.devices() where !observedAudioObjects.contains(device.id) {
            observedAudioObjects.insert(device.id)
            var address = Microphones.property(kAudioDevicePropertyDeviceIsRunningSomewhere)
            AudioObjectAddPropertyListenerBlock(device.id, &address, queue) { [weak self] _, _ in self?.check() }
        }
        guard #available(macOS 14.2, *) else { return }
        for process in Microphones.processObjects() where !observedAudioObjects.contains(process) {
            observedAudioObjects.insert(process)
            var address = Microphones.property(kAudioProcessPropertyIsRunningInput)
            AudioObjectAddPropertyListenerBlock(process, &address, queue) { [weak self] _, _ in self?.check() }
        }
    }

    private func installCameraListeners() {
        guard !installedCameraListeners else { return }
        installedCameraListeners = true
        var address = Cameras.property(kCMIOHardwarePropertyDevices)
        CMIOObjectAddPropertyListenerBlock(CMIOObjectID(kCMIOObjectSystemObject), &address, queue) { [weak self] _, _ in
            self?.check()
        }
    }

    private func observeNewCameras() {
        for camera in Cameras.devices() where !observedCameras.contains(camera) {
            observedCameras.insert(camera)
            var address = Cameras.property(kCMIODevicePropertyDeviceIsRunningSomewhere)
            CMIOObjectAddPropertyListenerBlock(camera, &address, queue) { [weak self] _, _ in self?.check() }
        }
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
