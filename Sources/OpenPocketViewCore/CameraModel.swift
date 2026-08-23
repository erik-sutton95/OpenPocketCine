import Foundation

/// GATT UUIDs and DJI BLE identifiers. Strings here so the core stays free of CoreBluetooth;
/// the app wraps them in `CBUUID`.
public enum BleConstants {
    public static let serviceFFF0 = "0000FFF0-0000-1000-8000-00805F9B34FB"
    public static let charFFF4 = "0000FFF4-0000-1000-8000-00805F9B34FB"  // notify + arm-pairing
    public static let charFFF5 = "0000FFF5-0000-1000-8000-00805F9B34FB"  // command writes
    public static let cccd = "00002902-0000-1000-8000-00805F9B34FB"

    // DJI BLE company ids (Android SparseArray key form; on the wire little-endian: AA 08 / AA F7).
    public static let djiCompanyIds: Set<Int> = [0x08AA, 0xF7AA, 0xE5C0]
    public static func isDjiCompanyId(_ cid: Int) -> Bool { djiCompanyIds.contains(cid) }
}

/// Per-model camera capabilities keyed on the BLE model id. Only the datalink UDP port and WiFi
/// security actually vary across the Osmo line. Ported from Osmosis `ble/CameraModel.kt` (trimmed:
/// the Xtra-rebrand 10004/no-poke override is omitted — this prototype targets the Pocket line).
/// ponytail: add Xtra brand handling if a rebadged unit ever needs it.
public struct CameraModel: Equatable, Sendable {
    public let name: String
    public let datalinkPort: Int
    public let tcpPoke: Bool
    public let wpa3: Bool
    public let verified: Bool
    public let isDrone: Bool

    public init(
        name: String, datalinkPort: Int = 9004, tcpPoke: Bool = true,
        wpa3: Bool = false, verified: Bool = false, isDrone: Bool = false
    ) {
        self.name = name
        self.datalinkPort = datalinkPort
        self.tcpPoke = tcpPoke
        self.wpa3 = wpa3
        self.verified = verified
        self.isDrone = isDrone
    }

    /// The SetPairingPIN token this device expects: a drone only releases WiFi creds for "DJI FLY".
    public var pairingToken: String { isDrone ? "DJI FLY" : "osmo" }

    /// Pocket and Nano live-view enable is captured (`0x09/0xa8`). Action / 360 is not.
    public var usesCapturedLiveEnable: Bool {
        switch CameraBodyFamily.resolve(modelId: nil, name: name) {
        case .pocket, .nano: return true
        case .other:
            let n = name.lowercased()
            return !n.contains("action") && !n.contains("360")
        }
    }

    /// `0x09/0xa8` receiver. Nano is `0x41` (Mimo 2026-08-18); Pocket stays `0x08`.
    public var liveViewEnableReceiver: UInt8 {
        family == .nano ? 0x41 : 0x08
    }

    /// Mimo Nano pairs `0x02/0x09 …03` with enable. Pocket never sent it.
    public var usesNanoLiveViewGate: Bool { family == .nano }

    /// Pocket tap-focus burst (`0x22`/`0x30`/`0x68`/`0x32`). Nano has no AF.
    public var supportsTapFocus: Bool { family != .nano }

    /// AF-S / AF-C (`0x02/0x24`) and AF-C track (`0x8E` pid `0x3B`). Nano has neither.
    public var supportsFocusMode: Bool { family != .nano }

    public var family: CameraBodyFamily {
        CameraBodyFamily.resolve(modelId: nil, name: name)
    }

    /// The other datalink config to try when `datalinkPort` never answers (9004+poke <-> 10004).
    public func alternate() -> CameraModel {
        datalinkPort == 9004
            ? CameraModel(
                name: name, datalinkPort: 10004, tcpPoke: false, wpa3: wpa3, isDrone: isDrone)
            : CameraModel(
                name: name, datalinkPort: 9004, tcpPoke: true, wpa3: wpa3, isDrone: isDrone)
    }

    public static let `default` = CameraModel(name: "DJI Osmo camera")

    static let byId: [Int: CameraModel] = [
        0x0010: CameraModel(name: "Osmo Action 2"),
        0x0012: CameraModel(name: "Osmo Action 3"),
        0x0014: CameraModel(name: "Osmo Action 4"),
        0x0015: CameraModel(name: "Osmo Action 5 Pro", verified: true),
        0x0017: CameraModel(name: "Osmo 360", wpa3: true),
        0x0018: CameraModel(name: "Osmo Action 6", verified: true),
        0x0019: CameraModel(name: "Osmo Nano", verified: true),
        0x0020: CameraModel(name: "Osmo Pocket 3", verified: true),
        0x0021: CameraModel(name: "Osmo Pocket 4", verified: true),
        0x0022: CameraModel(name: "Osmo Pocket 4 Pro", verified: true),
        0x0070: CameraModel(
            name: "Mavic 3", datalinkPort: 9003, tcpPoke: false, verified: true, isDrone: true),
        0x007E: CameraModel(name: "DJI Neo 2", datalinkPort: 9003, tcpPoke: false, isDrone: true),
    ]

    /// Resolve by BLE model id, then by local name (the Pocket 3 sends no manufacturer data, so it
    /// only resolves by name). Unknown ids at/above 0x40 are treated as drones.
    public static func resolve(modelId: Int?, name: String?) -> CameraModel {
        if let id = modelId, let m = byId[id] { return m }
        if let id = modelId, id >= 0x40 {
            return CameraModel(
                name: name.map { "DJI drone (\($0))" } ?? "DJI drone",
                datalinkPort: 9003, tcpPoke: false, isDrone: true)
        }
        let n = (name ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        // "pocket4p" before "pocket4": the Pro's BLE name is OsmoPocket4P-XXXX.
        switch true {
        case n.contains("pocket3"), n.contains("muse"): return byId[0x0020]!
        case n.contains("pocket4p"): return byId[0x0022]!
        case n.contains("pocket4"): return byId[0x0021]!
        case n.contains("360"): return byId[0x0017]!
        case n.contains("nano"), n.contains("atto"): return byId[0x0019]!
        case n.contains("action6"): return byId[0x0018]!
        case n.contains("action5"), n.contains("edgepro"): return byId[0x0015]!
        case n.contains("action4"), n.contains("edge"): return byId[0x0014]!
        default:
            return CameraModel(name: name?.isEmpty == false ? name! : CameraModel.default.name)
        }
    }
}

/// Which Osmo line a BLE advert, saved record, or SoftAP SSID belongs to.
/// Pocket and Nano both sit on `192.168.2.1` and share DJI company-id adverts —
/// family is how we refuse the other body's Wi-Fi and GATT.
public enum CameraBodyFamily: Equatable, Sendable {
    case pocket
    case nano
    case other

    public static func resolve(modelId: Int?, name: String?) -> CameraBodyFamily {
        if let id = modelId {
            switch id {
            case 0x0020, 0x0021, 0x0022: return .pocket
            case 0x0019: return .nano
            default: break
            }
        }
        let n = (name ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        if n.contains("pocket") || n.contains("muse") { return .pocket }
        if n.contains("nano") || n.contains("atto") { return .nano }
        return .other
    }

    public static func ofSSID(_ ssid: String) -> CameraBodyFamily {
        resolve(modelId: nil, name: ssid)
    }

    /// True when GetSSID / cached SoftAP is clearly the other line (Pocket SSID on a Nano tap).
    public static func ssidConflictsWithBody(
        ssid: String, modelId: Int?, advertisedName: String
    ) -> Bool {
        let body = resolve(modelId: modelId, name: advertisedName)
        let wifi = ofSSID(ssid)
        if body == .other || wifi == .other { return false }
        return body != wifi
    }
}

/// Model id -> display name, for the scan list. From Osmosis `BleConstants.MODEL_NAMES`.
public enum ModelNames {
    public static let byId: [Int: String] = [
        0x0006: "OsmoAction", 0x0010: "OsmoAction2", 0x0012: "OsmoAction3", 0x0014: "OsmoAction4",
        0x0015: "OsmoAction5Pro", 0x0017: "Osmo360", 0x0018: "OsmoAction6", 0x0019: "OsmoNano",
        0x0020: "OsmoPocket3", 0x0021: "OsmoPocket4", 0x0022: "OsmoPocket4Pro",
        0x0070: "Mavic3", 0x007E: "Neo2",
    ]
}
