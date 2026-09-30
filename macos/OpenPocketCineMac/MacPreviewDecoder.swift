import CoreMedia
import CoreVideo
import Foundation
import OpenPocketViewCore
import os
import VideoToolbox

/// One VideoToolbox decode session per camera. Pocket 3 is HEVC and Nano is AVC.
///
/// Decode stays off the main thread. The shared assembler keeps about two seconds
/// of access units, then drops the GOP until a new keyframe. Pocket does not send
/// periodic keyframes, so a main-thread decoder that falls behind freezes on the
/// last picture while record commands still work. A lost GOP asks for one new
/// keyframe, then one retry, and stops.
@MainActor
final class MacPreviewDecoder {
    var onPicture: ((CVPixelBuffer) -> Void)?
    var onPresented: (() -> Void)?
    var onNeedsKeyframe: (() -> Void)?
    private(set) var hasPicture = false

    private let engine = Engine()
    private var loggedPicture = false

    init() {
        engine.onFrame = { [weak self] in
            Task { @MainActor [weak self] in
                self?.drainFrames()
            }
        }
        engine.onNeedsKeyframe = { [weak self] in
            Task { @MainActor [weak self] in
                self?.onNeedsKeyframe?()
            }
        }
    }

    func reset() {
        engine.reset()
        hasPicture = false
        loggedPicture = false
    }

    /// Returns immediately. The access unit is decoded on the preview queue.
    func submit(accessUnit: [UInt8]) {
        engine.submit(accessUnit)
    }

    /// The assembler discarded frames that later pictures depend on.
    func noteReferenceLoss() {
        engine.noteReferenceLoss()
    }

    private func drainFrames() {
        while let frame = engine.nextFrame() {
            show(frame)
        }
    }

    private func show(_ buffer: CVPixelBuffer) {
        if !loggedPicture {
            loggedPicture = true
            ControlLiveLog.line(
                "mac preview: first picture \(CVPixelBufferGetWidth(buffer))x\(CVPixelBufferGetHeight(buffer))"
            )
        }
        hasPicture = true
        onPicture?(buffer)
        onPresented?()
    }
}

/// VideoToolbox state for one tile. Every method that touches the session runs on `queue`,
/// except the decompression callback, which only copies a frame or hops back onto `queue`.
private final class Engine: @unchecked Sendable {
    var onFrame: (() -> Void)?
    var onNeedsKeyframe: (() -> Void)?

    private let queue = DispatchQueue(label: "opv.mac.preview", qos: .userInteractive)
    private var codec: LiveVideoCodec?
    private var vps: [UInt8]?
    private var sps: [UInt8]?
    private var pps: [UInt8]?
    private var format: CMVideoFormatDescription?
    private var builtVPS: [UInt8]?
    private var builtSPS: [UInt8]?
    private var builtPPS: [UInt8]?
    private var session: VTDecompressionSession?
    private var sawRandomAccess = false
    private var frameIndex: Int64 = 0
    private let presented = OSAllocatedUnfairLock(initialState: false)
    private var lastKeyframeRequest = Date.distantPast
    private var unansweredKeyframes = 0
    private var keyframeToken = 0
    private let sessionGeneration = OSAllocatedUnfairLock(initialState: 0)
    private let mailbox = OSAllocatedUnfairLock(initialState: Mailbox())

    private static let keyframeInterval: TimeInterval = 2
    private static let maxKeyframeRequests = 2

    func submit(_ accessUnit: [UInt8]) {
        let unit = accessUnit
        queue.async { [weak self] in
            self?.decode(unit)
        }
    }

    func noteReferenceLoss() {
        queue.async { [weak self] in
            self?.requestKeyframe(reason: "discontinuity")
        }
    }

    func reset() {
        queue.sync {
            invalidateSession()
            codec = nil
            vps = nil
            sps = nil
            pps = nil
            format = nil
            builtVPS = nil
            builtSPS = nil
            builtPPS = nil
            sawRandomAccess = false
            frameIndex = 0
            lastKeyframeRequest = .distantPast
            unansweredKeyframes = 0
            keyframeToken += 1
        }
        presented.withLock { $0 = false }
        mailbox.withLock { $0 = Mailbox() }
    }

    private func decode(_ accessUnit: [UInt8]) {
        var slices: [[UInt8]] = []
        let nals = Hevc.nalUnits(accessUnit)
        if codec == nil { codec = LiveVideo.detect(nals: nals) }
        guard let codec else { return }
        let avc = codec == .avc
        var randomAccess = false
        for nal in nals where !nal.isEmpty {
            if avc {
                let type = Avc.nalType(nal[0])
                if type == Avc.idr { randomAccess = true }
                switch type {
                case Avc.sps: sps = nal
                case Avc.pps:
                    pps = nal
                    buildFormat()
                case let kind where Avc.isVCL(kind): slices.append(nal)
                default: break
                }
            } else {
                let type = Hevc.nalType(nal[0])
                if Hevc.isIRAP(type) { randomAccess = true }
                switch type {
                case Hevc.vps: vps = nal
                case Hevc.sps: sps = nal
                case Hevc.pps:
                    pps = nal
                    buildFormat()
                case let kind where Hevc.isVCL(kind): slices.append(nal)
                default: break
                }
            }
        }
        guard randomAccess || sawRandomAccess, !slices.isEmpty, let format,
            let sample = sampleBuffer(slices, format), ensureSession(format)
        else { return }
        let generation = sessionGeneration.withLock { $0 }
        var flags = VTDecodeInfoFlags()
        let status = VTDecompressionSessionDecodeFrame(
            session!, sampleBuffer: sample, flags: [._EnableAsynchronousDecompression],
            infoFlagsOut: &flags
        ) { [weak self] status, _, imageBuffer, _, _ in
            guard let self, self.sessionGeneration.withLock({ $0 }) == generation else { return }
            guard status == noErr, let imageBuffer else {
                self.queue.async { [weak self] in
                    guard let self, self.sessionGeneration.withLock({ $0 }) == generation else { return }
                    self.invalidateSession()
                    self.requestKeyframe(reason: "decode \(status)")
                }
                return
            }
            self.publish(imageBuffer)
        }
        if status != noErr {
            invalidateSession()
            requestKeyframe(reason: "submit \(status)")
            return
        }
        if randomAccess {
            sawRandomAccess = true
            keyframeToken += 1
            unansweredKeyframes = 0
        }
    }

    /// After a picture exists, one lost GOP gets an enable and a single retry.
    /// Further enables wait for another loss. Nothing is sent before the first picture.
    private func requestKeyframe(reason: String) {
        guard presented.withLock({ $0 }) else { return }
        let now = Date()
        guard now.timeIntervalSince(lastKeyframeRequest) >= Self.keyframeInterval else { return }
        guard unansweredKeyframes < Self.maxKeyframeRequests else { return }
        unansweredKeyframes += 1
        lastKeyframeRequest = now
        sawRandomAccess = false
        let token = keyframeToken
        let attempt = unansweredKeyframes
        ControlLiveLog.line("mac preview: keyframe reason=\(reason) attempt=\(attempt)")
        onNeedsKeyframe?()
        guard attempt == 1 else { return }
        queue.asyncAfter(deadline: .now() + Self.keyframeInterval) { [weak self] in
            guard let self, self.keyframeToken == token else { return }
            self.requestKeyframe(reason: "unanswered")
        }
    }

    private func publish(_ source: CVPixelBuffer) {
        presented.withLock { $0 = true }
        let buffer = Self.copyBGRA(source) ?? source
        let start = mailbox.withLock { box -> Bool in
            box.latest = buffer
            if box.busy { return false }
            box.busy = true
            return true
        }
        guard start else { return }
        onFrame?()
    }

    /// Main-thread display pump. Returns the newest copied frame, or nil when idle.
    fileprivate func nextFrame() -> CVPixelBuffer? {
        mailbox.withLock { box in
            let frame = box.latest
            box.latest = nil
            if frame == nil { box.busy = false }
            return frame
        }
    }

    private func ensureSession(_ format: CMFormatDescription) -> Bool {
        if session != nil { return true }
        let attributes: [String: Any] = [
            kCVPixelBufferPixelFormatTypeKey as String: Int(kCVPixelFormatType_32BGRA),
            kCVPixelBufferIOSurfacePropertiesKey as String: [:] as [String: Any],
        ]
        var created: VTDecompressionSession?
        let status = VTDecompressionSessionCreate(
            allocator: kCFAllocatorDefault, formatDescription: format, decoderSpecification: nil,
            imageBufferAttributes: attributes as CFDictionary, outputCallback: nil,
            decompressionSessionOut: &created)
        guard status == noErr, let created else { return false }
        VTSessionSetProperty(created, key: kVTDecompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        session = created
        return true
    }

    private func invalidateSession() {
        sessionGeneration.withLock { $0 += 1 }
        if let session { VTDecompressionSessionInvalidate(session) }
        session = nil
    }

    private func buildFormat() {
        if codec == .avc {
            guard let sps, let pps, format == nil || sps != builtSPS || pps != builtPPS else { return }
            sps.withUnsafeBufferPointer { s in
                pps.withUnsafeBufferPointer { p in
                    let pointers = [s.baseAddress!, p.baseAddress!]
                    let sizes = [sps.count, pps.count]
                    var description: CMFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromH264ParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 2,
                        parameterSetPointers: pointers, parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4, formatDescriptionOut: &description)
                    if status == noErr, let description {
                        adopt(description, vps: nil, sps: sps, pps: pps)
                    }
                }
            }
            return
        }
        guard let vps, let sps, let pps,
            format == nil || vps != builtVPS || sps != builtSPS || pps != builtPPS
        else { return }
        vps.withUnsafeBufferPointer { v in
            sps.withUnsafeBufferPointer { s in
                pps.withUnsafeBufferPointer { p in
                    let pointers = [v.baseAddress!, s.baseAddress!, p.baseAddress!]
                    let sizes = [vps.count, sps.count, pps.count]
                    var description: CMFormatDescription?
                    let status = CMVideoFormatDescriptionCreateFromHEVCParameterSets(
                        allocator: kCFAllocatorDefault, parameterSetCount: 3,
                        parameterSetPointers: pointers, parameterSetSizes: sizes,
                        nalUnitHeaderLength: 4, extensions: nil, formatDescriptionOut: &description)
                    if status == noErr, let description {
                        adopt(description, vps: vps, sps: sps, pps: pps)
                    }
                }
            }
        }
    }

    private func adopt(
        _ description: CMFormatDescription, vps: [UInt8]?, sps: [UInt8], pps: [UInt8]
    ) {
        format = description
        builtVPS = vps
        builtSPS = sps
        builtPPS = pps
        sawRandomAccess = false
        invalidateSession()
    }

    private func sampleBuffer(_ nals: [[UInt8]], _ format: CMVideoFormatDescription) -> CMSampleBuffer? {
        var bytes: [UInt8] = []
        for nal in nals {
            var length = UInt32(nal.count).bigEndian
            withUnsafeBytes(of: &length) { bytes.append(contentsOf: $0) }
            bytes.append(contentsOf: nal)
        }
        var block: CMBlockBuffer?
        guard
            CMBlockBufferCreateWithMemoryBlock(
                allocator: kCFAllocatorDefault, memoryBlock: nil, blockLength: bytes.count,
                blockAllocator: kCFAllocatorDefault, customBlockSource: nil, offsetToData: 0,
                dataLength: bytes.count, flags: 0, blockBufferOut: &block) == kCMBlockBufferNoErr,
            let block
        else { return nil }
        let copied = bytes.withUnsafeBytes { raw in
            CMBlockBufferReplaceDataBytes(
                with: raw.baseAddress!, blockBuffer: block, offsetIntoDestination: 0,
                dataLength: bytes.count)
        }
        guard copied == kCMBlockBufferNoErr else { return nil }
        frameIndex += 1
        var timing = CMSampleTimingInfo(
            duration: CMTime(value: 1, timescale: 60_000),
            presentationTimeStamp: CMTime(value: frameIndex, timescale: 60_000),
            decodeTimeStamp: .invalid)
        var sample: CMSampleBuffer?
        var sizes = [bytes.count]
        guard
            CMSampleBufferCreateReady(
                allocator: kCFAllocatorDefault, dataBuffer: block, formatDescription: format,
                sampleCount: 1, sampleTimingEntryCount: 1, sampleTimingArray: &timing,
                sampleSizeEntryCount: 1, sampleSizeArray: &sizes, sampleBufferOut: &sample) == noErr,
            let sample
        else { return nil }
        return sample
    }

    /// The decoder reuses its output buffers. Keep an independent BGRA copy for the layer
    /// so a recycled buffer cannot pin the pool or freeze the last picture in place.
    private static func copyBGRA(_ source: CVPixelBuffer) -> CVPixelBuffer? {
        let format = CVPixelBufferGetPixelFormatType(source)
        guard format == kCVPixelFormatType_32BGRA else { return nil }
        let width = CVPixelBufferGetWidth(source)
        let height = CVPixelBufferGetHeight(source)
        guard width > 0, height > 0 else { return nil }
        let attrs: [CFString: Any] = [
            kCVPixelBufferPixelFormatTypeKey: format,
            kCVPixelBufferIOSurfacePropertiesKey: [:] as [CFString: Any],
            kCVPixelBufferMetalCompatibilityKey: true,
        ]
        var dest: CVPixelBuffer?
        guard
            CVPixelBufferCreate(
                kCFAllocatorDefault, width, height, format, attrs as CFDictionary, &dest
            ) == kCVReturnSuccess,
            let dest
        else { return nil }
        guard CVPixelBufferLockBaseAddress(source, .readOnly) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(source, .readOnly) }
        guard CVPixelBufferLockBaseAddress(dest, []) == kCVReturnSuccess else { return nil }
        defer { CVPixelBufferUnlockBaseAddress(dest, []) }
        guard let srcBase = CVPixelBufferGetBaseAddress(source),
            let dstBase = CVPixelBufferGetBaseAddress(dest)
        else { return nil }
        let srcRow = CVPixelBufferGetBytesPerRow(source)
        let dstRow = CVPixelBufferGetBytesPerRow(dest)
        let rowBytes = min(srcRow, dstRow)
        let src = srcBase.bindMemory(to: UInt8.self, capacity: srcRow * height)
        let dst = dstBase.bindMemory(to: UInt8.self, capacity: dstRow * height)
        for y in 0..<height {
            (dst + y * dstRow).update(from: src + y * srcRow, count: rowBytes)
        }
        return dest
    }
}

private struct Mailbox {
    var latest: CVPixelBuffer?
    var busy = false
}
