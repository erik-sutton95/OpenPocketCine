import Darwin
import Foundation
import zlib

/// Camera-path gate for the Sentry URLSession only. Not registered globally.
final class ReliabilityReportingGate: @unchecked Sendable {
    static let shared = ReliabilityReportingGate()

    private let lock = NSLock()
    private var cameraSessionActive = false
    private var ipv4Override: Bool?
    private var validInternet = true
    private var pending: [ReliabilityReportingCancellable] = []

    var isCameraSessionActive: Bool {
        lock.lock()
        defer { lock.unlock() }
        return cameraSessionActive
    }

    /// Blocks SDK upload while a camera session is live or the camera IPv4 path is up,
    /// including when cellular internet is also available.
    var shouldBlockUpload: Bool {
        lock.lock()
        let session = cameraSessionActive
        let override = ipv4Override
        lock.unlock()
        let ipv4 = override ?? Self.cameraIPv4PathReady()
        return session || ipv4
    }

    var hasValidInternet: Bool {
        lock.lock()
        defer { lock.unlock() }
        return validInternet
    }

    func setCameraSessionActive(_ active: Bool) {
        lock.lock()
        cameraSessionActive = active
        let toCancel = active ? pending : []
        if active { pending.removeAll(keepingCapacity: true) }
        lock.unlock()
        if active {
            for task in toCancel { task.cancel() }
        }
    }

    func setCameraIPv4PathReadyForTests(_ ready: Bool?) {
        lock.lock()
        ipv4Override = ready
        lock.unlock()
        if ready == true {
            cancelPending()
        }
    }

    func setValidInternetForTests(_ ready: Bool) {
        lock.lock()
        validInternet = ready
        lock.unlock()
    }

    func register(_ task: ReliabilityReportingCancellable) {
        lock.lock()
        pending.append(task)
        let blockNow = cameraSessionActive || (ipv4Override ?? false)
        lock.unlock()
        if blockNow || shouldBlockUpload { task.cancel() }
    }

    func unregister(_ task: ReliabilityReportingCancellable) {
        lock.lock()
        pending.removeAll { $0 === task }
        lock.unlock()
    }

    func cancelPending(includeIndependent: Bool = true) {
        lock.lock()
        let toCancel = pending.filter { includeIndependent || !$0.independentOfAutomaticConsent }
        pending.removeAll { includeIndependent || !$0.independentOfAutomaticConsent }
        lock.unlock()
        for task in toCancel { task.cancel() }
    }

    func resetForTests() {
        lock.lock()
        cameraSessionActive = false
        ipv4Override = false
        validInternet = true
        let toCancel = pending
        pending.removeAll()
        lock.unlock()
        for task in toCancel { task.cancel() }
    }

    static func cameraIPv4PathReady() -> Bool {
        var list: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&list) == 0 else { return false }
        defer { freeifaddrs(list) }
        var cursor = list
        while let iface = cursor {
            if let addr = iface.pointee.ifa_addr, addr.pointee.sa_family == sa_family_t(AF_INET) {
                var host = [CChar](repeating: 0, count: Int(NI_MAXHOST))
                let length = socklen_t(
                    max(Int(addr.pointee.sa_len), MemoryLayout<sockaddr_in>.size))
                if getnameinfo(addr, length, &host, socklen_t(host.count), nil, 0, NI_NUMERICHOST)
                    == 0
                {
                    let ip = String(cString: host)
                    if ip.hasPrefix("192.168.2.") { return true }
                }
            }
            cursor = iface.pointee.ifa_next
        }
        return false
    }
}

protocol ReliabilityReportingCancellable: AnyObject {
    func cancel()
    var independentOfAutomaticConsent: Bool { get }
}

extension ReliabilityReportingCancellable {
    var independentOfAutomaticConsent: Bool { false }
}

extension URLSessionTask: ReliabilityReportingCancellable {}

enum ReliabilityReportingHostPolicy {
    static func host(fromDSN dsn: String) -> String? {
        URL(string: dsn)?.host
    }

    static func allows(_ url: URL, dsnHost: String?) -> Bool {
        guard let host = url.host, !host.isEmpty else { return false }
        guard url.scheme?.lowercased() == "https" else { return false }
        if let dsnHost, host.caseInsensitiveCompare(dsnHost) == .orderedSame {
            return true
        }
        return false
    }
}

enum ReliabilityReportingLoadDecision: Equatable {
    case forward
    case blockCameraPath
    case rejectHost
    case noInternet
}

enum ReliabilityReportingNetwork {
    static func decision(
        for url: URL?,
        dsnHost: String?,
        gate: ReliabilityReportingGate
    ) -> ReliabilityReportingLoadDecision {
        guard let url else { return .rejectHost }
        if gate.shouldBlockUpload { return .blockCameraPath }
        guard ReliabilityReportingHostPolicy.allows(url, dsnHost: dsnHost) else {
            return .rejectHost
        }
        if !gate.hasValidInternet { return .noInternet }
        return .forward
    }

    /// Fail the SDK request without an HTTP response so envelopes stay cached.
    static func retentionError(for decision: ReliabilityReportingLoadDecision) -> URLError {
        switch decision {
        case .blockCameraPath, .noInternet, .forward:
            return URLError(.notConnectedToInternet)
        case .rejectHost:
            return URLError(.cannotFindHost)
        }
    }
}

final class ReliabilityReportingTaskBox: ReliabilityReportingCancellable {
    var inner: URLSessionDataTask?
    func cancel() { inner?.cancel() }
}

/// Rejects hops off the DSN host so auth and attachments cannot follow a 3xx.
final class ReliabilityReportingRedirectGuard: NSObject, URLSessionTaskDelegate {
    static func shouldFollow(url: URL?, dsnHost: String?) -> Bool {
        guard let url else { return false }
        return ReliabilityReportingHostPolicy.allows(url, dsnHost: dsnHost)
    }

    func urlSession(
        _ session: URLSession,
        task: URLSessionTask,
        willPerformHTTPRedirection response: HTTPURLResponse,
        newRequest request: URLRequest,
        completionHandler: @escaping (URLRequest?) -> Void
    ) {
        if Self.shouldFollow(url: request.url, dsnHost: ReliabilityReportingURLProtocol.dsnHost) {
            completionHandler(request)
        } else {
            completionHandler(nil)
        }
    }
}

enum ReliabilityReportingEnvelopeID {
    static let maxHeaderBytes = 16 * 1_024
    static let maxBodyCopyBytes = 2 * 1_024 * 1_024

    static func eventID(from request: URLRequest) -> String? {
        let encoding = request.value(forHTTPHeaderField: "Content-Encoding")
        let body: Data?
        if let data = request.httpBody, !data.isEmpty {
            body = data
        } else if let stream = request.httpBodyStream {
            body = readStream(stream, limit: maxBodyCopyBytes)
        } else {
            body = nil
        }
        return eventID(fromBody: body, contentEncoding: encoding)
    }

    static func eventID(fromBody body: Data?, contentEncoding: String?) -> String? {
        guard let body, !body.isEmpty else { return nil }
        guard let header = envelopeHeaderLine(from: body, contentEncoding: contentEncoding) else {
            return nil
        }
        guard
            let object = try? JSONSerialization.jsonObject(with: header) as? [String: Any],
            let raw = object["event_id"] as? String
        else { return nil }
        let hex = raw.filter(\.isHexDigit).lowercased()
        return hex.count == 32 ? hex : nil
    }

    static func envelopeHeaderLine(from body: Data, contentEncoding: String?) -> Data? {
        let encoding = contentEncoding?.lowercased() ?? ""
        let gzipMagic = body.count >= 2 && body[0] == 0x1F && body[1] == 0x8B
        let treatAsGzip = encoding.contains("gzip") || (gzipMagic && encoding.isEmpty)
        let decoded: Data?
        if treatAsGzip {
            decoded = ReliabilityReportingGzip.inflateHeader(from: body, maxOutput: maxHeaderBytes)
        } else if body.count <= maxHeaderBytes {
            decoded = body
        } else {
            decoded = body.prefix(maxHeaderBytes)
        }
        guard let decoded, !decoded.isEmpty else { return nil }
        if let newline = decoded.firstIndex(of: 0x0A) {
            return decoded.prefix(upTo: newline)
        }
        return decoded.count < maxHeaderBytes ? decoded : nil
    }

    static func readStream(_ stream: InputStream, limit: Int) -> Data? {
        if stream.streamStatus == .notOpen { stream.open() }
        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 4_096)
        defer { stream.close() }
        while true {
            let n = stream.read(
                &buffer, maxLength: min(buffer.count, max(1, limit + 1 - data.count)))
            if n < 0 { return nil }
            if n == 0 { break }
            data.append(buffer, count: n)
            if data.count > limit { return nil }
        }
        return data
    }
}

enum ReliabilityReportingGzip {
    /// Inflate gzip until a newline or `maxOutput` bytes. Does not decode the rest of the envelope.
    static func inflateHeader(from data: Data, maxOutput: Int) -> Data? {
        guard data.count >= 2, maxOutput > 0 else { return nil }
        var stream = z_stream()
        let initStatus = inflateInit2_(
            &stream, 16 + MAX_WBITS, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { inflateEnd(&stream) }

        var output = Data()
        let status = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(min(data.count, Int(uInt.max)))
            var rc: Int32 = Z_OK
            while output.count < maxOutput && rc != Z_STREAM_END {
                let room = min(256, maxOutput - output.count)
                var buf = [UInt8](repeating: 0, count: room)
                rc = buf.withUnsafeMutableBytes { dest -> Int32 in
                    guard let outBase = dest.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_MEM_ERROR
                    }
                    stream.next_out = outBase
                    stream.avail_out = uInt(room)
                    return inflate(&stream, Z_NO_FLUSH)
                }
                let produced = room - Int(stream.avail_out)
                if produced > 0 {
                    output.append(contentsOf: buf.prefix(produced))
                    if output.contains(0x0A) { return Z_STREAM_END }
                }
                if rc == Z_BUF_ERROR { break }
                if rc != Z_OK && rc != Z_STREAM_END { return rc }
                if stream.avail_in == 0 { break }
            }
            return rc
        }
        if output.isEmpty { return nil }
        if status != Z_OK && status != Z_STREAM_END && !output.contains(0x0A) { return nil }
        return output
    }

    static func deflateForTests(_ data: Data) -> Data? {
        guard !data.isEmpty else { return nil }
        var stream = z_stream()
        let initStatus = deflateInit2_(
            &stream, Z_DEFAULT_COMPRESSION, Z_DEFLATED, 16 + MAX_WBITS, 8, Z_DEFAULT_STRATEGY,
            ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
        guard initStatus == Z_OK else { return nil }
        defer { deflateEnd(&stream) }
        var output = Data()
        let rc = data.withUnsafeBytes { raw -> Int32 in
            guard let base = raw.bindMemory(to: Bytef.self).baseAddress else { return Z_DATA_ERROR }
            stream.next_in = UnsafeMutablePointer(mutating: base)
            stream.avail_in = uInt(data.count)
            var status: Int32 = Z_OK
            while status != Z_STREAM_END {
                var buf = [UInt8](repeating: 0, count: 256)
                status = buf.withUnsafeMutableBytes { dest -> Int32 in
                    guard let outBase = dest.bindMemory(to: Bytef.self).baseAddress else {
                        return Z_MEM_ERROR
                    }
                    stream.next_out = outBase
                    stream.avail_out = 256
                    return deflate(&stream, Z_FINISH)
                }
                let produced = 256 - Int(stream.avail_out)
                if produced > 0 { output.append(contentsOf: buf.prefix(produced)) }
                if status != Z_OK && status != Z_STREAM_END { return status }
            }
            return status
        }
        guard rc == Z_STREAM_END, !output.isEmpty else { return nil }
        return output
    }
}

/// Intercepts only the dedicated Sentry URLSession. Never registered globally.
final class ReliabilityReportingURLProtocol: URLProtocol, @unchecked Sendable {
    static var gate: ReliabilityReportingGate = .shared
    static var dsnHost: String?
    static var onEnvelopeAccepted: ((String) -> Void)?
    static let redirectGuard = ReliabilityReportingRedirectGuard()
    static var forwardingSession: URLSession = makeForwardingSession()

    private var forwardingTask: ReliabilityReportingTaskBox?
    private var pendingEventID: String?

    static func makeForwardingSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        return URLSession(
            configuration: config, delegate: redirectGuard, delegateQueue: nil)
    }

    /// Copy stream bodies onto `httpBody` so parse does not consume the forwarded payload.
    static func materialized(_ request: URLRequest) -> (URLRequest, Data?) {
        if let body = request.httpBody, !body.isEmpty {
            return (request, body)
        }
        guard let stream = request.httpBodyStream,
            let data = ReliabilityReportingEnvelopeID.readStream(
                stream, limit: ReliabilityReportingEnvelopeID.maxBodyCopyBytes)
        else {
            return (request, nil)
        }
        var copy = request
        copy.httpBodyStream = nil
        copy.httpBody = data
        return (copy, data)
    }

    override class func canInit(with request: URLRequest) -> Bool { true }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        guard ReliabilityReportingConsent.isOptedIn else {
            failWithoutResponse(URLError(.notConnectedToInternet))
            return
        }
        let decision = ReliabilityReportingNetwork.decision(
            for: request.url, dsnHost: Self.dsnHost, gate: Self.gate)
        if decision != .forward {
            failWithoutResponse(ReliabilityReportingNetwork.retentionError(for: decision))
            return
        }
        let materialized = Self.materialized(request)
        if request.httpBodyStream != nil, materialized.1 == nil {
            failWithoutResponse(URLError(.dataLengthExceedsMaximum))
            return
        }
        pendingEventID = ReliabilityReportingEnvelopeID.eventID(
            fromBody: materialized.1,
            contentEncoding: request.value(forHTTPHeaderField: "Content-Encoding"))
        let box = ReliabilityReportingTaskBox()
        let dataTask = Self.forwardingSession.dataTask(with: materialized.0) {
            [weak self, weak box] data, response, error in
            guard let self else { return }
            if let box { Self.gate.unregister(box) }
            if Self.gate.shouldBlockUpload || !ReliabilityReportingConsent.isOptedIn {
                self.failWithoutResponse(URLError(.notConnectedToInternet))
                return
            }
            if let error, (error as NSError).code == NSURLErrorCancelled {
                self.failWithoutResponse(URLError(.notConnectedToInternet))
                return
            }
            if response == nil {
                self.failWithoutResponse(error ?? URLError(.notConnectedToInternet))
                return
            }
            if let response {
                self.client?.urlProtocol(
                    self, didReceive: response, cacheStoragePolicy: .notAllowed)
                if let http = response as? HTTPURLResponse,
                    (200..<300).contains(http.statusCode),
                    let eventID = self.pendingEventID
                {
                    Self.onEnvelopeAccepted?(eventID)
                }
            }
            if let data { self.client?.urlProtocol(self, didLoad: data) }
            if let error {
                self.client?.urlProtocol(self, didFailWithError: error)
            } else {
                self.client?.urlProtocolDidFinishLoading(self)
            }
        }
        box.inner = dataTask
        forwardingTask = box
        Self.gate.register(box)
        if Self.gate.shouldBlockUpload || !ReliabilityReportingConsent.isOptedIn {
            box.cancel()
            failWithoutResponse(URLError(.notConnectedToInternet))
            return
        }
        dataTask.resume()
    }

    override func stopLoading() {
        forwardingTask?.cancel()
        if let forwardingTask { Self.gate.unregister(forwardingTask) }
        forwardingTask = nil
    }

    private func failWithoutResponse(_ error: Error) {
        client?.urlProtocol(self, didFailWithError: error)
    }

    static func makeSDKSession() -> URLSession {
        let config = URLSessionConfiguration.ephemeral
        config.protocolClasses = [ReliabilityReportingURLProtocol.self]
        config.waitsForConnectivity = false
        config.timeoutIntervalForRequest = 20
        return URLSession(configuration: config)
    }
}

enum ReliabilityReportingBackoff {
    static func delaySeconds(attempt: Int, jitter: Double) -> TimeInterval {
        let exponent = Double(min(6, max(0, attempt)))
        let base = min(30, pow(2, exponent) * 0.5)
        let spread = min(1, max(0, jitter))
        return min(30, max(0.25, base * (0.7 + 0.6 * spread)))
    }
}
