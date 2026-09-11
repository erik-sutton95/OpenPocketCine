import Testing

@testable import OpenPocketViewCore

@Suite struct DumlNotificationAssemblerTests {
    private var frame: Duml.Frame {
        Duml.Frame(
            sender: 7, receiver: 2, seq: 1, flags: 0x40, cmdSet: 7, cmdId: 0xac,
            payload: [UInt8](repeating: 0x33, count: 391))
    }
    @Test func networkReportSpansNotifications() {
        let bytes = Duml.encode(frame)
        for cut in 1..<bytes.count {
            var reader = DumlNotificationAssembler()
            #expect(reader.append(Array(bytes.prefix(cut))).isEmpty)
            let frames = reader.append(Array(bytes.dropFirst(cut)))
            #expect(frames.count == 1)
            #expect(frames.first?.payload == frame.payload)
        }
    }
    @Test func multipleFramesAndBadCRCResynchronize() {
        var reader = DumlNotificationAssembler()
        let good = Duml.encode(frame)
        var bad = good
        bad[bad.count - 1] ^= 1
        let frames = reader.append([0, 1, 2] + bad + good + good)
        #expect(frames.count == 2)
    }
}
