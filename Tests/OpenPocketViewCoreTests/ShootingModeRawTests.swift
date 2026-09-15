import Foundation
import Testing

@testable import OpenPocketViewCore

/// Photo is the one shooting mode whose `0x02/0xE1` value is body-dependent — `0x17` on a
/// Pocket 4, `0x05` on a Pocket 3 / Nano — so only one of the two can be `ShootingMode.photo`.
/// Encoding through the enum dropped the other on the floor and the mode never reached the wire.
@Suite struct ShootingModeRawTests {
    @Test func rawEncodesBothPhotoEncodings() {
        #expect(Commands.setShootingMode(raw: 0x05) != nil)  // Pocket 3 / Nano
        #expect(Commands.setShootingMode(raw: 0x17) != nil)  // Pocket 4
        // The enum rawValue only carries Pocket 4; fromWire maps both to `.photo`.
        #expect(ShootingMode(rawValue: 0x05) == nil)
        #expect(ShootingMode.fromWire(0x05) == .photo)
        #expect(ShootingMode(rawValue: 0x17) == .photo)
    }

    @Test func rawEncodesEveryTabledMode() {
        for raw in ShootingMode.tabledRawValues {
            #expect(Commands.setShootingMode(raw: raw) != nil, "tabled mode \(raw) must encode")
        }
    }

    /// The refusal is the safety property: sweeping this opcode froze a Nano solid.
    @Test func rawRefusesUntabledValues() {
        for raw in [0x03, 0x04, 0x0C, 0x18, 0x99, 0xFF] as [UInt8] {
            #expect(Commands.setShootingMode(raw: raw) == nil, "untabled \(raw) must be refused")
        }
    }

    @Test func rawMatchesTheEnumFrameForSharedValues() {
        for mode in ShootingMode.allCases {
            let viaEnum = Commands.setShootingMode(mode, seq: 7)
            let viaRaw = Commands.setShootingMode(raw: mode.rawValue, seq: 7)
            #expect(viaRaw == viaEnum, "\(mode.label) must encode identically")
        }
    }
}
