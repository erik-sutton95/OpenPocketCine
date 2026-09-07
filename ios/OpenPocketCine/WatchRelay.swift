import CoreImage
import Foundation
import ImageIO
import OpenPocketViewCore
import UIKit
import UniformTypeIdentifiers

#if canImport(WatchConnectivity)
    import WatchConnectivity

    /// Carries a non-Sendable `WCSession` reply handler onto the main actor.
    private struct RelaySendableBox<Value>: @unchecked Sendable {
        let value: Value
    }

    /// iPhone-side WatchConnectivity relay for the OpenPocketCine watchOS companion.
    ///
    /// The iPhone owns the camera radio. This relay forwards a downscaled preview and a
    /// small state snapshot to a paired Apple Watch, and relays Record / shutter back.
    /// Foreground-only: no-ops when no watch is paired or reachable.
    @MainActor
    final class WatchRelay: NSObject {
        var onToggleRecord: (@MainActor () -> WatchCommandResult)?
        var onCapture: (@MainActor () -> WatchCommandResult)?
        var onReachabilityChanged: (@MainActor () -> Void)?

        private let session: WCSession?
        private var lastSentState: WatchRelayState?
        private var pendingPreview: (image: CIImage, timecode: String, isRecording: Bool)?
        private var framesInFlight = 0
        private static let maxFramesInFlight = 3
        private var rttEMA: TimeInterval = 0.15

        override init() {
            session = WCSession.isSupported() ? .default : nil
            super.init()
        }

        func activate() {
            guard let session else { return }
            session.delegate = self
            session.activate()
        }

        var isReady: Bool {
            guard let session else { return false }
            return session.activationState == .activated && session.isReachable
        }

        func ingestState(_ state: WatchRelayState) {
            guard lastSentState.map({ !state.matchesIgnoringLiveReadouts($0) }) ?? true else {
                return
            }
            guard isReady, let session,
                let data = try? WatchRelayEnvelope.encode(kind: .state, payload: state)
            else { return }
            lastSentState = state
            session.sendMessageData(
                data, replyHandler: nil,
                errorHandler: { @Sendable [weak self] _ in
                    Task { @MainActor in
                        if self?.lastSentState == state { self?.lastSentState = nil }
                    }
                })
        }

        /// Drop-stale preview. `image` must retain its pixel backing until encode runs.
        func ingestPreview(_ image: CIImage, timecode: String, isRecording: Bool) {
            guard isReady else { return }
            pendingPreview = (image: image, timecode: timecode, isRecording: isRecording)
            pumpFrames()
        }

        private func pumpFrames() {
            guard framesInFlight < Self.maxFramesInFlight, isReady, let pending = pendingPreview
            else { return }
            pendingPreview = nil
            framesInFlight += 1
            let params = adaptiveEncodingParams()
            Task { @MainActor [weak self] in
                let data = await Self.encodeFrame(
                    image: pending.image,
                    timecode: pending.timecode,
                    isRecording: pending.isRecording,
                    width: params.width,
                    quality: params.quality)
                guard let self else { return }
                self.dispatchFrame(data)
            }
        }

        private func dispatchFrame(_ data: Data?) {
            guard let data, isReady, let session else {
                frameAcked(sentAt: nil)
                return
            }
            let sentAt = CFAbsoluteTimeGetCurrent()
            let ack = RelaySendableBox(value: { [weak self] in self?.frameAcked(sentAt: sentAt) })
            session.sendMessageData(
                data,
                replyHandler: { @Sendable _ in Task { @MainActor in ack.value() } },
                errorHandler: { @Sendable _ in Task { @MainActor in ack.value() } })
        }

        private func frameAcked(sentAt: CFAbsoluteTime?) {
            if let sentAt {
                let rtt = CFAbsoluteTimeGetCurrent() - sentAt
                if rtt > 0, rtt < 5 { rttEMA = rttEMA * 0.8 + rtt * 0.2 }
            }
            framesInFlight = max(0, framesInFlight - 1)
            pumpFrames()
        }

        private func adaptiveEncodingParams() -> (width: CGFloat, quality: CGFloat) {
            switch rttEMA {
            case 0.35...: (width: 512, quality: 0.40)
            case 0.20..<0.35: (width: 672, quality: 0.45)
            default: (width: 832, quality: 0.50)
            }
        }

        private nonisolated static func encodeFrame(
            image: CIImage, timecode: String, isRecording: Bool,
            width: CGFloat, quality: CGFloat
        ) async -> Data? {
            guard let jpeg = thumbnailData(from: image, maxWidth: width, quality: quality)
            else { return nil }
            let frame = WatchRelayFrame(jpeg: jpeg, timecode: timecode, isRecording: isRecording)
            return try? WatchRelayEnvelope.encode(kind: .frame, payload: frame)
        }

        private func handleReachabilityChanged() {
            lastSentState = nil
            framesInFlight = 0
            pendingPreview = nil
            onReachabilityChanged?()
            pumpFrames()
        }

        private func handleCommand(_ data: Data) -> Data {
            let fallback = WatchCommandResult(
                accepted: false, isRecording: false, error: "unavailable")
            guard let kind = try? WatchRelayEnvelope.kind(of: data), kind == .command else {
                return (try? WatchRelayEnvelope.encode(kind: .result, payload: fallback)) ?? Data()
            }
            let result: WatchCommandResult
            let command = try? WatchRelayEnvelope.decode(WatchRelayCommand.self, from: data)
            switch command {
            case .toggleRecord:
                result = onToggleRecord.map { $0() } ?? fallback
            case .resume:
                let wasRecording = lastSentState?.isRecording ?? false
                lastSentState = nil
                framesInFlight = 0
                pendingPreview = nil
                pumpFrames()
                result = WatchCommandResult(accepted: true, isRecording: wasRecording, error: nil)
            case .capture:
                result = onCapture.map { $0() } ?? fallback
            case .none:
                result = fallback
            }
            return (try? WatchRelayEnvelope.encode(kind: .result, payload: result)) ?? Data()
        }

        nonisolated static func encodedFrameData(_ image: UIImage, quality: CGFloat) -> Data? {
            guard let cgImage = image.cgImage else {
                return image.jpegData(compressionQuality: quality)
            }
            let buffer = NSMutableData()
            guard
                let destination = CGImageDestinationCreateWithData(
                    buffer, UTType.heic.identifier as CFString, 1, nil)
            else { return image.jpegData(compressionQuality: quality) }
            CGImageDestinationAddImage(
                destination, cgImage,
                [kCGImageDestinationLossyCompressionQuality: quality] as CFDictionary)
            guard CGImageDestinationFinalize(destination), buffer.length > 0 else {
                return image.jpegData(compressionQuality: quality)
            }
            return buffer as Data
        }

        nonisolated static func thumbnailData(
            from image: CIImage, maxWidth: CGFloat, quality: CGFloat
        ) -> Data? {
            let extent = image.extent
            guard extent.width > 1, extent.height > 1 else { return nil }
            let scale = min(1, maxWidth / extent.width)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let target = scaled.extent.integral
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard target.width > 1, target.height > 1,
                let cg = context.createCGImage(scaled, from: target)
            else { return nil }
            return encodedFrameData(UIImage(cgImage: cg), quality: quality)
        }
    }

    extension WatchRelay: WCSessionDelegate {
        nonisolated func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {}

        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            WCSession.default.activate()
        }

        nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
            Task { @MainActor [weak self] in self?.handleReachabilityChanged() }
        }

        nonisolated func session(
            _ session: WCSession,
            didReceiveMessageData messageData: Data,
            replyHandler: @escaping (Data) -> Void
        ) {
            let reply = RelaySendableBox(value: replyHandler)
            Task { @MainActor [weak self] in
                let response = self?.handleCommand(messageData) ?? Data()
                reply.value(response)
            }
        }
    }

#else

    @MainActor
    final class WatchRelay: NSObject {
        var onToggleRecord: (@MainActor () -> WatchCommandResult)?
        var onCapture: (@MainActor () -> WatchCommandResult)?
        var onReachabilityChanged: (@MainActor () -> Void)?
        var isReady: Bool { false }
        func activate() {}
        func ingestState(_ state: WatchRelayState) {}
        func ingestPreview(_ image: CIImage, timecode: String, isRecording: Bool) {}
        nonisolated static func encodedFrameData(_ image: UIImage, quality: CGFloat) -> Data? {
            image.jpegData(compressionQuality: quality)
        }
        nonisolated static func thumbnailData(
            from image: CIImage, maxWidth: CGFloat, quality: CGFloat
        ) -> Data? {
            let extent = image.extent
            guard extent.width > 1, extent.height > 1 else { return nil }
            let scale = min(1, maxWidth / extent.width)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let target = scaled.extent.integral
            let context = CIContext(options: [.useSoftwareRenderer: false])
            guard target.width > 1, target.height > 1,
                let cg = context.createCGImage(scaled, from: target)
            else { return nil }
            return encodedFrameData(UIImage(cgImage: cg), quality: quality)
        }
    }

#endif
