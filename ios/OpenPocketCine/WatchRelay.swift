import CoreImage
import CoreVideo
import Foundation
import OpenPocketViewCore
import UIKit
import VideoToolbox

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
        private var pendingPreview:
            (
                image: CIImage, source: CVPixelBuffer?, unmanaged: Bool, timecode: String,
                isRecording: Bool
            )?
        private var framesInFlight = 0
        /// Pipeline hides WatchConnectivity RTT (fps ≈ depth/RTT). One in flight
        /// capped the wrist at ~1/RTT (~8–12 fps). Encode is detached so three
        /// JPEGs actually overlap instead of serializing on MainActor.
        private static let maxFramesInFlight = 3
        private var rttEMA: TimeInterval = 0.12
        /// Rec.709 / HLG identity CI fallback. Prefer `VTCreateCGImageFromCVPixelBuffer`.
        nonisolated private static let displayContext = CIContext(
            options: LiveMonitorWorkingSpace.displayContextOptions)
        /// LUT cube product (NSNull working space). Do not sRGB-linearize it.
        nonisolated private static let lutContext = CIContext(
            options: LiveMonitorWorkingSpace.contextOptions)

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
            guard let session, session.activationState == .activated,
                let data = try? WatchRelayEnvelope.encode(kind: .state, payload: state)
            else { return }
            lastSentState = state
            // Wrist-down / Always On drops `isReachable`. Application context still
            // delivers rec, timecode, and storage without a live message session.
            try? session.updateApplicationContext([WatchRelayContext.stateKey: data])
            guard session.isReachable else { return }
            session.sendMessageData(
                data, replyHandler: nil,
                errorHandler: { @Sendable [weak self] _ in
                    Task { @MainActor in
                        if self?.lastSentState == state { self?.lastSentState = nil }
                    }
                })
        }

        /// Drop-stale preview. `source` is the VT identity buffer (nil when a LUT
        /// cube owns the picture). Pixel backing must live until encode returns.
        func ingestPreview(
            _ image: CIImage, source: CVPixelBuffer? = nil, unmanaged: Bool = false,
            timecode: String, isRecording: Bool
        ) {
            guard isReady else { return }
            pendingPreview = (
                image: image, source: source, unmanaged: unmanaged, timecode: timecode,
                isRecording: isRecording
            )
            pumpFrames()
        }

        private func pumpFrames() {
            guard framesInFlight < Self.maxFramesInFlight, isReady, let pending = pendingPreview
            else { return }
            pendingPreview = nil
            framesInFlight += 1
            let params = adaptiveEncodingParams()
            let boxed = RelaySendableBox(value: pending)
            Task.detached(priority: .userInitiated) { [weak self] in
                let data = Self.encodeFrame(
                    image: boxed.value.image,
                    source: boxed.value.source,
                    unmanaged: boxed.value.unmanaged,
                    timecode: boxed.value.timecode,
                    isRecording: boxed.value.isRecording,
                    width: params.width,
                    quality: params.quality)
                await MainActor.run { [weak self] in
                    self?.dispatchFrame(data)
                }
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
            case 0.22...: (width: 320, quality: 0.38)
            case 0.12..<0.22: (width: 416, quality: 0.42)
            default: (width: 512, quality: 0.48)
            }
        }

        nonisolated private static func encodeFrame(
            image: CIImage, source: CVPixelBuffer?, unmanaged: Bool, timecode: String,
            isRecording: Bool, width: CGFloat, quality: CGFloat
        ) -> Data? {
            let jpeg: Data?
            if unmanaged {
                jpeg = thumbnailData(
                    from: image, unmanaged: true, maxWidth: width, quality: quality)
            } else if let source {
                jpeg = thumbnailData(from: source, maxWidth: width, quality: quality)
            } else {
                jpeg = thumbnailData(
                    from: image, unmanaged: false, maxWidth: width, quality: quality)
            }
            guard let jpeg else { return nil }
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
            image.jpegData(compressionQuality: quality)
        }

        /// Identity path. Matches `AVSampleBufferDisplayLayer` better than a
        /// DeviceRGB CI bake (that bake was a visible Rec.709 contrast shift).
        nonisolated static func thumbnailData(
            from buffer: CVPixelBuffer, maxWidth: CGFloat, quality: CGFloat
        ) -> Data? {
            var imageOut: CGImage?
            let status = VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &imageOut)
            guard status == noErr, let cg = imageOut,
                let jpeg = encodedFrameData(
                    scaledImage(cg, maxWidth: maxWidth), quality: quality)
            else {
                return thumbnailData(
                    from: CIImage(cvPixelBuffer: buffer), unmanaged: false, maxWidth: maxWidth,
                    quality: quality)
            }
            return jpeg
        }

        nonisolated static func thumbnailData(
            from image: CIImage, unmanaged: Bool = false, maxWidth: CGFloat, quality: CGFloat
        ) -> Data? {
            let extent = image.extent
            guard extent.width > 1, extent.height > 1 else { return nil }
            let scale = min(1, maxWidth / extent.width)
            let scaled = image.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
            let target = scaled.extent.integral
            guard target.width > 1, target.height > 1 else { return nil }
            let cg: CGImage?
            if unmanaged {
                cg = lutContext.createCGImage(scaled, from: target)
            } else {
                let srgb =
                    CGColorSpace(name: CGColorSpace.sRGB) ?? CGColorSpaceCreateDeviceRGB()
                cg = displayContext.createCGImage(
                    scaled, from: target, format: .RGBA8, colorSpace: srgb)
            }
            guard let cg else { return nil }
            return encodedFrameData(UIImage(cgImage: cg), quality: quality)
        }

        nonisolated private static func scaledImage(_ cg: CGImage, maxWidth: CGFloat) -> UIImage {
            let width = CGFloat(cg.width)
            let height = CGFloat(cg.height)
            let scale = min(1, maxWidth / max(width, 1))
            let size = CGSize(
                width: max(1, (width * scale).rounded()),
                height: max(1, (height * scale).rounded()))
            let format = UIGraphicsImageRendererFormat()
            format.scale = 1
            format.opaque = true
            format.preferredRange = .standard
            return UIGraphicsImageRenderer(size: size, format: format).image { _ in
                UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
            }
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
        func ingestPreview(
            _ image: CIImage, source: CVPixelBuffer? = nil, unmanaged: Bool = false,
            timecode: String, isRecording: Bool
        ) {}
        nonisolated static func encodedFrameData(_ image: UIImage, quality: CGFloat) -> Data? {
            image.jpegData(compressionQuality: quality)
        }
        nonisolated static func thumbnailData(
            from image: CIImage, unmanaged: Bool = false, maxWidth: CGFloat, quality: CGFloat
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
