import Foundation
import OpenPocketViewCore
import Sentry
import SwiftUI
import UIKit

/// Explicit, one-off feedback. Never starts the automatic SDK or changes its consent.
@MainActor @Observable final class ProblemReporting {
    static let shared = ProblemReporting()
    static let maximumStoredBytes = 5_000_000
    static let lifetime: TimeInterval = 7 * 24 * 60 * 60
    private(set) var pending: Pending?
    private(set) var status = ""
    private var upload: URLSessionDataTask?
    private var uploadToken: UUID?
    private var registeredUpload: ReliabilityReportingCancellable?
    private let file: URL
    private let session: URLSession
    private let dsnProvider: () -> String?
    private let isForeground: () -> Bool

    struct Pending: Codable {
        let id: String
        let created: Date
        let dsn: String
        let envelope: Data
        var attempts = 0
        var nextAttempt = Date.distantPast
        var failed = false
        var accepted = false
    }

    init(
        directory: URL? = nil,
        dsnProvider: @escaping () -> String? = ReliabilityReportingDSN.configured,
        sessionConfiguration: URLSessionConfiguration? = nil,
        isForeground: @escaping () -> Bool = { UIApplication.shared.applicationState == .active }
    ) {
        self.dsnProvider = dsnProvider
        self.isForeground = isForeground
        let root =
            directory
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("PrivateSupport", isDirectory: true)
        file = root.appendingPathComponent("pending.json")
        let configuration = sessionConfiguration ?? URLSessionConfiguration.ephemeral
        configuration.httpCookieStorage = nil
        configuration.urlCache = nil
        configuration.timeoutIntervalForRequest = 60
        configuration.timeoutIntervalForResource = 120
        session = URLSession(
            configuration: configuration, delegate: ProblemReportingRedirects(), delegateQueue: nil)
        if let data = try? Data(contentsOf: file), data.count < Self.maximumStoredBytes {
            pending = try? JSONDecoder().decode(Pending.self, from: data)
        }
        if pending != nil { status = "Waiting to send" }
    }

    static func envelope(
        id: String, message: String, email: String, diagnostics: String?, date: Date,
        images: [ProblemReportImage] = []
    ) throws -> Data {
        let feedback = SentryFeedback(
            message: message, name: nil, email: email.isEmpty ? nil : email, source: .custom)
        var event: [String: Any] = [
            "event_id": id, "type": "feedback", "platform": "cocoa",
            "timestamp": ISO8601DateFormatter().string(from: date),
            "contexts": ["feedback": feedback.serialize()],
        ]
        event["release"] = ReliabilityReportingConfiguration.release()
        event["environment"] = ReliabilityReportingConfiguration.environment
        event["dist"] = ReliabilityReportingConfiguration.build
        event["tags"] = [
            "sourceRevision": Bundle.main.object(forInfoDictionaryKey: "OPCSourceRevision")
                as? String ?? "unknown"
        ]
        func json(_ value: [String: Any]) throws -> Data {
            try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
        }
        let body = try json(event)
        var output = try json(["event_id": id])
        output.append(10)
        output.append(try json(["type": "feedback", "length": body.count]))
        output.append(10)
        output.append(body)
        output.append(10)
        if let diagnostics {
            let attachment = Data(PrivacyRedactor.redact(String(diagnostics.prefix(32_000))).utf8)
            output.append(
                try json([
                    "type": "attachment", "length": attachment.count,
                    "filename": "diagnostics.txt", "content_type": "text/plain",
                    "attachment_type": "event.attachment",
                ]))
            output.append(10)
            output.append(attachment)
            output.append(10)
        }
        guard images.count <= ProblemReportImage.maximumCount,
            images.allSatisfy({
                !$0.jpeg.isEmpty && $0.jpeg.count <= ProblemReportImage.maximumBytes
            })
        else { throw Failure.invalid }
        for (index, image) in images.enumerated() {
            output.append(
                try json([
                    "type": "attachment", "length": image.jpeg.count,
                    "filename": "image-\(index + 1).jpg", "content_type": "image/jpeg",
                    "attachment_type": "event.attachment",
                ]))
            output.append(10)
            output.append(image.jpeg)
            output.append(10)
        }
        return output
    }

    static func endpoint(dsn: String) -> URL? {
        guard ReliabilityReportingDSN.validated(dsn) != nil, var parts = URLComponents(string: dsn)
        else { return nil }
        let project = parts.path.split(separator: "/").last!
        let prefix = parts.path.split(separator: "/").dropLast().joined(separator: "/")
        let key = parts.user!
        parts.user = nil
        parts.password = nil
        parts.path = (prefix.isEmpty ? "" : "/" + prefix) + "/api/\(project)/envelope/"
        parts.queryItems = [
            URLQueryItem(name: "sentry_key", value: key),
            URLQueryItem(name: "sentry_version", value: "7"),
        ]
        return parts.url
    }

    func submit(
        message: String, email: String, diagnostics: String?, images: [ProblemReportImage] = []
    ) throws {
        guard pending == nil else { throw Failure.pending }
        let message = message.trimmingCharacters(in: .whitespacesAndNewlines)
        let email = email.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !message.isEmpty, message.count <= 4_000, email.count <= 254,
            email.isEmpty || (email.contains("@") && !email.contains(where: { $0.isWhitespace }))
        else { throw Failure.invalid }
        guard let dsn = dsnProvider(), Self.endpoint(dsn: dsn) != nil else {
            throw Failure.unavailable
        }
        let id = UUID().uuidString.replacingOccurrences(of: "-", with: "").lowercased()
        let now = Date()
        let record = Pending(
            id: id, created: now, dsn: dsn,
            envelope: try Self.envelope(
                id: id, message: message, email: email, diagnostics: diagnostics, date: now,
                images: images))
        try persist(record)
        pending = record
        status = "Waiting to send"
        tick()
    }

    private func cancelUpload() {
        uploadToken = nil
        if let registeredUpload { ReliabilityReportingGate.shared.unregister(registeredUpload) }
        registeredUpload = nil
        upload?.cancel()
        upload = nil
    }

    func discard() throws {
        cancelUpload()
        if FileManager.default.fileExists(atPath: file.path) {
            try FileManager.default.removeItem(at: file)
        }
        pending = nil
        status = "Report removed from this phone"
    }

    private func finishAccepted(_ record: Pending) {
        pending = record
        do {
            try persist(record)
            try discard()
            status = "Report sent. Thank you for helping improve OpenPocketCine."
        } catch {
            status = "Report received, but the local copy couldn't be removed."
        }
    }

    /// Called while the app exists, but sends only in the foreground and off camera Wi-Fi.
    func tick(now: Date = Date()) {
        guard let record = pending else { return }
        if now.timeIntervalSince(record.created) >= Self.lifetime {
            do {
                try discard()
                status = "Report expired before it could be sent. Please create a new report."
            } catch { status = "Couldn't remove the expired report. Please try again." }
            return
        }
        if record.accepted {
            finishAccepted(record)
            return
        }
        let gate = ReliabilityReportingGate.shared
        guard isForeground(), !gate.shouldBlockUpload else {
            cancelUpload()
            status = "Waiting to send — keep the app open after leaving camera Wi-Fi"
            return
        }
        guard !record.failed else {
            status =
                "Report couldn't be sent. Remove it and try again, or contact support@openpocketcine.app."
            return
        }
        guard upload == nil, now >= record.nextAttempt, gate.hasValidInternet,
            let url = Self.endpoint(dsn: record.dsn)
        else { return }
        var request = URLRequest(url: url)
        request.httpMethod = "POST"
        request.setValue("application/x-sentry-envelope", forHTTPHeaderField: "Content-Type")
        request.httpBody = record.envelope
        let token = UUID()
        let task = session.dataTask(with: request) { [weak self] _, response, error in
            Task { @MainActor in
                self?.finished(
                    id: record.id, token: token, response: response as? HTTPURLResponse,
                    error: error)
            }
        }
        upload = task
        uploadToken = token
        let registered = ManualReportUpload(task: task)
        registeredUpload = registered
        gate.register(registered)
        guard !gate.shouldBlockUpload else {
            cancelUpload()
            return
        }
        status = "Sending report…"
        task.resume()
    }

    private func finished(id: String, token: UUID, response: HTTPURLResponse?, error: Error?) {
        guard uploadToken == token else { return }
        if let registeredUpload { ReliabilityReportingGate.shared.unregister(registeredUpload) }
        registeredUpload = nil
        upload = nil
        uploadToken = nil
        guard var record = pending, record.id == id else { return }
        if error == nil, let response, (200..<300).contains(response.statusCode) {
            record.accepted = true
            finishAccepted(record)
            return
        }
        if (error as? URLError)?.code == .cancelled {
            status = "Waiting to send"
            return
        }
        record.attempts += 1
        let code = response?.statusCode ?? 0
        record.failed = error == nil && code >= 300 && code < 500 && code != 408 && code != 429
        let retry = Self.retryDelay(response: response, attempts: record.attempts)
        record.nextAttempt = Date().addingTimeInterval(retry)
        do { try persist(record) } catch { record.failed = true }
        pending = record
        status =
            record.failed
            ? "Report couldn't be sent. Remove it and try again, or contact support@openpocketcine.app."
            : "Waiting for a connection — your report is saved on this phone"
    }

    static func retryDelay(response: HTTPURLResponse?, attempts: Int) -> TimeInterval {
        let backoff = min(300, 30 * pow(2, Double(min(attempts, 4))))
        if let raw = response?.value(forHTTPHeaderField: "Retry-After") {
            if let seconds = Double(raw), seconds.isFinite { return max(backoff, seconds) }
            let parser = DateFormatter()
            parser.locale = Locale(identifier: "en_US_POSIX")
            parser.dateFormat = "EEE, dd MMM yyyy HH:mm:ss z"
            if let date = parser.date(from: raw) { return max(backoff, date.timeIntervalSinceNow) }
        }
        return backoff
    }

    private func persist(_ record: Pending) throws {
        var directory = file.deletingLastPathComponent()
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        var values = URLResourceValues()
        values.isExcludedFromBackup = true
        try directory.setResourceValues(values)
        let bytes = try JSONEncoder().encode(record)
        guard bytes.count < Self.maximumStoredBytes else { throw Failure.tooLarge }
        try bytes.write(to: file, options: [.atomic, .completeFileProtection])
    }

    enum Failure: LocalizedError {
        case pending, invalid, unavailable, tooLarge
        var errorDescription: String? {
            switch self {
            case .tooLarge: "This report is too large. Remove an image or shorten the description and try again."
            case .pending: "A report is already waiting to send."
            case .invalid: "Describe what happened and check your optional email address."
            case .unavailable:
                "Reporting isn't available in this build. Contact support@openpocketcine.app."
            }
        }
    }
}

private final class ProblemReportingRedirects: NSObject, URLSessionTaskDelegate {
    func urlSession(
        _ session: URLSession, task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse, newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) { completionHandler(nil) }
}

private final class ManualReportUpload: ReliabilityReportingCancellable {
    let task: URLSessionTask
    init(task: URLSessionTask) { self.task = task }
    var independentOfAutomaticConsent: Bool { true }
    func cancel() { task.cancel() }
}
