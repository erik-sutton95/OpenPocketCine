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
        let family: String
        switch model.family {
        case .pocket: family = "pocket"
        case .nano: family = "nano"
        case .other: family = "other"
        }
        let zoomStops = model.zoomStops.map { String($0) }.joined(separator: ",")
        return """
            {"name":"\(escaped)","datalinkPort":\(model.datalinkPort),"tcpPoke":\(bool(model.tcpPoke)),"wpa3":\(bool(model.wpa3)),"verified":\(bool(model.verified)),"isDrone":\(bool(model.isDrone)),"pairingToken":"\(model.pairingToken)","family":"\(family)","liveViewEnableReceiver":\(Int(model.liveViewEnableReceiver)),"usesNanoLiveViewGate":\(bool(model.usesNanoLiveViewGate)),"supportsTapFocus":\(bool(model.supportsTapFocus)),"supportsFocusMode":\(bool(model.supportsFocusMode)),"usesCapturedLiveEnable":\(bool(model.usesCapturedLiveEnable)),"needsFirstPictureFormatPoke":\(bool(model.needsFirstPictureFormatPoke)),"zoomStops":[\(zoomStops)]}
            """
    }

    public static func statusJSON(_ status: CameraStatus) -> String {
        func bool(_ v: Bool) -> String { v ? "true" : "false" }
        func quote(_ s: String?) -> String {
            guard let s else { return "null" }
            let escaped =
                s
                .replacingOccurrences(of: "\\", with: "\\\\")
                .replacingOccurrences(of: "\"", with: "\\\"")
            return "\"\(escaped)\""
        }
        let blob = status.audioDspBlob.flatMap { $0.isEmpty ? nil : hex($0) }
        func ints(_ xs: [Int]) -> String {
            "[\(xs.map(String.init).joined(separator: ","))]"
        }
        let isoCaps = status.availableIsoIndices.map { Int($0.rawValue) }
        let colorCaps = status.availableColorModes.map { Int($0.rawValue) }
        let formatCaps = status.availableVideoFormats.flatMap {
            [Int($0.resolution.rawValue), Int($0.frameRate.rawValue)]
        }
        let zoomFactorJSON = status.zoomFactor.map { String($0) } ?? "null"
        let glamourJSON = status.glamourEnabled.map { bool($0) } ?? "null"
        let selfieFlipJSON = status.selfieFlip.map { bool($0.isOn) } ?? "null"
        return """
            {"batteryPercent":\(status.batteryPercent),"batteryMilliVolts":\(status.batteryMilliVolts),"batteryMilliAmps":\(status.batteryMilliAmps),"docked":\(bool(status.docked)),"charging":\(bool(status.charging)),"storageTotalMb":\(status.storageTotalMb),"storageFreeMb":\(status.storageFreeMb),"sdTotalMb":\(status.sdTotalMb),"sdFreeMb":\(status.sdFreeMb),"internalTotalMb":\(status.internalTotalMb),"internalFreeMb":\(status.internalFreeMb),"inPlayback":\(bool(status.inPlayback)),"firmware":\(quote(status.firmware)),"isRecording":\(bool(status.isRecording)),"shootingMode":\(status.shootingMode),"recordElapsedSec":\(status.recordElapsedSec),"recordRemainingSec":\(status.recordRemainingSec),"timecode":\(quote(status.timecode)),"iso":\(status.iso),"shutterDenom":\(status.shutterDenom),"fps":\(status.fps),"expoMode":\(intOrMinus(status.expoMode?.rawValue)),"isoIndex":\(intOrMinus(status.isoIndex?.rawValue)),"colorMode":\(intOrMinus(status.colorMode?.rawValue)),"videoResolution":\(intOrMinus(status.videoResolution?.rawValue)),"fpsIndex":\(intOrMinus(status.videoFormat?.frameRate.rawValue)),"whiteBalanceMode":\(intOrMinus(status.whiteBalance?.mode.rawValue)),"whiteBalanceKelvin":\(status.whiteBalanceKelvin),"whiteBalanceTint":\(status.whiteBalanceTint ?? 0),"focusMode":\(intOrMinus(status.focusMode?.rawValue)),"audioChannel":\(intOrMinus(status.audioChannel?.rawValue)),"vocalBoost":\(intOrMinus(status.vocalBoost?.rawValue)),"audioDspAt2":\(intOrMinus(status.audioDspAt2?.rawValue)),"audioDspBlob":\(quote(blob)),"zoomFactorRaw":\(status.zoomFactorRaw),"availableShutterDenoms":\(ints(status.availableShutterDenoms)),"availableIsoIndices":\(ints(isoCaps)),"evComp":\(intOrMinus(status.evComp?.rawValue)),"isoLimit":\(intOrMinus(status.isoLimit?.rawValue)),"availableColorModes":\(ints(colorCaps)),"availableVideoFormats":\(ints(formatCaps)),"focusX":\(status.focusX),"focusY":\(status.focusY),"hasCameraFocusPoint":\(bool(status.hasCameraFocusPoint)),"focusTrack":\(intOrMinus(status.focusTrack?.rawValue)),"zoomLens":\(intOrMinus(status.zoomLens)),"zoomFactor":\(zoomFactorJSON),"glamourEnabled":\(glamourJSON),"selfieFlip":\(selfieFlipJSON),"gimbalFace":\(intOrMinus(status.gimbalFace?.rawValue)),"windNR":\(intOrMinus(status.windNR?.rawValue)),"directionalAudio":\(intOrMinus(status.directionalAudio?.rawValue)),"audioMetersLeft":\(status.audioMeters.left.levelDB),"audioMetersRight":\(status.audioMeters.right.levelDB),"audioPeakLeft":\(status.audioMeters.left.peakDB),"audioPeakRight":\(status.audioMeters.right.peakDB)}
            """
    }

    public static func status(fromJSON json: String) -> CameraStatus {
        var status = CameraStatus()
        func int(_ key: String, default def: Int) -> Int {
            guard let range = json.range(of: "\"\(key)\":") else { return def }
            let tail = json[range.upperBound...]
            var digits = ""
            for ch in tail {
                if ch == "-" && digits.isEmpty {
                    digits.append(ch)
                    continue
                }
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
                if ch == "-" && digits.isEmpty {
                    digits.append(ch)
                    continue
                }
                if ch.isNumber {
                    digits.append(ch)
                } else if ch == "," {
                    if let n = Int(digits) { out.append(n) }
                    digits = ""
                }
            }
            return out
        }
        func optionalNumber(_ key: String) -> Double? {
            guard let range = json.range(of: "\"\(key)\":") else { return nil }
            var s = ""
            var started = false
            for ch in json[range.upperBound...] {
                if ch.isWhitespace && !started { continue }
                if !started && ch == "n" { return nil }
                started = true
                if ch == "-" && s.isEmpty {
                    s.append(ch)
                    continue
                }
                if ch.isNumber || ch == "." || ch == "e" || ch == "E" || ch == "+" {
                    s.append(ch)
                } else {
                    break
                }
            }
            return Double(s)
        }
        func number(_ key: String, default def: Double) -> Double {
            optionalNumber(key) ?? def
        }
        func optionalFlag(_ key: String) -> Bool? {
            if json.contains("\"\(key)\":true") { return true }
            if json.contains("\"\(key)\":false") { return false }
            return nil
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
        if let color = ColorMode(rawValue: UInt8(truncatingIfNeeded: int("colorMode", default: -1)))
        {
            status.colorMode = color
        }
        if let res = VideoResolution(
            rawValue: UInt8(truncatingIfNeeded: int("videoResolution", default: -1)))
        {
            status.videoResolution = res
        }
        if let fpsIdx = VideoFrameRate(
            rawValue: UInt8(truncatingIfNeeded: int("fpsIndex", default: -1))),
            let res = status.videoResolution
        {
            status.videoFormat = VideoFormat(resolution: res, frameRate: fpsIdx)
        }
        let wbMode = WhiteBalanceMode(
            rawValue: UInt8(truncatingIfNeeded: int("whiteBalanceMode", default: -1)))
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
        if let focus = FocusMode(rawValue: UInt8(truncatingIfNeeded: int("focusMode", default: -1)))
        {
            status.focusMode = focus
        }
        if let ch = AudioChannel(
            rawValue: UInt8(truncatingIfNeeded: int("audioChannel", default: -1)))
        {
            status.audioChannel = ch
        }
        if let boost = VocalBoost(
            rawValue: UInt8(truncatingIfNeeded: int("vocalBoost", default: -1)))
        {
            status.vocalBoost = boost
        }
        if let hex = str("audioDspBlob"), let bytes = hexBytes(hex),
            bytes.count == AudioDspBlob.size
        {
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
        status.availableShutterDenoms = intArray("availableShutterDenoms").filter {
            (1...16_000).contains($0)
        }
        status.availableIsoIndices = intArray("availableIsoIndices").compactMap {
            IsoIndex(rawValue: UInt8(truncatingIfNeeded: $0))
        }
        if let ev = EvComp(rawValue: UInt8(truncatingIfNeeded: int("evComp", default: -1))) {
            status.evComp = ev
        }
        if let limit = IsoLimit(rawValue: UInt8(truncatingIfNeeded: int("isoLimit", default: -1))) {
            status.isoLimit = limit
        }
        status.availableColorModes = intArray("availableColorModes").compactMap {
            ColorMode(rawValue: UInt8(truncatingIfNeeded: $0))
        }
        let formatFlat = intArray("availableVideoFormats")
        var formats: [VideoFormat] = []
        var fi = 0
        while fi + 1 < formatFlat.count {
            if let res = VideoResolution(rawValue: UInt8(truncatingIfNeeded: formatFlat[fi])),
                let rate = VideoFrameRate(rawValue: UInt8(truncatingIfNeeded: formatFlat[fi + 1]))
            {
                formats.append(VideoFormat(resolution: res, frameRate: rate))
            }
            fi += 2
        }
        status.availableVideoFormats = formats
        status.focusX = number("focusX", default: CamLensState.defaultX)
        status.focusY = number("focusY", default: CamLensState.defaultY)
        status.hasCameraFocusPoint = flag("hasCameraFocusPoint")
        if let track = FocusTrackMode(
            rawValue: UInt8(truncatingIfNeeded: int("focusTrack", default: -1)))
        {
            status.focusTrack = track
        }
        let lens = int("zoomLens", default: -1)
        if (0...65_535).contains(lens) { status.zoomLens = UInt16(lens) }
        if let glamour = optionalFlag("glamourEnabled") { status.glamourEnabled = glamour }
        if let flip = optionalFlag("selfieFlip") {
            status.selfieFlip = flip ? .on : .off
        }
        if let face = GimbalFace(rawValue: int("gimbalFace", default: -1)) {
            status.gimbalFace = face
        }
        if let wind = optionalUInt8(int("windNR", default: -1)).flatMap(
            WindNoiseReduction.init(rawValue:))
        {
            status.windNR = wind
        }
        if let dir = optionalUInt8(int("directionalAudio", default: -1)).flatMap(
            DirectionalAudio.init(rawValue:))
        {
            status.directionalAudio = dir
        }
        if json.contains("\"audioMetersLeft\":") || json.contains("\"audioMetersRight\":")
            || json.contains("\"audioPeakLeft\":") || json.contains("\"audioPeakRight\":")
        {
            let floor = AudioMeterBallistics.floorDB
            status.audioMeters = AudioMeterLevels(
                left: AudioMeterChannel(
                    levelDB: number("audioMetersLeft", default: floor),
                    peakDB: number("audioPeakLeft", default: floor)
                ),
                right: AudioMeterChannel(
                    levelDB: number("audioMetersRight", default: floor),
                    peakDB: number("audioPeakRight", default: floor)
                )
            )
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
        case shootPhoto = 36
        case setShootingMode = 37
        case setEv = 38
        case setIsoLimit = 39
        case getIsoLimit = 40
        case setFov = 41
        case setZoomLens = 42
        case setZoomSlew = 43
        case setZoomStop = 44
        case gimbalRecenter = 45
        case gimbalFlip = 46
        case gimbalStick = 47
        case setTrackingBox = 48
        case clearTrackingBox = 49
        case pollTracking = 50
        case setFocusTrack = 51
        case getFocusTrack = 52
        case getGlamour = 53
        case setGlamour = 54
        case exitPlayback = 55
        case mediaList = 56
        case mediaListTrigger = 57
        case deleteMedia = 58
        case setMediaFavorite = 59
        case nanoLiveViewGate = 60
        case getSelfieFlip = 61
    }

    public static func encodeCommand(kind: CommandKind, seq: UInt16, extra: String?) -> Duml.Frame?
    {
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
            let parts = (extra ?? "").split(
                separator: "\u{1f}", maxSplits: 1, omittingEmptySubsequences: false)
            guard parts.count == 2, let subId = UInt32(parts[1]) else { return nil }
            return Commands.subscribe(key: String(parts[0]), subId: subId, seq: seq)
        case .enterPlayback:
            return Commands.enterPlayback(seq: seq)
        case .liveViewEnable:
            let receiver = parseUInt8(extra) ?? Commands.liveViewEnableReceiverPocket
            return Commands.liveViewEnable(seq: seq, receiver: receiver)
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
            guard let raw = extra.flatMap({ UInt8($0) }), let index = IsoIndex(rawValue: raw) else {
                return nil
            }
            return Commands.setIsoIndex(index, seq: seq)
        case .setColorMode:
            guard let raw = extra.flatMap({ UInt8($0) }), let mode = ColorMode(rawValue: raw) else {
                return nil
            }
            return Commands.setColorMode(mode, seq: seq)
        case .setFocusMode:
            let mode: FocusMode = (extra == "2" || extra == "continuous") ? .continuous : .single
            return Commands.setFocusMode(mode, seq: seq)
        case .setWhiteBalanceAuto:
            let tint = extra.flatMap { Int($0) } ?? 0
            return Commands.setWhiteBalanceAuto(tint: tint, seq: seq)
        case .setWhiteBalanceCustom:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let kelvin = Int(parts[0]), let tint = Int(parts[1]) else {
                return nil
            }
            return Commands.setWhiteBalanceCustom(kelvin: kelvin, tint: tint, seq: seq)
        case .getAudioChannel:
            return Commands.getAudioChannel(seq: seq)
        case .setAudioChannel:
            guard let raw = extra.flatMap({ UInt8($0) }), let channel = AudioChannel(rawValue: raw)
            else { return nil }
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
            guard parts.count >= 2, let x = Float(parts[0]), let y = Float(parts[1]) else {
                return nil
            }
            return Commands.tapFocusPoint(x, y, seq: seq)
        case .tapFocusHint:
            return Commands.tapFocusLiveHint(seq: seq)
        case .tapFocusCommit:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let x = Float(parts[0]), let y = Float(parts[1]) else {
                return nil
            }
            return Commands.tapFocusCommit(x, y, seq: seq)
        case .shootPhoto:
            return Commands.shootPhoto(seq: seq)
        case .setShootingMode:
            guard let raw = parseUInt8(extra), let mode = ShootingMode(rawValue: raw) else {
                return nil
            }
            return Commands.setShootingMode(mode, seq: seq)
        case .setEv:
            guard let raw = parseUInt8(extra), let ev = EvComp(rawValue: raw) else { return nil }
            return Commands.setEv(ev, seq: seq)
        case .setIsoLimit:
            guard let raw = parseUInt8(extra), let limit = IsoLimit(rawValue: raw) else {
                return nil
            }
            return Commands.setIsoLimit(limit, seq: seq)
        case .getIsoLimit:
            return Commands.getIsoLimit(seq: seq)
        case .setFov:
            guard let raw = parseUInt8(extra), let fov = FovSetting(rawValue: raw) else {
                return nil
            }
            return Commands.setFov(fov, seq: seq)
        case .setZoomLens:
            guard let position = parseUInt16(extra) else { return nil }
            return Commands.setZoomLens(position, seq: seq)
        case .setZoomSlew:
            guard let value = parseUInt16(extra) else { return nil }
            return Commands.setZoomSlew(value, seq: seq)
        case .setZoomStop:
            return Commands.setZoomStop(seq: seq)
        case .gimbalRecenter:
            return Commands.gimbalRecenter(seq: seq)
        case .gimbalFlip:
            return Commands.gimbalFlip(seq: seq)
        case .gimbalStick:
            return encodeGimbalStick(seq: seq, extra: extra)
        case .setTrackingBox:
            let parts = splitExtra(extra)
            guard parts.count >= 5,
                let id = parseUInt16(parts[0]),
                let x = Float(parts[1]), let y = Float(parts[2]),
                let width = Float(parts[3]), let height = Float(parts[4])
            else { return nil }
            return Commands.setTrackingBox(
                id: id, x: x, y: y, width: width, height: height, seq: seq)
        case .clearTrackingBox:
            return Commands.clearTrackingBox(seq: seq)
        case .pollTracking:
            return Commands.pollTracking(seq: seq)
        case .setFocusTrack:
            guard let raw = parseUInt8(extra), let mode = FocusTrackMode(rawValue: raw) else {
                return nil
            }
            return Commands.setFocusTrack(mode, seq: seq)
        case .getFocusTrack:
            return Commands.getFocusTrack(seq: seq)
        case .getGlamour:
            return Commands.getGlamour(seq: seq)
        case .setGlamour:
            guard let blob = hexBytes(extra ?? "") else { return nil }
            return Commands.setGlamour(blob, seq: seq)
        case .exitPlayback:
            return Commands.exitPlayback(seq: seq)
        case .mediaList:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let counter = parseUInt8(parts[0]),
                let cursor = parseUInt32(parts[1])
            else { return nil }
            return Commands.mediaList(counter: counter, cursor: cursor, seq: seq)
        case .mediaListTrigger:
            return Commands.mediaListTrigger(seq: seq)
        case .deleteMedia:
            let parts = splitExtra(extra)
            guard parts.count >= 2, let handle = parseUInt32(parts[0]),
                let counter = parseUInt32(parts[1])
            else { return nil }
            return Commands.deleteMedia(handle: handle, counter: counter, seq: seq)
        case .setMediaFavorite:
            let parts = splitExtra(extra)
            guard parts.count >= 3, let handle = parseUInt32(parts[0]),
                let counter = parseUInt32(parts[2])
            else { return nil }
            return Commands.setMediaFavorite(
                handle: handle, on: isOn(parts[1]), counter: counter, seq: seq)
        case .getSelfieFlip:
            return Commands.getSelfieFlip(seq: seq)
        case .nanoLiveViewGate:
            guard extra != nil else { return nil }
            return Commands.nanoLiveViewGate(start: isOn(extra), seq: seq)
        }
    }

    /// `"x\u{1f}y\u{1f}sensitivity"` uses `GimbalStick.encode`. Two parts are
    /// normalized x,y when both sit in −1…1, otherwise raw axis0,axis1.
    private static func encodeGimbalStick(seq: UInt16, extra: String?) -> Duml.Frame? {
        let parts = splitStickExtra(extra)
        if parts.count >= 3,
            let x = Double(parts[0]), let y = Double(parts[1]), let sensitivity = Int(parts[2])
        {
            let axes = GimbalStick.encode(x: x, y: y, sensitivity: sensitivity)
            return Commands.gimbalStick(axis0: axes.axis0, axis1: axes.axis1, seq: seq)
        }
        guard parts.count >= 2, let a0 = Double(parts[0]), let a1 = Double(parts[1]) else {
            return nil
        }
        if abs(a0) <= 1, abs(a1) <= 1 {
            let axes = GimbalStick.encode(x: a0, y: a1)
            return Commands.gimbalStick(axis0: axes.axis0, axis1: axes.axis1, seq: seq)
        }
        guard let axis0 = parseUInt16(parts[0]), let axis1 = parseUInt16(parts[1]) else {
            return nil
        }
        return Commands.gimbalStick(axis0: axis0, axis1: axis1, seq: seq)
    }

    private static func intOrMinus<T: BinaryInteger>(_ value: T?) -> Int {
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

    private static func splitStickExtra(_ extra: String?) -> [String] {
        let raw = extra ?? ""
        if raw.contains("\u{1f}") { return splitExtra(raw) }
        if raw.contains(",") {
            return raw.split(separator: ",", omittingEmptySubsequences: false).map {
                String($0).trimmingCharacters(in: .whitespaces)
            }
        }
        return raw.isEmpty ? [] : [raw]
    }

    private static func isOn(_ raw: String?) -> Bool {
        raw == "1" || raw == "true" || raw == "on"
    }

    private static func parseUInt64(_ raw: String?) -> UInt64? {
        guard let s = raw?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            return nil
        }
        if s.lowercased().hasPrefix("0x") {
            return UInt64(s.dropFirst(2), radix: 16)
        }
        return UInt64(s)
    }

    private static func parseUInt8(_ raw: String?) -> UInt8? {
        guard let value = parseUInt64(raw), value <= UInt64(UInt8.max) else { return nil }
        return UInt8(value)
    }

    private static func parseUInt16(_ raw: String?) -> UInt16? {
        guard let value = parseUInt64(raw), value <= UInt64(UInt16.max) else { return nil }
        return UInt16(value)
    }

    private static func parseUInt32(_ raw: String?) -> UInt32? {
        guard let value = parseUInt64(raw), value <= UInt64(UInt32.max) else { return nil }
        return UInt32(value)
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

    /// Stick axes as `"axis0,axis1"` (`x` −1…1 right, `y` −1…1 up).
    public static func gimbalStickEncode(
        x: Double, y: Double, invertPan: Bool, sensitivity: Int
    ) -> String {
        let axes = GimbalStick.encode(
            x: x, y: y, invertPan: invertPan, sensitivity: sensitivity)
        return "\(axes.axis0),\(axes.axis1)"
    }

    /// Next chip-cycle lens from `currentFactor` (1 → 3 → 6 → 12 → 1).
    public static func camFovChipWrite(currentFactor: Double) -> String {
        let next = CamFov.nextJump(from: currentFactor)
        if let write = CamFov.chipWrite(forJump: next) {
            switch write {
            case .lens(let position), .slew(let position):
                return String(position)
            }
        }
        return String(CamFov.lensPosition(for: next))
    }

    /// Probe + labels for playback conform preview. Request keys: `nominalFrameRate`,
    /// `minFrameDurationSeconds`, `listedRate`, optional `targetRate` / `sourceSeconds`.
    public static func conformPreviewJSON(_ request: String) -> String {
        let source = ConformPreview.probe(
            nominalFrameRate: jsonOptionalNumber(request, key: "nominalFrameRate"),
            minFrameDurationSeconds: jsonOptionalNumber(request, key: "minFrameDurationSeconds"),
            listedRate: jsonOptionalNumber(request, key: "listedRate"))
        let availability = ConformPreview.availability(for: source)
        var dict: [String: Any] = [
            "isVariableFrameRate": source.isVariableFrameRate,
            "isAlreadyConformed": source.isAlreadyConformed,
            "audioLabel": ConformPreview.audioLabel,
            "conformFloor": NSNumber(value: ConformPreview.conformFloor),
            "targetRates": ConformPreview.targetRates.map { NSNumber(value: $0) },
            "availability": availabilityName(availability),
            "targets": availability.targets.map { NSNumber(value: $0) },
        ]
        if let reason = availability.unavailableReason {
            dict["unavailableReason"] = reason
        }
        if let capture = source.captureRate {
            dict["captureRate"] = NSNumber(value: capture)
            dict["menuHeader"] = ConformPreview.menuHeader(captureRate: capture)
            dict["rateLabel"] = ConformPreview.rateLabel(capture)
            dict["targetLabels"] = availability.targets.map {
                ConformPreview.targetLabel(captureRate: capture, targetRate: $0)
            }
            if let target = jsonOptionalNumber(request, key: "targetRate") {
                let speed = ConformPreview.speed(captureRate: capture, targetRate: target)
                dict["speed"] = NSNumber(value: speed)
                dict["targetLabel"] = ConformPreview.targetLabel(
                    captureRate: capture, targetRate: target)
                dict["label"] = ConformPreview.label(captureRate: capture, targetRate: target)
                if let seconds = jsonOptionalNumber(request, key: "sourceSeconds") {
                    dict["conformedDuration"] = NSNumber(
                        value: ConformPreview.conformedDuration(
                            sourceSeconds: seconds, speed: speed))
                }
            }
        }
        guard JSONSerialization.isValidJSONObject(dict),
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private final class WatchdogStore: @unchecked Sendable {
        let lock = NSLock()
        var boxes: [Int64: FeedWatchdog] = [:]
        var next: Int64 = 1
    }

    private static let watchdogStore = WatchdogStore()

    public static func feedWatchdogCreate() -> Int64 {
        let store = watchdogStore
        store.lock.lock()
        defer { store.lock.unlock() }
        let handle = store.next
        store.next += 1
        store.boxes[handle] = FeedWatchdog()
        return handle
    }

    public static func feedWatchdogReset(handle: Int64) {
        let store = watchdogStore
        store.lock.lock()
        store.boxes[handle] = FeedWatchdog()
        store.lock.unlock()
    }

    public static func feedWatchdogDestroy(handle: Int64) {
        let store = watchdogStore
        store.lock.lock()
        store.boxes.removeValue(forKey: handle)
        store.lock.unlock()
    }

    /// Stateful tick. Keep the handle for the session — a fresh `FeedWatchdog()`
    /// every call is always `.idle`.
    public static func feedWatchdogTick(handle: Int64, snapshotJSON: String) -> String {
        let store = watchdogStore
        store.lock.lock()
        defer { store.lock.unlock() }
        guard var watchdog = store.boxes[handle] else { return "none" }
        let action = feedWatchdogAction(snapshotJSON: snapshotJSON, watchdog: &watchdog)
        store.boxes[handle] = watchdog
        return action
    }

    /// One idle-watchdog tick. Action is `none` / `resendLiveViewEnable` /
    /// `rebuildVTSession` / `reopenDatalink` / `fullSessionRejoin`.
    public static func feedWatchdogAction(snapshotJSON: String) -> String {
        var watchdog = FeedWatchdog()
        return feedWatchdogAction(snapshotJSON: snapshotJSON, watchdog: &watchdog)
    }

    private static func feedWatchdogAction(
        snapshotJSON: String, watchdog: inout FeedWatchdog
    ) -> String {
        let json = snapshotJSON
        let snap = FeedWatchdog.Snapshot(
            now: jsonNumber(json, key: "now", default: 0),
            lastDecodedFrameAge: jsonOptionalNumber(json, key: "lastDecodedFrameAge"),
            lastVideoPacketAge: jsonOptionalNumber(json, key: "lastVideoPacketAge"),
            lastAccessUnitAge: jsonOptionalNumber(json, key: "lastAccessUnitAge"),
            lastStatusAge: jsonOptionalNumber(json, key: "lastStatusAge"),
            flowHealthy: jsonBool(json, key: "flowHealthy", default: false),
            pathReady: jsonBool(json, key: "pathReady", default: false),
            hasFormat: jsonBool(json, key: "hasFormat", default: false),
            decoderFailed: jsonBool(json, key: "decoderFailed", default: false),
            live: jsonBool(json, key: "live", default: false),
            sawPicture: jsonBool(json, key: "sawPicture", default: false),
            tcpPokeReady: jsonBool(json, key: "tcpPokeReady", default: false),
            displayedImageRemoved: jsonBool(json, key: "displayedImageRemoved", default: false),
            lastBleNotifyAge: jsonOptionalNumber(json, key: "lastBleNotifyAge"),
            secondsSinceLastRebuild: jsonOptionalNumber(json, key: "secondsSinceLastRebuild"),
            hadVideo: jsonBool(json, key: "hadVideo", default: true),
            secondsSinceLastEnable: jsonOptionalNumber(json, key: "secondsSinceLastEnable"),
            secondsSinceFocusTrackSet: jsonOptionalNumber(json, key: "secondsSinceFocusTrackSet")
        )
        switch watchdog.tick(snap) {
        case .none: return "none"
        case .resendLiveViewEnable: return "resendLiveViewEnable"
        case .rebuildVTSession: return "rebuildVTSession"
        case .reopenDatalink: return "reopenDatalink"
        case .fullSessionRejoin: return "fullSessionRejoin"
        }
    }

    private static func availabilityName(_ availability: ConformPreview.Availability) -> String {
        switch availability {
        case .available: "available"
        case .unknownRate: "unknownRate"
        case .variableRate: "variableRate"
        case .alreadyConformed: "alreadyConformed"
        case .notHighFrameRate: "notHighFrameRate"
        }
    }

    private static func jsonBool(_ json: String, key: String, default def: Bool) -> Bool {
        if json.contains("\"\(key)\":true") { return true }
        if json.contains("\"\(key)\":false") { return false }
        return def
    }

    private static func jsonOptionalNumber(_ json: String, key: String) -> Double? {
        guard let range = json.range(of: "\"\(key)\":") else { return nil }
        var s = ""
        var started = false
        for ch in json[range.upperBound...] {
            if ch.isWhitespace && !started { continue }
            if !started && ch == "n" { return nil }
            started = true
            if ch == "-" && s.isEmpty {
                s.append(ch)
                continue
            }
            if ch.isNumber || ch == "." || ch == "e" || ch == "E" || ch == "+" {
                s.append(ch)
            } else {
                break
            }
        }
        return Double(s)
    }

    private static func jsonNumber(_ json: String, key: String, default def: Double) -> Double {
        jsonOptionalNumber(json, key: key) ?? def
    }
}

/// Mutable depacketizer box so JNI can hold a handle across feeds.
public final class HevcDepacketizerBox: @unchecked Sendable {
    public var depacketizer = HevcDepacketizer()
    public init() {}
}
