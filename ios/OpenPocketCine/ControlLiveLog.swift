import Foundation
import os

/// Structured expo lines for the agent loop: os.Logger + a capped Documents journal.
/// Pull with `tools/pull-control-log.sh` (no sudo, no pcap).
///
/// Journal writes ride a utility queue — `line` never does file I/O on the
/// caller's thread (it sits on the command send path).
enum ControlLiveLog {
    private static let log = Logger(
        subsystem: "com.opencapture.openpocketcine", category: "session")
    private static let queue = DispatchQueue(label: "opv.control-log", qos: .utility)
    private static let cap = 2500
    /// Trim cadence in appends — not a size stat per line.
    private static let trimEvery = 128
    private static let name = "control-live.log"

    nonisolated static func line(_ text: String) {
        log.info("\(text, privacy: .public)")
        let stampedAt = Date()
        queue.async { append(stampedAt, text) }
    }

    // Queue-confined.
    private static var appendsSinceTrim = 0
    private static let stamper = ISO8601DateFormatter()

    private static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    private static func append(_ date: Date, _ text: String) {
        guard let url else { return }
        let row = Data("\(stamper.string(from: date)) \(text)\n".utf8)
        if FileManager.default.fileExists(atPath: url.path) {
            if let handle = try? FileHandle(forWritingTo: url) {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: row)
            }
            appendsSinceTrim += 1
            if appendsSinceTrim >= trimEvery {
                appendsSinceTrim = 0
                trimIfNeeded(url)
            }
        } else {
            try? row.write(to: url)
        }
    }

    /// Read/rewrite only on the trim cadence — never per send/ack line.
    private static func trimIfNeeded(_ url: URL) {
        guard let existing = try? String(contentsOf: url, encoding: .utf8) else { return }
        var lines = existing.split(whereSeparator: \.isNewline).map(String.init)
        guard lines.count > cap else { return }
        lines = Array(lines.suffix(cap))
        try? (lines.joined(separator: "\n") + "\n").write(
            to: url, atomically: true, encoding: .utf8)
    }
}
