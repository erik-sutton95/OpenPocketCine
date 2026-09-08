import CoreMedia
import CoreVideo
import Foundation
import OpenPocketViewCore
import VideoToolbox

/// HEVC re-encode of identity live buffers. Keyframes come from this session, never `0x09/0xa8`.
final class WatcherRelayEncoder: @unchecked Sendable {
    private let queue = DispatchQueue(label: "opc.watcher-relay.encode", qos: .userInitiated)
    var bitsPerSecond: Int = WatcherRelayBitrate.ladder[0] {
        didSet {
            guard bitsPerSecond != oldValue else { return }
            let next = bitsPerSecond
            queue.async {
                self.targetBitrate = next
                self.applyBitrateLocked()
            }
        }
    }
    private var targetBitrate = WatcherRelayBitrate.ladder[0]
    private var session: VTCompressionSession?
    private var width = 0
    private var height = 0
    private var keyPolicy = WatcherRelayEncodePolicy()

    func invalidate() {
        queue.async {
            if let session = self.session { VTCompressionSessionInvalidate(session) }
            self.session = nil
            self.width = 0
            self.height = 0
        }
    }

    /// The transport holds its admission slot through the output callback, not just submission.
    func encode(
        _ buffer: CVPixelBuffer, forceKey: Bool,
        completion: @escaping (Annex?, Bool) -> Void
    ) {
        queue.async { [self] in
            let w = CVPixelBufferGetWidth(buffer)
            let h = CVPixelBufferGetHeight(buffer)
            guard w > 8, h > 8 else {
                completion(nil, true)
                return
            }
            if session == nil || w != width || h != height { rebuildLocked(width: w, height: h) }
            guard let session else {
                completion(nil, true)
                return
            }
            let now = ProcessInfo.processInfo.systemUptime
            let key = keyPolicy.forceKeyframe(requested: forceKey, now: now)
            let props = key ? [kVTEncodeFrameOptionKey_ForceKeyFrame: true] as CFDictionary : nil
            let pts = CMTime(value: CMTimeValue(now * 90_000), timescale: 90_000)
            let output = Output(completion)
            var info = VTEncodeInfoFlags()
            let status = VTCompressionSessionEncodeFrame(
                session, imageBuffer: buffer, presentationTimeStamp: pts, duration: .invalid,
                frameProperties: props, infoFlagsOut: &info,
                outputHandler: { status, _, sample in
                    output.finish(sample.flatMap(Self.annexB), failed: status != noErr)
                })
            if status != noErr || info.contains(.frameDropped) {
                output.finish(nil, failed: status != noErr)
            }
        }
    }

    /// VT may complete on another thread, including before EncodeFrame returns.
    private final class Output: @unchecked Sendable {
        private let lock = NSLock()
        private var completion: ((Annex?, Bool) -> Void)?
        init(_ completion: @escaping (Annex?, Bool) -> Void) { self.completion = completion }
        func finish(_ value: Annex?, failed: Bool) {
            lock.lock()
            let callback = completion
            completion = nil
            lock.unlock()
            callback?(value, failed)
        }
    }

    private func rebuildLocked(width: Int, height: Int) {
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        self.width = width
        self.height = height
        var sess: VTCompressionSession?
        let status = VTCompressionSessionCreate(
            allocator: nil,
            width: Int32(width),
            height: Int32(height),
            codecType: kCMVideoCodecType_HEVC,
            encoderSpecification: nil,
            imageBufferAttributes: nil,
            compressedDataAllocator: nil,
            outputCallback: nil,
            refcon: nil,
            compressionSessionOut: &sess)
        guard status == noErr, let sess else { return }
        VTSessionSetProperty(sess, key: kVTCompressionPropertyKey_RealTime, value: kCFBooleanTrue)
        VTSessionSetProperty(
            sess, key: kVTCompressionPropertyKey_ProfileLevel,
            value: kVTProfileLevel_HEVC_Main_AutoLevel)
        VTSessionSetProperty(
            sess, key: kVTCompressionPropertyKey_ExpectedFrameRate, value: 25 as CFNumber)
        VTSessionSetProperty(
            sess, key: kVTCompressionPropertyKey_MaxKeyFrameInterval, value: 50 as CFNumber)
        VTSessionSetProperty(
            sess, key: kVTCompressionPropertyKey_AllowFrameReordering, value: kCFBooleanFalse)
        // The admission window is two frames. VT must emit before it needs a third.
        VTSessionSetProperty(
            sess, key: kVTCompressionPropertyKey_MaxFrameDelayCount,
            value: 1 as CFNumber)
        session = sess
        applyBitrateLocked()
        VTCompressionSessionPrepareToEncodeFrames(sess)
    }

    private func applyBitrateLocked() {
        guard let session else { return }
        let bps = targetBitrate as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps)
        let bytes = Int64(targetBitrate / 8) as CFNumber
        VTSessionSetProperty(
            session, key: kVTCompressionPropertyKey_DataRateLimits,
            value: [bytes, 1] as CFArray)
    }

    struct Annex {
        var data: Data
        var isKey: Bool
        var sets: [Data]?
    }

    private static func annexB(from sample: CMSampleBuffer) -> Annex? {
        guard let block = CMSampleBufferGetDataBuffer(sample) else { return nil }
        var length = 0
        var pointer: UnsafeMutablePointer<Int8>?
        guard
            CMBlockBufferGetDataPointer(
                block, atOffset: 0, lengthAtOffsetOut: nil, totalLengthOut: &length,
                dataPointerOut: &pointer) == noErr, let pointer, length > 4
        else { return nil }
        let bytes = UnsafeRawPointer(pointer).assumingMemoryBound(to: UInt8.self)
        var out = Data()
        var offset = 0
        while offset + 4 <= length {
            let n =
                Int(bytes[offset]) << 24 | Int(bytes[offset + 1]) << 16
                | Int(bytes[offset + 2]) << 8 | Int(bytes[offset + 3])
            offset += 4
            guard n > 0, offset + n <= length else { break }
            out.append(contentsOf: [0, 0, 0, 1])
            out.append(UnsafeBufferPointer(start: bytes + offset, count: n))
            offset += n
        }
        var isKey = true
        if let atts = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [Any],
            let dict = atts.first as? [NSString: Any]
        {
            isKey = (dict[kCMSampleAttachmentKey_NotSync] as? Bool) != true
        }
        var sets: [Data] = []
        if isKey, let desc = CMSampleBufferGetFormatDescription(sample) {
            var count = 0
            CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                desc, parameterSetIndex: 0, parameterSetPointerOut: nil,
                parameterSetSizeOut: nil, parameterSetCountOut: &count,
                nalUnitHeaderLengthOut: nil)
            for i in 0..<count {
                var ptr: UnsafePointer<UInt8>?
                var size = 0
                CMVideoFormatDescriptionGetHEVCParameterSetAtIndex(
                    desc, parameterSetIndex: i, parameterSetPointerOut: &ptr,
                    parameterSetSizeOut: &size, parameterSetCountOut: nil,
                    nalUnitHeaderLengthOut: nil)
                if let ptr, size > 0 { sets.append(Data(bytes: ptr, count: size)) }
            }
        }
        if isKey {
            var prefixed = Data()
            for set in sets {
                prefixed.append(contentsOf: [0, 0, 0, 1])
                prefixed.append(set)
            }
            prefixed.append(out)
            out = prefixed
        }
        return Annex(data: out, isKey: isKey, sets: sets.isEmpty ? nil : sets)
    }
}
