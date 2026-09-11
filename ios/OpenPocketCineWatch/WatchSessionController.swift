import Foundation
import OpenPocketViewCore
import SwiftUI
import UIKit
import WatchConnectivity

/// watchOS-side WatchConnectivity client. Decodes relay envelopes from the iPhone
/// into an observable model, and sends Record / shutter commands with a reply.
@MainActor
@Observable
final class WatchSessionController: NSObject {
    private(set) var feedImage: UIImage?
    private(set) var frameTimecode: String?
    private(set) var state: WatchRelayState?
    private(set) var isReachable = false
    private(set) var isSendingCommand = false
    private(set) var commandMessage: String?

    @ObservationIgnored private let session: WCSession? =
        WCSession.isSupported() ? .default : nil

    func activate() {
        guard let session else { return }
        session.delegate = self
        if session.activationState != .activated {
            session.activate()
        }
        isReachable = session.isReachable
        ingestApplicationContext(session.receivedApplicationContext)
        #if targetEnvironment(simulator)
            if feedImage == nil { feedImage = Self.sampleFrame }
        #endif
    }

    func resume() {
        activate()
        guard let session, session.isReachable else { return }
        guard
            let data = try? WatchRelayEnvelope.encode(
                kind: .command, payload: WatchRelayCommand.resume)
        else { return }
        session.sendMessageData(
            data, replyHandler: { @Sendable _ in }, errorHandler: { @Sendable _ in })
    }

    func sendCapture() {
        send(.capture)
    }

    func sendToggleRecord() {
        send(.toggleRecord)
    }

    private func send(_ command: WatchRelayCommand) {
        guard let session, session.isReachable, !isSendingCommand else { return }
        guard
            let data = try? WatchRelayEnvelope.encode(kind: .command, payload: command)
        else { return }
        isSendingCommand = true
        commandMessage = nil
        session.sendMessageData(
            data,
            replyHandler: { @Sendable reply in
                Task { @MainActor [weak self] in self?.handleCommandReply(reply) }
            },
            errorHandler: { @Sendable _ in
                Task { @MainActor [weak self] in self?.isSendingCommand = false }
            })
    }

    private func handleCommandReply(_ data: Data) {
        isSendingCommand = false
        guard let kind = try? WatchRelayEnvelope.kind(of: data), kind == .result else { return }
        guard
            let result = try? WatchRelayEnvelope.decode(WatchCommandResult.self, from: data)
        else { return }
        commandMessage = result.error
        if let current = state {
            state = current.replacing(isRecording: result.isRecording)
        }
    }

    private func ingest(_ data: Data) {
        guard let kind = try? WatchRelayEnvelope.kind(of: data) else { return }
        switch kind {
        case .state:
            if let decoded = try? WatchRelayEnvelope.decode(WatchRelayState.self, from: data) {
                state = decoded
            }
        case .frame:
            if let frame = try? WatchRelayEnvelope.decode(WatchRelayFrame.self, from: data) {
                frameTimecode = frame.timecode
                if let image = UIImage(data: frame.jpeg) {
                    feedImage = image
                }
            }
        case .command, .result:
            break
        }
    }

    private func ingestApplicationContext(_ context: [String: Any]) {
        guard let data = context[WatchRelayContext.stateKey] as? Data else { return }
        ingest(data)
    }

    #if targetEnvironment(simulator)
        private static let sampleFrame: UIImage? = {
            let size = CGSize(width: 320, height: 180)
            let colorSpace = CGColorSpaceCreateDeviceRGB()
            guard
                let ctx = CGContext(
                    data: nil,
                    width: Int(size.width),
                    height: Int(size.height),
                    bitsPerComponent: 8,
                    bytesPerRow: 0,
                    space: colorSpace,
                    bitmapInfo: CGImageAlphaInfo.premultipliedLast.rawValue)
            else { return nil }
            let colors =
                [
                    CGColor(srgbRed: 0.10, green: 0.10, blue: 0.12, alpha: 1),
                    CGColor(srgbRed: 0.18, green: 0.42, blue: 0.55, alpha: 1),
                ] as CFArray
            guard
                let gradient = CGGradient(
                    colorsSpace: colorSpace, colors: colors, locations: [0, 1])
            else { return nil }
            ctx.drawLinearGradient(
                gradient,
                start: .zero,
                end: CGPoint(x: size.width, y: size.height),
                options: [])
            guard let cg = ctx.makeImage() else { return nil }
            return UIImage(cgImage: cg)
        }()
    #endif
}

extension WatchSessionController: WCSessionDelegate {
    nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        Task { @MainActor [weak self] in
            self?.isReachable = WCSession.default.isReachable
        }
    }

    nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        Task { @MainActor [weak self] in
            self?.isReachable = WCSession.default.isReachable
        }
    }

    nonisolated func session(_ session: WCSession, didReceiveMessageData messageData: Data) {
        Task { @MainActor [weak self] in self?.ingest(messageData) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveMessageData messageData: Data,
        replyHandler: @escaping (Data) -> Void
    ) {
        replyHandler(Data())
        Task { @MainActor [weak self] in self?.ingest(messageData) }
    }

    nonisolated func session(
        _ session: WCSession,
        didReceiveApplicationContext applicationContext: [String: Any]
    ) {
        let data = applicationContext[WatchRelayContext.stateKey] as? Data
        Task { @MainActor [weak self] in
            guard let data else { return }
            self?.ingest(data)
        }
    }
}
