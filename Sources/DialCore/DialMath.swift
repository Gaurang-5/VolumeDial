import Foundation
import CoreGraphics

public enum DialMath {
    public static func showOutput(hasChannels: Bool, isVirtual: Bool, isAggregate: Bool, isHidden: Bool) -> Bool {
        hasChannels && !isHidden && (!isVirtual || isAggregate)
    }
    public static func volume(atAngle angle: Double) -> Double {
        let sweep = (angle + 225).truncatingRemainder(dividingBy: 360)
        let positive = sweep < 0 ? sweep + 360 : sweep
        if positive > 270 { return positive < 315 ? 1 : 0 }
        return clamp(positive / 270)
    }
    public static func hardwareValue(_ fraction: Double, maximum: Int) -> Int {
        Int((clamp(fraction) * Double(max(0, maximum))).rounded())
    }
    public static func panelFrame(anchor: CGRect, visibleFrame: CGRect, size: CGSize) -> CGRect {
        let safe = visibleFrame.insetBy(dx: 8, dy: 8)
        let width = min(size.width, safe.width), height = min(size.height, safe.height)
        return CGRect(x: min(max(anchor.midX - width / 2, safe.minX), safe.maxX - width),
                      y: min(max(anchor.minY - 8 - height, safe.minY), safe.maxY - height),
                      width: width, height: height)
    }
    public static func restorationValues<Key: Hashable>(current: [Key: Double], saved: [Key: Double]) -> [Key: Double] {
        current.reduce(into: [:]) { result, entry in
            result[entry.key] = clamp(saved[entry.key] ?? (entry.value > 0 ? entry.value : 0.25))
        }
    }
    public static func clamp(_ value: Double) -> Double {
        value.isFinite ? min(1, max(0, value)) : 0
    }
    public static func rotationDelta(from: Double, to: Double) -> Double {
        var delta = (to - from).truncatingRemainder(dividingBy: 360)
        if delta > 180 { delta -= 360 }
        if delta < -180 { delta += 360 }
        return delta
    }
    public static func shiftedVolumes(_ values: [Double], to target: Double) -> [Double] {
        guard !values.isEmpty else { return [] }
        let target = clamp(target)
        return values.map { _ in target }
    }
}
