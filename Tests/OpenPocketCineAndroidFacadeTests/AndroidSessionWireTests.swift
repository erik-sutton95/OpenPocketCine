import Foundation
import OpenPocketCineAndroidFacade
import OpenPocketViewCore
import Testing

@Suite
struct AndroidSessionWireTests {
    @Test
    func setExpoModeExtrasMatchIosPayload() {
        let auto = AndroidSessionWire.encodeCommand(kind: .setExpoMode, seq: 1, extra: "auto")
        let manual = AndroidSessionWire.encodeCommand(kind: .setExpoMode, seq: 1, extra: "manual")
        let rawManual = AndroidSessionWire.encodeCommand(kind: .setExpoMode, seq: 1, extra: "4")
        #expect(auto?.cmdSet == 0x02)
        #expect(auto?.cmdId == 0x1E)
        #expect(auto?.payload == [0x01, 0x00])
        #expect(manual?.payload == [0x04, 0x00])
        #expect(rawManual?.payload == [0x04, 0x00])
        #expect(auto?.payload == Commands.setExpoMode(.auto, seq: 1).payload)
        #expect(manual?.payload == Commands.setExpoMode(.manual, seq: 1).payload)
        #expect(ExpoMode.allCases.map(\.label) == ["Auto", "Manual"])
    }
}
