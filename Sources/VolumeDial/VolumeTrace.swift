import Foundation

// Opt-in local diagnostics for intermittent hardware changes; no audio is recorded.
enum VolumeTrace {
    static func record(_ message: String) {
        guard CommandLine.arguments.contains("--trace-volume") else { return }
        let line = "\(Date().ISO8601Format()) \(message)\n"
        if let data = line.data(using: .utf8) { FileHandle.standardError.write(data) }
    }
}
