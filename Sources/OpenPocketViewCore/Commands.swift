import Foundation

/// Builders for the DUML frames of the connection spine, ported byte-for-byte from Osmosis
/// (`duml/OsmoCommands.kt`, `camera/CameraSession.kt`). BLE frames carry a message id in `seq`;
/// datalink frames carry the running `dumlSeq` there (the DatalinkDriver assigns it).
public enum Commands {
    /// The app identity the camera keys its remembered pairing approval on (Osmosis DEFAULT_IDENTIFIER).
    public static let defaultIdentifier = "284ae5b8d76b3375a04a6417ad71bea3"

    /// Status keys to subscribe to (`0x00/0x99`), starting at subId 0x69DF.
    /// `camcap_shutter` / `camcap_iso` are capability tables (legal wheel values).
    /// Extra `cam_*` / `timecode_info` keys are read-only live HUD (no SETs).
    public static let subscriptionKeys = [
        "camcap_mode_profile", "camcap_video_format", "camcap_fov", "camcap_iso",
        "camcap_shutter",
        "camcap_photo_storage_format", "camcap_color_mode", "cam_storage", "cam_status",
        "timecode_info", "cam_expo_param", "cam_video_param_v2", "cam_record_time",
        "cam_image_effect", "cam_lens_state", "cam_fov",
        "cam_audio_status_v2",
    ]
    public static let firstSubId: UInt32 = 0x69DF

    static func rx(type: UInt8, id: UInt8) -> UInt8 { (id << 5) | type }

    // ---- BLE session sequence (written to fff5, paced) ----------------------------------------

    /// `0x00/0x2b` -> session (0xF0). `04 00` wakes before pairing; `01 01` repeats as keepalive.
    public static func sessionWake(id: UInt16 = 0x802B) -> Duml.Frame {
        ping([0x04, 0x00], id: id)
    }
    public static func sessionKeepalive(id: UInt16 = 0x802B) -> Duml.Frame {
        ping([0x01, 0x01], id: id)
    }
    private static func ping(_ payload: [UInt8], id: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxSession, seq: id,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x2B, payload: payload)
    }

    /// `0x07/0x45` SetPairingPIN. Reply `[00 01]`=already paired, `[00 02]`=approve on the camera.
    public static func setPairingPin(
        pin: String, identifier: String = defaultIdentifier, id: UInt16 = 0x8092
    ) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxWifi, seq: id, flags: Duml.flagRequest,
            cmdSet: 0x07, cmdId: 0x45, payload: Duml.packString(identifier) + Duml.packString(pin))
    }

    /// The camera's first-time approval arrives as a `0x07/0x46` *request*; answer it with this response.
    public static func pairApprovalAck(seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxWifi, seq: seq, flags: Duml.flagResponse,
            cmdSet: 0x07, cmdId: 0x46, payload: [0x00])
    }

    /// `0x53/0x10` -> type 0x1C. The camera answers `01 00 00 00` and wakes its AP.
    public static func session5310(id: UInt16 = 0x8053) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rx1C, seq: id, flags: Duml.flagRequest,
            cmdSet: 0x53, cmdId: 0x10, payload: [0, 0, 0, 0])
    }

    public static func getWifiSsid(id: UInt16 = 0x8007) -> Duml.Frame { wifiQuery(0x07, id: id) }
    public static func getWifiPassword(id: UInt16 = 0x800E) -> Duml.Frame {
        wifiQuery(0x0E, id: id)
    }
    private static func wifiQuery(_ cmd: UInt8, id: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxWifi, seq: id, flags: Duml.flagRequest,
            cmdSet: 0x07, cmdId: cmd, payload: [])
    }

    // ---- Datalink registration (seq = dumlSeq, assigned by the driver) -------------------------

    /// `0x00/0x81` device-info, cmdType 4 (flags 0x80) -> DM368 (type 0x08, id 2).
    public static func appDeviceInfo(seq: UInt16) -> Duml.Frame {
        var b = [UInt8](repeating: 0, count: 62)  // "\0APP" + 37*00 + 02 + 8*00 + 02 08 + 10*00
        b[1] = 0x41
        b[2] = 0x50
        b[3] = 0x50
        b[41] = 0x02
        b[50] = 0x02
        b[51] = 0x08
        return Duml.Frame(
            sender: Duml.senderApp, receiver: rx(type: 0x08, id: 2), seq: seq,
            flags: 0x80, cmdSet: 0x00, cmdId: 0x81, payload: b)
    }

    static let appPresence: [UInt8] = [
        0x17, 0x00, 0x46, 0x23, 0x7C, 0x41, 0x50, 0x50, 0x00, 0x00, 0x00, 0x00, 0x00, 0x02,
    ]

    /// `0x00/0x88` app-presence, re-sent ~1 Hz to hold the session/playback -> DM368 (type 0x08, id 1).
    public static func appPresenceFrame(seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: rx(type: 0x08, id: 1), seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x88, payload: appPresence)
    }

    /// `0x03/0xDA` gimbal init -> Gimbal (type 0x03, id 0).
    public static func gimbalInit(seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: rx(type: 0x03, id: 0), seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x03, cmdId: 0xDA,
            payload: [0x05, 0xFF, 0xFF, 0xFF, 0xFF])
    }

    /// `0x00/0x99` status subscription -> DM368 (type 0x08, id 1). Payload is Mimo's exact layout.
    public static func subscribe(key: String, subId: UInt32, seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: rx(type: 0x08, id: 1), seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x99,
            payload: subscriptionPayload(key, subId))
    }

    /// `[02 02 00 00][subId u32-LE][00 00 00][innerLen u16-LE][nameLen u16-LE][name][00 00 00 00]`,
    /// innerLen = nameLen + 6, name unpadded. Verified sizes: fov 29 B, base 30 B, video_format 38 B.
    static func subscriptionPayload(_ name: String, _ subId: UInt32) -> [UInt8] {
        let nb = Array(name.utf8)
        var p: [UInt8] = [0x02, 0x02, 0x00, 0x00]
        p += le32(subId)
        p += [0, 0, 0]
        p += le16(nb.count + 6)  // innerLen
        p += le16(nb.count)
        p += nb
        p += [0, 0, 0, 0]
        return p
    }

    /// `0x02/0x0c` enter playback -> Camera. `01 01 00 01` enter, `01 01 00 00` exit.
    public static func enterPlayback(seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq, flags: Duml.flagRequest,
            cmdSet: 0x02, cmdId: 0x0C, payload: [0x01, 0x01, 0x00, 0x01])
    }

    /// `0x02/0x0c` leave playback. Same opcode as enter; payload `01 01 00 00`.
    public static func exitPlayback(seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq, flags: Duml.flagRequest,
            cmdSet: 0x02, cmdId: 0x0C, payload: [0x01, 0x01, 0x00, 0x00])
    }

    /// `0x00/0x26` media list. Cursor at bytes 10–13; counter at byte 4.
    public static func mediaList(counter: UInt8, cursor: UInt32, seq: UInt16 = 0) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x26,
            payload: MediaListCommand.listPayload(counter: counter, cursor: cursor))
    }

    /// `0x00/0x26` stream trigger `4a040e10…` — Osmosis / Mimo, between the two list queries.
    public static func mediaListTrigger(seq: UInt16 = 0) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x26,
            payload: MediaListCommand.triggerPayload)
    }

    /// `0x00/0x28` delete. Osmosis: `[count][handles][counter:u32] 00 [count:u32] 01 01 00 00`.
    public static func deleteMedia(handle: UInt32, counter: UInt32, seq: UInt16 = 0) -> Duml.Frame {
        var payload: [UInt8] = [0x01]
        payload += le32(handle)
        payload += le32(counter)
        payload += [0x00]
        payload += le32(1)
        payload += [0x01, 0x01, 0x00, 0x00]
        return Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x00, cmdId: 0x28, payload: payload)
    }

    /// `0x02/0xBF` star. `01 01 [handle:u32] [counter:u32] 00 [on:u8] 00 00 00`.
    public static func setMediaFavorite(
        handle: UInt32, on: Bool, counter: UInt32, seq: UInt16 = 0
    ) -> Duml.Frame {
        var payload: [UInt8] = [0x01, 0x01]
        payload += le32(handle)
        payload += le32(counter)
        payload += [0x00, on ? 0x01 : 0x00, 0x00, 0x00, 0x00]
        return camera(0xBF, payload, seq: seq)
    }

    /// Pocket live-view enable target (system type 0x08, id 0).
    public static let liveViewEnableReceiverPocket: UInt8 = rx(type: 0x08, id: 0)
    /// Nano live-view enable target. Mimo `mimo-nano-live-20260818`: `rcv=0x41`
    /// (type 1, id 2). Pocket `0x08` ACKs `E0` on Nano and no pktType-0x02 starts.
    public static let liveViewEnableReceiverNano: UInt8 = 0x41

    /// `0x09/0xa8` **start live view** / IDR. Bytes from Mimo. Pocket `rcv=0x08`;
    /// Nano must use `liveViewEnableReceiverNano`. Re-sending every second resets
    /// the encoder GOP and the IDR never lands — that was the black-screen bug.
    public static func liveViewEnable(
        seq: UInt16, receiver: UInt8 = liveViewEnableReceiverPocket
    ) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: receiver, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x09, cmdId: 0xA8,
            payload: [0x00, 0x04, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00])
    }

    /// Nano `0x02/0x09` sent with every Mimo enable (`…03`) and with feed stop (`…04`).
    /// ACK `00`. Unlabeled beyond start/stop pairing — do not send on Pocket.
    public static func nanoLiveViewGate(start: Bool, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x09, [0, 0, 0, 0, 0, 0, 0, 0, 0, 0, start ? 0x03 : 0x04], seq: seq)
    }

    // ---- Camera control (Osmosis §10–14, App → Camera `0x01`, flags `0x40`) ---------------------

    /// `0x02/0x02` start recording. Payload `[01]`. Not a toggle — `[01]` while REC answers `df`.
    public static func recordStart(seq: UInt16 = 0) -> Duml.Frame { camera(0x02, [0x01], seq: seq) }

    /// `0x02/0x02` stop recording. Payload `[00]`.
    public static func recordStop(seq: UInt16 = 0) -> Duml.Frame { camera(0x02, [0x00], seq: seq) }

    /// `0x02/0x01` shutter trigger. Payload `[01]`. In Video mode the camera answers `d9`.
    public static func shootPhoto(seq: UInt16 = 0) -> Duml.Frame { camera(0x01, [0x01], seq: seq) }

    /// `0x02/0xE1` shooting mode. Only send tabled `ShootingMode` values — do not enumerate.
    public static func setShootingMode(_ mode: ShootingMode, seq: UInt16 = 0) -> Duml.Frame {
        camera(0xE1, [mode.rawValue], seq: seq)
    }

    /// `0x02/0x8E` GET = `00 01 <pid:u16-LE>`.
    public static func paramGet(_ param: CameraParam, seq: UInt16 = 0) -> Duml.Frame {
        let pid = param.rawValue
        return camera(0x8E, [0x00, 0x01, UInt8(pid & 0xFF), UInt8(pid >> 8)], seq: seq)
    }

    /// `0x02/0x8E` SET = `01 01 <pid:u16-LE> <len:u8> <value…>`.
    public static func paramSet(_ param: CameraParam, value: [UInt8], seq: UInt16 = 0) -> Duml.Frame
    {
        let pid = param.rawValue
        var p: [UInt8] = [0x01, 0x01, UInt8(pid & 0xFF), UInt8(pid >> 8), UInt8(value.count)]
        p += value
        return camera(0x8E, p, seq: seq)
    }

    public static func setIsoLimit(_ limit: IsoLimit, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.isoLimit, value: [limit.rawValue], seq: seq)
    }

    /// `0x02/0x8E` pid `0x000F` GET `00 01 0F 00`. Pocket replies `00 00 01 0F 00 01 <ceiling>`.
    public static func getIsoLimit(seq: UInt16 = 0) -> Duml.Frame {
        paramGet(.isoLimit, seq: seq)
    }

    /// `0x02/0x2E` 1-byte EV. mimo-settings-1 while Auto, ACK `00`:
    /// `10` (pkt 53846), `11`, `12`, `0f`. Echoes `cam_expo_param` `@6`. `0x10` = 0.0.
    public static func setEv(_ ev: EvComp, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x2E, [ev.rawValue], seq: seq)
    }

    public static func setFov(_ fov: FovSetting, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.fov, value: [fov.rawValue], seq: seq)
    }

    /// Classic DUML `0x22` = AE Meter Set. Mimo tap sends `[02]` (spot).
    /// `/tmp/mimo-tap-focus-20260818.pcapng` — first of the four-write burst.
    public static func tapFocusPrepare(seq: UInt16 = 0) -> Duml.Frame {
        camera(0x22, [0x02], seq: seq)
    }

    /// Classic DUML `0x30` = Focus Region Set. Normalized 0…1 float32 LE + 13× `00`
    /// (21 B). `mimo-tap-focus-20260818` — 20 B is ACK `E3`.
    public static func tapFocusPoint(_ x: Float, _ y: Float, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x30, floatLE(x) + floatLE(y) + [UInt8](repeating: 0, count: 13), seq: seq)
    }

    /// Classic DUML `0x32` = AE Meter Region Set. `00 02 01 00` + xy + 8× `00`.
    public static func tapFocusCommit(_ x: Float, _ y: Float, seq: UInt16 = 0) -> Duml.Frame {
        camera(
            0x32,
            [0x00, 0x02, 0x01, 0x00] + floatLE(x) + floatLE(y) + [UInt8](repeating: 0, count: 8),
            seq: seq)
    }

    /// Classic DUML `0x68` = AE Lock Status Set. Mimo tap sends `[08]`.
    /// Not App Glamour (`0x8E` pid `0x0039`). Same bytes as `liveViewPrepare`.
    public static func tapFocusLiveHint(seq: UInt16 = 0) -> Duml.Frame {
        camera(0x68, [0x08], seq: seq)
    }

    /// Mimo live-entry (`mimo-disconnect-20260822-105228`): `0x02/0x68` payload
    /// `08` immediately before the first `0x09/0xa8` after a SoftAP join. Same
    /// bytes as `tapFocusLiveHint`. First live after gallery is 0x68 then an
    /// `0xa8` burst then a 137 B VPS. Return-from-gallery can skip 0x68 when
    /// the 5-tuple is already live. Do not send on Nano (no captured pair).
    public static func liveViewPrepare(seq: UInt16 = 0) -> Duml.Frame {
        tapFocusLiveHint(seq: seq)
    }

    /// Mimo tap burst (`mimo-tap-focus-20260818`). AF-S and AF-C are the same
    /// four writes; each ACK is `00`. `0x32` alone times out.
    public static func tapFocus(_ x: Float, _ y: Float, seq: UInt16 = 0) -> [Duml.Frame] {
        [
            tapFocusPrepare(seq: seq),
            tapFocusPoint(x, y, seq: seq),
            tapFocusLiveHint(seq: seq),
            tapFocusCommit(x, y, seq: seq),
        ]
    }

    /// `0x02/0xA6` drag-to-track SET. `01 00 00` + u16-LE id + 4×f32 LE origin/size.
    public static func setTrackingBox(
        id: UInt16, x: Float, y: Float, width: Float, height: Float, seq: UInt16 = 0
    ) -> Duml.Frame {
        camera(
            0xA6,
            [0x01, 0x00, 0x00] + le16(Int(id)) + floatLE(x) + floatLE(y) + floatLE(width)
                + floatLE(height),
            seq: seq
        )
    }

    /// `0x02/0xA6` clear — 21× `00`.
    public static func clearTrackingBox(seq: UInt16 = 0) -> Duml.Frame {
        camera(0xA6, [UInt8](repeating: 0, count: 21), seq: seq)
    }

    /// `0x02/0xA5` GET `00`. Reply `00 01 00 00` locked / `00 00 00 00` idle.
    public static func pollTracking(seq: UInt16 = 0) -> Duml.Frame {
        camera(0xA5, [0x00], seq: seq)
    }

    /// `0x02/0x28` shutter SET. 7 B: `01` + u16-LE `(denom | 0x8000)` + `00 00 00 40`.
    /// No GET on this opcode — legal values arrive as `camcap_shutter` (`CamCapShutter`).
    /// Denom is the N in 1/N (4…16000). Prefer `Int` — `UInt8` cannot encode 1/256 and above.
    public static func setShutter(denom: Int, seq: UInt16 = 0) -> Duml.Frame {
        let encoded = UInt16(clamping: denom) | 0x8000
        return camera(
            0x28, [0x01, UInt8(encoded & 0xFF), UInt8(encoded >> 8), 0x00, 0x00, 0x00, 0x40],
            seq: seq)
    }

    public static func setShutter(denom: UInt8, seq: UInt16 = 0) -> Duml.Frame {
        setShutter(denom: Int(denom), seq: seq)
    }

    /// `0x02/0x2A` ISO index. `00` Auto; `03`=100 … `0B`=25600. No GET — expo `@5` / `@16`.
    public static func setIsoIndex(_ index: IsoIndex, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x2A, [index.rawValue], seq: seq)
    }

    /// `0x02/0x42` color. Normal `3F`, HDR `3C`, D-Log `17`, D-Log2 `41`.
    public static func setColorMode(_ mode: ColorMode, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x42, [mode.rawValue], seq: seq)
    }

    /// `0x02/0x24` focus. Single `01`, Continuous `02`.
    public static func setFocusMode(_ mode: FocusMode, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x24, [mode.rawValue], seq: seq)
    }

    /// `0x02/0x8E` pid `0x003B` GET `00 01 3B 00`.
    public static func getFocusTrack(seq: UInt16 = 0) -> Duml.Frame {
        paramGet(.focusTrack, seq: seq)
    }

    /// SET `01 01 3B 00 02 01 <mode>`. Default `00`, Showcase `01`, Lock `02`, Priority `03`.
    public static func setFocusTrack(_ mode: FocusTrackMode, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.focusTrack, value: mode.setValue, seq: seq)
    }

    /// `0x02/0x2C` white balance. 5 B `[mode][K/100 u16-LE][tint i16-LE]`.
    /// Auto is kelvin 0 and keeps `tint` (Mimo `00 00 00 14 00` at tint 20).
    public static func setWhiteBalance(_ wb: WhiteBalance, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x2C, wb.setPayload, seq: seq)
    }

    public static func setWhiteBalanceAuto(tint: Int = 0, seq: UInt16 = 0) -> Duml.Frame {
        setWhiteBalance(.auto(tint: tint), seq: seq)
    }

    public static func setWhiteBalanceCustom(kelvin: Int, tint: Int, seq: UInt16 = 0) -> Duml.Frame
    {
        setWhiteBalance(.custom(kelvin: kelvin, tint: tint), seq: seq)
    }

    /// `0x02/0x8E` pid `0x0020` GET `00 01 20 00`.
    public static func getAudioChannel(seq: UInt16 = 0) -> Duml.Frame {
        paramGet(.audioChannel, seq: seq)
    }

    /// SET `01 01 20 00 01 <v>`. Stereo `02`, Mono `01`, Spatial `03`.
    public static func setAudioChannel(_ channel: AudioChannel, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.audioChannel, value: [channel.rawValue], seq: seq)
    }

    /// `0x02/0x8E` pid `0x0039` GET `00 01 39 00`. Reply is a 62-byte glamour blob.
    public static func getGlamour(seq: UInt16 = 0) -> Duml.Frame {
        paramGet(.glamour, seq: seq)
    }

    /// SET the 62-byte glamour blob. Only use to force Off (`GlamourEffect.disabled`).
    public static func setGlamour(_ blob: [UInt8], seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.glamour, value: blob, seq: seq)
    }

    /// `0x02/0x8E` pid `0x0038` GET `00 01 38 00`. Control Center Selfie Flip.
    public static func getSelfieFlip(seq: UInt16 = 0) -> Duml.Frame {
        paramGet(.selfieFlip, seq: seq)
    }

    /// `0x02/0x8E` pid `0x004C` GET `00 01 4C 00`.
    public static func getVocalBoost(seq: UInt16 = 0) -> Duml.Frame {
        paramGet(.vocalBoost, seq: seq)
    }

    /// SET `01 01 4C 00 01 <v>`. Off `00`, On `01`.
    public static func setVocalBoost(_ boost: VocalBoost, seq: UInt16 = 0) -> Duml.Frame {
        paramSet(.vocalBoost, value: [boost.rawValue], seq: seq)
    }

    /// `0x02/0xA0` GET audio-DSP blob (empty). Reply `00` + 26 B. Then patch `@2` and SET `0x9F`.
    public static func audioDspGet(seq: UInt16 = 0) -> Duml.Frame { camera(0xA0, [], seq: seq) }

    /// First-live / audio-sheet probes. ISO limit is not audio — GET it from the ISO sheet.
    public static var audioStateGets: [Duml.Frame] {
        [getAudioChannel(), getVocalBoost(), audioDspGet()]
    }

    /// `0x02/0x9F` SET = the 26-byte GET blob. Do not invent the other bytes.
    public static func audioDspSet(_ blob: [UInt8], seq: UInt16 = 0) -> Duml.Frame {
        camera(0x9F, blob, seq: seq)
    }

    /// `0x02/0x18` res+fps. 5 B `[res][fps_idx] 00 00 00`. No GET.
    public static func setVideoFormat(_ format: VideoFormat, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x18, format.setPayload, seq: seq)
    }

    public static func setVideoFormat(
        resolution: VideoResolution, frameRate: VideoFrameRate, seq: UInt16 = 0
    ) -> Duml.Frame {
        setVideoFormat(VideoFormat(resolution: resolution, frameRate: frameRate), seq: seq)
    }

    /// `0x02/0xb8` slider SET. `0A 4E` + u16-LE lens `@14` (217 = 1×, 651 = 3×,
    /// 2604 = 12×). Mimo pinch is this form at 50 ms for the whole range.
    public static func setZoomLens(_ position: UInt16, seq: UInt16 = 0) -> Duml.Frame {
        camera(0xB8, [0x0A, 0x4E, UInt8(position & 0xFF), UInt8(position >> 8)], seq: seq)
    }

    /// Factor → slider SET (`0A 4E` + inverse-focal lens). Chip 12× is a slew.
    public static func setZoom(factor: Double, seq: UInt16 = 0) -> Duml.Frame {
        setZoomLens(CamFov.lensPosition(for: factor), seq: seq)
    }

    /// `0x02/0xb8` `03 00` + u16-LE. 100 (`64 00`) slews toward 12×; 300
    /// (`2C 01`) from 12× lands at 9.15×. ACK `00`.
    public static func setZoomSlew(_ value: UInt16, seq: UInt16 = 0) -> Duml.Frame {
        camera(0xB8, [0x03, 0x00, UInt8(value & 0xFF), UInt8(value >> 8)], seq: seq)
    }

    /// `0x02/0xb8` `FF 00 00 00` — stop after a `03 00` slew on older firmware.
    public static func setZoomStop(seq: UInt16 = 0) -> Duml.Frame {
        camera(0xB8, [0xFF, 0x00, 0x00, 0x00], seq: seq)
    }

    // ---- Gimbal (`rcv=0x04`). Flip/mode/speed ACK flags `0x80`; stick flags `0x00`, no ACK. ----

    /// `0x04/0x4C` `FE 08` — Mimo recenter-gimbal button
    /// (`captures/mimo-gimbal-recenter-20260819.pcapng`). Mimo has no
    /// stick double-tap; OPC sends this on stick double-tap (hardware
    /// joystick). Not `0x03/0xDA` (register / post-FPV). Flip stays `FE 09`.
    public static func gimbalRecenter(seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x4C, [0xFE, 0x08], seq: seq)
    }

    /// `0x04/0x4C` `FE 09` — front ↔ selfie toggle. Same SET both ways.
    /// Mimo flip control; OPC sends this on stick triple-tap.
    public static func gimbalFlip(seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x4C, [0xFE, 0x09], seq: seq)
    }

    /// `0x04/0x4C` `02 08` — Follow / Tilt Locked family. Pair with `setGimbalTiltLock`.
    public static func gimbalFollowFamily(seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x4C, [0x02, 0x08], seq: seq)
    }

    /// `0x04/0x4C` `01 08` — FPV. This take did not write param `04`.
    public static func gimbalFpv(seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x4C, [0x01, 0x08], seq: seq)
    }

    /// `0x04/0x01` flags `0x00`, 10 B, no ACK. Axes u16-LE @0/@4, center 1024 ±550, trailer `00 80 22 00`.
    public static func gimbalStick(axis0: UInt16, axis1: UInt16, seq: UInt16 = 0) -> Duml.Frame {
        var p = le16(Int(axis0))
        p += [0x00, 0x00]
        p += le16(Int(axis1))
        p += [0x00, 0x80, 0x22, 0x00]
        return gimbal(0x01, p, seq: seq, flags: Duml.flagNotify)
    }

    /// `0x04/0x50` GET `01 04 05` (params `04` + `05`).
    public static func gimbalParamsGet(seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x50, [0x01, 0x04, 0x05], seq: seq)
    }

    /// `0x04/0x50` SET `00 05 01 <speed>`.
    public static func setGimbalSpeed(_ speed: GimbalSpeed, seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x50, [0x00, 0x05, 0x01, speed.rawValue], seq: seq)
    }

    /// `0x04/0x50` SET `00 04 01 <tilt>`. `00` Follow, `01` Tilt Locked.
    public static func setGimbalTiltLock(_ lock: GimbalTiltLock, seq: UInt16 = 0) -> Duml.Frame {
        gimbal(0x50, [0x00, 0x04, 0x01, lock.rawValue], seq: seq)
    }

    /// `0x02/0x1E` SET — `mimo-settings-1` (8 writes, all ACK `00`).
    /// Manual `04 00` (pkt 41562, 50459, 63271, 106227). Auto `01 00` (43232, 51815, 67896, 106978).
    /// No GET: zero empty `0x1E`, no `0x8E` pid tracks this. Read `cam_expo_param` `@7`.
    public static func setExpoMode(_ mode: ExpoMode, seq: UInt16 = 0) -> Duml.Frame {
        camera(0x1E, mode.setPayload, seq: seq)
    }

    public static func setExpoManual(_ on: Bool, seq: UInt16 = 0) -> Duml.Frame {
        setExpoMode(on ? .manual : .auto, seq: seq)
    }

    private static func floatLE(_ v: Float) -> [UInt8] {
        var le = v.bitPattern.littleEndian
        return withUnsafeBytes(of: &le) { Array($0) }
    }

    private static func camera(_ cmd: UInt8, _ payload: [UInt8], seq: UInt16) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: Duml.rxCamera, seq: seq,
            flags: Duml.flagRequest, cmdSet: 0x02, cmdId: cmd, payload: payload)
    }

    private static func gimbal(
        _ cmd: UInt8, _ payload: [UInt8], seq: UInt16,
        flags: UInt8 = Duml.flagRequest
    ) -> Duml.Frame {
        Duml.Frame(
            sender: Duml.senderApp, receiver: rx(type: 0x04, id: 0), seq: seq,
            flags: flags, cmdSet: 0x04, cmdId: cmd, payload: payload)
    }

    static func le16(_ v: Int) -> [UInt8] { [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF)] }
    static func le32(_ v: UInt32) -> [UInt8] {
        [UInt8(v & 0xFF), UInt8((v >> 8) & 0xFF), UInt8((v >> 16) & 0xFF), UInt8((v >> 24) & 0xFF)]
    }
}
