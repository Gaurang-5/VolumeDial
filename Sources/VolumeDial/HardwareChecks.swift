import AppKit

enum HardwareChecks {
    @MainActor static func verifyGroupVolume() {
        var monitors = MonitorVolume.discover()
        for _ in 0..<2 where monitors.isEmpty { monitors = MonitorVolume.discover() }
        let controller = AudioController(monitors: monitors)
        guard let group = controller.outputs.first(where: { AudioHardware.leaves($0.id).count > 1 }) else {
            print("FAIL: No multi-output group available")
            Darwin.exit(1)
        }
        let members = AudioHardware.leaves(group.id)
        let memberNames = members.map(AudioHardware.name)
        let groupMonitors = monitors.filter { memberNames.contains($0.name) }
        guard !groupMonitors.isEmpty else {
            print("FAIL: The group monitor backend was not discovered")
            Darwin.exit(1)
        }
        let savedControls = members.flatMap(AudioHardware.controls)
        let originalRoute = controller.outputID
        Task { @MainActor in
            controller.selectOutput(group.id)
            try? await Task.sleep(nanoseconds: 800_000_000)
            var passed = controller.outputID == group.id
            for fraction in [0.2, 0.4] {
                controller.setVolume(fraction)
                try? await Task.sleep(nanoseconds: 2_000_000_000)
                let core = members.flatMap(AudioHardware.controls)
                let displays = await Task.detached { groupMonitors.compactMap(MonitorVolume.read) }.value
                let allCore = !core.isEmpty && core.allSatisfy { abs($0.value - fraction) < 0.025 }
                let allDisplays = displays.count == groupMonitors.count && displays.allSatisfy { abs($0.value - fraction) < 0.025 }
                let result = allCore && allDisplays
                passed = passed && result
                print("\(result ? "PASS" : "FAIL") requested \(Int(fraction * 100))%: CoreAudio=\(core.map { Int(($0.value * 100).rounded()) }), DDC=\(displays.map { Int(($0.value * 100).rounded()) })")
            }
            // Wait for queued work before restoring the pre-test volumes and route.
            try? await Task.sleep(nanoseconds: 1_000_000_000)
            for control in savedControls {
                if !AudioHardware.write(control, value: control.value) { passed = false }
            }
            let restored = await Task.detached {
                groupMonitors.compactMap { MonitorVolume.write($0, fraction: $0.value) }
            }.value
            passed = passed && restored.count == groupMonitors.count
            controller.selectOutput(originalRoute)
            try? await Task.sleep(nanoseconds: 500_000_000)
            controller.refresh()
            passed = passed && controller.outputID == originalRoute
            print("Restored original volume levels and output: \(controller.outputName)")
            Darwin.exit(passed ? 0 : 1)
        }
        NSApplication.shared.run()
    }
}
