import AppKit
import SwiftUI
import DialCore

@main
struct VolumeDialMain {
    @MainActor static func main() {
        let app = NSApplication.shared
        app.setActivationPolicy(.accessory)
        if CommandLine.arguments.contains("--verify-group-volume") {
            HardwareChecks.verifyGroupVolume()
            return
        }
        if CommandLine.arguments.contains("--diagnose") {
            let monitors = MonitorVolume.discover()
            print(AudioController(monitors: monitors).diagnostic())
            for monitor in monitors {
                print("DDC: \(monitor.name), \(Int((monitor.value * 100).rounded()))%, maximum \(monitor.maximum)")
            }
            return
        }
        if CommandLine.arguments.contains("--verify-routing") {
            let monitors = MonitorVolume.discover()
            let controller = AudioController(monitors: monitors)
            let original = controller.outputID
            let targets = controller.outputs.sorted { left, right in
                let leftGroup = AudioHardware.leaves(left.id).count > 1
                let rightGroup = AudioHardware.leaves(right.id).count > 1
                return leftGroup == rightGroup ? left.name > right.name : !leftGroup
            }
            Task { @MainActor in
                var passed = !targets.isEmpty
                for output in targets {
                    controller.selectOutput(output.id)
                    try? await Task.sleep(nanoseconds: 800_000_000)
                    controller.refresh()
                    let matches = controller.outputID == output.id
                    print("\(matches ? "PASS" : "FAIL") selected \(output.name); active members: \(AudioHardware.leaves(controller.outputID).map(AudioHardware.name).joined(separator: ", "))")
                    passed = passed && matches
                }
                controller.selectOutput(original)
                try? await Task.sleep(nanoseconds: 500_000_000)
                controller.refresh()
                passed = passed && controller.outputID == original
                print("Restored output: \(controller.outputName)")
                Darwin.exit(passed ? 0 : 1)
            }
            app.run()
            return
        }
        let delegate = AppDelegate()
        app.delegate = delegate
        withExtendedLifetime(delegate) { app.run() }
    }
}

@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
    let audio = AudioController()
    private var item: NSStatusItem!
    private let panel = DialWindow(contentRect: .zero, styleMask: [.borderless, .nonactivatingPanel], backing: .buffered, defer: false)
    private var scrollMonitor: Any?
    private var outsideMonitor: Any?
    private var localClickMonitor: Any?
    private var lastStatusSignature = ""

    func applicationDidFinishLaunching(_ notification: Notification) {
        // Keep one resident copy if the user opens the app again.
        if let identifier = Bundle.main.bundleIdentifier,
           NSRunningApplication.runningApplications(withBundleIdentifier: identifier).contains(where: { $0.processIdentifier != ProcessInfo.processInfo.processIdentifier }) {
            NSApp.terminate(nil)
            return
        }
        item = NSStatusBar.system.statusItem(withLength: 36)
        item.button?.target = self
        item.button?.action = #selector(togglePopover)
        item.button?.sendAction(on: .leftMouseDown)
        panel.isOpaque = false
        panel.backgroundColor = .clear
        panel.hasShadow = true
        panel.level = .popUpMenu
        panel.isMovable = false
        panel.collectionBehavior = [.canJoinAllSpaces, .fullScreenAuxiliary]
        panel.contentViewController = NSHostingController(rootView: DialPanel(audio: audio).clipShape(RoundedRectangle(cornerRadius: 22)))
        audio.onChange = { [weak self] in self?.updateStatus() }
        updateStatus()
        VolumeTrace.record("app ready")
        scrollMonitor = NSEvent.addLocalMonitorForEvents(matching: .scrollWheel) { [weak self] event in
            guard let self, let button = self.item.button, event.window == button.window,
                  button.bounds.contains(button.convert(event.locationInWindow, from: nil)) else { return event }
            self.audio.setVolume(self.audio.volume + event.scrollingDeltaY * (event.hasPreciseScrollingDeltas ? 0.002 : 0.02))
            return nil
        }
        outsideMonitor = NSEvent.addGlobalMonitorForEvents(matching: [.leftMouseDown, .rightMouseDown]) { [weak self] _ in
            guard let self else { return }
            // The menu bar can deliver mouse-down globally before the status
            // button's mouse-up action. Leave that click to togglePopover.
            let point = NSEvent.mouseLocation
            if let frame = self.statusButtonFrame, frame.contains(point) { return }
            if self.panel.isVisible && self.panel.frame.contains(point) { return }
            self.panel.orderOut(nil)
        }
        localClickMonitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard let self else { return event }
            if event.type == .keyDown && event.keyCode == 53 { self.panel.orderOut(nil); return nil }
            return event
        }
        if CommandLine.arguments.contains("--show") {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { self.togglePopover() }
        }
    }

    func applicationWillTerminate(_ notification: Notification) {
        if let scrollMonitor { NSEvent.removeMonitor(scrollMonitor) }
        if let outsideMonitor { NSEvent.removeMonitor(outsideMonitor) }
        if let localClickMonitor { NSEvent.removeMonitor(localClickMonitor) }
    }

    func applicationShouldHandleReopen(_ sender: NSApplication, hasVisibleWindows flag: Bool) -> Bool {
        if !panel.isVisible { togglePopover() }
        return true
    }

    private func updateStatus() {
        let signature = "\(audio.outputID)|\(audio.outputName)|\(audio.hasControl)|\(Int((audio.volume * 100).rounded()))"
        guard signature != lastStatusSignature else { return }
        lastStatusSignature = signature
        let image = NSImage(size: NSSize(width: 23, height: 23), flipped: false) { [volume = audio.volume, enabled = audio.hasControl] rect in
            NSColor.labelColor.setStroke()
            let arc = NSBezierPath()
            arc.lineWidth = 1.4
            arc.lineCapStyle = .round
            arc.appendArc(withCenter: NSPoint(x: 11.5, y: 11.5), radius: 8, startAngle: 225, endAngle: -45, clockwise: true)
            arc.stroke()
            let theta = (225 - volume * 270) * .pi / 180
            let marker = NSBezierPath()
            marker.lineWidth = 2
            marker.lineCapStyle = .round
            marker.move(to: NSPoint(x: 11.5 + cos(theta) * 3.5, y: 11.5 + sin(theta) * 3.5))
            marker.line(to: NSPoint(x: 11.5 + cos(theta) * 6, y: 11.5 + sin(theta) * 6))
            marker.stroke()
            if !enabled {
                let slash = NSBezierPath()
                slash.move(to: NSPoint(x: 5, y: 5)); slash.line(to: NSPoint(x: 18, y: 18)); slash.stroke()
            }
            return true
        }
        image.isTemplate = true
        item.button?.image = image
        item.button?.toolTip = "\(audio.outputName) · \(audio.hasControl ? "\(Int((audio.volume * 100).rounded()))%" : "Hardware volume")"
        item.button?.setAccessibilityLabel("Volume Dial, \(audio.outputName)")
        if panel.isVisible { positionPanel() }
    }

    @objc private func togglePopover() {
        if panel.isVisible {
            panel.orderOut(nil)
            VolumeTrace.record("panel closed by status toggle")
            return
        }
        audio.refresh()
        positionPanel()
        NSApp.activate(ignoringOtherApps: true)
        panel.makeKeyAndOrderFront(nil)
        VolumeTrace.record("panel opened by status toggle")
    }

    private func positionPanel() {
        guard let anchor = statusButtonFrame, let window = item.button?.window else { return }
        guard let screen = NSScreen.screens.first(where: { $0.frame.contains(CGPoint(x: anchor.midX, y: anchor.midY)) }) ?? window.screen else { return }
        let size = panel.contentViewController?.view.fittingSize ?? CGSize(width: 340, height: 510)
        let frame = DialMath.panelFrame(anchor: anchor, visibleFrame: screen.visibleFrame, size: CGSize(width: 340, height: size.height))
        if panel.frame != frame { panel.setFrame(frame, display: true) }
    }

    private var statusButtonFrame: CGRect? {
        guard let button = item.button, let window = button.window else { return nil }
        return window.convertToScreen(button.convert(button.bounds, to: nil))
    }
}

final class DialWindow: NSPanel {
    override var canBecomeKey: Bool { true }
    override var canBecomeMain: Bool { false }
}
