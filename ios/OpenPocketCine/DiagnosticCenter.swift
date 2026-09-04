import Foundation
import MetricKit
import OpenPocketViewCore
import SwiftUI
import UIKit
import os

/// On-device diagnostics: unified log, capped journal, exceptions, MetricKit,
/// and a shareable report. Nothing is uploaded. Personal name, location,
/// device name, and Wi-Fi passwords are stripped before a line is stored.
final class DiagnosticCenter: NSObject, MXMetricManagerSubscriber {
    static let shared = DiagnosticCenter()

    private let log = Logger(
        subsystem: "com.opencapture.openpocketcine", category: "diagnostics")
    private let signposter = OSSignposter(
        subsystem: "com.opencapture.openpocketcine", category: "diagnostics")
    private var screenshotObserver: NSObjectProtocol?
    private var installed = false

    /// Last compact summary copied for TestFlight paste.
    private(set) var lastCompactSummary = ""
    var onCopiedForTestFlight: (() -> Void)?

    nonisolated static var documentsURL: URL? {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first
    }

    nonisolated static var diagnosticsDirectory: URL? {
        guard let docs = documentsURL else { return nil }
        let dir = docs.appendingPathComponent("diagnostics", isDirectory: true)
        try? FileManager.default.createDirectory(at: dir, withIntermediateDirectories: true)
        return dir
    }

    nonisolated static var exceptionsURL: URL? {
        diagnosticsDirectory?.appendingPathComponent("exceptions.log")
    }

    @MainActor
    func install() {
        guard !installed else { return }
        installed = true
        MXMetricManager.shared.add(self)
        opcInstallUncaughtExceptionHandler()
        screenshotObserver = NotificationCenter.default.addObserver(
            forName: UIApplication.userDidTakeScreenshotNotification,
            object: nil,
            queue: .main
        ) { [weak self] _ in
            DispatchQueue.main.async {
                self?.copyCompactSummaryForTestFlight()
            }
        }
        event(
            level: .notice, category: .diagnostics, code: "boot",
            message: "diagnostics installed")
    }

    func event(
        level: DiagnosticLevel,
        category: DiagnosticCategory,
        code: String,
        message: String,
        fields: [String: String] = [:],
        error: Error? = nil,
        includeStack: Bool = false
    ) {
        var fields = fields
        if let error {
            fields["error"] = String(describing: error)
        }
        if includeStack || level == .error || level == .fault {
            fields["stack"] = currentStack()
        }
        let event = DiagnosticEvent(
            level: level, category: category, code: code,
            message: PrivacyRedactor.redact(message),
            fields: fields.mapValues { PrivacyRedactor.redact($0) })
        let line = event.journalLine
        switch level {
        case .debug: log.debug("\(line, privacy: .public)")
        case .info: log.info("\(line, privacy: .public)")
        case .notice: log.notice("\(line, privacy: .public)")
        case .warning: log.warning("\(line, privacy: .public)")
        case .error: log.error("\(line, privacy: .public)")
        case .fault: log.fault("\(line, privacy: .public)")
        }
        if level.persistsToJournal {
            ControlLiveLog.appendRedacted(line)
        }
        if level == .error || level == .fault {
            appendException(line)
        }
    }

    func record(error: Error, category: DiagnosticCategory, code: String, message: String) {
        event(
            level: .error, category: category, code: code, message: message,
            error: error, includeStack: true)
    }

    func beginInterval(_ name: StaticString) -> OSSignpostIntervalState {
        signposter.beginInterval(name)
    }

    func endInterval(_ name: StaticString, _ state: OSSignpostIntervalState) {
        signposter.endInterval(name, state)
    }

    @MainActor
    func environment(session: CameraSession) -> DiagnosticEnvironment {
        let info = Bundle.main.infoDictionary
        let family = session.connectedCamera?.model.family
        let familyName: String
        switch family {
        case .pocket: familyName = "pocket"
        case .nano: familyName = "nano"
        case .other: familyName = "other"
        case nil: familyName = "none"
        }
        let phase: String
        switch session.phase {
        case .idle: phase = "idle"
        case .scanning: phase = "scanning"
        case .connectingGatt: phase = "connectingGatt"
        case .pairing: phase = "pairing"
        case .awaitingApproval: phase = "awaitingApproval"
        case .readingWifiCreds: phase = "readingWifiCreds"
        case .joiningWifi: phase = "joiningWifi"
        case .openingDatalink: phase = "openingDatalink"
        case .live: phase = "live"
        case .failed: phase = "failed"
        }
        return DiagnosticEnvironment(
            appVersion: info?["CFBundleShortVersionString"] as? String ?? "0",
            appBuild: info?["CFBundleVersion"] as? String ?? "0",
            osName: "iOS",
            osVersion: ProcessInfo.processInfo.operatingSystemVersionString,
            deviceModel: Self.machineIdentifier,
            cameraFamily: familyName,
            cameraModel: session.connectedCamera?.model.name ?? "none",
            phase: phase,
            vpnActive: LocalVPNProbe.isActive())
    }

    @MainActor
    func writeReport(session: CameraSession) -> URL? {
        let env = environment(session: session)
        let journal = ControlLiveLog.recentLines()
        let exceptions = Self.readLines(Self.exceptionsURL)
        let extras = Self.metricKitExtras()
        let body = DiagnosticReport.fullReport(
            environment: env, journal: journal, exceptions: exceptions, extras: extras)
        guard let dir = Self.diagnosticsDirectory else { return nil }
        let name = "report.txt"
        let url = dir.appendingPathComponent(name)
        try? body.write(to: url, atomically: true, encoding: .utf8)
        event(
            level: .notice, category: .diagnostics, code: "report",
            message: "wrote diagnostic report")
        return url
    }

    /// Compact paste plus `report.txt` for the system share sheet.
    @MainActor
    func beginShare(session: CameraSession) -> URL? {
        copyCompactSummaryForTestFlight(session: session)
        return writeReport(session: session)
    }

    @MainActor
    func compactSummary(session: CameraSession) -> String {
        DiagnosticReport.compactSummary(
            environment: environment(session: session),
            recent: ControlLiveLog.recentLines())
    }

    @MainActor
    func copyCompactSummaryForTestFlight(session: CameraSession? = nil) {
        let session = session ?? AppModelDiagnosticsAnchor.session
        let text = compactSummary(session: session)
        lastCompactSummary = text
        UIPasteboard.general.string = text
        event(
            level: .notice, category: .diagnostics, code: "testflight-paste",
            message: "copied compact diagnostics for TestFlight feedback")
        onCopiedForTestFlight?()
    }

    func didReceive(_ payloads: [MXMetricPayload]) {
        persistMetricKit(kind: "metric", payloads: payloads.map { $0.jsonRepresentation() })
    }

    func didReceive(_ payloads: [MXDiagnosticPayload]) {
        persistMetricKit(kind: "diagnostic", payloads: payloads.map { $0.jsonRepresentation() })
        for payload in payloads {
            event(
                level: .error, category: .diagnostics, code: "metrickit",
                message: "MetricKit diagnostic payload received")
            _ = payload
        }
    }

    private func persistMetricKit(kind: String, payloads: [Data]) {
        guard let dir = Self.diagnosticsDirectory else { return }
        for (i, data) in payloads.enumerated() {
            let text = PrivacyRedactor.redact(String(data: data, encoding: .utf8) ?? "")
            let url = dir.appendingPathComponent("metrickit-\(kind)-\(i).json")
            try? text.write(to: url, atomically: true, encoding: .utf8)
        }
    }

    private func appendException(_ line: String) {
        guard let url = Self.exceptionsURL else { return }
        let row = Data("\(ISO8601DateFormatter().string(from: Date())) \(line)\n".utf8)
        if FileManager.default.fileExists(atPath: url.path),
            let handle = try? FileHandle(forWritingTo: url)
        {
            defer { try? handle.close() }
            _ = try? handle.seekToEnd()
            try? handle.write(contentsOf: row)
        } else {
            try? row.write(to: url)
        }
        trimExceptions()
    }

    private func trimExceptions() {
        guard let url = Self.exceptionsURL,
            let existing = try? String(contentsOf: url, encoding: .utf8)
        else { return }
        var lines = existing.split(whereSeparator: \.isNewline).map(String.init)
        if lines.count > DiagnosticReport.exceptionCap {
            lines = Array(lines.suffix(DiagnosticReport.exceptionCap))
            try? (lines.joined(separator: "\n") + "\n").write(
                to: url, atomically: true, encoding: .utf8)
        }
    }

    private func currentStack() -> String {
        PrivacyRedactor.redact(Thread.callStackSymbols.prefix(24).joined(separator: " | "))
    }

    nonisolated static func recordUncaught(_ exception: NSException) {
        let reason = PrivacyRedactor.redact(exception.reason ?? "")
        let stack = PrivacyRedactor.redact(exception.callStackSymbols.joined(separator: " | "))
        let line =
            "fault diagnostics ns-exception name=\(exception.name.rawValue) reason=\(reason) stack=\(stack)"
        ControlLiveLog.appendRedacted(line)
        if let url = exceptionsURL {
            let row = Data("\(ISO8601DateFormatter().string(from: Date())) \(line)\n".utf8)
            if FileManager.default.fileExists(atPath: url.path),
                let handle = try? FileHandle(forWritingTo: url)
            {
                defer { try? handle.close() }
                _ = try? handle.seekToEnd()
                try? handle.write(contentsOf: row)
            } else {
                try? row.write(to: url)
            }
        }
    }

    nonisolated static func readLines(_ url: URL?) -> [String] {
        guard let url, let text = try? String(contentsOf: url, encoding: .utf8) else {
            return []
        }
        return text.split(whereSeparator: \.isNewline).map(String.init)
    }

    nonisolated static func metricKitExtras() -> [(name: String, body: String)] {
        guard let dir = diagnosticsDirectory else { return [] }
        let files =
            (try? FileManager.default.contentsOfDirectory(
                at: dir, includingPropertiesForKeys: nil)) ?? []
        return files.filter { $0.lastPathComponent.hasPrefix("metrickit-") }.compactMap {
            url in
            guard let body = try? String(contentsOf: url, encoding: .utf8), !body.isEmpty else {
                return nil
            }
            return (url.lastPathComponent, body)
        }
    }

    nonisolated static var machineIdentifier: String {
        var info = utsname()
        uname(&info)
        return withUnsafePointer(to: &info.machine) { ptr in
            ptr.withMemoryRebound(to: CChar.self, capacity: 1) { String(cString: $0) }
        }
    }
}

/// Weak back-reference so screenshot handling can read the live session
/// without a DiagnosticCenter ↔ AppModel import cycle at init.
enum AppModelDiagnosticsAnchor {
    @MainActor static weak var model: AppModel?
    @MainActor static var session: CameraSession {
        model?.session ?? CameraSession()
    }
}

struct DiagnosticSharePayload: Identifiable {
    let id = UUID()
    let url: URL
}

struct DiagnosticActivityShareView: UIViewControllerRepresentable {
    let items: [Any]

    func makeUIViewController(context: Context) -> UIActivityViewController {
        UIActivityViewController(activityItems: items, applicationActivities: nil)
    }

    func updateUIViewController(_ controller: UIActivityViewController, context: Context) {}
}

private var opcPreviousUncaught: NSUncaughtExceptionHandler?

private func opcInstallUncaughtExceptionHandler() {
    opcPreviousUncaught = NSGetUncaughtExceptionHandler()
    NSSetUncaughtExceptionHandler { exception in
        DiagnosticCenter.recordUncaught(exception)
        opcPreviousUncaught?(exception)
    }
}
