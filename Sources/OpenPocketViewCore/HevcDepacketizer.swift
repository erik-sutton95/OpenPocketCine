import Foundation

/// Reassembles Osmo live video. A DJI marker carries a 16-byte header and the
/// little-endian encoded byte count. A large Nano picture spans several transport
/// groups (byte 16 changes after 63 fragments); only the declared size ends it.
/// Sized frames validate the video transport sequence and emit on their final
/// packet. Older/unsized input retains the group-boundary fallback below.
public struct HevcDepacketizer {
    private static let maxEncodedBytes = 4 * 1024 * 1024
    private var sizedMode = false
    private var expectedSize: Int?
    private var sizedBuffer: [UInt8] = []
    private var lastSizedSequence: UInt16?
    private var currentFrame: UInt8?
    private var buffer: [UInt8] = []
    private var lastPosition: Int?
    private var corrupt = false
    /// Frames dropped because a fragment was missing or reordered. Diagnostic for the live-view HUD.
    public private(set) var droppedIncomplete = 0

    public init() {}

    /// Returns a finished (and complete) access unit when its final packet arrives (or a legacy group ends).
    public mutating func feed(_ payload: [UInt8]) -> [UInt8]? {
        guard payload.count > 20, payload[6] == 0x02 else { return nil }  // video packets only
        let body = payload[20...]
        let marker = body.starts(with: [0, 0, 1, 0xff])
        let declared = Self.declaredSize(body)
        let nonzeroDeclaration =
            marker && body.count >= 16
            && body.dropFirst(4).prefix(4).contains(where: { $0 != 0 })
        if sizedMode || nonzeroDeclaration {
            if !sizedMode {
                sizedMode = true
                buffer.removeAll(keepingCapacity: false)
            }
            return feedSized(payload, body: body, marker: marker, declared: declared)
        }
        let frameNo = payload[16]
        let position = Int(payload[18]) * 2 + Int(payload[17] >> 7)  // fragment index within the frame

        var completed: [UInt8]?
        if let cur = currentFrame, cur != frameNo {
            if !buffer.isEmpty {
                if corrupt {
                    droppedIncomplete += 1
                } else {
                    completed = Hevc.stripDjiMarker(buffer)
                }
            }
            buffer.removeAll(keepingCapacity: true)
            corrupt = false
            lastPosition = nil
        }
        currentFrame = frameNo
        if let last = lastPosition {
            if position == last { return completed }  // UDP dup — do not mark the AU corrupt
            if position < last {
                // Same frameNo after a GOP restart / encoder pause. Closing the
                // leftover AU and starting over beats splicing P-frames onto it.
                if !buffer.isEmpty {
                    if corrupt {
                        droppedIncomplete += 1
                    } else {
                        completed = Hevc.stripDjiMarker(buffer)
                    }
                }
                buffer.removeAll(keepingCapacity: true)
                corrupt = false
            } else if position != last + 1 {
                corrupt = true  // lost / reordered fragment
            }
        }
        lastPosition = position
        if payload.count - 20 <= Self.maxEncodedBytes + 16 - buffer.count {
            buffer.append(contentsOf: payload[20...])
        } else {
            corrupt = true
        }
        return completed
    }

    private static func declaredSize(_ body: ArraySlice<UInt8>) -> Int? {
        guard body.count >= 16, body.starts(with: [0, 0, 1, 0xff]) else { return nil }
        let count = (0..<4).reduce(UInt32(0)) {
            $0 | (UInt32(body[body.startIndex + 4 + $1]) << ($1 * 8))
        }
        guard count > 0, count <= maxEncodedBytes else { return nil }
        return Int(count) + 16
    }

    private mutating func feedSized(
        _ packet: [UInt8], body: ArraySlice<UInt8>, marker: Bool, declared: Int?
    ) -> [UInt8]? {
        let sequence = UInt16(packet[4]) | (UInt16(packet[5]) << 8)
        if sequence == lastSizedSequence { return nil }
        if marker {
            if expectedSize != nil { droppedIncomplete += 1 }
            sizedBuffer.removeAll(keepingCapacity: true)
            expectedSize = declared
            lastSizedSequence = nil
        }
        guard let expectedSize else { return nil }
        if let last = lastSizedSequence, sequence != last &+ 8 {
            droppedIncomplete += 1
            self.expectedSize = nil
            sizedBuffer.removeAll(keepingCapacity: true)
            lastSizedSequence = sequence
            return nil
        }
        lastSizedSequence = sequence
        guard body.count <= expectedSize - sizedBuffer.count else {
            droppedIncomplete += 1
            self.expectedSize = nil
            sizedBuffer.removeAll(keepingCapacity: true)
            return nil
        }
        sizedBuffer.append(contentsOf: body)
        guard sizedBuffer.count == expectedSize else { return nil }
        let accessUnit = Array(sizedBuffer.dropFirst(16))
        sizedBuffer.removeAll(keepingCapacity: true)
        self.expectedSize = nil
        return accessUnit
    }

    public mutating func reset() {
        sizedMode = false
        expectedSize = nil
        sizedBuffer.removeAll(keepingCapacity: false)
        lastSizedSequence = nil
        currentFrame = nil
        buffer.removeAll(keepingCapacity: true)
        lastPosition = nil
        corrupt = false
        droppedIncomplete = 0
    }
}
