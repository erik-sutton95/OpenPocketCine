import Foundation

/// Exposure auto/manual. SET is `0x02/0x1E` (`mimo-settings-1`, 8 writes, all ACK `00`).
/// No GET in that capture — no empty `0x1E`, no `0x8E` pid tracks this field.
/// Current value is `cam_expo_param` `@7` (`01` auto / `04` manual; 753/753 pushes).
public enum ExpoMode: UInt8, CaseIterable, Sendable {
    case auto = 0x01
    case manual = 0x04

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .manual: "Manual"
        }
    }

    /// SET payload as captured: `01 00` auto, `04 00` manual.
    public var setPayload: [UInt8] { [rawValue, 0x00] }

    /// Unpack `cam_expo_param` — `@7` echoes the SET first byte.
    public static func parseExpoParam(_ value: [UInt8]) -> ExpoMode? {
        guard value.count > 7 else { return nil }
        return ExpoMode(rawValue: value[7])
    }
}

/// Osmosis §13a shooting-mode values. Sparse — table it, never compute. Echoed at `0x02/0x80` `@57`.
public enum ShootingMode: UInt8, CaseIterable, Sendable {
    case slowMo = 0x00
    case video = 0x01
    case timeLapse = 0x02
    case photo = 0x17  // Pocket 4 (Mimo mimo-settings-1). Nano used 0x05 → 0xEE here.
    case hyperLapse = 0x0A
    case superNight = 0x28

    public var label: String {
        switch self {
        case .slowMo: "SlowMo"
        case .video: "Video"
        case .timeLapse: "TimeLapse"
        case .photo: "Photo"
        case .hyperLapse: "HyperLapse"
        case .superNight: "SuperNight"
        }
    }

    public var isPhoto: Bool { self == .photo || self == .superNight }
}

/// Osmosis §14 / Mimo 2026-08-14 `0x02/0x8E` pids.
/// Glamour is pid `0x0039` (blob). AF-C track is pid `0x003B`.
public enum CameraParam: UInt16, Sendable {
    case fov = 0x0009
    case isoLimit = 0x000F
    case audioChannel = 0x0020
    /// Control Center Selfie Flip. Mimo GETs ~1 Hz (`00` off / `01` on).
    /// Body switch only — no app SET. Timed Flip take `mimo-flip-timed-20260825-235315`.
    case selfieFlip = 0x0038
    case glamour = 0x0039
    case focusTrack = 0x003B
    case vocalBoost = 0x004C

    /// GET reply `00 00 01 <pid u16-LE> 01 <value>`. SET ACK is a lone `00` — not this.
    public static func parseGetReply(_ payload: [UInt8]) -> (pid: UInt16, value: UInt8)? {
        guard payload.count >= 7,
            payload[0] == 0x00, payload[1] == 0x00, payload[2] == 0x01,
            payload[5] == 0x01
        else { return nil }
        let pid = UInt16(payload[3]) | (UInt16(payload[4]) << 8)
        return (pid, payload[6])
    }

    /// Untracked pid `0x38` GET reply. Must not complete audio / glamour / AF-C
    /// `0x8E` waiters — those are other pids on the same opcode.
    public static func isSelfieFlipGetReply(set: UInt8, cmd: UInt8, payload: [UInt8]) -> Bool {
        set == 0x02 && cmd == 0x8E && parseGetReply(payload)?.pid == selfieFlip.rawValue
    }

    /// GET reply `00 00 01 <pid u16-LE> <len> <blob>`. Used by glamour (`len = 0x3E`).
    public static func parseBlobReply(_ payload: [UInt8]) -> (pid: UInt16, value: [UInt8])? {
        guard payload.count >= 6,
            payload[0] == 0x00, payload[1] == 0x00, payload[2] == 0x01
        else { return nil }
        let pid = UInt16(payload[3]) | (UInt16(payload[4]) << 8)
        let len = Int(payload[5])
        guard len >= 1, payload.count >= 6 + len else { return nil }
        return (pid, Array(payload[6..<(6 + len)]))
    }
}

/// App Glamour Effects — Mimo sparkle sheet (None / Smooth / Brighten / Slim / Eyes + sliders).
/// `/tmp/mimo-glamour-20260818.pcapng` 2026-08-18. **Not** `0x02/0x68`.
public enum GlamourEffect {
    public static let pid: UInt16 = CameraParam.glamour.rawValue
    public static let blobLength = 62
    /// Value `@5`: `00` None / Off, `01` any effect on.
    public static let enableOffset = 5

    public static func blob(fromGetReply payload: [UInt8]) -> [UInt8]? {
        guard let parsed = CameraParam.parseBlobReply(payload),
            parsed.pid == pid, parsed.value.count == blobLength
        else { return nil }
        return parsed.value
    }

    public static func isEnabled(_ blob: [UInt8]) -> Bool {
        blob.count > enableOffset && blob[enableOffset] != 0
    }

    /// Same strengths, master off. Mimo None writes this (pkt#9889, #64523).
    public static func disabled(_ blob: [UInt8]) -> [UInt8]? {
        guard blob.count == blobLength else { return nil }
        var next = blob
        next[enableOffset] = 0
        return next
    }
}

/// `0x02/0x8E` pid `0x000F` — Auto ISO **ceiling**, not `IsoIndex`.
///
/// Osmosis §14 labeled SET `04` = 100–800, `05` = 100–1600. Pocket 4 Pro GET
/// replies were `07` and `09`. `camcap_iso_auto_max` publishes the full
/// ceiling list plus the color-mode base (100 or 400):
///
/// - Normal / HDR: `02 0b 00 08 02…09 64 00` → `02`–`09`, base 100
/// - D-Log: `02 07 00 04 04…07 90 01` → `04`–`07`, base 400
/// - D-Log2: `01 01 00 00` → no Auto
///
/// Ceiling = `100 << (raw − 1)`. Same raw, different base — D-Log `04` is
/// 400–800, not a second opcode. Do not treat raw as `IsoIndex`
/// (`IsoIndex` `04` is 200).
public enum IsoLimit: UInt8, CaseIterable, Sendable {
    case max200 = 0x02
    case max400 = 0x03
    case max800 = 0x04
    case max1600 = 0x05
    case max3200 = 0x06
    case max6400 = 0x07
    case max12800 = 0x08
    case max25600 = 0x09

    /// Osmosis `range800` name — same SET byte `04`.
    public static let range800 = IsoLimit.max800
    /// Osmosis `range1600` name — same SET byte `05`.
    public static let range1600 = IsoLimit.max1600

    public var ceiling: Int { 100 << Int(rawValue - 1) }

    /// Base-100 label (Osmosis Nano Rec.709). Prefer `label(base:)` in the UI.
    public var label: String { label(base: 100) }

    public func label(base: Int) -> String { "\(base)–\(ceiling)" }

    /// GET `0x8E` pid `0x000F` only when Auto ISO exists. D-Log2 has no ceiling
    /// and Pocket often leaves that GET unanswered. Unknown color = Normal.
    public static func shouldGet(colorMode: ColorMode?) -> Bool {
        (colorMode ?? .normal).offersIsoAuto
    }
}

/// Operator HUD copy for control replies. Probe GET names stay in the journal.
public enum ControlHud {
    /// Zoom / color / SET notes are a toast, not a parked chrome pill.
    public static let toastHoldSeconds: TimeInterval = 2
    public static let toastOpacity: Double = 0.72
    public static let toastOffsetFromFeedTop: Double = 22

    public static func timeoutNote(name: String, announce: Bool) -> String? {
        announce ? "\(name) timed out" : nil
    }

    /// Chip / pinch / color drum while rolling in D-Log2. No opcode names.
    public static let recordingColorLockNote =
        "Can't change color while recording — D-Log2 can't zoom"

    /// Center Y for the control toast. Parks under a mounted top bar when that
    /// bar overlays the feed (DISP 1). Falls back to the feed edge when the
    /// bar is off or already sits above the picture (DISP 2 / portrait).
    public static func toastCenterY(feedMinY: Double, chromeBottomY: Double? = nil) -> Double {
        let edge: Double
        if let chromeBottomY, chromeBottomY > feedMinY + 0.5 {
            edge = chromeBottomY
        } else {
            edge = feedMinY
        }
        return edge + toastOffsetFromFeedTop
    }

}

public enum FovSetting: UInt8, CaseIterable, Sendable {
    case wide = 0x01
    case naturalWide = 0x05

    public var label: String {
        switch self {
        case .wide: "Wide"
        case .naturalWide: "Natural"
        }
    }
}

/// Reply oracle from Osmosis camera-control (payload first byte).
public enum CameraReply: Equatable, Sendable {
    case ok
    case wrongState
    case badParameter
    case unsupported
    case other(UInt8)

    public static func parse(_ payload: [UInt8]) -> CameraReply {
        guard let b = payload.first else { return .other(0xFF) }
        switch b {
        case 0x00: return .ok
        case 0xD9: return .wrongState
        case 0xDF, 0xE3, 0xEE: return .badParameter
        case 0xE0: return .unsupported
        default: return .other(b)
        }
    }

    public var isSuccess: Bool {
        if case .ok = self { return true }
        return false
    }

    public var message: String {
        switch self {
        case .ok: "ok"
        case .wrongState: "camera rejected that in this mode"
        case .badParameter: "camera rejected that value"
        case .unsupported: "camera does not support that command"
        case .other(let b): String(format: "camera reply 0x%02X", b)
        }
    }
}

/// `cam_expo_param` shutter / ISO / EV fields (Mimo 2026-08-14). `@13` is not ISO.
public enum ExpoParam {
    /// `@2–3` = `denom | 0x8000` u16-LE. Not `@16`.
    public static func shutterDenom(_ value: [UInt8]) -> Int? {
        guard value.count >= 4 else { return nil }
        let raw = UInt16(value[2]) | (UInt16(value[3]) << 8)
        let denom = Int(raw & 0x7FFF)
        return (1...16_000).contains(denom) ? denom : nil
    }

    /// `@5` = 1-byte index (`00` Auto, `03`=100 … `0B`=25600).
    public static func isoIndex(_ value: [UInt8]) -> IsoIndex? {
        guard value.count > 5 else { return nil }
        return IsoIndex(rawValue: value[5])
    }

    /// `@6` = EV raw. mimo-settings-1 `0x02/0x2E` SET echoes here (not WB).
    public static func evComp(_ value: [UInt8]) -> EvComp? {
        guard value.count > 6 else { return nil }
        return EvComp(rawValue: value[6])
    }

    /// `@16` u16-LE = ISO number. Auto `@16` floats with the meter.
    public static func isoValue(_ value: [UInt8]) -> Int? {
        guard value.count >= 18 else { return nil }
        let iso = Int(UInt16(value[16]) | (UInt16(value[17]) << 8))
        return (50...102_400).contains(iso) ? iso : nil
    }
}

/// `0x02/0x2E` 1-byte EV. mimo-settings-1 while Auto, all ACK `00`:
/// `10` (pkt 53846), `11` (55417 / 55762 / 57954 / 58208), `12` (56064), `0f` (62279).
/// Each write lands in `cam_expo_param` `@6` on the next push. `0x10` = 0.0;
/// ⅓-stop steps. Drum −3.0…+3.0 is `07`…`19` (same index; ends not in that take).
public struct EvComp: Hashable, Sendable, Comparable {
    /// Third-stops from 0. −9 = −3.0, 0 = 0.0, +9 = +3.0.
    public var thirds: Int

    public static let minThirds = -9
    public static let maxThirds = 9
    public static let zero = EvComp(thirds: 0)
    /// Operator minus (U+2212) so `−3.0` matches the bar / drum.
    public static let minusSign = "\u{2212}"
    public static let allCases: [EvComp] = (minThirds...maxThirds).map { EvComp(thirds: $0) }

    public init(thirds: Int) {
        self.thirds = min(max(thirds, Self.minThirds), Self.maxThirds)
    }

    public init?(rawValue: UInt8) {
        let thirds = Int(rawValue) - 0x10
        guard (Self.minThirds...Self.maxThirds).contains(thirds) else { return nil }
        self.thirds = thirds
    }

    public init?(label: String) {
        if label == "0.0" {
            thirds = 0
            return
        }
        let negative = label.hasPrefix(Self.minusSign) || label.hasPrefix("-")
        let positive = label.hasPrefix("+")
        guard negative || positive else { return nil }
        let body = String(label.dropFirst())
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard parts.count == 2, let whole = Int(parts[0]), let frac = Int(parts[1]) else {
            return nil
        }
        let fracThirds: Int
        switch frac {
        case 0: fracThirds = 0
        case 3: fracThirds = 1
        case 7: fracThirds = 2
        default: return nil
        }
        let t = whole * 3 + fracThirds
        guard (0...Self.maxThirds).contains(t) else { return nil }
        thirds = negative ? -t : t
    }

    /// SET / `@6` byte. `0x10` + thirds.
    public var rawValue: UInt8 { UInt8(clamping: 0x10 + thirds) }

    /// `0.0`, `+1.0`, `−1.3`.
    public var label: String {
        if thirds == 0 { return "0.0" }
        let sign = thirds > 0 ? "+" : Self.minusSign
        let absThirds = abs(thirds)
        let frac = [".0", ".3", ".7"][absThirds % 3]
        return "\(sign)\(absThirds / 3)\(frac)"
    }

    public static func < (lhs: EvComp, rhs: EvComp) -> Bool { lhs.thirds < rhs.thirds }
}

/// `0x02/0x2A` 1-byte index. Not the ISO number. No GET — read `cam_expo_param` `@5` / `@16`.
public enum IsoIndex: UInt8, CaseIterable, Sendable {
    case auto = 0x00
    case iso100 = 0x03
    case iso200 = 0x04
    case iso400 = 0x05
    case iso800 = 0x06
    case iso1600 = 0x07
    case iso3200 = 0x08
    case iso6400 = 0x09
    case iso12800 = 0x0A
    case iso25600 = 0x0B

    /// nil for Auto.
    public var isoValue: Int? {
        switch self {
        case .auto: nil
        case .iso100: 100
        case .iso200: 200
        case .iso400: 400
        case .iso800: 800
        case .iso1600: 1600
        case .iso3200: 3200
        case .iso6400: 6400
        case .iso12800: 12800
        case .iso25600: 25600
        }
    }

    public var label: String {
        if let isoValue { return "\(isoValue)" }
        return "Auto"
    }

    /// Next / previous full-stop slot in `available`. Skips Auto. nil at the end.
    public static func stepped(
        from current: IsoIndex, stops: Int, available: [IsoIndex]
    ) -> IsoIndex? {
        let list = available.filter { $0 != .auto }
        guard current != .auto, let index = list.firstIndex(of: current) else { return nil }
        let next = index + stops
        guard list.indices.contains(next), next != index else { return nil }
        return list[next]
    }

    /// Closest offered manual index to a live ISO number (`cam_expo_param` `@16`).
    public static func nearest(to value: Int, available: [IsoIndex]) -> IsoIndex? {
        let list = available.filter { $0 != .auto }
        return list.min { a, b in
            abs((a.isoValue ?? 0) - value) < abs((b.isoValue ?? 0) - value)
        }
    }
}

/// `0x02/0x42` color. No GET — `cam_image_effect` `@2`.
///
/// Per body (DJI spec; D-Log2 is Pocket 4 Pro only):
/// 4 Pro `3F` Normal / `3C` HDR / `17` D-Log / `41` D-Log2.
/// Pocket 4 `3F` / `3C` / `17` D-Log (no D-Log2).
/// Pocket 3 `3F` / `3C` HDR (HLG) / `00` D-Log M — `17` showed "colour 4" (#160).
/// Nano `camcap_color_mode` (Mimo 2026-08-18): `01 04 00 03 00 3F 3D` →
/// `00` D-Log M / `3F` Normal 8-bit / `3D` Normal 10-bit.
/// Swap `3D`/`00` if a labeled SET capture says otherwise.
public enum ColorMode: UInt8, CaseIterable, Sendable {
    case normal = 0x3F
    case hdr = 0x3C
    case dLog = 0x17
    case dLog2 = 0x41
    case normal10 = 0x3D
    case dLogM = 0x00

    public var label: String {
        switch self {
        case .normal: "Normal"
        case .hdr: "HDR"
        case .dLog: "D-Log"
        case .dLog2: "D-Log2"
        case .normal10: "Normal 10-bit"
        case .dLogM: "D-Log M 10-bit"
        }
    }

    /// Log encodings Auto can bind a Rec.709 cube to.
    public var bindsAutoLUT: Bool {
        switch self {
        case .dLog, .dLog2, .dLogM: true
        default: false
        }
    }

    public func label(for family: CameraBodyFamily) -> String {
        if family == .nano, self == .normal { return "Normal 8-bit" }
        if family == .pocket, self == .dLogM { return "D-Log M" }
        return label
    }

    public init?(label: String) {
        switch label {
        case "Normal 8-bit": self = .normal
        case "D-Log M": self = .dLogM
        default:
            guard let match = Self.allCases.first(where: { $0.label == label }) else { return nil }
            self = match
        }
    }

    /// Family fallback. Pocket 4 Pro is the only body with D-Log2 — use
    /// `available(for: CameraModel)` when the name is known.
    public static func available(for family: CameraBodyFamily) -> [ColorMode] {
        switch family {
        case .nano: [.normal, .normal10, .dLogM]
        case .pocket, .other: [.normal, .hdr, .dLog]
        }
    }

    /// DJI comparison: 4 Pro D-Log2 / D-Log; Pocket 4 D-Log; Pocket 3 HLG / D-Log M.
    /// Nano is the captured `camcap_color_mode` wheel. D-Log2 is 4 Pro only.
    public static func available(for model: CameraModel) -> [ColorMode] {
        if model.family == .nano { return available(for: .nano) }
        let n = model.name.lowercased().replacingOccurrences(of: " ", with: "")
        if n.contains("pocket4p") || n.contains("4pro") {
            return [.normal, .hdr, .dLog, .dLog2]
        }
        if n.contains("pocket4") { return [.normal, .hdr, .dLog] }
        if n.contains("pocket3") || n.contains("muse") {
            return [.normal, .hdr, .dLogM]
        }
        return available(for: model.family)
    }

    /// Indices Mimo offered per color in the labeled take. Do not invent others.
    public var isoIndices: [IsoIndex] {
        switch self {
        case .dLog2: [.iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200]
        case .dLog: [.auto, .iso400, .iso800, .iso1600, .iso3200, .iso6400]
        case .normal, .hdr, .normal10, .dLogM:
            [
                .auto, .iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200, .iso6400, .iso12800,
                .iso25600,
            ]
        }
    }

    /// D-Log2 has no Auto ISO — even if `IsoLimit` grows, this stays false.
    public var offersIsoAuto: Bool { self != .dLog2 }

    /// `camcap_iso_auto_max` base: 100 Normal/HDR, 400 D-Log. nil = no Auto.
    public var isoAutoBase: Int? {
        switch self {
        case .dLog2: nil
        case .dLog: 400
        case .normal, .hdr, .normal10, .dLogM: 100
        }
    }

    /// Ceiling codes from `camcap_iso_auto_max` for this color.
    public var isoAutoLimits: [IsoLimit] {
        switch self {
        case .dLog2: []
        case .dLog: [.max800, .max1600, .max3200, .max6400]
        case .normal, .hdr, .normal10, .dLogM:
            [
                .max200, .max400, .max800, .max1600, .max3200, .max6400, .max12800, .max25600,
            ]
        }
    }

    public var isoAutoLabels: [String] {
        guard let base = isoAutoBase else { return [] }
        return isoAutoLimits.map { $0.label(base: base) }
    }

    public static func parseImageEffect(_ value: [UInt8]) -> ColorMode? {
        guard value.count > 2 else { return nil }
        return ColorMode(rawValue: value[2])
    }
}

/// `0x02/0x24` focus. SET `01`/`02`; `cam_lens_state` `@0` is `B1`/`B2`.
public enum FocusMode: UInt8, CaseIterable, Sendable {
    case single = 0x01
    case continuous = 0x02

    public var label: String {
        switch self {
        case .single: "Single"
        case .continuous: "Continuous"
        }
    }

    public static func parseLensState(_ value: [UInt8]) -> FocusMode? {
        guard let b = value.first else { return nil }
        switch b {
        case 0x01, 0xB1: return .single
        case 0x02, 0xB2: return .continuous
        default: return nil
        }
    }
}

/// AF point inside `cam_lens_state` (67 B). mimo-tap-focus-20260818: after a
/// tap the same x/y as `0x30` land as f32-LE at `@1` and `@5` (echoed again at
/// `@50`/`@54`). Idle / centre is ~0.5, 0.5.
public enum CamLensState {
    public static let defaultX = 0.5
    public static let defaultY = 0.5

    public static func focusPoint(_ value: [UInt8]) -> (x: Double, y: Double)? {
        guard value.count >= 9,
            let x = f32(value, 1), let y = f32(value, 5),
            x.isFinite, y.isFinite, (0...1).contains(x), (0...1).contains(y)
        else { return nil }
        return (x, y)
    }

    private static func f32(_ value: [UInt8], _ offset: Int) -> Double? {
        guard offset + 4 <= value.count else { return nil }
        var bits: UInt32 = 0
        for i in 0..<4 { bits |= UInt32(value[offset + i]) << (8 * i) }
        let f = Float(bitPattern: bits)
        return f.isFinite ? Double(f) : nil
    }
}

/// When the camera's AF point should replace the painted one.
public enum CameraFocusPolicy {
    public static let changeThreshold = 0.012

    public static func shouldAdopt(
        currentX: Double, currentY: Double, cameraX: Double, cameraY: Double
    ) -> Bool {
        abs(currentX - cameraX) >= changeThreshold
            || abs(currentY - cameraY) >= changeThreshold
    }
}

/// AF-C submenu. `0x02/0x8E` pid `0x003B`. `/tmp/mimo-afc-options-20260818.pcapng`.
/// SET/GET value is `01 <mode>`. Independent of `0x24` — persists across AF-S.
public enum FocusTrackMode: UInt8, CaseIterable, Sendable {
    case `default` = 0x00
    case productShowcase = 0x01
    case subjectLock = 0x02
    case registeredPriority = 0x03

    public var label: String {
        switch self {
        case .default: "Default"
        case .productShowcase: "Product Showcase"
        case .subjectLock: "Subject Lock Tracking"
        case .registeredPriority: "Registered Subject Priority"
        }
    }

    /// SET/GET blob `01 <raw>`.
    public var setValue: [UInt8] { [0x01, rawValue] }

    /// Camera can pause HEVC while switching AF-C intelligence. Hold the
    /// 2 s stall rebuild so a chip tap does not flash Reconnecting.
    public static let videoGrace: TimeInterval = 4

    public static func shouldHoldWatchdog(secondsSinceSet: TimeInterval?) -> Bool {
        guard let secondsSinceSet else { return false }
        return secondsSinceSet >= 0 && secondsSinceSet < videoGrace
    }

    public static func parseReply(_ payload: [UInt8]) -> FocusTrackMode? {
        guard let parsed = CameraParam.parseBlobReply(payload),
            parsed.pid == CameraParam.focusTrack.rawValue,
            parsed.value.count == 2, parsed.value[0] == 0x01
        else { return nil }
        return FocusTrackMode(rawValue: parsed.value[1])
    }
}

/// FOCUS picker rows. Single is `0x24`. The rest are AF-C + pid `0x003B`.
public enum FocusOption: Equatable, CaseIterable, Sendable {
    case single
    case continuousDefault
    case productShowcase
    case subjectLock
    case registeredPriority

    public var label: String {
        switch self {
        case .single: FocusMode.single.label
        case .continuousDefault: FocusTrackMode.default.label
        case .productShowcase: FocusTrackMode.productShowcase.label
        case .subjectLock: FocusTrackMode.subjectLock.label
        case .registeredPriority: FocusTrackMode.registeredPriority.label
        }
    }

    public var chip: String {
        switch self {
        case .single: "AF-S"
        case .continuousDefault: "AF-C"
        case .productShowcase: "Showcase"
        case .subjectLock: "Lock"
        case .registeredPriority: "Priority"
        }
    }

    public var focusMode: FocusMode {
        self == .single ? .single : .continuous
    }

    public var track: FocusTrackMode? {
        switch self {
        case .single: nil
        case .continuousDefault: .default
        case .productShowcase: .productShowcase
        case .subjectLock: .subjectLock
        case .registeredPriority: .registeredPriority
        }
    }

    public static func resolve(mode: FocusMode?, track: FocusTrackMode?) -> FocusOption? {
        switch mode {
        case .single: return .single
        case .continuous:
            switch track {
            case .productShowcase: return .productShowcase
            case .subjectLock: return .subjectLock
            case .registeredPriority: return .registeredPriority
            case .default, nil: return .continuousDefault
            }
        case nil: return nil
        }
    }
}

/// `0x02/0x2C` first byte. Auto `00`, Custom `06`.
public enum WhiteBalanceMode: UInt8, CaseIterable, Sendable {
    case auto = 0x00
    case custom = 0x06

    public var label: String {
        switch self {
        case .auto: "Auto"
        case .custom: "Custom"
        }
    }
}

/// 5-byte WB: `[mode][K/100 u16-LE][tint i16-LE]`. Kelvin 2000–10000 / 100; tint −100…+100.
/// Auto SET is kelvin 0 and **keeps tint** (`00 00 00 <tint>`). Mimo never zeros tint on Auto.
public struct WhiteBalance: Equatable, Sendable {
    public var mode: WhiteBalanceMode
    public var kelvin: Int
    public var tint: Int

    public init(mode: WhiteBalanceMode, kelvin: Int, tint: Int) {
        self.mode = mode
        self.kelvin = kelvin
        self.tint = min(max(tint, -100), 100)
    }

    public static let auto = WhiteBalance(mode: .auto, kelvin: 0, tint: 0)

    /// Auto on the wire: kelvin bytes stay 0; tint is the last two bytes.
    public static func auto(tint: Int) -> WhiteBalance {
        WhiteBalance(mode: .auto, kelvin: 0, tint: tint)
    }

    public static func custom(kelvin: Int, tint: Int) -> WhiteBalance {
        WhiteBalance(mode: .custom, kelvin: kelvin, tint: tint)
    }

    public var setPayload: [UInt8] {
        let kHundreds: UInt16 = mode == .auto ? 0 : UInt16(clamping: max(kelvin, 0) / 100)
        let t = Int16(clamping: tint)
        let tu = UInt16(bitPattern: t)
        return [
            mode.rawValue, UInt8(kHundreds & 0xFF), UInt8(kHundreds >> 8), UInt8(tu & 0xFF),
            UInt8(tu >> 8),
        ]
    }

    /// `cam_image_effect` `@4` mode, `@5–6` K/100 (Custom only), `@7–8` tint.
    /// Auto `@5–6` is live-measured and not a SET kelvin — ignore it.
    public static func parseImageEffect(_ value: [UInt8]) -> WhiteBalance? {
        guard value.count >= 9, let mode = WhiteBalanceMode(rawValue: value[4]) else { return nil }
        let tint = Int(Int16(bitPattern: UInt16(value[7]) | (UInt16(value[8]) << 8)))
        if mode == .auto {
            return WhiteBalance.auto(tint: tint)
        }
        let hundreds = Int(UInt16(value[5]) | (UInt16(value[6]) << 8))
        return WhiteBalance.custom(kelvin: hundreds * 100, tint: tint)
    }
}

/// `0x02/0x8E` pid `0x0020`. Stereo `02`, Mono `01`, Spatial `03`.
public enum AudioChannel: UInt8, CaseIterable, Sendable {
    case stereo = 0x02
    case mono = 0x01
    case spatial = 0x03

    public var label: String {
        switch self {
        case .mono: "Mono"
        case .stereo: "Stereo"
        case .spatial: "Spatial"
        }
    }
}

/// `0x02/0x8E` pid `0x004C`. Off `00`, On `01`.
public enum VocalBoost: UInt8, CaseIterable, Sendable {
    case off = 0x00
    case on = 0x01

    public var label: String {
        switch self {
        case .off: "Off"
        case .on: "On"
        }
    }
}

/// `0x02/0x8E` pid `0x0038`. Off `00`, On `01`. Control Center Selfie Flip.
public enum SelfieFlip: UInt8, CaseIterable, Sendable {
    case off = 0x00
    case on = 0x01

    public var isOn: Bool { self == .on }

    public var label: String {
        switch self {
        case .off: "Off"
        case .on: "On"
        }
    }
}

/// Wind NR lives in audio-DSP blob `@2` (`1A` On / `18` Off). Shares the byte with directional.
public enum WindNoiseReduction: UInt8, CaseIterable, Sendable {
    case off = 0x18
    case on = 0x1A

    public var label: String {
        switch self {
        case .off: "Off"
        case .on: "On"
        }
    }
}

/// Directional audio in the same blob `@2`. All `DA`, Front `3A`, Front+back `BA`.
public enum DirectionalAudio: UInt8, CaseIterable, Sendable {
    case all = 0xDA
    case front = 0x3A
    case frontAndBack = 0xBA

    public var label: String {
        switch self {
        case .all: "All"
        case .front: "Front"
        case .frontAndBack: "Front+back"
        }
    }
}

/// Shared audio-DSP `@2`. Wind and directional overwrite each other — GET, patch, SET.
public enum AudioDspAt2: Equatable, Sendable {
    case wind(WindNoiseReduction)
    case directional(DirectionalAudio)
    case unknown(UInt8)

    public init(raw: UInt8) {
        if let wind = WindNoiseReduction(rawValue: raw) {
            self = .wind(wind)
        } else if let dir = DirectionalAudio(rawValue: raw) {
            self = .directional(dir)
        } else {
            self = .unknown(raw)
        }
    }

    public var rawValue: UInt8 {
        switch self {
        case .wind(let w): w.rawValue
        case .directional(let d): d.rawValue
        case .unknown(let b): b
        }
    }
}

/// GET `0x02/0xA0` empty → `00` + 26-byte blob. SET `0x02/0x9F` = that blob. Do not invent bytes.
public enum AudioDspBlob {
    public static let size = 26

    public static func blob(fromGetReply payload: [UInt8]) -> [UInt8]? {
        guard payload.count >= 1 + size, payload[0] == 0x00 else { return nil }
        return Array(payload[1..<(1 + size)])
    }

    public static func patch(_ blob: [UInt8], byte2: UInt8) -> [UInt8] {
        guard blob.count > 2 else { return blob }
        var out = blob
        out[2] = byte2
        return out
    }

    /// Captured directional bytes already have the wind-on bit. Keep that
    /// stop when turning wind on so the Directional tab stays honest.
    public static func patchWind(_ blob: [UInt8], _ value: WindNoiseReduction) -> [UInt8] {
        switch value {
        case .off:
            return patch(blob, byte2: WindNoiseReduction.off.rawValue)
        case .on:
            if let dir = directional(from: blob.count > 2 ? blob[2] : 0) {
                return patch(blob, byte2: dir.rawValue)
            }
            return patch(blob, byte2: WindNoiseReduction.on.rawValue)
        }
    }

    public static func patchDirectional(_ blob: [UInt8], _ value: DirectionalAudio) -> [UInt8] {
        patch(blob, byte2: value.rawValue)
    }

    public static func at2(_ blob: [UInt8]) -> AudioDspAt2? {
        guard blob.count > 2 else { return nil }
        return AudioDspAt2(raw: blob[2])
    }

    /// Wind off is only `18`. Every captured directional byte includes wind-on.
    public static func wind(from raw: UInt8) -> WindNoiseReduction? {
        switch raw {
        case WindNoiseReduction.off.rawValue:
            return .off
        case WindNoiseReduction.on.rawValue,
            DirectionalAudio.all.rawValue,
            DirectionalAudio.front.rawValue,
            DirectionalAudio.frontAndBack.rawValue:
            return .on
        default:
            return nil
        }
    }

    public static func directional(from raw: UInt8) -> DirectionalAudio? {
        DirectionalAudio(rawValue: raw)
    }

    public static func applyByte2(_ raw: UInt8, to status: inout CameraStatus) {
        status.audioDspAt2 = AudioDspAt2(raw: raw)
        if let wind = wind(from: raw) { status.windNR = wind }
        if let dir = directional(from: raw) { status.directionalAudio = dir }
    }
}

/// `0x02/0x18` `@0`. Only 1080p / 4K were in the labeled take.
public enum VideoResolution: UInt8, CaseIterable, Sendable {
    case p1080 = 0x0A
    case p4K = 0x10

    public var label: String {
        switch self {
        case .p1080: "1080p"
        case .p4K: "4K"
        }
    }

    /// OpenZCine resolution-tab title. Pocket only advertised these two.
    public var tabTitle: String {
        switch self {
        case .p1080: "1080"
        case .p4K: "4K"
        }
    }
}

/// `0x02/0x18` `@1` fps index. SET only the six labeled values.
public enum VideoFrameRate: UInt8, CaseIterable, Sendable {
    case fps24 = 0x01
    case fps25 = 0x02
    case fps30 = 0x03
    case fps48 = 0x04
    case fps50 = 0x05
    case fps60 = 0x06

    public var fps: Int {
        switch self {
        case .fps24: 24
        case .fps25: 25
        case .fps30: 30
        case .fps48: 48
        case .fps50: 50
        case .fps60: 60
        }
    }

    public var label: String { "\(fps)" }

    /// OpenZCine framerate-drum row (`24p`, not a bare `24`).
    public var drumLabel: String { "\(fps)p" }

    public init?(drumLabel: String) {
        guard let match = Self.allCases.first(where: { $0.drumLabel == drumLabel }) else {
            return nil
        }
        self = match
    }

    /// Labeled Video-mode SET (`0x02/0x18`). SlowMo 100/120/240 is display-only
    /// until a SlowMo `camcap_video_format` / SET take lands.
    public static let labeledVideo: [VideoFrameRate] = [
        .fps24, .fps25, .fps30, .fps48, .fps50, .fps60,
    ]
}

/// One 5-byte SET: `[res][fps_idx] 00 00 00`. No GET — `cam_video_param_v2` `@0–1`.
public struct VideoFormat: Equatable, Hashable, Sendable {
    public var resolution: VideoResolution
    public var frameRate: VideoFrameRate

    public init(resolution: VideoResolution, frameRate: VideoFrameRate) {
        self.resolution = resolution
        self.frameRate = frameRate
    }

    public var setPayload: [UInt8] {
        [resolution.rawValue, frameRate.rawValue, 0x00, 0x00, 0x00]
    }

    /// Top-deck chip, OpenZCine `resolutionFrameRate` shape (`4K · 25p`).
    public var chipLabel: String {
        "\(resolution.label) · \(frameRate.fps)p"
    }

    public static func parseVideoParamV2(_ value: [UInt8]) -> VideoFormat? {
        guard value.count >= 2,
            let res = VideoResolution(rawValue: value[0]),
            let fps = VideoFrameRate(rawValue: value[1])
        else { return nil }
        return VideoFormat(resolution: res, frameRate: fps)
    }

    /// Other labeled resolution, same fps. Pocket 3 first picture: the FORMAT
    /// sheet skips a same-tab SET, so 4K→4K never restarts the live encoder.
    public static func firstPictureEncoderKick(from original: VideoFormat) -> VideoFormat {
        VideoFormat(
            resolution: original.resolution == .p4K ? .p1080 : .p4K,
            frameRate: original.frameRate)
    }

    /// Reported P3 boot is 4K 25/30. Unknown falls back to 4K 30, not 1080 24.
    public static func firstPictureOriginal(
        format: VideoFormat?,
        resolution: VideoResolution?,
        fps: Int
    ) -> VideoFormat {
        if let format { return format }
        let res = resolution ?? .p4K
        let rate = VideoFrameRate.allCases.first { $0.fps == fps } ?? .fps30
        return VideoFormat(resolution: res, frameRate: rate)
    }
}

/// `0x04/0x50` param `05`. Fast `00`, Default `01`, Slow `02`.
public enum GimbalSpeed: UInt8, CaseIterable, Sendable {
    case fast = 0x00
    case defaultSpeed = 0x01
    case slow = 0x02

    public var label: String {
        switch self {
        case .fast: "Fast"
        case .defaultSpeed: "Default"
        case .slow: "Slow"
        }
    }
}

/// `0x04/0x50` param `04`. `00` unlocked (Follow), `01` locked. FPV may leave a leftover `01`.
public enum GimbalTiltLock: UInt8, CaseIterable, Sendable {
    case unlocked = 0x00
    case locked = 0x01

    public var label: String {
        switch self {
        case .unlocked: "Follow"
        case .locked: "Tilt Locked"
        }
    }
}

/// GET `0x04/0x50` reply `00 01 04 01 <tilt> 05 01 <speed>`. Cannot tell FPV from Tilt Locked.
public struct GimbalParamState: Equatable, Sendable {
    public var tiltLock: GimbalTiltLock
    public var speed: GimbalSpeed?

    public init(tiltLock: GimbalTiltLock, speed: GimbalSpeed?) {
        self.tiltLock = tiltLock
        self.speed = speed
    }

    public static func parseGetReply(_ payload: [UInt8]) -> GimbalParamState? {
        guard payload.count >= 8,
            payload[0] == 0x00, payload[1] == 0x01, payload[2] == 0x04, payload[3] == 0x01,
            payload[5] == 0x05, payload[6] == 0x01
        else { return nil }
        let tilt = GimbalTiltLock(rawValue: payload[4]) ?? (payload[4] == 0 ? .unlocked : .locked)
        return GimbalParamState(tiltLock: tilt, speed: GimbalSpeed(rawValue: payload[7]))
    }
}

/// Gimbal face from `0x04/0x27` `@2` bit `0x40`: set = 180 / `FE 09`, clear =
/// front. Wire JSON is `0` front / `1` 180 / `-1` unknown. Not Selfie Flip
/// (`0x8E` pid `0x0038`).
public enum GimbalFace: Int, Equatable, Sendable {
    case front = 0
    case selfie = 1

    public static func parse(_ payload: [UInt8]) -> GimbalFace? {
        guard payload.count > 2 else { return nil }
        return (payload[2] & 0x40) != 0 ? .selfie : .front
    }
}

/// Screen-relative pan follows the **live** picture.
///
/// Invert is TT180: `FE 09` to the **selfie pole**. Joystick yaw never sets
/// or clears it. `FE 08` recenter does not touch it. The Pocket picks `FE 09`
/// destination from current `|yaw|` (front half → ±180°, back half → 0°).
/// Live extra-mirror matches Mimo: TT180 and Selfie Flip **off** (pid `0x38`
/// `00` — encoder is mirrored). Flip **on** (`01`) already encodes
/// true-to-scene, so skip extra-mirror. Shell XORs MIRROR assist.
public struct GimbalStickMapping: Equatable, Sendable {
    public var face: GimbalFace?
    public var wireFace: GimbalFace?
    public var rotated180: Bool
    public var holdFace: Bool
    public var seenFront: Bool
    public var rotateParity: Bool
    /// Invert / extra-mirror latch: last `FE 09` arrived at selfie, or connect
    /// seed while `|yaw| > 90°`. Not joystick 180.
    public var commanded180: Bool
    /// Control Center Selfie Flip (`0x8E` pid `0x0038`). On → skip extra-mirror.
    public var selfieFlip: Bool
    /// Queued `FE 09` destinations (`true` = settle at 180 / invert on).
    public var pendingWant180: [Bool]
    public var pendingRotateCount: Int { pendingWant180.count }
    /// Last `0x04/0x05` i16-LE @4 in 0.1°.
    public var yawTenthDeg: Int16?
    /// First settled attitude adopted as TT180 so reconnect-at-180 inverts
    /// without another triple-tap.
    public var poseSeeded: Bool
    /// Settled-front votes before locking a front seed. One 0° stub must not
    /// beat a following 180 on reconnect.
    public var poseSeedFrontCount: Int

    public init(
        face: GimbalFace? = nil, wireFace: GimbalFace? = nil, rotated180: Bool = false,
        holdFace: Bool = false, seenFront: Bool = false, rotateParity: Bool = false,
        commanded180: Bool = false, selfieFlip: Bool = false,
        pendingWant180: [Bool] = [], yawTenthDeg: Int16? = nil, poseSeeded: Bool = false,
        poseSeedFrontCount: Int = 0
    ) {
        self.face = face
        self.wireFace = wireFace
        self.rotated180 = rotated180
        self.holdFace = holdFace
        self.seenFront = seenFront
        self.rotateParity = rotateParity
        self.commanded180 = commanded180
        self.selfieFlip = selfieFlip
        self.pendingWant180 = pendingWant180
        self.yawTenthDeg = yawTenthDeg
        self.poseSeeded = poseSeeded
        self.poseSeedFrontCount = poseSeedFrontCount
    }

    /// Extra-mirror live HEVC like Mimo: TT180 and Flip off.
    public var poseViewFlip: Bool { commanded180 && !selfieFlip }

    /// Invert pan with TT180 so stick pan stays picture-relative.
    public var invertPan: Bool { commanded180 }

    public mutating func noteRotate180() {
        noteRotate180(fromBody: false)
    }

    /// Queue a settle for app `FE 09`. Destination is current `|yaw|`, same as
    /// the Pocket. Holds the next `0x27` XOR so we do not treat our echo as body.
    public mutating func noteRotate180(fromBody: Bool) {
        if !fromBody { holdFace = true }
        pendingWant180.append(GimbalStick.fe09GoesTo180(yawTenthDeg: yawTenthDeg))
    }

    /// Body `FE 09`: `0x27` bit `0x40` tracks the invert latch, not physical yaw.
    /// Joystick 180 does not XOR this bit. Latch the bit; do not queue a dest.
    @discardableResult
    public mutating func noteBodyFace(_ new: GimbalFace?) -> Bool {
        let previous = wireFace
        let wasHold = holdFace
        _ = applyFace(new)
        guard !wasHold, let previous, let new, new != previous else { return false }
        commanded180 = new == .selfie
        poseSeeded = true
        poseSeedFrontCount = 0
        return true
    }

    /// Apply 0x27. Returns false when ignored (leftover selfie or `FE 09` echo).
    @discardableResult
    public mutating func applyFace(_ new: GimbalFace?) -> Bool {
        guard let new else { return false }
        if new == .front { seenFront = true }
        if new == .selfie, !seenFront { return false }
        if holdFace {
            if wireFace == nil {
                wireFace = new
                return false
            }
            if new == wireFace { return false }
            wireFace = new
            rotateParity.toggle()
            holdFace = false
            return false
        }
        wireFace = new
        let decoded: GimbalFace = (new == .selfie) != rotateParity ? .selfie : .front
        let changed = face != decoded
        face = decoded
        return changed
    }

    public mutating func applyAttitude(_ payload: [UInt8]) {
        guard let yaw = GimbalStick.yawTenthDeg(payload) else { return }
        let rotated = abs(Int(yaw)) > GimbalStick.rotated180TenthDeg
        if let want180 = pendingWant180.first {
            if GimbalStick.rotationSettled(yawTenthDeg: yaw, want180: want180) {
                commanded180 = want180
                pendingWant180.removeFirst()
                poseSeeded = true
                poseSeedFrontCount = 0
            }
        } else if !poseSeeded {
            if rotated {
                commanded180 = true
                poseSeeded = true
                poseSeedFrontCount = 0
            } else if GimbalStick.rotationSettled(yawTenthDeg: yaw, want180: false) {
                poseSeedFrontCount += 1
                if poseSeedFrontCount >= GimbalStick.poseSeedFrontVotes {
                    commanded180 = false
                    poseSeeded = true
                }
            } else {
                poseSeedFrontCount = 0
            }
        }
        rotated180 = rotated
        yawTenthDeg = yaw
    }
}

/// Stick range from the labeled take: center 1024, travel ±550 (474…1574).
/// Pocket hardware: axis0 is tilt (up=`max`, down=`min`); axis1 is pan
/// (left=`min`, right=`max`). First-cut X→axis0 / Y→axis1 was a 90° rotate.
public enum GimbalStick {
    public static let center: UInt16 = 1024
    public static let travel: UInt16 = 550
    public static let min: UInt16 = 474
    public static let max: UInt16 = 1574
    /// Rest snap. Inside this, both axes stay 1024.
    public static let deadzone: Double = 0.08
    /// Operator ticks. 4 is the captured ±550 throw.
    public static let sensitivityRange: ClosedRange<Int> = 1...5
    public static let defaultSensitivity = 4
    /// Mimo streamed `0x04/0x01` only while the on-screen stick was held.
    public static let streamInterval: TimeInterval = 0.04
    /// Stay inside this (as a fraction of travel) and the press is a tap.
    public static let tapSlop: Double = 0.18
    /// Second tap inside this window recenters; a third tap in the same
    /// window flips (Mimo `0x04/0x4C` `FE 09`) instead.
    public static let doubleTapWindow: TimeInterval = 0.35
    /// Encoded luma above this (0…1) flips the stick to dark chrome.
    public static let chromeGoDarkAbove: Double = 0.55
    /// Encoded luma below this flips the stick back to light chrome.
    public static let chromeGoLightBelow: Double = 0.42

    /// Hysteresis so a mid-grey wall does not flicker the stick.
    public static func prefersDarkChrome(luma: Double?, previous: Bool) -> Bool {
        guard let luma else { return previous }
        if previous { return luma > chromeGoLightBelow }
        return luma > chromeGoDarkAbove
    }

    /// Stick ∩ feed in feed-normalised top-left 0…1. `nil` when the stick
    /// sits on the canvas, not the picture.
    public static func chromeSampleRegion(
        stick: MonitorLayoutRegion, feed: MonitorLayoutRegion
    ) -> MonitorLayoutRegion? {
        guard feed.width > 1, feed.height > 1 else { return nil }
        let x = Swift.max(stick.x, feed.x)
        let y = Swift.max(stick.y, feed.y)
        let maxX = Swift.min(stick.maxX, feed.maxX)
        let maxY = Swift.min(stick.maxY, feed.maxY)
        let width = maxX - x
        let height = maxY - y
        guard width > 4, height > 4 else { return nil }
        return MonitorLayoutRegion(
            x: (x - feed.x) / feed.width,
            y: (y - feed.y) / feed.height,
            width: width / feed.width,
            height: height / feed.height)
    }

    public static func isTap(normalizedMagnitude: Double) -> Bool {
        normalizedMagnitude < tapSlop
    }

    public static func isDoubleTap(secondsSincePreviousTap: TimeInterval?) -> Bool {
        guard let since = secondsSincePreviousTap else { return false }
        return since >= 0 && since < doubleTapWindow
    }

    /// Counts stick taps so double-tap can wait for a possible triple.
    public struct TapSequence: Equatable, Sendable {
        public private(set) var count = 0
        private var lastAt: TimeInterval?

        public enum Result: Equatable, Sendable {
            case first
            case second
            case third
        }

        public init() {}

        public mutating func tap(at time: TimeInterval) -> Result {
            if let last = lastAt, time - last >= 0, time - last < GimbalStick.doubleTapWindow {
                count += 1
                lastAt = time
                if count >= 3 {
                    reset()
                    return .third
                }
                return .second
            }
            count = 1
            lastAt = time
            return .first
        }

        /// After `doubleTapWindow` from the second tap, commit recenter if no third arrived.
        public mutating func commitDouble() -> Bool {
            guard count == 2 else { return false }
            reset()
            return true
        }

        public mutating func reset() {
            count = 0
            lastAt = nil
        }
    }

    public static func clampedSensitivity(_ value: Int) -> Int {
        Swift.min(Swift.max(value, sensitivityRange.lowerBound), sensitivityRange.upperBound)
    }

    /// 4 = 1.0 (current). 5 saturates earlier; 1–3 never reach full throw.
    public static func sensitivityGain(_ value: Int) -> Double {
        Double(clampedSensitivity(value)) / Double(defaultSensitivity)
    }

    /// Clamp a unit axis (−1…1) onto 1024 ± 550, then apply sensitivity.
    public static func axis(_ normalized: Double, sensitivity: Int = defaultSensitivity) -> UInt16 {
        let n = Swift.min(Swift.max(normalized, -1), 1)
        if abs(n) < deadzone { return center }
        let scaled = Swift.min(Swift.max(n * sensitivityGain(sensitivity), -1), 1)
        let raw = Double(center) + scaled * Double(travel)
        let clamped = Swift.min(Swift.max(raw.rounded(), Double(min)), Double(max))
        return UInt16(clamped)
    }

    /// Screen-relative pan from 0x27 face. Unknown bit keeps the front mapping.
    public static func invertPan(for face: GimbalFace?) -> Bool {
        face == .selfie
    }

    /// View-space X flip: TT180 extra-mirror XOR MIRROR assist.
    public static func liveViewFlip(poseViewFlip: Bool, assistMirror: Bool) -> Bool {
        poseViewFlip != assistMirror
    }

    /// Stick invert follows the visible picture (TT180 XOR MIRROR).
    public static func liveInvertPan(poseInvert: Bool, assistMirror: Bool) -> Bool {
        poseInvert != assistMirror
    }

    /// `0x04/0x05` i16-LE @4 in 0.1°. |angle| > 90° is the selfie-facing pose.
    /// Short payloads fail closed (`nil`).
    public static let rotated180TenthDeg = 900
    /// Invert latch like Mimo: end of the 180, not the midpoint.
    public static let settle180TenthDeg = 1650
    public static let settleFrontTenthDeg = 150
    /// Reconnect often pushes a 0° stub before the real 180. Do not lock front yet.
    public static let poseSeedFrontVotes = 3

    public static func yawTenthDeg(_ payload: [UInt8]) -> Int16? {
        guard payload.count >= 6 else { return nil }
        return Int16(bitPattern: UInt16(payload[4]) | UInt16(payload[5]) << 8)
    }

    public static func rotated180(_ payload: [UInt8]) -> Bool? {
        guard let yaw = yawTenthDeg(payload) else { return nil }
        return abs(Int(yaw)) > rotated180TenthDeg
    }

    public static func rotationSettled(yawTenthDeg: Int16, want180: Bool) -> Bool {
        let angle = abs(Int(yawTenthDeg))
        return want180 ? angle >= settle180TenthDeg : angle <= settleFrontTenthDeg
    }

    /// Pocket `FE 09` destination: front half (`|yaw| ≤ 90°`) goes to ±180°.
    /// Unknown yaw assumes front (first live, no `0x05` yet).
    public static func fe09GoesTo180(yawTenthDeg: Int16?) -> Bool {
        guard let yaw = yawTenthDeg else { return true }
        return abs(Int(yaw)) <= rotated180TenthDeg
    }

    /// `x` −1…1 left…right → pan (axis1). `y` −1…1 down…up → tilt (axis0).
    /// Tracking uses the same pan invert as the free stick.
    public static func encode(
        x: Double, y: Double, invertPan: Bool = false,
        sensitivity: Int = defaultSensitivity
    ) -> (axis0: UInt16, axis1: UInt16) {
        (axis(y, sensitivity: sensitivity), axis(invertPan ? -x : x, sensitivity: sensitivity))
    }

    public static func encode(
        x: Double, y: Double, face: GimbalFace?,
        sensitivity: Int = defaultSensitivity
    ) -> (axis0: UInt16, axis1: UInt16) {
        encode(x: x, y: y, invertPan: invertPan(for: face), sensitivity: sensitivity)
    }
}

/// Pocket hybrid zoom. Mimo’s operator 1× / 3× / 12× is **not** `cam_fov / 1024`.
///
/// Labeled pinch `/tmp/mimo-zoom-1x3x-20260817.pcapng`: slow 1× → 12× is lens
/// **217 → 2604** (587 sliders, 50 ms, no slew). Start `cam_fov` 12287, end 2341.
/// 3× is the sensor hop at lens **651**. `cam_fov / 1024` runs backwards and
/// jumps at the hop — do not show it as the chip number.
///
/// Writes are slider `0A 4E` + lens `@14` for chips and pinch. Tele engages at
/// 3.0×. Do not invent a 2.9→3.0 snap.
public enum CamFov {
    public static let unit: UInt32 = 1024
    public static let minFactor = 1.0
    public static let maxFactor = 12.0
    /// Operator jump stops. Mimo chips 1× / 3×; 6× and 12× are pinch detents.
    public static let jumps: [Double] = [1, 3, 6, 12]
    /// `cam_fov` `@0` at operator 1× (Mimo 1× → 12× take, start).
    public static let rawAt1x: UInt32 = 12_287
    /// `cam_fov` `@0` at the 3× hop (`98 24 00 00`).
    public static let rawAt3x: UInt32 = 9368
    /// `cam_fov` `@0` at operator 12× (end of the 1× → 12× take).
    public static let rawAt12x: UInt32 = 2341
    public static let raw12x: UInt32 = rawAt1x
    public static let rawWide: UInt32 = rawAt12x
    /// `@14` at operator 1×. SET `0A 4E D9 00`.
    public static let lens1x: UInt16 = 217
    /// `@14` at operator 3× (sensor hop / Mimo 3× chip).
    public static let lens3x: UInt16 = 651
    /// `@14` at operator 6× (lerp 3×→12×). Pocket 4 Pro detent.
    public static let lens6x: UInt16 = 1302
    /// `@14` at operator 12×. SET `0A 4E 2C 0A`.
    public static let lens12x: UInt16 = 2604
    public static let lensSlewDetent: UInt16 = lens3x
    public static let lensWide: UInt16 = lens12x
    public static let lensMax: UInt16 = lens12x
    public static let lensTele: UInt16 = lens1x
    /// `0x02/0xb8` `03 00 64 00` — older takes, toward 1× / lens 217.
    public static let slewTele: UInt16 = 100
    /// `0x02/0xb8` `03 00 2C 01` — older takes, 1× → 3× detent.
    public static let slewWide: UInt16 = 300

    public static var wideFactor: Double { minFactor }
    public static var slewDetent: Double { teleEngage }

    public static func rawAt0(_ value: [UInt8]) -> UInt32? {
        guard value.count >= 4 else { return nil }
        return UInt32(value[0])
            | (UInt32(value[1]) << 8)
            | (UInt32(value[2]) << 16)
            | (UInt32(value[3]) << 24)
    }

    /// u16-LE `@14` when the blob is long enough and in the zoom range.
    public static func lensAt14(_ value: [UInt8]) -> UInt16? {
        guard value.count >= 16 else { return nil }
        let lens = UInt16(value[14]) | (UInt16(value[15]) << 8)
        guard (100...3_000).contains(lens) else { return nil }
        return lens
    }

    /// Operator factor from `cam_fov` `@0`. Inverted vs `@0 / 1024`.
    public static func factor(raw: UInt32) -> Double {
        if raw == 0 { return minFactor }
        if raw >= rawAt1x { return minFactor }
        if raw <= rawAt12x { return maxFactor }
        if raw >= rawAt3x {
            let t = Double(rawAt1x - raw) / Double(rawAt1x - rawAt3x)
            return clamp(minFactor + t * 2)
        }
        let t = Double(rawAt3x - raw) / Double(rawAt3x - rawAt12x)
        return clamp(3 + t * 9)
    }

    public static func factor(_ value: [UInt8]) -> Double? {
        rawAt0(value).map { factor(raw: $0) }
    }

    /// Operator factor from lens `@14` (217 = 1×, 651 = 3×, 2604 = 12×).
    public static func factor(lens: UInt16) -> Double? {
        guard lens > 0 else { return nil }
        if lens <= lens1x { return minFactor }
        if lens >= lens12x { return maxFactor }
        if lens <= lens3x {
            let t = Double(lens - lens1x) / Double(lens3x - lens1x)
            return clamp(minFactor + t * 2)
        }
        let t = Double(lens - lens3x) / Double(lens12x - lens3x)
        return clamp(3 + t * 9)
    }

    public static func clamp(_ factor: Double, max: Double = maxFactor) -> Double {
        min(Swift.max(factor, minFactor), max)
    }

    private static func lerpLens(_ a: UInt16, _ b: UInt16, _ t: Double) -> UInt16 {
        let t = min(max(t, 0), 1)
        return UInt16((Double(a) + t * (Double(b) - Double(a))).rounded())
    }

    /// Slider SET unit: piecewise through the 1× / 3× / 12× lens stops.
    /// No 0.1× snap — pinch writes every distinct lens tick. Chips still land
    /// on `chipWrite` (217 / 651 / 1302 / 2604).
    public static func lensPosition(for factor: Double) -> UInt16 {
        let f = clamp(factor)
        if abs(f - minFactor) < 0.001 { return lens1x }
        if abs(f - maxFactor) < 0.001 { return lens12x }
        if f <= 3 {
            return lerpLens(lens1x, lens3x, (f - minFactor) / 2)
        }
        return lerpLens(lens3x, lens12x, (f - 3) / 9)
    }

    public static func displayLabel(raw: UInt32) -> String {
        displayLabel(factor: factor(raw: raw))
    }

    public static func displayLabel(factor: Double) -> String {
        let shown = displayTenths(factor)
        if abs(shown - maxFactor) < 0.05 { return "12×" }
        let nearest = shown.rounded()
        if abs(shown - nearest) < 0.05, (1...12).contains(Int(nearest)) {
            return "\(Int(nearest))×"
        }
        return String(format: "%.1f×", shown)
    }

    /// Cycle through `stops` (default 4 Pro 1×/3×/6×/12×). Pocket 4 is 1×/2×/4×.
    public static func nextJump(from factor: Double, stops: [Double] = jumps) -> Double {
        let stops = stops.isEmpty ? jumps : stops
        for stop in stops where factor < stop - 0.05 { return stop }
        return stops[0]
    }

    /// True on a chip detent (0.1× quantized). Default is 4 Pro 1/3/6/12.
    public static func isJumpStop(_ factor: Double, stops: [Double] = jumps) -> Bool {
        let shown = displayTenths(factor)
        let stops = stops.isEmpty ? jumps : stops
        return stops.contains { abs(shown - $0) < 0.05 }
    }

    /// Older chip takes used slews. The 1×–3×–12× pinch take did not.
    public static func slew(forJump factor: Double) -> UInt16? {
        _ = factor
        return nil
    }

    /// Cycle-button write. 1× / 2× / 3× / 4× / 6× / 12× sliders.
    public enum ChipWrite: Equatable, Sendable {
        case slew(UInt16)
        case lens(UInt16)
    }

    public static func chipWrite(forJump factor: Double) -> ChipWrite? {
        if abs(factor - 1) < 0.1 { return .lens(lens1x) }
        if abs(factor - 2) < 0.1 { return .lens(lensPosition(for: 2)) }
        if abs(factor - 3) < 0.1 { return .lens(lens3x) }
        if abs(factor - 4) < 0.1 { return .lens(lensPosition(for: 4)) }
        if abs(factor - 6) < 0.1 { return .lens(lens6x) }
        if abs(factor - 12) < 0.1 { return .lens(lens12x) }
        return nil
    }

    /// Mimo pinch is always a slider. `slewing` is ignored (kept so call sites compile).
    public enum PinchCommand: Equatable, Sendable {
        case slider(UInt16)
        case slew(UInt16)
        case hold
    }

    public static func pinchCommand(
        live: Double, preview: Double, slewing: UInt16?
    ) -> PinchCommand {
        _ = live
        _ = slewing
        return .slider(pinchLens(for: preview))
    }

    /// Telephoto engages at 3.0×. 1.0…2.9 stays on the wide sensor.
    public static let teleEngage = 3.0

    /// Clamp only. The camera switches at 3.0× — do not invent a 2.9→3.0 hop.
    public static func snapHybrid(_ factor: Double) -> Double {
        clamp(factor)
    }

    /// Mimo-style 0.1× steps (1.0, 1.1, … 3.0, 3.1, … 12.0).
    public static func displayTenths(_ factor: Double) -> Double {
        (clamp(factor) * 10).rounded() / 10
    }

    /// Unquantized pinch target. The chip still shows `displayTenths`.
    public static func pinchFactor(
        anchor: Double, magnification: Double, max: Double = maxFactor
    ) -> Double {
        clamp(anchor * magnification, max: max)
    }

    /// Pinch HUD between status pushes. 0.1× quantized; 2.9× stays 2.9×.
    public static func pinchPreview(anchor: Double, magnification: Double) -> Double {
        displayTenths(pinchFactor(anchor: anchor, magnification: magnification))
    }

    /// Slider lens for a pinch target. Not snapped to 0.1× — Mimo steps lens by 1.
    public static func pinchLens(for factor: Double) -> UInt16 {
        lensPosition(for: factor)
    }

    /// Chip number: pinch preview while fingers are down, else live hybrid,
    /// else the last 1× / 3× / 6× / 12× stop.
    public static func readout(
        live: Double?, preview: Double?, fallback: Double, optimistic: Double? = nil
    ) -> Double {
        if let preview { return displayTenths(preview) }
        if let optimistic { return displayTenths(optimistic) }
        if let live { return displayTenths(live) }
        return displayTenths(fallback)
    }

    /// Lens is monotonic with the 1× → 12× pinch. `cam_fov` jumps at the 3× hop.
    public static func hybridFactor(raw: UInt32, lens: UInt16?) -> Double? {
        if let lens, let fromLens = factor(lens: lens) { return fromLens }
        return raw == 0 ? nil : factor(raw: raw)
    }

    public static func matches(_ live: Double, _ target: Double) -> Bool {
        abs(displayTenths(live) - displayTenths(target)) < 0.15
    }

    /// 3.0× and above use the telephoto sensor.
    public static func usesTelephoto(_ factor: Double) -> Bool {
        displayTenths(factor) >= teleEngage
    }

    /// D-Log2 cannot zoom at all. Any step off 1× must hop to D-Log first.
    public static func colorMode(forZoom factor: Double, current: ColorMode?) -> ColorMode? {
        guard current == .dLog2, displayTenths(factor) > 1.05 else { return nil }
        return .dLog
    }

    /// Body will not change color while rolling, so D-Log2 cannot leave 1×.
    public static func zoomNeedsColorHopWhileRecording(
        factor: Double, current: ColorMode?, isRecording: Bool
    ) -> Bool {
        isRecording && colorMode(forZoom: factor, current: current) != nil
    }

    /// Restore D-Log2 only when parked back at 1×, not at 2.9×.
    public static func shouldRestoreDLog2(factor: Double) -> Bool {
        displayTenths(factor) <= 1.05
    }
}
