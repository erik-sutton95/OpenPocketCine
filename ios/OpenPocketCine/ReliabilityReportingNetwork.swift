import Foundation
import OpenCineAppKit

// The reporting network policy (camera-path gate, DSN host policy, envelope event ID, backoff) is
// OpenCineAppKit's; this file is its adapter to the Sentry SDK's own URLSession.

extension ReliabilityReportingGate {
    /// The camera network this app's cameras serve.
    static let shared = ReliabilityReportingGate(cameraIPv4Prefix: "192.168.2.")
}

final class ReliabilityReportingTaskBox: ReliabilityReportingCancellable {
    var inner: URLSessionDataTask?
    func cancel() { inner?.cancel() }
}

/// Intercepts only the dedicated Sentry URLSession. Never registered globally.
final class ReliabilityReportingURLProtocol: URLProtocol, @unchecked Sendable {
    static var gate: ReliabilityReportingGate = .shared
    static var dsnHost: String?
    static var onEnvelopeAccepted: ((String) -> Void)?
    static let redirectGuard = ReliabilityReportingRedirectGuard {
        ReliabilityReportingURLProtocol.dsnHost
    }
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
        let materialized = ReliabilityReportingEnvelopeID.materialized(request)
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
