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

    // Log lines are redacted on the UDP queue that also runs the 40 Hz ACK
    // pump; compiling eight expressions per line was measurable there.
    private static let regexLock = NSLock()
    nonisolated(unsafe) private static var regexCache: [String: NSRegularExpression] = [:]

    private static func regex(_ pattern: String) -> NSRegularExpression? {
        regexLock.lock()
        defer { regexLock.unlock() }
        if let cached = regexCache[pattern] { return cached }
        let compiled = try? NSRegularExpression(pattern: pattern)
        regexCache[pattern] = compiled
        return compiled
    }

    private static func replace(_ text: String, pattern: String, template: String) -> String {
        guard let regex = regex(pattern) else { return text }
        let range = NSRange(text.startIndex..., in: text)
        return regex.stringByReplacingMatches(in: text, range: range, withTemplate: template)
    }

    private static func replace(
        _ text: String, pattern: String, transform: ([String]) -> String
    ) -> String {
        guard let regex = regex(pattern) else { return text }
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

    /// Hard cap for explicit manual submission, including truncation markers.
    public static let manualReportCharacterCap = 32_000
    private static let reservedJournalCharacters = 8_000
    private static let reservedExceptionCharacters = 3_500
    private static let reservedTypedExtraCharacters = 10_000

    /// Bounded report for the native Send form. Same inputs as `fullReport`.
    public static func manualReport(
        environment: DiagnosticEnvironment,
        journal: [String],
        exceptions: [String],
        extras: [(name: String, body: String)] = []
    ) -> String {
        let cap = manualReportCharacterCap
        let journalLines = journal.map { PrivacyRedactor.redact($0) }
        let collectorCount = exceptions.filter { isCollectorException($0) }.count
        let exceptionLines = exceptions.map { PrivacyRedactor.redact($0) }.filter {
            !isCollectorException($0)
        }
        var typed: [(name: String, body: String)] = []
        var metricKit: [(name: String, body: String)] = []
        var other: [(name: String, body: String)] = []
        for extra in extras {
            let name = PrivacyRedactor.redact(extra.name)
            let body = PrivacyRedactor.redact(extra.body)
            guard !name.isEmpty, !body.isEmpty else { continue }
            if isTypedIncidentExtra(name) {
                typed.append((name, body))
            } else if name.lowercased().hasPrefix("metrickit-") {
                metricKit.append((name, body))
            } else {
                other.append((name, body))
            }
        }
        typed = orderedTypedExtras(typed)
        metricKit.sort { $0.name > $1.name }

        let header = manualHeader(environment: environment, hasTypedExtras: !typed.isEmpty)
        // Reserve separators and a bounded omission notice so low-priority extras
        // cannot force the final clamp to discard reserved journal evidence.
        var remaining = max(0, cap - header.count - 1_024)
        let exceptionBudget =
            exceptionLines.isEmpty ? 0 : min(reservedExceptionCharacters, remaining)
        remaining -= exceptionBudget
        let typedBudget = typed.isEmpty ? 0 : min(reservedTypedExtraCharacters, remaining)
        remaining -= typedBudget
        let journalBudget = journalLines.isEmpty ? 0 : min(reservedJournalCharacters, remaining)
        remaining -= journalBudget

        var omitted: [String] = []
        if collectorCount > 0 {
            omitted.append("omitted \(collectorCount) collector MetricKit stacks")
        }

        let exceptionSection = fitLineSection(
            title: "Exceptions / faults",
            lines: Array(exceptionLines.suffix(exceptionCap)),
            budget: exceptionBudget)
        var typedFitted = fitExtras(
            typed, budget: typedBudget, allowTextTruncate: true, omitted: &omitted)
        let journalSection = fitLineSection(
            title: "Journal",
            lines: Array(journalLines.suffix(journalCap)),
            budget: journalBudget)

        var leftover =
            remaining
            + unusedBudget(exceptionBudget, exceptionSection)
            + unusedBudget(typedBudget, typedFitted.map(\.section))
            + unusedBudget(journalBudget, journalSection)

        let typedIncluded = Set(typedFitted.map(\.name))
        let typedRemainder = typed.filter { !typedIncluded.contains($0.name) }
        if leftover > 0, !typedRemainder.isEmpty {
            let more = fitExtras(
                typedRemainder, budget: leftover, allowTextTruncate: true, omitted: &omitted)
            leftover -= joinedSectionCount(more.map(\.section))
            typedFitted.append(contentsOf: more)
        }
        let otherFitted: [String]
        if leftover > 0 {
            let moreOther = fitExtras(
                other, budget: leftover, allowTextTruncate: false, omitted: &omitted)
            leftover -= joinedSectionCount(moreOther.map(\.section))
            otherFitted = moreOther.map(\.section)
        } else {
            for extra in other {
                omitted.append("omitted extra \(extra.name) (did not fit)")
            }
            otherFitted = []
        }
        let metricFitted: [String]
        if leftover > 0 {
            let moreMetric = fitExtras(
                metricKit, budget: leftover, allowTextTruncate: false, omitted: &omitted)
            leftover -= joinedSectionCount(moreMetric.map(\.section))
            metricFitted = moreMetric.map(\.section)
        } else {
            if !metricKit.isEmpty {
                omitted.append("omitted \(metricKit.count) MetricKit extras that did not fit")
            }
            metricFitted = []
        }
        _ = leftover

        let fittedNames = Set(typedFitted.map(\.name))
        omitted.removeAll { note in
            fittedNames.contains { note.contains($0) }
        }

        var sections = [header]
        if let exceptionSection { sections.append(exceptionSection) }
        sections.append(contentsOf: typedFitted.map(\.section))
        if let journalSection { sections.append(journalSection) }
        sections.append(contentsOf: otherFitted)
        sections.append(contentsOf: metricFitted)
        if !omitted.isEmpty {
            let notice = omitted.joined(separator: "; ")
            sections.append(
                "[truncated: \(String(notice.prefix(900)))\(notice.count > 900 ? "; further omissions" : "")]"
            )
        }
        return clampSections(sections, cap: cap)
    }

    private static func manualHeader(
        environment: DiagnosticEnvironment, hasTypedExtras: Bool
    ) -> String {
        let stamp = ISO8601DateFormatter()
        stamp.timeZone = TimeZone(secondsFromGMT: 0)
        stamp.formatOptions = [.withInternetDateTime]
        var lines = [
            "OpenPocketCine diagnostic report",
            "Privacy: no personal name, email, location, device name, or Wi-Fi password.",
            "Generated: \(stamp.string(from: Date()))",
            "Prepared for explicit manual submission.",
            "Environment below is a report-time snapshot, not necessarily the failure state.",
            "",
            "app: \(environment.appVersion) (\(environment.appBuild))",
            "os: \(environment.osName) \(environment.osVersion)",
            "device: \(environment.deviceModel)",
            "camera: \(environment.cameraModel)",
            "family: \(environment.cameraFamily)",
            "phase: \(environment.phase)",
            "vpn: \(environment.vpnActive ? "on" : "off")",
        ]
        if !hasTypedExtras {
            lines.append("incidents: none captured")
        }
        return PrivacyRedactor.redact(lines.joined(separator: "\n"))
    }

    private static func isCollectorException(_ line: String) -> Bool {
        if line.contains("MetricKit diagnostic payload received") { return true }
        if line.contains("diagnostics metrickit") { return true }
        return false
    }

    private static func isTypedIncidentExtra(_ name: String) -> Bool {
        let lower = name.lowercased()
        if lower == "incidents.txt" { return true }
        if lower == "session-summary.json" { return true }
        if lower.hasPrefix("incident-") && lower.hasSuffix(".json") { return true }
        if lower.hasPrefix("session-") && lower.hasSuffix(".json") { return true }
        return false
    }

    private static func orderedTypedExtras(
        _ extras: [(name: String, body: String)]
    ) -> [(name: String, body: String)] {
        let listing = extras.filter { $0.name.lowercased() == "incidents.txt" }
        let summaries = extras.filter {
            let lower = $0.name.lowercased()
            return lower == "session-summary.json"
                || (lower.hasPrefix("session-") && lower.hasSuffix(".json"))
        }
        let incidents = extras.filter {
            let lower = $0.name.lowercased()
            return lower.hasPrefix("incident-") && lower.hasSuffix(".json")
        }
        // FeedIncidentStore exports newest first; preserve that ordering.
        return listing + summaries + incidents
    }

    private static func isJSONExtra(name: String, body: String) -> Bool {
        if name.lowercased().hasSuffix(".json") { return true }
        if let first = body.first(where: { !$0.isWhitespace }), first == "{" || first == "[" {
            return true
        }
        return false
    }

    private static func unusedBudget(_ budget: Int, _ section: String?) -> Int {
        max(0, budget - (section?.count ?? 0))
    }

    private static func unusedBudget(_ budget: Int, _ sections: [String]) -> Int {
        max(0, budget - joinedSectionCount(sections))
    }

    private static func joinedSectionCount(_ sections: [String]) -> Int {
        guard !sections.isEmpty else { return 0 }
        return sections.reduce(0) { $0 + $1.count } + 2 * (sections.count - 1)
    }

    private static func fitLineSection(title: String, lines: [String], budget: Int) -> String? {
        guard !lines.isEmpty, budget > 0 else { return nil }
        var kept: [String] = []
        for line in lines.reversed() {
            let candidateCount = kept.count + 1
            let heading = "\(title) (last \(candidateCount) lines)\n"
            let body = ([line] + kept).joined(separator: "\n")
            let omitted = lines.count - candidateCount
            let suffix = omitted > 0 ? "\n[truncated: omitted \(omitted) older lines]" : ""
            if heading.count + body.count + suffix.count > budget {
                if kept.isEmpty {
                    let clippedMarker = "\n[truncated: newest line shortened; older lines omitted]"
                    let room = max(0, budget - heading.count - clippedMarker.count)
                    return heading + String(line.prefix(room)) + clippedMarker
                }
                break
            }
            kept.insert(line, at: 0)
        }
        guard !kept.isEmpty else { return nil }
        let omitted = lines.count - kept.count
        var text = "\(title) (last \(kept.count) lines)\n" + kept.joined(separator: "\n")
        if omitted > 0 {
            text += "\n[truncated: omitted \(omitted) older lines]"
        }
        return text
    }

    private static func fitExtras(
        _ extras: [(name: String, body: String)],
        budget: Int,
        allowTextTruncate: Bool,
        omitted: inout [String]
    ) -> [(name: String, section: String)] {
        var remaining = budget
        var fitted: [(name: String, section: String)] = []
        for extra in extras {
            let json = isJSONExtra(name: extra.name, body: extra.body)
            let separator = fitted.isEmpty ? 0 : 2
            if json || !allowTextTruncate {
                let section = "\(extra.name)\n\(extra.body)"
                let cost = section.count + separator
                if cost <= remaining {
                    fitted.append((extra.name, section))
                    remaining -= cost
                } else {
                    omitted.append("omitted extra \(extra.name) (did not fit)")
                }
                continue
            }
            let separatorCost = fitted.isEmpty ? 0 : 2
            let heading = extra.name + "\n"
            let marker = "\n[truncated: older incident detail omitted]"
            let room = remaining - separatorCost - heading.count
            if room >= extra.body.count {
                let section = heading + extra.body
                fitted.append((extra.name, section))
                remaining -= section.count + separatorCost
            } else if room > marker.count {
                // Incident listings are newest first; keep their beginning.
                let prefix = String(extra.body.prefix(room - marker.count))
                let section = heading + prefix + marker
                fitted.append((extra.name, section))
                remaining -= section.count + separatorCost
            } else {
                omitted.append("omitted extra \(extra.name) (did not fit)")
            }
        }
        return fitted
    }

    private static func clampSections(_ sections: [String], cap: Int) -> String {
        let original = sections.joined(separator: "\n\n")
        guard original.count > cap else { return original }
        let marker = "[truncated: report capped at \(cap) characters]"
        var kept = sections
        // Every iteration removes a real section; never reinsert the marker
        // into the mutable list (which could otherwise prevent progress).
        while kept.count > 1 {
            kept.removeLast()
            let result = (kept + [marker]).joined(separator: "\n\n")
            if result.count <= cap { return result }
        }
        return String((kept.first ?? "").prefix(max(0, cap - marker.count - 2))) + "\n\n" + marker
    }
}
