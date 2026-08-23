import Foundation

/// Reassembles the Osmo live-view video from datalink packets. Feed it every UDP payload from the
/// datalink; it keeps the pktType-0x02 ones, groups their fragments into frames by the frame counter
/// (byte 16), and emits a complete HEVC access unit (Annex-B, DJI marker stripped) each time a frame
/// boundary is crossed. Pure — the app hands the access units to VideoToolbox.
///
/// Loss-aware: fragments within a frame carry a position (`byte18 * 2 + byte17>>7`) that increments
/// by exactly 1 (verified across a full capture). If a fragment is lost or reordered over Wi-Fi, the
/// position jumps, the frame is marked corrupt and dropped — better to skip a frame than feed a
/// broken access unit to the decoder (which stalls VideoToolbox).
///
/// One frame of latency by design: a frame is known complete only when the next frame's first
/// fragment arrives (its byte-16 counter differs). At ~25 fps that's ~40 ms.
public struct HevcDepacketizer {
    private var currentFrame: UInt8?
    private var buffer: [UInt8] = []
    private var lastPosition: Int?
    private var corrupt = false
    /// Frames dropped because a fragment was missing or reordered. Diagnostic for the live-view HUD.
    public private(set) var droppedIncomplete = 0

    public init() {}

    /// Returns a finished (and complete) access unit when `payload` starts a new frame, else nil.
    public mutating func feed(_ payload: [UInt8]) -> [UInt8]? {
        guard payload.count > 20, payload[6] == 0x02 else { return nil }  // video packets only
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
        if let last = lastPosition, position != last + 1 { corrupt = true }  // lost / reordered fragment
        lastPosition = position
        buffer.append(contentsOf: payload[20...])
        return completed
    }

    public mutating func reset() {
        currentFrame = nil
        buffer.removeAll(keepingCapacity: true)
        lastPosition = nil
        corrupt = false
        droppedIncomplete = 0
    }
}
