import AppKit
import CoreAudio
import DialCore

struct OutputDevice: Identifiable, Equatable {
    let id: AudioDeviceID
    let name: String
}

struct VolumeControl {
    let device: AudioDeviceID
    let element: AudioObjectPropertyElement
    let value: Double
    let rawValue: Double
    var key: String { "\(device):\(element)" }
}

enum AudioHardware {
    static func address(_ selector: AudioObjectPropertySelector,
                        scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                        element: AudioObjectPropertyElement = kAudioObjectPropertyElementMain) -> AudioObjectPropertyAddress {
        AudioObjectPropertyAddress(mSelector: selector, mScope: scope, mElement: element)
    }

    static func uint(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector,
                     scope: AudioObjectPropertyScope = kAudioObjectPropertyScopeGlobal,
                     element: AudioObjectPropertyElement = 0) -> UInt32? {
        var addr = address(selector, scope: scope, element: element)
        var value: UInt32 = 0
        var size = UInt32(MemoryLayout<UInt32>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
        return value
    }

    static func ids(_ device: AudioObjectID, _ selector: AudioObjectPropertySelector) -> [AudioObjectID] {
        var addr = address(selector)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return [] }
        var result = [AudioObjectID](repeating: 0, count: Int(size) / MemoryLayout<AudioObjectID>.size)
        let status = result.withUnsafeMutableBytes { buffer in
            AudioObjectGetPropertyData(device, &addr, 0, nil, &size, buffer.baseAddress!)
        }
        return status == noErr ? result : []
    }

    static func name(_ device: AudioObjectID) -> String {
        var addr = address(kAudioObjectPropertyName)
        var value: Unmanaged<CFString>?
        var size = UInt32(MemoryLayout<Unmanaged<CFString>?>.size)
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return "Unknown output" }
        return value?.takeRetainedValue() as String? ?? "Unknown output"
    }

    static func channelCount(_ device: AudioDeviceID) -> Int {
        var addr = address(kAudioDevicePropertyStreamConfiguration, scope: kAudioDevicePropertyScopeOutput)
        var size: UInt32 = 0
        guard AudioObjectGetPropertyDataSize(device, &addr, 0, nil, &size) == noErr, size > 0 else { return 0 }
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: Int(size), alignment: MemoryLayout<AudioBufferList>.alignment)
        defer { buffer.deallocate() }
        guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, buffer) == noErr else { return 0 }
        return UnsafeMutableAudioBufferListPointer(buffer.assumingMemoryBound(to: AudioBufferList.self)).reduce(0) { $0 + Int($1.mNumberChannels) }
    }

    static func writable(_ device: AudioDeviceID, _ selector: AudioObjectPropertySelector, element: UInt32) -> Bool {
        var addr = address(selector, scope: kAudioDevicePropertyScopeOutput, element: element)
        var settable = DarwinBoolean(false)
        return AudioObjectHasProperty(device, &addr) &&
            AudioObjectIsPropertySettable(device, &addr, &settable) == noErr && settable.boolValue
    }

    static func controls(_ device: AudioDeviceID) -> [VolumeControl] {
        func read(_ element: UInt32) -> VolumeControl? {
            guard writable(device, kAudioDevicePropertyVolumeScalar, element: element) else { return nil }
            var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: element)
            var value: Float32 = 0
            var size = UInt32(MemoryLayout<Float32>.size)
            guard AudioObjectGetPropertyData(device, &addr, 0, nil, &size, &value) == noErr else { return nil }
            let muted = uint(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: element) == 1 ||
                uint(device, kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput) == 1
            return VolumeControl(device: device, element: element, value: muted ? 0 : DialMath.clamp(Double(value)), rawValue: DialMath.clamp(Double(value)))
        }
        if let master = read(0) { return [master] }
        let count = channelCount(device)
        guard count > 0 else { return [] }
        return (1...count).compactMap { read(UInt32($0)) }
    }

    static func leaves(_ device: AudioDeviceID, visited: Set<AudioDeviceID> = []) -> [AudioDeviceID] {
        guard !visited.contains(device) else { return [] }
        let children = ids(device, kAudioAggregateDevicePropertyActiveSubDeviceList)
        if children.isEmpty { return channelCount(device) > 0 ? [device] : [] }
        var seen = visited.union([device])
        var result: [AudioDeviceID] = []
        for child in children {
            for leaf in leaves(child, visited: seen) where !seen.contains(leaf) {
                seen.insert(leaf)
                result.append(leaf)
            }
        }
        return result
    }

    static func write(_ control: VolumeControl, value: Double) -> Bool {
        var addr = address(kAudioDevicePropertyVolumeScalar, scope: kAudioDevicePropertyScopeOutput, element: control.element)
        var scalar = Float32(DialMath.clamp(value))
        guard AudioObjectSetPropertyData(control.device, &addr, 0, nil, UInt32(MemoryLayout<Float32>.size), &scalar) == noErr else { return false }
        var success = true
        if value > 0 {
            for element in Set([UInt32(0), control.element]) where writable(control.device, kAudioDevicePropertyMute, element: element) {
                var muteAddr = address(kAudioDevicePropertyMute, scope: kAudioDevicePropertyScopeOutput, element: element)
                var unmuted: UInt32 = 0
                success = AudioObjectSetPropertyData(control.device, &muteAddr, 0, nil, 4, &unmuted) == noErr && success
            }
        }
        return success
    }
}

@MainActor
final class AudioController: ObservableObject {
    @Published var outputName = "No audio output"
    @Published var outputID: AudioDeviceID = 0
    @Published var outputs: [OutputDevice] = []
    @Published var volume = 0.0
    @Published var hasControl = false
    @Published var unsupported: [String] = []
    @Published var memberNames: [String] = []
    @Published var error: String?
    @Published var isSwitching = false
    private var selectionGeneration = 0
    private var controls: [VolumeControl] = []
    private var mutedSnapshot: (AudioDeviceID, [VolumeControl])?
    private var monitors: [MonitorLevel] = []
    private var activeMonitors: [MonitorLevel] = []
    private var monitorBusy = false
    private var pendingMonitorWrites: [String: Double] = [:]
    private var monitorMuteSnapshot: [String: Double] = [:]
    private var lastMonitorRead = Date.distantPast
    private var lastDiscovery = Date.distantPast
    private var lastCommand = Date.distantPast
    private var timer: Timer?
    var onChange: (() -> Void)?

    init(monitors: [MonitorLevel] = []) {
        self.monitors = monitors
        if !monitors.isEmpty { lastDiscovery = Date() }
        refresh()
        timer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.refresh() }
        }
    }

    func refresh() {
        let id = AudioHardware.uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) ?? 0
        if id != outputID {
            mutedSnapshot = nil; monitorMuteSnapshot = [:]; pendingMonitorWrites = [:]; error = nil
            lastCommand = .distantPast
            outputID = id
        }
        let newName = id == 0 ? "No audio output" : AudioHardware.name(id)
        if outputName != newName { outputName = newName }
        let newOutputs = AudioHardware.ids(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDevices)
            .filter { device in
                DialMath.showOutput(hasChannels: AudioHardware.channelCount(device) > 0,
                                    isVirtual: AudioHardware.uint(device, kAudioDevicePropertyTransportType) == kAudioDeviceTransportTypeVirtual,
                                    isAggregate: AudioHardware.uint(device, kAudioObjectPropertyClass) == kAudioAggregateDeviceClassID,
                                    isHidden: AudioHardware.uint(device, kAudioDevicePropertyIsHidden) == 1)
            }.map { OutputDevice(id: $0, name: AudioHardware.name($0)) }
        if outputs != newOutputs { outputs = newOutputs }
        let leaves = AudioHardware.leaves(id)
        let names = leaves.map(AudioHardware.name)
        let newMembers = leaves.count > 1 ? names : []
        if memberNames != newMembers { memberNames = newMembers }
        controls = leaves.flatMap(AudioHardware.controls)
        let unsupportedCore = leaves.filter { AudioHardware.controls($0).isEmpty }.map(AudioHardware.name)
        let physicalOutputNames = newOutputs.filter {
            AudioHardware.uint($0.id, kAudioObjectPropertyClass) != kAudioAggregateDeviceClassID
        }.map(\.name)
        activeMonitors = MonitorVolume.matching(outputNames: unsupportedCore, allOutputNames: physicalOutputNames, monitors: monitors)
        let newUnsupported = unsupportedCore.filter {
            MonitorVolume.matching(outputNames: [$0], allOutputNames: physicalOutputNames, monitors: monitors).isEmpty
        }
        if unsupported != newUnsupported { unsupported = newUnsupported }
        let available = !controls.isEmpty || !activeMonitors.isEmpty
        if hasControl != available { hasControl = available }
        let levels = controls.map(\.value) + activeMonitors.map(\.value)
        if Date().timeIntervalSince(lastCommand) > 0.4 && pendingMonitorWrites.isEmpty && !monitorBusy {
            let actual = levels.isEmpty ? 0 : levels.reduce(0, +) / Double(levels.count)
            if abs(volume - actual) > 0.0001 {
                VolumeTrace.record("observation route=\(id) dial=\(actual) core=\(controls.map(\.value)) monitor=\(activeMonitors.map(\.value))")
                volume = actual
            }
        }
        serviceMonitors()
        onChange?()
    }

    private func serviceMonitors() {
        guard !monitorBusy, !isSwitching else { return }
        if !pendingMonitorWrites.isEmpty { drainMonitorWrites(); return }
        let discover = Date().timeIntervalSince(lastDiscovery) > 15
        guard discover || Date().timeIntervalSince(lastMonitorRead) > 2 else { return }
        monitorBusy = true
        lastMonitorRead = Date()
        if discover { lastDiscovery = Date() }
        let current = activeMonitors
        let existing = monitors
        Task {
            let result = await Task.detached(priority: .utility) {
                discover ? MonitorVolume.discover(existing: existing) : current.compactMap(MonitorVolume.read)
            }.value
            if discover { monitors = result }
            else {
                for level in result {
                    if let index = monitors.firstIndex(where: { $0.id == level.id }) { monitors[index] = level }
                }
            }
            monitorBusy = false
            refresh()
        }
    }

    private func drainMonitorWrites() {
        guard !monitorBusy, !pendingMonitorWrites.isEmpty else { return }
        let targets = pendingMonitorWrites
        pendingMonitorWrites = [:]
        let current = activeMonitors
        let route = outputID
        monitorBusy = true
        Task {
            let results = await Task.detached(priority: .userInitiated) { () -> [MonitorLevel] in
                current.compactMap { monitor in
                    guard AudioHardware.uint(AudioObjectID(kAudioObjectSystemObject), kAudioHardwarePropertyDefaultOutputDevice) == route,
                          let target = targets[monitor.id] else { return nil }
                    return MonitorVolume.write(monitor, fraction: target)
                }
            }.value
            for result in results {
                if let index = monitors.firstIndex(where: { $0.id == result.id }) { monitors[index] = result }
            }
            if results.count < targets.count && outputID == route { error = "The monitor did not confirm the volume change." }
            monitorBusy = false
            lastMonitorRead = Date()
            refresh()
        }
    }

    func setVolume(_ value: Double, for expectedOutput: AudioDeviceID? = nil) {
        let request = VolumeRequest(outputID: expectedOutput ?? outputID, value: value)
        refresh()
        guard hasControl, request.canApply(currentOutputID: outputID, isSwitching: isSwitching) else { return }
        VolumeTrace.record("volume request route=\(outputID) target=\(request.value)")
        lastCommand = Date()
        volume = DialMath.clamp(value)
        let values = DialMath.shiftedVolumes(controls.map(\.value), to: value)
        var failed = false
        for (control, target) in zip(controls, values) {
            if !AudioHardware.write(control, value: target) { failed = true }
        }
        error = failed ? "An output could not be adjusted. Try again after reconnecting it." : nil
        mutedSnapshot = nil
        monitorMuteSnapshot = [:]
        for monitor in activeMonitors { pendingMonitorWrites[monitor.id] = volume }
        drainMonitorWrites()
        refresh()
    }

    func toggleMute() {
        refresh()
        guard hasControl else { return }
        VolumeTrace.record("mute toggle route=\(outputID) current=\(volume)")
        if volume > 0.001 {
            let snapshot = (outputID, controls)
            let monitorSnapshot = Dictionary(uniqueKeysWithValues: activeMonitors.map { ($0.id, $0.value) })
            setVolume(0)
            mutedSnapshot = snapshot
            monitorMuteSnapshot = monitorSnapshot
        } else {
            let current = Dictionary(uniqueKeysWithValues: controls.map { ($0.key, $0.rawValue) })
            let saved = mutedSnapshot.flatMap { snapshot in
                snapshot.0 == outputID ? Dictionary(uniqueKeysWithValues: snapshot.1.map { ($0.key, $0.value) }) : nil
            } ?? [:]
            let restored = DialMath.restorationValues(current: current, saved: saved)
            var failed = false
            for control in controls {
                if let target = restored[control.key], !AudioHardware.write(control, value: target) { failed = true }
            }
            error = failed ? "Some outputs could not be restored." : nil
            for monitor in activeMonitors { pendingMonitorWrites[monitor.id] = monitorMuteSnapshot[monitor.id] ?? (monitor.value > 0 ? monitor.value : 0.25) }
            monitorMuteSnapshot = [:]
            lastCommand = .distantPast
            drainMonitorWrites()
            mutedSnapshot = nil
            refresh()
        }
    }

    func selectOutput(_ id: AudioDeviceID) {
        guard outputs.contains(where: { $0.id == id }) else { return }
        selectionGeneration += 1
        let generation = selectionGeneration
        isSwitching = true
        pendingMonitorWrites = [:]
        Task {
            // Complete in-flight monitor writes before changing their route.
            let deadline = Date().addingTimeInterval(5)
            while monitorBusy && Date() < deadline {
                try? await Task.sleep(nanoseconds: 20_000_000)
            }
            guard generation == selectionGeneration else { return }
            guard !monitorBusy else {
                isSwitching = false
                error = "The monitor is busy. Please try switching again."
                return
            }
            var addr = AudioHardware.address(kAudioHardwarePropertyDefaultOutputDevice)
            var selected = id
            let status = AudioObjectSetPropertyData(AudioObjectID(kAudioObjectSystemObject), &addr, 0, nil, 4, &selected)
            try? await Task.sleep(nanoseconds: 350_000_000)
            guard generation == selectionGeneration else { return }
            isSwitching = false
            refresh()
            error = status == noErr && outputID == id ? nil : "The system did not switch to the selected output."
        }
    }

    func diagnostic() -> String {
        (["Current output: \(outputName) (\(outputID))", "Readable volume: \(volume)", "Writable Core Audio controls: \(controls.count)", "Writable monitors: \(activeMonitors.map(\.name).joined(separator: ", "))", "Members: \(memberNames.joined(separator: ", "))", "Unsupported: \(unsupported.joined(separator: ", "))"] +
         outputs.map { "Output: \($0.name) [\($0.id)] controls=\(AudioHardware.controls($0.id).count) members=\(AudioHardware.leaves($0.id))" }).joined(separator: "\n")
    }
}
