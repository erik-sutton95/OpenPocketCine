import Foundation
import OpenPocketViewCore
import os

/// Structured expo lines for the agent loop: os.Logger + a capped Documents journal.
/// Pull with `tools/pull-control-log.sh` (no sudo, no pcap).
///
/// Redaction, os_log and journal writes ride a utility queue: `line` never runs
/// regexes or file I/O on the caller's thread (the UDP queue that also owns the
/// 40 Hz ACK pump, or Main). Person identifiers are stripped before a line is
/// stored (`PrivacyRedactor`).
enum ControlLiveLog {
    private static let log = Logger(
        subsystem: "com.opencapture.openpocketcine", category: "session")
    private static let queue = DispatchQueue(label: "opv.control-log", qos: .utility)
    private static let cap = DiagnosticReport.journalCap
    /// Trim cadence in appends — not a size stat per line.
    private static let trimEvery = 128
    private static let name = "control-live.log"

    nonisolated static func line(_ text: String) {
        appendRedacted(text)
    }

    /// Already-redacted structured line (exceptions, DiagnosticCenter).
    /// `logNow` writes os_log on the caller first, for a process about to abort.
    nonisolated static func appendRedacted(_ text: String, logNow: Bool = false) {
        let stampedAt = Date()
        if logNow { log.info("\(text, privacy: .public)") }
        queue.async {
            let safe = PrivacyRedactor.redact(text)
            if !logNow { log.info("\(safe, privacy: .public)") }
            append(stampedAt, safe)
        }
    }

    nonisolated static func recentLines() -> [String] {
        queue.sync {
            guard let url else { return [] }
            guard let existing = try? String(contentsOf: url, encoding: .utf8) else {
                return []
            }
            return existing.split(whereSeparator: \.isNewline).map(String.init)
        }
    }

    // Queue-confined.
    private static var appendsSinceTrim = 0
    /// Held open between trims instead of an exists/open/seek/close per line.
    private static var handle: FileHandle?
    private static let stamper = ISO8601DateFormatter()

    private static var url: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
            .appendingPathComponent(name)
    }

    private static func append(_ date: Date, _ text: String) {
        guard let url else { return }
        let row = Data("\(stamper.string(from: date)) \(text)\n".utf8)
        if handle == nil {
            guard FileManager.default.fileExists(atPath: url.path) else {
                try? row.write(to: url)
                return
            }
            handle = try? FileHandle(forWritingTo: url)
            _ = try? handle?.seekToEnd()
        }
        if (try? handle?.write(contentsOf: row)) == nil { closeHandle() }
        appendsSinceTrim += 1
        if appendsSinceTrim >= trimEvery {
            appendsSinceTrim = 0
            // Trim replaces the file; reopen afterwards (also recovers a removed journal).
            closeHandle()
            trimIfNeeded(url)
        }
    }

    private static func closeHandle() {
        try? handle?.close()
        handle = nil
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
