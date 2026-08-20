import Foundation
import OpenPocketViewCore

/// Darwin-safe wire helpers used by the Android JNI shims. Compiles on macOS
/// so `swift test` still sees a real facade target; JNI itself stays
/// `#if os(Android)` in `SwiftCoreJNI.swift`.
public enum AndroidSessionWire {
    public static var coreVersion: String {
        #if arch(arm64)
            let arch = "arm64"
        #elseif arch(x86_64)
            let arch = "x86_64"
        #else
            let arch = "unknown"
        #endif
        return "OpenPocketViewCore swift-android/\(arch)"
    }

    /// Packed DUML frame: sender, receiver, seq LE, flags, cmdSet, cmdId, payload.
    public static func pack(_ frame: Duml.Frame) -> [UInt8] {
        var out: [UInt8] = [
            frame.sender,
            frame.receiver,
            UInt8(frame.seq & 0xFF),
            UInt8((frame.seq >> 8) & 0xFF),
            frame.flags,
            frame.cmdSet,
            frame.cmdId,
        ]
        out.append(contentsOf: frame.payload)
        return out
    }

    public static func unpack(_ data: [UInt8]) -> Duml.Frame? {
        guard data.count >= 7 else { return nil }
        let seq = UInt16(data[2]) | (UInt16(data[3]) << 8)
        return Duml.Frame(
            sender: data[0],
            receiver: data[1],
            seq: seq,
            flags: data[4],
            cmdSet: data[5],
            cmdId: data[6],
            payload: Array(data[7...])
        )
    }

    /// Concatenated scan: `[u16le count]` then `[u16le len][packed]…`.
    public static func packFrames(_ frames: [Duml.Frame]) -> [UInt8] {
        var out: [UInt8] = [
            UInt8(frames.count & 0xFF),
            UInt8((frames.count >> 8) & 0xFF),
        ]
        for frame in frames {
            let packed = pack(frame)
            out.append(UInt8(packed.count & 0xFF))
            out.append(UInt8((packed.count >> 8) & 0xFF))
            out.append(contentsOf: packed)
        }
        return out
    }

    public static func cameraModelJSON(modelId: Int?, name: String?) -> String {
        let model = CameraModel.resolve(modelId: modelId, name: name)
        func bool(_ v: Bool) -> String { v ? "true" : "false" }
        let escaped = (model.name)
            .replacingOccurrences(of: "\\", with: "\\\\")
            .replacingOccurrences(of: "\"", with: "\\\"")
        return """
        {"name":"\(escaped)","datalinkPort":\(model.datalinkPort),"tcpPoke":\(bool(model.tcpPoke)),"wpa3":\(bool(model.wpa3)),"verified":\(bool(model.verified)),"isDrone":\(bool(model.isDrone)),"pairingToken":"\(model.pairingToken)"}
        """
    }

    public static func statusJSON(_ status: CameraStatus) -> String {
        func bool(_ v: Bool) -> String { v ? "true" : "false" }
        func quote(_ s: String?) -> String {
            guard let s else { return "null" }
            let escaped = s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        let blob = status.audioDspBlob.flatMap { $0.isEmpty ? nil : hex($0) }
        func ints(_ xs: [Int]) -> String {
            "[\(xs.map(String.init).joined(separator: ","))]"
        }
        let isoCaps = status.availableIsoIndices.map { Int($0.rawValue) }
        return """
        {"batteryPercent":\(status.batteryPercent),"batteryMilliVolts":\(status.batteryMilliVolts),"batteryMilliAmps":\(status.batteryMilliAmps),"docked":\(bool(status.docked)),"charging":\(bool(status.charging)),"storageTotalMb":\(status.storageTotalMb),"storageFreeMb":\(status.storageFreeMb),"sdTotalMb":\(status.sdTotalMb),"sdFreeMb":\(status.sdFreeMb),"internalTotalMb":\(status.internalTotalMb),"internalFreeMb":\(status.internalFreeMb),"inPlayback":\(bool(status.inPlayback)),"firmware":\(quote(status.firmware)),"isRecording":\(bool(status.isRecording)),"shootingMode":\(status.shootingMode),"recordElapsedSec":\(status.recordElapsedSec),"recordRemainingSec":\(status.recordRemainingSec),"timecode":\(quote(status.timecode)),"iso":\(status.iso),"shutterDenom":\(status.shutterDenom),"fps":\(status.fps),"expoMode":\(intOrMinus(status.expoMode?.rawValue)),"isoIndex":\(intOrMinus(status.isoIndex?.rawValue)),"colorMode":\(intOrMinus(status.colorMode?.rawValue)),"videoResolution":\(intOrMinus(status.videoResolution?.rawValue)),"fpsIndex":\(intOrMinus(status.videoFormat?.frameRate.rawValue)),"whiteBalanceMode":\(intOrMinus(status.whiteBalance?.mode.rawValue)),"whiteBalanceKelvin":\(status.whiteBalanceKelvin),"whiteBalanceTint":\(status.whiteBalanceTint ?? 0),"focusMode":\(intOrMinus(status.focusMode?.rawValue)),"audioChannel":\(intOrMinus(status.audioChannel?.rawValue)),"vocalBoost":\(intOrMinus(status.vocalBoost?.rawValue)),"audioDspAt2":\(intOrMinus(status.audioDspAt2?.rawValue)),"audioDspBlob":\(quote(blob)),"zoomFactorRaw":\(status.zoomFactorRaw),"availableShutterDenoms":\(ints(status.availableShutterDenoms)),"availableIsoIndices":\(ints(isoCaps))}
        """
    }

    public static func status(fromJSON json: String) -> CameraStatus {
        var status = CameraStatus()
        func int(_ key: String, default def: Int) -> Int {
            guard let range = json.range(of: "\"\(key)\":") else { return def }
            let tail = json[range.upperBound...]
            var digits = ""
            for ch in tail {
                if ch == "-" && digits.isEmpty { digits.append(ch); continue }
                if ch.isNumber { digits.append(ch) } else { break }
            }
            return Int(digits) ?? def
        }
        func flag(_ key: String) -> Bool {
            json.contains("\"\(key)\":true")
        }
        func str(_ key: String) -> String? {
            guard let range = json.range(of: "\"\(key)\":\"") else { return nil }
            var s = ""
            for ch in json[range.upperBound...] {
                if ch == "\"" { break }
                s.append(ch)
            }
            return s.isEmpty ? nil : s
        }
        func intArray(_ key: String) -> [Int] {
            guard let range = json.range(of: "\"\(key)\":[") else { return [] }
            var out: [Int] = []
            var digits = ""
            for ch in json[range.upperBound...] {
                if ch == "]" {
                    if let n = Int(digits) { out.append(n) }
                    break
                }
                if ch == "-" && digits.isEmpty { digits.append(ch); continue }
                if ch.isNumber { digits.append(ch) }
                else if ch == "," {
                    if let n = Int(digits) { out.append(n) }
                    digits = ""
                }
            }
            return out
        }
        status.batteryPercent = int("batteryPercent", default: -1)
        status.batteryMilliVolts = int("batteryMilliVolts", default: 0)
        status.batteryMilliAmps = int("batteryMilliAmps", default: 0)
        status.docked = flag("docked")
        status.charging = flag("charging")
        status.storageTotalMb = int("storageTotalMb", default: 0)
        status.storageFreeMb = int("storageFreeMb", default: 0)
        status.sdTotalMb = int("sdTotalMb", default: 0)
        status.sdFreeMb = int("sdFreeMb", default: 0)
        status.internalTotalMb = int("internalTotalMb", default: -1)
        status.internalFreeMb = int("internalFreeMb", default: -1)
        status.inPlayback = flag("inPlayback")
        status.isRecording = flag("isRecording")
        status.shootingMode = int("shootingMode", default: -1)
        status.recordElapsedSec = int("recordElapsedSec", default: 0)
        status.recordRemainingSec = int("recordRemainingSec", default: 0)
        status.iso = int("iso", default: -1)
        status.shutterDenom = int("shutterDenom", default: -1)
        status.fps = int("fps", default: 0)
        status.timecode = str("timecode")
        status.firmware = str("firmware")
        if let mode = ExpoMode(rawValue: UInt8(truncatingIfNeeded: int("expoMode", default: -1))) {
            status.expoMode = mode
        }
        if let idx = IsoIndex(rawValue: UInt8(truncatingIfNeeded: int("isoIndex", default: -1))) {
            status.isoIndex = idx
        }
        if let color = ColorMode(rawValue: UInt8(truncatingIfNeeded: int("colorMode", default: -1))) {
            status.colorMode = color
        }
        if let res = VideoResolution(rawValue: UInt8(truncatingIfNeeded: int("videoResolution", default: -1))) {
            status.videoResolution = res
        }
        if let fpsIdx = VideoFrameRate(rawValue: UInt8(truncatingIfNeeded: int("fpsIndex", default: -1))),
           let res = status.videoResolution {
            status.videoFormat = VideoFormat(resolution: res, frameRate: fpsIdx)
        }
        let wbMode = WhiteBalanceMode(rawValue: UInt8(truncatingIfNeeded: int("whiteBalanceMode", default: -1)))
        if let wbMode {
            status.whiteBalance = WhiteBalance(
                mode: wbMode,
                kelvin: int("whiteBalanceKelvin", default: -1),
                tint: int("whiteBalanceTint", default: 0)
            )
            status.whiteBalanceKelvin = status.whiteBalance?.kelvin ?? -1
            status.whiteBalanceTint = status.whiteBalance?.tint
        } else {
            status.whiteBalanceKelvin = int("whiteBalanceKelvin", default: -1)
        }
        if let focus = FocusMode(rawValue: UInt8(truncatingIfNeeded: int("focusMode", default: -1))) {
            status.focusMode = focus
        }
        if let ch = AudioChannel(rawValue: UInt8(truncatingIfNeeded: int("audioChannel", default: -1))) {
            status.audioChannel = ch
        }
        if let boost = VocalBoost(rawValue: UInt8(truncatingIfNeeded: int("vocalBoost", default: -1))) {
            status.vocalBoost = boost
        }
        if let hex = str("audioDspBlob"), let bytes = hexBytes(hex), bytes.count == AudioDspBlob.size {
            status.audioDspBlob = bytes
            if bytes.count > 2 {
                AudioDspBlob.applyByte2(bytes[2], to: &status)
            } else {
                status.audioDspAt2 = AudioDspBlob.at2(bytes)
            }
        } else if let at2 = optionalUInt8(int("audioDspAt2", default: -1)) {
            AudioDspBlob.applyByte2(at2, to: &status)
        }
        let zoomRaw = int("zoomFactorRaw", default: 0)
        if zoomRaw > 0 { status.zoomFactorRaw = UInt32(clamping: zoomRaw) }
        status.availableShutterDenoms = intArray("availableShutterDenoms").filter { (1...16_000).contains($0) }
        status.availableIsoIndices = intArray("availableIsoIndices").compactMap {
            IsoIndex(rawValue: UInt8(truncatingIfNeeded: $0))
        }
        return status
    }

    public enum CommandKind: Int32 {
        case sessionWake = 1
        case sessionKeepalive = 2
        case setPairingPin = 3
        case pairApprovalAck = 4
        case session5310 = 5
        case getWifiSsid = 6
        case getWifiPassword = 7
        case appDeviceInfo = 8
        case appPresence = 9
        case gimbalInit = 10
        case subscribe = 11
        case enterPlayback = 12
        case liveViewEnable = 13
        case recordStart = 14
        case recordStop = 15
        case setExpoMode = 16
        case setShutter = 17
        case setIsoIndex = 18
        case setColorMode = 19
        case setFocusMode = 20
        case setWhiteBalanceAuto = 21
        case setWhiteBalanceCustom = 22
        case getAudioChannel = 23
        case setAudioChannel = 24
        case getVocalBoost = 25
        case setVocalBoost = 26
        case audioDspGet = 27
        case audioDspSet = 28
        case audioDspPatchWind = 29
        case audioDspPatchDirectional = 30
        case setVideoFormat = 31
        case tapFocusPrepare = 32
        case tapFocusPoint = 33
        case tapFocusHint = 34
        case tapFocusCommit = 35
    }

    public static func encodeCommand(kind: CommandKind, seq: UInt16, extra: String?) -> Duml.Frame? {
        switch kind {
        case .sessionWake:
            return Commands.sessionWake(id: seq)
        case .sessionKeepalive:
            return Commands.sessionKeepalive(id: seq)
        case .setPairingPin:
            return Commands.setPairingPin(pin: extra ?? "osmo", id: seq)
        case .pairApprovalAck:
            return Commands.pairApprovalAck(seq: seq)
        case .session5310:
            return Commands.session5310(id: seq)
        case .getWifiSsid:
            return Commands.getWifiSsid(id: seq)
        case .getWifiPassword:
            return Commands.getWifiPassword(id: seq)
        case .appDeviceInfo:
            return Commands.appDeviceInfo(seq: seq)
        case .appPresence:
            return Commands.appPresenceFrame(seq: seq)
        case .gimbalInit:
            return Commands.gimbalInit(seq: seq)
        case .subscribe:
            let parts = (extra ?? "").split(separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let subId = UInt32(parts[1]) else { return nil }
            return Commands.subscribe(key: String(parts[0]), subId: subId, seq: seq)
        case .enterPlayback:
            return Commands.enterPlayback(seq: seq)
        case .liveViewEnable:
            return Commands.liveViewEnable(seq: seq)
        case .recordStart:
            return Commands.recordStart(seq: seq)
        case .recordStop:
            return Commands.recordStop(seq: seq)
        case .setExpoMode:
            let mode: ExpoMode = (extra == "manual" || extra == "4") ? .manual : .auto
            return Commands.setExpoMode(mode, seq: seq)
        case .setShutter:
            guard let denom = extra.flatMap(Int.init) else { return nil }
            return Commands.setShutter(denom: denom, seq: seq)
        case .setIsoIndex:
            guard let raw = extra.flatMap({ UInt8($0) }), let index = IsoIndex(rawValue: raw) else { return nil }
            return Commands.setIsoIndex(index, seq: seq)
        case .setColorMode:
            guard let raw = extra.flatMap({ UInt8($0) }), let mode = ColorMode(rawValue: raw) else { return nil }
            return Commands.setColorMode(mode, seq: seq)
        case .setFocusMode:
            let mode: FocusMode = (extra == "2" || extra == "continuous") ? .continuous : .single
            return Commands.setFocusMode(mode, seq: seq)
        case .setWhiteBalanceAuto:
            return Commands.setWhiteBalanceAuto(seq: seq)
        case .setWhiteBalanceCustom:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let kelvin = Int(parts[0]), let tint = Int(parts[1]) else { return nil }
            return Commands.setWhiteBalanceCustom(kelvin: kelvin, tint: tint, seq: seq)
        case .getAudioChannel:
            return Commands.getAudioChannel(seq: seq)
        case .setAudioChannel:
            guard let raw = extra.flatMap({ UInt8($0) }), let channel = AudioChannel(rawValue: raw) else { return nil }
            return Commands.setAudioChannel(channel, seq: seq)
        case .getVocalBoost:
            return Commands.getVocalBoost(seq: seq)
        case .setVocalBoost:
            let boost: VocalBoost = (extra == "1" || extra == "on") ? .on : .off
            return Commands.setVocalBoost(boost, seq: seq)
        case .audioDspGet:
            return Commands.audioDspGet(seq: seq)
        case .audioDspSet:
            guard let blob = hexBytes(extra ?? "") else { return nil }
            return Commands.audioDspSet(blob, seq: seq)
        case .audioDspPatchWind:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let blob = hexBytes(parts[0]) else { return nil }
            let wind: WindNoiseReduction = (parts[1] == "1" || parts[1] == "on") ? .on : .off
            return Commands.audioDspSet(AudioDspBlob.patchWind(blob, wind), seq: seq)
        case .audioDspPatchDirectional:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let blob = hexBytes(parts[0]) else { return nil }
            let dir: DirectionalAudio
            switch parts[1] {
            case "1", "front": dir = .front
            case "2", "frontAndBack": dir = .frontAndBack
            default: dir = .all
            }
            return Commands.audioDspSet(AudioDspBlob.patchDirectional(blob, dir), seq: seq)
        case .setVideoFormat:
            let parts = splitExtra(extra)
            guard parts.count >= 2,
                  let resRaw = UInt8(parts[0]), let fpsRaw = UInt8(parts[1]),
                  let res = VideoResolution(rawValue: resRaw),
                  let fps = VideoFrameRate(rawValue: fpsRaw)
            else { return nil }
            return Commands.setVideoFormat(resolution: res, frameRate: fps, seq: seq)
        case .tapFocusPrepare:
            return Commands.tapFocusPrepare(seq: seq)
        case .tapFocusPoint:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let x = Float(parts[0]), let y = Float(parts[1]) else { return nil }
            return Commands.tapFocusPoint(x, y, seq: seq)
        case .tapFocusHint:
            return Commands.tapFocusLiveHint(seq: seq)
        case .tapFocusCommit:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let x = Float(parts[0]), let y = Float(parts[1]) else { return nil }
            return Commands.tapFocusCommit(x, y, seq: seq)
        }
    }

    private static func intOrMinus(_ value: UInt8?) -> Int {
        guard let value else { return -1 }
        return Int(value)
    }

    private static func optionalUInt8(_ value: Int) -> UInt8? {
        guard (0...255).contains(value) else { return nil }
        return UInt8(value)
    }

    private static func splitExtra(_ extra: String?) -> [String] {
        (extra ?? "").split(separator: "\u{1f}", omittingEmptySubsequences: false).map(String.init)
    }

    static func hex(_ bytes: [UInt8]) -> String {
        bytes.map { String(format: "%02x", $0) }.joined()
    }

    static func hexBytes(_ hex: String) -> [UInt8]? {
        let s = hex.filter { !$0.isWhitespace }
        guard !s.isEmpty, s.count.isMultiple(of: 2) else { return nil }
        var out: [UInt8] = []
        out.reserveCapacity(s.count / 2)
        var i = s.startIndex
        while i < s.endIndex {
            let j = s.index(i, offsetBy: 2)
            guard let byte = UInt8(s[i..<j], radix: 16) else { return nil }
            out.append(byte)
            i = j
        }
        return out
    }

    public static func csd(from annexB: [UInt8]) -> [UInt8]? {
        let nals = Hevc.nalUnits(annexB)
        let avc = LiveVideo.detect(nals: nals) == .avc
        var out: [UInt8] = []
        for nal in nals {
            guard let first = nal.first else { continue }
            let keep: Bool
            if avc {
                let type = Avc.nalType(first)
                keep = type == Avc.sps || type == Avc.pps
            } else {
                let type = Hevc.nalType(first)
                keep = type == Hevc.vps || type == Hevc.sps || type == Hevc.pps
            }
            if keep {
                out.append(contentsOf: [0, 0, 0, 1])
                out.append(contentsOf: nal)
            }
        }
        return out.isEmpty ? nil : out
    }

    public static func nalTypeSummary(_ annexB: [UInt8]) -> String {
        let nals = Hevc.nalUnits(annexB)
        let avc = LiveVideo.detect(nals: nals) == .avc
        let types = nals.compactMap { nal -> Int? in
            guard let first = nal.first else { return nil }
            return avc ? Avc.nalType(first) : Hevc.nalType(first)
        }
        return Set(types).sorted().map(String.init).joined(separator: ",")
    }
}

/// Mutable depacketizer box so JNI can hold a handle across feeds.
public final class HevcDepacketizerBox: @unchecked Sendable {
    public var depacketizer = HevcDepacketizer()
    public init() {}
}
