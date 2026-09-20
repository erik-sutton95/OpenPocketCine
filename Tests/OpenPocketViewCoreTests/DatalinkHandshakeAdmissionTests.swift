import Testing

@testable import OpenPocketViewCore

struct DatalinkHandshakeAdmissionTests {
    @Test func shortAckCannotRegisterBeforeInitialWindow() {
        var admission = DatalinkHandshakeAdmission()
        admission.reset(epoch: 1)
        admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 1)
        #expect(admission.acknowledged)
        #expect(admission.initialCommandSequence == nil)
        admission.receive(packet(type: 1, count: 34, channel: 0x6000), epoch: 1)
        #expect(admission.initialCommandSequence == 0x6008)
    }

    @Test func telemetryBeforeAckStillRequiresBothAndLatchesTheInitialWindow() {
        var admission = DatalinkHandshakeAdmission()
        admission.reset(epoch: 1)
        admission.receive(packet(type: 1, count: 34, channel: 0x6000), epoch: 1)
        #expect(admission.initialCommandSequence == nil)
        admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 1)
        admission.receive(packet(type: 1, count: 34, channel: 0x6010), epoch: 1)
        #expect(admission.initialCommandSequence == 0x6008)
    }

    @Test func longStatusAndOtherPacketTypesCannotSubstituteForWindow() {
        var admission = DatalinkHandshakeAdmission()
        admission.reset(epoch: 1)
        admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 1)
        for input in [
            packet(type: 1, count: 91, channel: 0x6000),
            packet(type: 1, count: 33, channel: 0x6000),
            packet(type: 2, count: 34, channel: 0x6000),
            packet(type: 3, count: 34, channel: 0x6000),
        ] {
            admission.receive(input, epoch: 1)
            #expect(admission.initialCommandSequence == nil)
        }
        admission.receive(packet(type: 1, count: 34, channel: 0x6000), epoch: 1)
        #expect(admission.initialCommandSequence == 0x6008)
    }

    @Test func zeroAndWraparoundAreValidWindowSequences() {
        for (channel, next): (UInt16, UInt16) in [(0, 8), (0xFFF8, 0)] {
            var admission = DatalinkHandshakeAdmission()
            admission.reset(epoch: 1)
            admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 1)
            admission.receive(packet(type: 1, count: 34, channel: channel), epoch: 1)
            #expect(admission.initialCommandSequence == next)
        }
    }

    @Test func retiredEpochCannotAcknowledgeOrSeedReplacement() {
        var admission = DatalinkHandshakeAdmission()
        admission.reset(epoch: 1)
        admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 1)
        admission.reset(epoch: 2)
        admission.receive(packet(type: 1, count: 34, channel: 0x6000), epoch: 1)
        admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 1)
        #expect(!admission.acknowledged)
        #expect(admission.initialCommandSequence == nil)
        admission.receive(packet(type: 1, count: 34, channel: 0x9000), epoch: 2)
        admission.reset(epoch: 1)
        admission.receive(packet(type: 0, count: 15, channel: 1), epoch: 2)
        #expect(admission.initialCommandSequence == 0x9008)
    }

    private func packet(type: UInt8, count: Int, channel: UInt16) -> [UInt8] {
        var bytes = [UInt8](repeating: 0, count: count)
        bytes[6] = type
        bytes[8] = UInt8(truncatingIfNeeded: channel)
        bytes[9] = UInt8(truncatingIfNeeded: channel >> 8)
        return bytes
    }
}
