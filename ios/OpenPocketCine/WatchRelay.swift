import CoreImage
import CoreVideo
import Foundation
import OpenPocketViewCore
import UIKit
import VideoToolbox

/// Reservations cover encoding and transport together. Invalidating a preview
/// generation drops its results, but its work keeps a slot until completion.
struct WatchPreviewPump {
    struct Ticket: Hashable, Sendable {
        fileprivate let generation: UInt64
        fileprivate let sequence: UInt64
    }

    private var generation: UInt64 = 0
    private var sequence: UInt64 = 0
    private var outstanding: Set<Ticket> = []
    var inFlightCount: Int { outstanding.count }

    mutating func reserve() -> Ticket? {
        guard outstanding.count < 3 else { return nil }
        sequence &+= 1
        let ticket = Ticket(generation: generation, sequence: sequence)
        outstanding.insert(ticket)
        return ticket
    }

    func isCurrent(_ ticket: Ticket) -> Bool {
        ticket.generation == generation && outstanding.contains(ticket)
    }

    mutating func complete(_ ticket: Ticket) -> Bool {
        outstanding.remove(ticket) != nil
    }

    mutating func invalidate() {
        generation &+= 1
    }
}

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
                image: CIImage, source: CVPixelBuffer?, unmanaged: Bool, mirrored: Bool,
                timecode: String, isRecording: Bool
            )?
        /// Pipeline hides WatchConnectivity RTT (fps ≈ depth/RTT). One in flight
        /// capped the wrist at ~1/RTT (~8–12 fps). Encode is detached so three
        /// JPEGs actually overlap instead of serializing on MainActor.
        private var framePump = WatchPreviewPump()
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

        var hasCompanion: Bool {
            guard let session else { return false }
            return session.isPaired && session.isWatchAppInstalled
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
            mirrored: Bool = false, timecode: String, isRecording: Bool
        ) {
            guard isReady else { return }
            pendingPreview = (
                image: image, source: source, unmanaged: unmanaged, mirrored: mirrored,
                timecode: timecode, isRecording: isRecording
            )
            pumpFrames()
        }

        private func pumpFrames() {
            guard isReady, let pending = pendingPreview, let ticket = framePump.reserve()
            else { return }
            pendingPreview = nil
            let params = adaptiveEncodingParams()
            let boxed = RelaySendableBox(value: pending)
            Task.detached(priority: .userInitiated) { [weak self] in
                let data = Self.encodeFrame(
                    image: boxed.value.image,
                    source: boxed.value.source,
                    unmanaged: boxed.value.unmanaged,
                    mirrored: boxed.value.mirrored,
                    timecode: boxed.value.timecode,
                    isRecording: boxed.value.isRecording,
                    width: params.width,
                    quality: params.quality)
                await MainActor.run { [weak self] in
                    self?.dispatchFrame(data, ticket: ticket)
                }
            }
        }

        private func dispatchFrame(_ data: Data?, ticket: WatchPreviewPump.Ticket) {
            guard framePump.isCurrent(ticket), let data, isReady, let session else {
                frameAcked(ticket: ticket, sentAt: nil)
                return
            }
            let sentAt = CFAbsoluteTimeGetCurrent()
            let ack = RelaySendableBox(value: { [weak self] in
                self?.frameAcked(ticket: ticket, sentAt: sentAt)
            })
            session.sendMessageData(
                data,
                replyHandler: { @Sendable _ in Task { @MainActor in ack.value() } },
                errorHandler: { @Sendable _ in Task { @MainActor in ack.value() } })
        }

        private func frameAcked(ticket: WatchPreviewPump.Ticket, sentAt: CFAbsoluteTime?) {
            let isCurrent = framePump.isCurrent(ticket)
            guard framePump.complete(ticket) else { return }
            if isCurrent, let sentAt {
                let rtt = CFAbsoluteTimeGetCurrent() - sentAt
                if rtt > 0, rtt < 5 { rttEMA = rttEMA * 0.8 + rtt * 0.2 }
            }
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
            image: CIImage, source: CVPixelBuffer?, unmanaged: Bool, mirrored: Bool,
            timecode: String, isRecording: Bool, width: CGFloat, quality: CGFloat
        ) -> Data? {
            let jpeg: Data?
            if unmanaged {
                jpeg = thumbnailData(
                    from: image, unmanaged: true, mirrored: mirrored, maxWidth: width,
                    quality: quality)
            } else if let source {
                jpeg = thumbnailData(
                    from: source, mirrored: mirrored, maxWidth: width, quality: quality)
            } else {
                jpeg = thumbnailData(
                    from: image, unmanaged: false, mirrored: mirrored, maxWidth: width,
                    quality: quality)
            }
            guard let jpeg else { return nil }
            let frame = WatchRelayFrame(jpeg: jpeg, timecode: timecode, isRecording: isRecording)
            return try? WatchRelayEnvelope.encode(kind: .frame, payload: frame)
        }

        private func handleReachabilityChanged() {
            lastSentState = nil
            framePump.invalidate()
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
                handleReachabilityChanged()
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
            from buffer: CVPixelBuffer, mirrored: Bool = false, maxWidth: CGFloat, quality: CGFloat
        ) -> Data? {
            var imageOut: CGImage?
            let status = VTCreateCGImageFromCVPixelBuffer(buffer, options: nil, imageOut: &imageOut)
            guard status == noErr, let cg = imageOut,
                let jpeg = encodedFrameData(
                    scaledImage(cg, mirrored: mirrored, maxWidth: maxWidth), quality: quality)
            else {
                return thumbnailData(
                    from: CIImage(cvPixelBuffer: buffer), unmanaged: false, mirrored: mirrored,
                    maxWidth: maxWidth, quality: quality)
            }
            return jpeg
        }

        nonisolated static func thumbnailData(
            from image: CIImage, unmanaged: Bool = false, mirrored: Bool = false,
            maxWidth: CGFloat, quality: CGFloat
        ) -> Data? {
            let extent = image.extent
            guard extent.width > 1, extent.height > 1 else { return nil }
            let scale = min(1, maxWidth / extent.width)
            let oriented =
                mirrored
                ? image.transformed(
                    by: CGAffineTransform(
                        a: -1, b: 0, c: 0, d: 1, tx: extent.minX + extent.maxX, ty: 0))
                : image
            let scaled = oriented.transformed(by: CGAffineTransform(scaleX: scale, y: scale))
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

        nonisolated private static func scaledImage(
            _ cg: CGImage, mirrored: Bool, maxWidth: CGFloat
        ) -> UIImage {
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
            return UIGraphicsImageRenderer(size: size, format: format).image { renderer in
                if mirrored {
                    renderer.cgContext.translateBy(x: size.width, y: 0)
                    renderer.cgContext.scaleBy(x: -1, y: 1)
                }
                UIImage(cgImage: cg).draw(in: CGRect(origin: .zero, size: size))
            }
        }
    }

    extension WatchRelay: WCSessionDelegate {
        nonisolated func session(
            _ session: WCSession,
            activationDidCompleteWith activationState: WCSessionActivationState,
            error: Error?
        ) {
            Task { @MainActor [weak self] in self?.handleReachabilityChanged() }
        }

        nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

        nonisolated func sessionDidDeactivate(_ session: WCSession) {
            WCSession.default.activate()
        }

        nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
            Task { @MainActor [weak self] in self?.handleReachabilityChanged() }
        }

        nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
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
        var hasCompanion: Bool { false }
        func activate() {}
        func ingestState(_ state: WatchRelayState) {}
        func ingestPreview(
            _ image: CIImage, source: CVPixelBuffer? = nil, unmanaged: Bool = false,
            mirrored: Bool = false, timecode: String, isRecording: Bool
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
