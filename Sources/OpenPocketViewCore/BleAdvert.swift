import Foundation

/// Decodes a DJI BLE advertisement's manufacturer payload (company id already stripped) into a
/// classic model id. Ported from Osmosis `ble/BleAdvert.kt`.
///
/// DJI ships two advert formats. The newer one leaves the classic model byte at zero and puts a
/// 16-bit product type deeper in — which is why an Osmo Pocket 4 Pro scans as `unknown(0x0000)`
/// to anything that only reads the classic byte. Selector: bit 2 of payload byte 5.
///
/// iOS note: `CBAdvertisementDataManufacturerDataKey` gives the raw value with the 2-byte company
/// id little-endian first. Strip those two bytes before calling `decode`.
public enum BleAdvert {
    /// DJI ProductType -> classic model id (shipping products only, from Osmosis).
    static let productTypeToModelId: [Int: Int] = [
        40: 0x0006, 143: 0x0010, 231: 0x0012, 203: 0x0014, 235: 0x0015,
        224: 0x0017, 223: 0x0018, 222: 0x0019, 145: 0x0020, 219: 0x0021,
        218: 0x0022, 229: 0x0087,
    ]

    public struct Decoded: Equatable {
        public let modelId: Int?
        public let newFormat: Bool
        public let rawProductType: Int?
    }

    /// `payload` = manufacturer-specific data for a DJI company id, company id already stripped.
    public static func decode(_ payload: [UInt8]) -> Decoded {
        if let pt = productType(payload) {
            let mapped = productTypeToModelId[pt]
            // A product type we can read but haven't mapped is still worth reporting as new-format:
            // the classic byte is zero here, so falling back would only ever say unknown(0x0000).
            if mapped != nil || legacyModelId(payload) == nil {
                return Decoded(modelId: mapped, newFormat: true, rawProductType: pt)
            }
        }
        return Decoded(
            modelId: legacyModelId(payload), newFormat: false, rawProductType: productType(payload))
    }

    public static func modelId(_ payload: [UInt8]) -> Int? { decode(payload).modelId }

    private static let newFormatFlagIndex = 5
    private static let newFormatFlagMask: UInt8 = 0x04
    private static let productTypeIndex = 10

    private static func productType(_ p: [UInt8]) -> Int? {
        guard p.count > newFormatFlagIndex, (p[newFormatFlagIndex] & newFormatFlagMask) != 0 else {
            return nil
        }
        guard p.count >= productTypeIndex + 2 else { return nil }
        return Int(p[productTypeIndex]) | (Int(p[productTypeIndex + 1]) << 8)
    }

    private static func legacyModelId(_ p: [UInt8]) -> Int? {
        guard p.count >= 2 else { return nil }
        let id = Int(p[0]) | (Int(p[1]) << 8)
        return id == 0 ? nil : id  // zero is what the new format leaves behind, not a model
    }
}
