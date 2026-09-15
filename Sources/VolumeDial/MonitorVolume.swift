import Foundation
import DialCore
import Darwin

struct MonitorLevel: Sendable {
    let id: String
    let name: String
    let maximum: Int
    var value: Double
}

enum MonitorVolume {
    static func matching(outputNames: [String], allOutputNames: [String], monitors: [MonitorLevel]) -> [MonitorLevel] {
        func key(_ name: String) -> String {
            name.lowercased().unicodeScalars.filter(CharacterSet.alphanumerics.contains).map(String.init).joined()
        }
        let active = Set(outputNames.map(key))
        return monitors.filter { monitor in
            let name = key(monitor.name)
            return !name.isEmpty && active.contains(name) &&
                monitors.filter { key($0.name) == name }.count == 1 &&
                allOutputNames.filter { key($0) == name }.count == 1
        }
    }

    static var helper: URL {
        Bundle.main.bundleURL.appendingPathComponent("Contents/Helpers/m1ddc")
    }

    // Invoked on a utility task, never on the UI thread. A hung monitor cannot hang the dial.
    static func run(_ arguments: [String]) -> String? {
        guard FileManager.default.isExecutableFile(atPath: helper.path) else { return nil }
        // Diagnostics and the resident app must not interleave DDC transactions.
        let lockPath = NSTemporaryDirectory() + "com.gaurang.volumedial-ddc.lock"
        let lock = Darwin.open(lockPath, O_CREAT | O_RDWR, S_IRUSR | S_IWUSR)
        guard lock >= 0 else { return nil }
        defer { Darwin.close(lock) }
        guard flock(lock, LOCK_EX) == 0 else { return nil }
        defer { flock(lock, LOCK_UN) }
        let process = Process()
        let pipe = Pipe()
        process.executableURL = helper
        process.arguments = arguments
        process.standardOutput = pipe
        process.standardError = FileHandle.nullDevice
        do { try process.run() } catch { return nil }
        let deadline = Date().addingTimeInterval(2)
        while process.isRunning && Date() < deadline { Thread.sleep(forTimeInterval: 0.01) }
        if process.isRunning { process.terminate(); return nil }
        guard process.terminationStatus == 0 else { return nil }
        return String(data: pipe.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func discover(existing: [MonitorLevel] = [], command: ([String]) -> String? = run) -> [MonitorLevel] {
        guard let listing = command(["display", "list"]) else { return existing }
        return listing.split(separator: "\n").compactMap { line in
            guard let nameStart = line.firstIndex(of: "]"), let uuidStart = line.lastIndex(of: "("), line.last == ")" else { return nil }
            let id = String(line[line.index(after: uuidStart)..<line.index(before: line.endIndex)])
            let name = String(line[line.index(after: nameStart)..<uuidStart]).trimmingCharacters(in: .whitespaces)
            let known = existing.first { $0.id == id && $0.name == name }
            if let known {
                if let text = command(["display", id, "get", "volume"]), let value = Int(text), (0...known.maximum).contains(value) {
                    return MonitorLevel(id: id, name: name, maximum: known.maximum, value: Double(value) / Double(known.maximum))
                }
                return known
            }
            guard let maxText = command(["display", id, "max", "volume"]), let maximum = Int(maxText), maximum > 0, maximum <= 65535,
                  let currentText = command(["display", id, "get", "volume"]), let current = Int(currentText), (0...maximum).contains(current) else { return nil }
            return MonitorLevel(id: id, name: name, maximum: maximum, value: Double(current) / Double(maximum))
        }
    }

    static func read(_ monitor: MonitorLevel) -> MonitorLevel? {
        guard let text = run(["display", monitor.id, "get", "volume"]), let value = Int(text), (0...monitor.maximum).contains(value) else { return nil }
        var result = monitor
        result.value = Double(value) / Double(monitor.maximum)
        return result
    }

    static func write(_ monitor: MonitorLevel, fraction: Double) -> MonitorLevel? {
        let value = DialMath.hardwareValue(fraction, maximum: monitor.maximum)
        guard run(["display", monitor.id, "set", "volume", String(value)]) != nil else { return nil }
        // The display acknowledges the write before its volume register settles.
        for _ in 0..<3 {
            Thread.sleep(forTimeInterval: 0.25)
            if let result = read(monitor), DialMath.hardwareValue(result.value, maximum: result.maximum) == value { return result }
        }
        return nil
    }
}
