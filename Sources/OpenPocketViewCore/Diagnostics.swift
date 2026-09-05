import Foundation

/// Severity for on-device diagnostics. Debug stays off the journal.
public enum DiagnosticLevel: String, Equatable, Sendable, CaseIterable {
    case debug
    case info
    case notice
    case warning
    case error
    case fault

    /// Debug is for a connected Console session, not the tester journal.
    public var persistsToJournal: Bool { self != .debug }
}

/// Stable buckets so a report can be grepped without dumping the ACK pump.
public enum DiagnosticCategory: String, Equatable, Sendable, CaseIterable {
    case session
    case feed
    case control
    case ble
    case decoder
    case recovery
    case diagnostics
}

/// One structured line. `code` is a stable token (`first-picture`, `ns-exception`).
public struct DiagnosticEvent: Equatable, Sendable {
    public var timestamp: Date
    public var level: DiagnosticLevel
    public var category: DiagnosticCategory
    public var code: String
    public var message: String
    public var fields: [String: String]

    public init(
        timestamp: Date = Date(),
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        code: String,
        message: String,
        fields: [String: String] = [:]
    ) {
        self.timestamp = timestamp
        self.level = level
        self.category = category
        self.code = code
        self.message = message
        self.fields = fields
    }

    public var journalLine: String {
        var line = "\(level.rawValue) \(category.rawValue) \(code) \(message)"
        if !fields.isEmpty {
            let body = fields.keys.sorted().map { "\($0)=\(fields[$0] ?? "")" }.joined(
                separator: " ")
            line += " \(body)"
        }
        return line
    }
}

/// Device/app context for a report. Never a personal device name or location.
public struct DiagnosticEnvironment: Equatable, Sendable {
    public var appVersion: String
    public var appBuild: String
    public var osName: String
    public var osVersion: String
    public var deviceModel: String
    public var cameraFamily: String
    public var cameraModel: String
    public var phase: String
    /// Local VPN / ad-blocker tunnel (AdGuard, Blokada, RethinkDNS). Not a
    /// personal identifier. Testers' reports for a black live well need this.
    public var vpnActive: Bool

    public init(
        appVersion: String,
        appBuild: String,
        osName: String,
        osVersion: String,
        deviceModel: String,
        cameraFamily: String = "unknown",
        cameraModel: String = "none",
        phase: String = "none",
        vpnActive: Bool = false
    ) {
        self.appVersion = appVersion
        self.appBuild = appBuild
        self.osName = osName
        self.osVersion = osVersion
        self.deviceModel = deviceModel
        self.cameraFamily = cameraFamily
        self.cameraModel = cameraModel
        self.phase = phase
        self.vpnActive = vpnActive
    }
}

/// Strip person identifiers from diagnostic text. Opcodes, seq, and camera
/// family stay. Home paths, emails, MACs, passphrases, and non-camera SSIDs go.
public enum PrivacyRedactor: Sendable {
    public static func redact(_ text: String) -> String {
        var out = text
        out = replace(out, pattern: #"(?i)(/Users|/home)/[^/\s]+"#, template: "$1/<redacted>")
        out = replace(out, pattern: #"(?i)\\Users\\[^\\\s]+"#, template: "\\Users\\<redacted>")
        out = replace(
            out,
            pattern: #"(?i)\b[A-Z0-9._%+\-]+@[A-Z0-9.\-]+\.[A-Z]{2,}\b"#,
            template: "<email>")
        out = replace(
            out,
            pattern: #"\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\b"#,
            template: "<mac>")
        out = replace(
            out,
            pattern: #"(?i)\b(password|passphrase|psk|wifiPassword)\s*[:=]\s*\S+"#,
            template: "$1=<redacted>")
        out = replace(
            out,
            pattern: #"(?i)\bBearer\s+[A-Za-z0-9._\-]+"#,
            template: "Bearer <redacted>")
        out = redactSSID(out)
        out = redactPublicIPv4(out)
        return out
    }

    /// Compact paste for TestFlight feedback. Hard cap so it fits a comment.
    public static let compactCharacterCap = 1400

    public static func clampCompact(_ text: String) -> String {
        if text.count <= compactCharacterCap { return text }
        return String(text.prefix(compactCharacterCap - 1)) + "…"
    }

    private static func redactSSID(_ text: String) -> String {
        replace(text, pattern: #"(?i)\b(ssid)\s*[:=]\s*([^\s,;]+)"#) { match in
            let value = match.last ?? ""
            if isCameraNetwork(value) { return match[0] }
            return "ssid=<redacted>"
        }
    }

    private static func redactPublicIPv4(_ text: String) -> String {
        replace(text, pattern: #"\b(\d{1,3})(\.\d{1,3}){3}\b"#) { match in
            let ip = match[0]
            if isLocalIPv4(ip) { return ip }
            return "<ip>"
        }
    }

    public static func isCameraNetwork(_ raw: String) -> Bool {
        let n = raw.lowercased().replacingOccurrences(of: "\"", with: "")
            .replacingOccurrences(of: "'", with: "")
        return n.contains("osmo") || n.contains("pocket") || n.contains("nano")
            || n.contains("muse") || n.contains("atto") || n.contains("xtra")
            || n.contains("edge")
    }

    public static func isLocalIPv4(_ ip: String) -> Bool {
        if ip.hasPrefix("127.") || ip.hasPrefix("192.168.") || ip.hasPrefix("10.") {
            return true
        }
        if ip.hasPrefix("172.") {
            let parts = ip.split(separator: ".")
            if parts.count >= 2, let second = Int(parts[1]), (16...31).contains(second) {
                return true
            }
        }
        return false
    }

    private static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replace(
        _ text: String, pattern: String, transform: ([String]) -> String
    ) -> String {
        guard let regex = try? NSRegularExpression(pattern: pattern) else { return text }
        let ns = text as NSString
        let matches = regex.matches(in: text, range: NSRange(location: 0, length: ns.length))
        var out = text
        for match in matches.reversed() {
            guard let full = Range(match.range, in: out) else { continue }
            var groups: [String] = []
            for i in 0..<match.numberOfRanges {
                if let r = Range(match.range(at: i), in: out) {
                    groups.append(String(out[r]))
                } else {
                    groups.append("")
                }
            }
            out.replaceSubrange(full, with: transform(groups))
        }
        return out
    }
}

/// Assemble tester-facing diagnostic text. No analytics upload.
public enum DiagnosticReport: Sendable {
    public static let journalCap = 2500
    public static let exceptionCap = 200

    public static func compactSummary(
        environment: DiagnosticEnvironment,
        recent: [String]
    ) -> String {
        var lines = [
            "OpenPocketCine diagnostics (no name, no location)",
            "app \(environment.appVersion) (\(environment.appBuild)) \(environment.osName) \(environment.osVersion) \(environment.deviceModel)",
            "camera \(environment.cameraModel) family=\(environment.cameraFamily) phase=\(environment.phase) vpn=\(environment.vpnActive ? "on" : "off")",
        ]
        let tail = recent.suffix(12)
        if !tail.isEmpty {
            lines.append("recent:")
            lines.append(contentsOf: tail)
        }
        return PrivacyRedactor.clampCompact(
            PrivacyRedactor.redact(lines.joined(separator: "\n")))
    }

    public static func fullReport(
        environment: DiagnosticEnvironment,
        journal: [String],
        exceptions: [String],
        extras: [(name: String, body: String)] = []
    ) -> String {
        var sections: [String] = []
        sections.append(
            """
            OpenPocketCine diagnostic report
            Privacy: no personal name, email, location, device name, or Wi-Fi password.
            Generated for a tester to paste or share. Not uploaded.

            app: \(environment.appVersion) (\(environment.appBuild))
            os: \(environment.osName) \(environment.osVersion)
            device: \(environment.deviceModel)
            camera: \(environment.cameraModel)
            family: \(environment.cameraFamily)
            phase: \(environment.phase)
            vpn: \(environment.vpnActive ? "on" : "off")
            """)
        if !exceptions.isEmpty {
            sections.append(
                "Exceptions / faults\n" + exceptions.suffix(exceptionCap).joined(separator: "\n"))
        }
        for extra in extras where !extra.body.isEmpty {
            sections.append("\(extra.name)\n\(extra.body)")
        }
        if !journal.isEmpty {
            sections.append(
                "Journal (last \(min(journal.count, journalCap)) lines)\n"
                    + journal.suffix(journalCap).joined(separator: "\n"))
        }
        return PrivacyRedactor.redact(sections.joined(separator: "\n\n"))
    }
}
