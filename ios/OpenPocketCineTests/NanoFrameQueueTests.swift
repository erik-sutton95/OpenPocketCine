import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class NanoFrameQueueTests: XCTestCase {
    func testNewSocketSchedulesFrameDeliveryAfterDiscardedOldHop() {
        let assembler = SoftAPVideoAssembler()
        _ = assembler.ingest(packet(0, start + [0x02, 1]))
        XCTAssertTrue(assembler.ingest(packet(1, start + [0x02, 2])).shouldHop)
        // The old main-actor hop is now rejected by the socket generation gate.
        assembler.noteRebuild()
        _ = assembler.ingest(packet(2, start + [0x02, 3]))
        XCTAssertTrue(assembler.ingest(packet(3, start + [0x02, 4])).shouldHop)
        XCTAssertEqual(assembler.takePending().count, 1)
    }

    private let start: [UInt8] = [0, 0, 0, 1]

    private func packet(_ frame: UInt8, _ nal: [UInt8]) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: 20)
        bytes[6] = 2
        bytes[16] = frame
        return bytes + nal
    }

    func testNanoBacklogPreservesParametersAndBoundsPSlices() {
        let assembler = SoftAPVideoAssembler()
        let key: [UInt8] = [0, 0, 0, 1, 0x67, 0x11, 0, 0, 0, 1, 0x68, 0x22, 0, 0, 0, 1, 0x65, 0x33]
        _ = assembler.ingest(packet(0, key))
        for frame in UInt8(1)...11 {
            _ = assembler.ingest(packet(frame, start + [0x41, frame]))
        }
        let pending = assembler.takePending()
        XCTAssertLessThanOrEqual(pending.count, 8)
        XCTAssertTrue(
            pending.contains(Hevc.stripDjiMarker(key)),
            "Nano SPS/PPS/IDR must survive an overloaded main queue")
    }

    func testNanoCodecSurvivesQueueDrainForLaterIDR() {
        let assembler = SoftAPVideoAssembler()
        _ = assembler.ingest(packet(0, start + [0x67, 1]))
        _ = assembler.ingest(packet(1, start + [0x41, 1]))
        _ = assembler.takePending()
        let idr: [UInt8] = [0, 0, 0, 1, 0x65, 0x33]
        _ = assembler.ingest(packet(2, idr))
        for frame in UInt8(3)...14 {
            _ = assembler.ingest(packet(frame, start + [0x41, frame]))
        }
        let pending = assembler.takePending()
        XCTAssertLessThanOrEqual(pending.count, 8)
        XCTAssertTrue(pending.contains(Hevc.stripDjiMarker(idr)))
    }

    func testPocketBacklogStillProtectsHEVCParameters() {
        let assembler = SoftAPVideoAssembler()
        let key: [UInt8] = [0, 0, 0, 1, 0x40, 1, 0, 0, 0, 1, 0x42, 1, 0, 0, 0, 1, 0x44, 1]
        _ = assembler.ingest(packet(0, key))
        for frame in UInt8(1)...11 {
            _ = assembler.ingest(packet(frame, start + [0x02, frame]))
        }
        let pending = assembler.takePending()
        XCTAssertLessThanOrEqual(pending.count, 8)
        XCTAssertTrue(pending.contains(Hevc.stripDjiMarker(key)))
    }
}
