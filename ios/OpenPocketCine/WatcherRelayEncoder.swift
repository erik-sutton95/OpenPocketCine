import CoreMedia
import CoreVideo
import Foundation
import OpenPocketViewCore
import VideoToolbox

/// HEVC re-encode of identity live buffers. Keyframes come from this session, never `0x09/0xa8`.
final class WatcherRelayEncoder: @unchecked Sendable {
    var bitsPerSecond: Int = WatcherRelayBitrate.ladder[0] {
        didSet { applyBitrate() }
    }

    private var session: VTCompressionSession?
    private var width = 0
    private var height = 0
    private var lastKeyAt: CFAbsoluteTime = 0
    private let lock = NSLock()
    var onEncoded: ((Data, Bool, [Data]?) -> Void)?

    func invalidate() {
        lock.lock()
        defer { lock.unlock() }
        if let session {
            VTCompressionSessionInvalidate(session)
        }
        session = nil
        width = 0
        height = 0
    }

    func encode(_ buffer: CVPixelBuffer, forceKey: Bool) {
        let w = CVPixelBufferGetWidth(buffer)
        let h = CVPixelBufferGetHeight(buffer)
        guard w > 8, h > 8 else { return }
        lock.lock()
        if session == nil || w != width || h != height {
            rebuildLocked(width: w, height: h)
        }
        guard let session else {
            lock.unlock()
            return
        }
        let now = CFAbsoluteTimeGetCurrent()
        var key = forceKey
        if now - lastKeyAt >= 1, forceKey {
            lastKeyAt = now
        } else if forceKey, now - lastKeyAt < 1 {
            key = false
        } else if forceKey {
            lastKeyAt = now
        }
        var props: [NSString: Any] = [:]
        if key { props[kVTEncodeFrameOptionKey_ForceKeyFrame] = true }
        lock.unlock()
        var info = VTEncodeInfoFlags()
        let pts = CMTime(value: CMTimeValue(now * 90_000), timescale: 90_000)
        VTCompressionSessionEncodeFrame(
            session, imageBuffer: buffer, presentationTimeStamp: pts, duration: .invalid,
            frameProperties: props as CFDictionary, infoFlagsOut: &info,
            outputHandler: { [weak self] _, _, sample in
                guard let self, let sample else { return }
                if let annex = Self.annexB(from: sample) {
                    self.onEncoded?(annex.data, annex.isKey, annex.sets)
                }
            })
    }

    func requestKeyframe() {
        lastKeyAt = 0
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
        session = sess
        applyBitrateLocked()
        VTCompressionSessionPrepareToEncodeFrames(sess)
    }

    private func applyBitrate() {
        lock.lock()
        applyBitrateLocked()
        lock.unlock()
    }

    private func applyBitrateLocked() {
        guard let session else { return }
        let bps = bitsPerSecond as CFNumber
        VTSessionSetProperty(session, key: kVTCompressionPropertyKey_AverageBitRate, value: bps)
        let bytes = Int64(bitsPerSecond / 8) as CFNumber
        VTSessionSetProperty(
            session, key: kVTCompressionPropertyKey_DataRateLimits,
            value: [bytes, 1] as CFArray)
    }

    private struct Annex {
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
        var isKey = false
        if let atts = CMSampleBufferGetSampleAttachmentsArray(sample, createIfNecessary: false)
            as? [Any],
            let dict = atts.first as? [NSString: Any]
        {
            isKey = (dict[kCMSampleAttachmentKey_NotSync] as? Bool) != true
        }
        var sets: [Data] = []
        if let desc = CMSampleBufferGetFormatDescription(sample) {
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
