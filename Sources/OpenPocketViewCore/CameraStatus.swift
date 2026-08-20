import Foundation

/// The decoded live status the camera pushes unprompted over the datalink. Ported from Osmosis
/// `net/DumlSession.kt` (`applyStatusFrame`) and `core/CameraStatus.kt`.
public struct CameraStatus: Equatable, Sendable {
    public var batteryPercent: Int = -1
    public var batteryMilliVolts: Int = 0
    public var batteryMilliAmps: Int = 0     // signed; negative = discharging
    public var docked = false
    public var charging = false
    public var storageTotalMb = 0
    public var storageFreeMb = 0
    public var sdTotalMb = 0
    public var sdFreeMb = 0
    public var internalTotalMb = -1          // -1 unknown, 0 confirmed absent
    public var internalFreeMb = -1
    public var inPlayback = false
    public var firmware: String?
    /// `0x02/0x80` byte0 bit7 (Osmosis recording bit). Idle live1 is `0x01`.
    public var isRecording = false
    /// `0x02/0x80` `@57` — Osmosis `0x02/0xE1` shooting-mode enum. `-1` = not present.
    public var shootingMode: Int = -1
    /// `0x02/0x80` `@29` elapsed seconds while recording (0 when idle).
    public var recordElapsedSec: Int = 0
    /// Best-effort remaining record time from `0x02/0x80` `@17` (seconds). 0 = unknown/idle.
    public var recordRemainingSec: Int = 0
    /// SMPTE-style readout from `timecode_info` (`@3–6` = HH MM SS FF). HUD uses `timecodeClock`.
    public var timecode: String?
    /// Auto/manual from `cam_expo_param` `@7`. nil unknown. Not a DUML GET — Mimo never GETs `0x1E`.
    public var expoMode: ExpoMode?
    /// ISO number from `cam_expo_param` u16-LE `@16`. `-1` unknown. `@13` is not ISO.
    public var iso: Int = -1
    /// ISO index from `cam_expo_param` `@5`. nil unknown.
    public var isoIndex: IsoIndex?
    /// EV from `cam_expo_param` `@6` (`0x02/0x2E` echo). nil unknown / out of −3…+3.
    public var evComp: EvComp?
    /// Last `0x8E` pid `0x000F` GET reply (Auto ISO ceiling).
    public var isoLimit: IsoLimit?
    /// Shutter as 1/N from `cam_expo_param` `@2–3` (`denom | 0x8000`). `-1` unknown. Not `@16`.
    public var shutterDenom: Int = -1
    /// Legal 1/N denoms from `camcap_shutter`, camera order. Empty until the cap push.
    public var availableShutterDenoms: [Int] = []
    /// Legal ISO indices from `camcap_iso`. Empty until the cap push.
    public var availableIsoIndices: [IsoIndex] = []
    /// Frame rate from `cam_video_param_v2` fps index `@1`. 0 = unknown.
    public var fps: Int = 0
    /// Resolution from `cam_video_param_v2` `@0` (`0A` 1080p / `10` 4K). nil if unlabeled.
    public var videoResolution: VideoResolution?
    /// Packed res+fps when both `@0–1` are labeled values.
    public var videoFormat: VideoFormat?
    /// Color from `cam_image_effect` `@2`.
    public var colorMode: ColorMode?
    /// Legal `0x02/0x42` values from `camcap_color_mode`. Empty until that push.
    public var availableColorModes: [ColorMode] = []
    /// Scopes / false colour / zebra transfer for `colorMode`. Nil until `@2` arrives.
    public var monitorTransfer: MonitorTransfer? { colorMode.map(MonitorTransfer.init) }
    /// WB from `cam_image_effect` `@4–8`. Expo does not carry WB.
    public var whiteBalance: WhiteBalance?
    /// Kelvin from `whiteBalance` when custom and > 0; `-1` unknown / Auto.
    public var whiteBalanceKelvin: Int = -1
    /// Tint from `whiteBalance` (`−100…+100`). nil unknown.
    public var whiteBalanceTint: Int?
    /// Focus from `cam_lens_state` `@0` (`B1` Single / `B2` Continuous).
    public var focusMode: FocusMode?
    /// AF point from `cam_lens_state` f32 `@1` / `@5`. 0.5, 0.5 until a tap.
    public var focusX: Double = CamLensState.defaultX
    public var focusY: Double = CamLensState.defaultY
    /// True after a `cam_lens_state` blob carried a legal AF point.
    public var hasCameraFocusPoint = false
    /// Last `0x8E` pid `0x003B` GET/SET. AF-C submenu; ignored while AF-S.
    public var focusTrack: FocusTrackMode?
    /// `cam_fov` u32-LE `@0`. 0 = unknown. 12287 is operator 1×, not 12×.
    public var zoomFactorRaw: UInt32 = 0
    /// `cam_lens_state` u16-LE `@14`. nil until a long enough push arrives.
    public var zoomLens: UInt16?
    /// Hybrid zoom (1.0×…12×). Prefers lens `@14` (monotonic 1×→12× pinch).
    public var zoomFactor: Double? {
        CamFov.hybridFactor(raw: zoomFactorRaw, lens: zoomLens)
    }
    /// Last `0x8E` pid `0x0020` GET reply.
    public var audioChannel: AudioChannel?
    /// Last `0x8E` pid `0x0039` 62-byte glamour blob.
    public var glamourBlob: [UInt8]?
    /// True when glamour blob `@5` is non-zero.
    public var glamourEnabled: Bool?
    /// Last `0x8E` pid `0x004C` GET reply.
    public var vocalBoost: VocalBoost?
    /// Last `0xA0` GET blob (26 B). Patch `@2`, SET `0x9F` — do not invent the rest.
    public var audioDspBlob: [UInt8]?
    /// Interpreted audio-DSP blob `@2`.
    public var audioDspAt2: AudioDspAt2?
    /// Wind NR from DSP `@2`. Survives a directional byte (those include wind-on).
    public var windNR: WindNoiseReduction?
    /// Directional audio from DSP `@2`. Kept when `@2` is a wind-only byte.
    public var directionalAudio: DirectionalAudio?
    /// Live VU / peak from subscribe `cam_audio_status_v2`. Camera-held; no local decay.
    public var audioMeters: AudioMeterLevels = .silent
    /// Last raw `cam_audio_status_v2` value (diagnostics / verify-on-HW).
    public var audioStatusRaw: [UInt8]?
    /// `0x04/0x27` `@2` bit `0x40`.
    public var gimbalFace: GimbalFace?
    /// Last `0x04/0x50` GET reply. Cannot tell FPV from Tilt Locked.
    public var gimbalParams: GimbalParamState?
    /// Mechanical iris readout. Pocket has none; `cam_blur_aperture` is beauty blur, not f-stop.
    public var irisLabel: String?
    public init() {}

    /// Osmo live bar: hours:minutes:seconds. Frames stay in `timecode` (`@6`).
    public var timecodeClock: String { Self.clockDisplay(timecode) }

    public static func clockDisplay(_ raw: String?) -> String {
        guard let raw, !raw.isEmpty else { return "--:--:--" }
        let parts = raw.split(separator: ":")
        guard parts.count >= 3 else { return raw }
        return parts.prefix(3).joined(separator: ":")
    }

    public var shootingModeLabel: String {
        switch shootingMode {
        case 0x00: "SlowMo"
        case 0x01: "Video"
        case 0x02: "TimeLapse"
        case 0x05, 0x17: "Photo"
        case 0x0A: "HyperLapse"
        case 0x28: "SuperNight"
        case -1: inPlayback ? "Playback" : "Capture"
        default: String(format: "0x%02X", shootingMode)
        }
    }
}

public enum CameraStatusDecoder {
    /// Apply one status push frame to `status`. Returns true if it was a recognised status frame.
    @discardableResult
    public static func apply(_ frame: Duml.Frame, to status: inout CameraStatus) -> Bool {
        let p = frame.payload
        switch (frame.cmdSet, frame.cmdId) {
        case (0x02, 0x80) where p.count >= 13:
            // bit 30 of the flags word = the camera's own "am I in playback"; storage of active store.
            let flags = u32(p, 0)
            status.inPlayback = (flags & 0x4000_0000) != 0
            status.isRecording = (flags & 0x0000_0080) != 0
            let total = Int(u32(p, 5)), free = Int(u32(p, 9))
            if (1...50_000_000).contains(total) { status.storageTotalMb = total }
            if (0...50_000_000).contains(free) { status.storageFreeMb = free }
            if p.count >= 21 {
                let remain = Int(u32(p, 17))
                if (0...86_400).contains(remain) { status.recordRemainingSec = remain }
            }
            if p.count >= 31 {
                status.recordElapsedSec = Int(u16(p, 29))
            }
            if p.count >= 58 { status.shootingMode = Int(p[57]) }
            return true

        case (0x02, 0xDC) where p.count >= 22:
            // [total][free] u32-LE MiB per store: first (SD) @6/@10, built-in @24/@28 when present.
            let sdTotal = Int(u32(p, 6)), sdFree = Int(u32(p, 10))
            let hasInternal = p.count >= 32
            if sane(sdTotal) { status.sdTotalMb = sdTotal }
            if sane(sdFree) { status.sdFreeMb = sdFree }
            if hasInternal {
                let it = Int(u32(p, 24)), ifree = Int(u32(p, 28))
                if sane(it) { status.internalTotalMb = it }
                if sane(ifree) { status.internalFreeMb = ifree }
            } else {
                status.internalTotalMb = 0; status.internalFreeMb = 0   // single-store: confirmed absent
            }
            return true

        case (0x0D, 0x02) where p.count >= 21:
            // u16@1 mV, i32@5 mA (signed), @20 percent, @27 dock attached, @32 charging.
            if p.count >= 34 {
                let mv = Int(p[1]) | (Int(p[2]) << 8)
                status.batteryMilliAmps = Int(Int32(bitPattern: u32(p, 5)))   // signed mA
                status.docked = p[27] != 0
                status.charging = p[32] == 1
                if (2000...5000).contains(mv) { status.batteryMilliVolts = mv }
            }
            let bp = Int(p[20])
            if (0...100).contains(bp) { status.batteryPercent = bp }
            return true

        case (0x04, 0x05):
            return true   // gimbal position heartbeat — swallow, it is not a running-state signal

        case (0x04, 0x27):
            if let face = GimbalFace.parse(p) { status.gimbalFace = face }
            return p.count > 2

        case (0x04, 0x50):
            if let params = GimbalParamState.parseGetReply(p) {
                status.gimbalParams = params
                return true
            }
            return false

        case (0x02, 0x8E):
            if let blob = GlamourEffect.blob(fromGetReply: p) {
                status.glamourBlob = blob
                status.glamourEnabled = GlamourEffect.isEnabled(blob)
                return true
            }
            if let track = FocusTrackMode.parseReply(p) {
                status.focusTrack = track
                return true
            }
            if let parsed = CameraParam.parseGetReply(p) {
                switch parsed.pid {
                case CameraParam.audioChannel.rawValue:
                    status.audioChannel = AudioChannel(rawValue: parsed.value)
                case CameraParam.vocalBoost.rawValue:
                    status.vocalBoost = VocalBoost(rawValue: parsed.value)
                case CameraParam.isoLimit.rawValue:
                    status.isoLimit = IsoLimit(rawValue: parsed.value)
                default:
                    break
                }
                return true
            }
            return false

        case (0x02, 0xA0):
            if let blob = AudioDspBlob.blob(fromGetReply: p) {
                status.audioDspBlob = blob
                if blob.count > 2 {
                    AudioDspBlob.applyByte2(blob[2], to: &status)
                } else {
                    status.audioDspAt2 = AudioDspBlob.at2(blob)
                }
                return true
            }
            return false

        case (0x00, 0x00) where p.count >= 6:
            if let fw = firmware(p) { status.firmware = fw; return true }
            return false

        case (0x00, 0x99):
            return applySubscribePush(p, to: &status)

        default:
            return false
        }
    }

    /// `0x00/0x99` camera→app push: `02 06 00 00 | idx | 00×3 | total_len | name_len | name | 00×6 | value_len | value`.
    @discardableResult
    public static func applySubscribePush(_ payload: [UInt8], to status: inout CameraStatus) -> Bool {
        guard let item = SubscribePush.parse(payload) else { return false }
        switch item.name {
        case "timecode_info" where item.value.count >= 8:
            status.timecode = Self.timecodeString(item.value)
            return true
        case CamCapShutter.subscribeKey:
            let denoms = CamCapShutter.parseDenoms(item.value)
            if !denoms.isEmpty { status.availableShutterDenoms = denoms }
            return !denoms.isEmpty
        case CamCapIso.subscribeKey:
            let indices = CamCapIso.parseIndices(item.value)
            if !indices.isEmpty { status.availableIsoIndices = indices }
            return !indices.isEmpty
        case CamCapColorMode.subscribeKey:
            let modes = CamCapColorMode.parse(item.value)
            if !modes.isEmpty { status.availableColorModes = modes }
            return !modes.isEmpty
        case "cam_expo_param" where item.value.count >= 8:
            if let mode = ExpoMode.parseExpoParam(item.value) { status.expoMode = mode }
            if let denom = ExpoParam.shutterDenom(item.value) { status.shutterDenom = denom }
            if let idx = ExpoParam.isoIndex(item.value) { status.isoIndex = idx }
            if let iso = ExpoParam.isoValue(item.value) { status.iso = iso }
            status.evComp = ExpoParam.evComp(item.value)
            return true
        case "cam_video_param_v2" where item.value.count >= 2:
            if let fps = fps(index: item.value[1]) { status.fps = fps }
            if let res = VideoResolution(rawValue: item.value[0]) { status.videoResolution = res }
            if let format = VideoFormat.parseVideoParamV2(item.value) { status.videoFormat = format }
            return true
        case "cam_image_effect" where item.value.count > 2:
            if let color = ColorMode.parseImageEffect(item.value) { status.colorMode = color }
            if let wb = WhiteBalance.parseImageEffect(item.value) {
                status.whiteBalance = wb
                status.whiteBalanceKelvin = wb.kelvin > 0 ? wb.kelvin : -1
                status.whiteBalanceTint = wb.tint
            }
            return true
        case "cam_lens_state" where !item.value.isEmpty:
            if let focus = FocusMode.parseLensState(item.value) { status.focusMode = focus }
            if let lens = CamFov.lensAt14(item.value) { status.zoomLens = lens }
            if let point = CamLensState.focusPoint(item.value) {
                status.focusX = point.x
                status.focusY = point.y
                status.hasCameraFocusPoint = true
            }
            return true
        case "cam_fov" where item.value.count >= 4:
            if let raw = CamFov.rawAt0(item.value) { status.zoomFactorRaw = raw }
            return true
        case "cam_record_time" where item.value.count >= 4:
            let sec = Int(u32(item.value, 0))
            if (0...86_400).contains(sec) { status.recordElapsedSec = sec }
            return true
        case CamAudioStatus.subscribeKey:
            status.audioStatusRaw = item.value
            if let levels = CamAudioStatus.parse(item.value) {
                status.audioMeters = levels
            }
            return true
        default:
            return false
        }
    }

    /// `timecode_info` 8 B: `@3–6` = HH MM SS FF (2026-08-14 Mimo: `00 00 00 05 16 2f 12 00` → `05:22:47:18`).
    /// `@0–2` stay 0; `@7` unused. Older live1 decode used `@4–7` and showed 22:xx as hours.
    public static func timecodeString(_ value: [UInt8]) -> String {
        let hh = Int(value[3]), mm = Int(value[4]), ss = Int(value[5])
        return String(format: "%02d:%02d:%02d:%02d", hh, mm, ss, Int(value[6]))
    }

    /// Osmosis `VideoFrameRate` table (Nano / Pocket share the index).
    public static func fps(index: UInt8) -> Int? {
        switch index {
        case 1: 24
        case 2: 25
        case 3: 30
        case 4: 48
        case 5: 50
        case 6: 60
        case 7: 120
        case 8: 240
        case 10: 100
        case 11: 96
        case 29: 15
        default: nil
        }
    }

    private static func u16(_ p: [UInt8], _ i: Int) -> UInt16 {
        UInt16(p[i]) | (UInt16(p[i + 1]) << 8)
    }
    private static func u32(_ p: [UInt8], _ i: Int) -> UInt32 {
        UInt32(p[i]) | (UInt32(p[i + 1]) << 8) | (UInt32(p[i + 2]) << 16) | (UInt32(p[i + 3]) << 24)
    }
    private static func sane(_ v: Int) -> Bool { (0...50_000_000).contains(v) }

    // GetVersion reply is NUL-separated ASCII (sdk\0name\0firmware); take the last version-shaped token.
    private static func firmware(_ p: [UInt8]) -> String? {
        p.split(separator: 0x00).reversed().lazy
            .map { String(decoding: $0, as: UTF8.self) }
            .first { $0.count >= 4 && $0.count <= 24 && $0.contains(where: \.isNumber) }
    }
}

/// Osmosis §8 camera→app subscribe push. Subscribe requests use verb `02 02`; pushes use `02 06`.
public enum SubscribePush {
    public static func parse(_ payload: [UInt8]) -> (name: String, value: [UInt8])? {
        guard payload.count >= 24, payload[0] == 0x02, payload[1] == 0x06 else { return nil }
        let nameLen = Int(payload[13]) | (Int(payload[14]) << 8)
        guard nameLen > 0, nameLen < 80, 15 + nameLen + 8 <= payload.count else { return nil }
        let nameBytes = payload[15..<(15 + nameLen)]
        guard let name = String(bytes: nameBytes, encoding: .utf8), !name.isEmpty else { return nil }
        let valueLenAt = 15 + nameLen + 6
        guard valueLenAt + 2 <= payload.count else { return nil }
        let valueLen = Int(payload[valueLenAt]) | (Int(payload[valueLenAt + 1]) << 8)
        let valueAt = valueLenAt + 2
        guard valueAt + valueLen <= payload.count else { return nil }
        return (name, Array(payload[valueAt..<(valueAt + valueLen)]))
    }

    /// Build a push payload for tests (and Android JSON round-trips).
    public static func pack(name: String, value: [UInt8], idx: UInt32 = 0) -> [UInt8] {
        let nb = Array(name.utf8)
        var p: [UInt8] = [0x02, 0x06, 0x00, 0x00]
        p += [
            UInt8(idx & 0xFF), UInt8((idx >> 8) & 0xFF),
            UInt8((idx >> 16) & 0xFF), UInt8((idx >> 24) & 0xFF),
        ]
        p += [0, 0, 0]
        let inner = 2 + nb.count + 6 + 2 + value.count
        p += [UInt8(inner & 0xFF), UInt8((inner >> 8) & 0xFF)]
        p += [UInt8(nb.count & 0xFF), UInt8((nb.count >> 8) & 0xFF)]
        p += nb
        p += [0, 0, 0, 0, 0, 0]
        p += [UInt8(value.count & 0xFF), UInt8((value.count >> 8) & 0xFF)]
        p += value
        return p
    }
}
