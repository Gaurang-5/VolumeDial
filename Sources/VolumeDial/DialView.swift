import SwiftUI
import AppKit
import ServiceManagement
import DialCore

struct DialPalette {
    let dark: Bool
    var ink: Color { dark ? Color(red: 0.71, green: 0.82, blue: 0.94) : Color(red: 0.16, green: 0.25, blue: 0.36) }
    var mutedInk: Color { dark ? Color(red: 0.43, green: 0.50, blue: 0.58) : Color(red: 0.39, green: 0.45, blue: 0.51) }
    var base: Color { dark ? Color(red: 0.10, green: 0.12, blue: 0.15) : Color(red: 0.81, green: 0.84, blue: 0.87) }
    var panelTop: Color { dark ? Color(red: 0.17, green: 0.20, blue: 0.24) : Color(red: 0.9, green: 0.92, blue: 0.93) }
    var knobTop: Color { dark ? Color(red: 0.23, green: 0.27, blue: 0.32) : Color(red: 0.89, green: 0.91, blue: 0.93) }
    var shadow: Color { dark ? .black.opacity(0.6) : Color(red: 0.48, green: 0.54, blue: 0.59).opacity(0.43) }
    var highlight: Color { .white.opacity(dark ? 0.07 : 0.83) }
    var rim: Color { .white.opacity(dark ? 0.2 : 0.95) }
    var engraving: Color { .white.opacity(dark ? 0.1 : 0.23) }
    var markerTop: Color { dark ? Color(red: 0.06, green: 0.08, blue: 0.11) : Color(red: 0.59, green: 0.65, blue: 0.70) }
    var markerBottom: Color { dark ? Color(red: 0.31, green: 0.38, blue: 0.45) : Color(red: 0.79, green: 0.83, blue: 0.86) }
}

struct DialPanel: View {
    @ObservedObject var audio: AudioController
    @AppStorage("haptics") private var haptics = true
    @AppStorage("appearance") private var appearance = "system"
    @Environment(\.colorScheme) private var systemColorScheme
    @State private var loginEnabled = SMAppService.mainApp.status == .enabled
    @State private var settingsError: String?

    private var preferredScheme: ColorScheme? {
        appearance == "dark" ? .dark : appearance == "light" ? .light : nil
    }
    private var palette: DialPalette { DialPalette(dark: (preferredScheme ?? systemColorScheme) == .dark) }

    var body: some View {
        VStack(spacing: 0) {
            RotaryDial(audio: audio, haptics: haptics, palette: palette)
                .frame(width: 290, height: 290).padding(.top, 24)
            Menu {
                ForEach(audio.outputs) { output in
                    Button {
                        audio.selectOutput(output.id)
                    } label: {
                        if output.id == audio.outputID { Label(output.name, systemImage: "checkmark") }
                        else { Text(output.name) }
                    }
                }
            } label: {
                Text(audio.outputName)
                    .font(.system(size: 14, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .lineLimit(2).multilineTextAlignment(.center)
            }
            .menuStyle(.borderlessButton).menuIndicator(.hidden)
            .fixedSize(horizontal: false, vertical: true)
            .accessibilityLabel("Current audio output: \(audio.outputName). Choose output")
            .disabled(audio.isSwitching)
            .padding(.horizontal, 24).padding(.top, 4).padding(.bottom, 28)
        }
        .frame(width: 340)
        .background(LinearGradient(colors: [palette.panelTop, palette.base], startPoint: .topLeading, endPoint: .bottomTrailing))
        .overlay(alignment: .topTrailing) {
            Button {
                appearance = palette.dark ? "light" : "dark"
            } label: {
                Image(systemName: palette.dark ? "sun.max" : "moon")
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(palette.ink)
                    .frame(width: 28, height: 28)
                    .background(Circle().fill(.white.opacity(palette.dark ? 0.07 : 0.28)))
                    .overlay(Circle().stroke(.white.opacity(palette.dark ? 0.08 : 0.45), lineWidth: 0.5))
                    .contentShape(Circle())
            }
            .buttonStyle(.plain)
            .help(palette.dark ? "Switch to light mode" : "Switch to dark mode")
            .accessibilityLabel(palette.dark ? "Switch to light mode" : "Switch to dark mode")
            .padding(12)
        }
        .preferredColorScheme(preferredScheme)
        .contextMenu {
            Button(audio.volume < 0.001 ? "Restore volume" : "Mute") { audio.toggleMute() }
                .disabled(!audio.hasControl)
            Toggle("Trackpad haptics", isOn: $haptics)
            Picker("Appearance", selection: $appearance) {
                Text("System").tag("system")
                Text("Light").tag("light")
                Text("Dark").tag("dark")
            }
            Toggle("Launch at login", isOn: Binding(get: { loginEnabled }, set: { enabled in
                do {
                    if enabled { try SMAppService.mainApp.register() }
                    else { try SMAppService.mainApp.unregister() }
                    loginEnabled = SMAppService.mainApp.status == .enabled
                    if enabled && !loginEnabled { settingsError = "Allow Volume Dial in System Settings → General → Login Items." }
                } catch { settingsError = error.localizedDescription }
            }))
            if let message = audio.error ?? settingsError { Text(message) }
            if !audio.unsupported.isEmpty {
                Divider()
                Text("Hardware volume only: " + audio.unsupported.joined(separator: ", "))
            }
            Divider()
            Button("Quit Volume Dial") { NSApplication.shared.terminate(nil) }
        }
    }
}

struct RotaryDial: View {
    @ObservedObject var audio: AudioController
    let haptics: Bool
    let palette: DialPalette
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            Canvas { context, size in
                let center = CGPoint(x: size.width / 2, y: size.height / 2)
                for index in 0...60 {
                    let radians = (135 + Double(index) * 4.5) * .pi / 180
                    let active = audio.hasControl && Double(index) / 60 <= audio.volume
                    let selected = audio.hasControl && index == Int((audio.volume * 60).rounded())
                    let outer = 136.0
                    let inner = outer - (selected ? 15 : index % 5 == 0 ? 11 : 8)
                    var line = Path()
                    line.move(to: CGPoint(x: center.x + cos(radians) * inner, y: center.y + sin(radians) * inner))
                    line.addLine(to: CGPoint(x: center.x + cos(radians) * outer, y: center.y + sin(radians) * outer))
                    context.stroke(line, with: .color(active ? palette.ink : palette.mutedInk.opacity(palette.dark ? 0.65 : 0.45)), style: StrokeStyle(lineWidth: selected ? 2.8 : 1.1, lineCap: .round))
                }
            }
            Circle()
                .fill(LinearGradient(colors: [palette.knobTop, palette.base], startPoint: .topLeading, endPoint: .bottomTrailing))
                .shadow(color: palette.shadow, radius: 12, x: 10, y: 14)
                .shadow(color: palette.highlight, radius: 11, x: -9, y: -10)
                .overlay(Circle().stroke(LinearGradient(colors: [palette.rim, .white.opacity(0.05)], startPoint: .topLeading, endPoint: .bottomTrailing), lineWidth: 1.5))
                .frame(width: 202, height: 202)
            Canvas { context, size in
                for index in 0..<100 {
                    let radians = Double(index) * .pi / 50
                    var line = Path()
                    line.move(to: CGPoint(x: 101 + cos(radians) * 92, y: 101 + sin(radians) * 92))
                    line.addLine(to: CGPoint(x: 101 + cos(radians) * 96, y: 101 + sin(radians) * 96))
                    context.stroke(line, with: .color(palette.engraving), lineWidth: 1)
                }
            }.frame(width: 202, height: 202)
                .rotationEffect(.degrees(audio.volume * 270))
            Circle()
                .fill(LinearGradient(colors: [palette.markerTop, palette.markerBottom], startPoint: .top, endPoint: .bottom))
                .overlay(Circle().stroke(.white.opacity(0.25), lineWidth: 0.7))
                .frame(width: 29, height: 29)
                .offset(y: -65)
                .rotationEffect(.degrees(-135 + audio.volume * 270))
            DialInteraction(value: audio.volume, outputID: audio.outputID, enabled: audio.hasControl && !audio.isSwitching, haptics: haptics,
                            onChange: { [route = audio.outputID] value in audio.setVolume(value, for: route) })
                .accessibilityLabel("Output volume")
                .accessibilityValue(audio.hasControl ? "\(Int(audio.volume * 100)) percent" : "Unavailable")
                .accessibilityAdjustableAction { direction in
                    audio.setVolume(audio.volume + (direction == .increment ? 0.02 : -0.02))
                }
        }
        .animation(reduceMotion ? nil : .interactiveSpring(response: 0.16, dampingFraction: 0.88), value: audio.volume)
    }
}

struct DialInteraction: NSViewRepresentable {
    var value: Double
    var outputID: UInt32
    var enabled: Bool
    var haptics: Bool
    var onChange: (Double) -> Void
    func makeNSView(context: Context) -> KnobInput { KnobInput() }
    func updateNSView(_ view: KnobInput, context: Context) {
        if view.outputID != outputID || !enabled { view.cancelGesture() }
        view.outputID = outputID
        if !view.isDragging { view.value = value }
        view.isEnabled = enabled; view.haptics = haptics; view.onChange = onChange
    }
}

final class KnobInput: NSView {
    var value = 0.0
    var outputID: UInt32 = 0
    var isEnabled = true
    var haptics = true
    var onChange: ((Double) -> Void)?
    private var previousAngle: Double?
    private(set) var isDragging = false
    override var isFlipped: Bool { true }
    override var acceptsFirstResponder: Bool { true }
    override func resetCursorRects() { addCursorRect(bounds, cursor: isEnabled ? .openHand : .arrow) }

    private func angle(_ event: NSEvent) -> Double? {
        let point = convert(event.locationInWindow, from: nil)
        let x = point.x - bounds.midX, y = point.y - bounds.midY
        guard hypot(x, y) > 24 else { return nil }
        return atan2(y, x) * 180 / .pi
    }
    override func mouseDown(with event: NSEvent) {
        guard isEnabled else { return }
        window?.makeFirstResponder(self)
        previousAngle = angle(event)
        isDragging = true
        if let angle = previousAngle { change(DialMath.volume(atAngle: angle)) }
        NSCursor.closedHand.push()
    }
    override func mouseDragged(with event: NSEvent) {
        guard isEnabled, isDragging else { return }
        if let next = angle(event) { change(DialMath.volume(atAngle: next)) }
        previousAngle = angle(event)
    }
    override func mouseUp(with event: NSEvent) {
        cancelGesture()
    }
    func cancelGesture() {
        if isDragging { NSCursor.pop() }
        isDragging = false
        previousAngle = nil
    }
    override func scrollWheel(with event: NSEvent) {
        guard isEnabled else { return }
        let delta = event.scrollingDeltaY == 0 ? event.scrollingDeltaX : event.scrollingDeltaY
        change(value + delta * (event.hasPreciseScrollingDeltas ? 0.002 : 0.02))
    }
    override func keyDown(with event: NSEvent) {
        switch event.keyCode {
        case 126, 124: change(value + (event.modifierFlags.contains(.shift) ? 0.1 : 0.01))
        case 125, 123: change(value - (event.modifierFlags.contains(.shift) ? 0.1 : 0.01))
        default: super.keyDown(with: event)
        }
    }
    private func change(_ target: Double) {
        guard isEnabled else { return }
        let next = DialMath.clamp(target)
        if haptics && Int(next * 50) != Int(value * 50) {
            NSHapticFeedbackManager.defaultPerformer.perform(.levelChange, performanceTime: .now)
        }
        value = next
        onChange?(next)
    }
}
