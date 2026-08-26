package com.opencapture.openpocketcine.bridge

/**
 * JNI binding to `libOpenPocketCineAndroid.so` — OpenPocketViewCore plus
 * `OpenPocketCineAndroidFacade`. Staged by `:app:stageSwiftCore` / `just android-core`.
 */
object SwiftCore {
    val isAvailable: Boolean by lazy {
        try {
            System.loadLibrary("OpenPocketCineAndroid")
            true
        } catch (_: UnsatisfiedLinkError) {
            false
        }
    }

    const val CMD_SESSION_WAKE = 1
    const val CMD_SESSION_KEEPALIVE = 2
    const val CMD_SET_PAIRING_PIN = 3
    const val CMD_PAIR_APPROVAL_ACK = 4
    const val CMD_SESSION_5310 = 5
    const val CMD_GET_WIFI_SSID = 6
    const val CMD_GET_WIFI_PASSWORD = 7
    const val CMD_APP_DEVICE_INFO = 8
    const val CMD_APP_PRESENCE = 9
    const val CMD_GIMBAL_INIT = 10
    const val CMD_SUBSCRIBE = 11
    const val CMD_ENTER_PLAYBACK = 12
    const val CMD_LIVE_VIEW_ENABLE = 13
    const val CMD_RECORD_START = 14
    const val CMD_RECORD_STOP = 15
    const val CMD_SET_EXPO_MODE = 16
    const val CMD_SET_SHUTTER = 17
    const val CMD_SET_ISO_INDEX = 18
    const val CMD_SET_COLOR_MODE = 19
    const val CMD_SET_FOCUS_MODE = 20
    const val CMD_SET_WB_AUTO = 21
    const val CMD_SET_WB_CUSTOM = 22
    const val CMD_GET_AUDIO_CHANNEL = 23
    const val CMD_SET_AUDIO_CHANNEL = 24
    const val CMD_GET_VOCAL_BOOST = 25
    const val CMD_SET_VOCAL_BOOST = 26
    const val CMD_AUDIO_DSP_GET = 27
    const val CMD_AUDIO_DSP_SET = 28
    const val CMD_AUDIO_DSP_PATCH_WIND = 29
    const val CMD_AUDIO_DSP_PATCH_DIRECTIONAL = 30
    const val CMD_SET_VIDEO_FORMAT = 31
    const val CMD_TAP_FOCUS_PREPARE = 32
    const val CMD_TAP_FOCUS_POINT = 33
    const val CMD_TAP_FOCUS_HINT = 34
    const val CMD_TAP_FOCUS_COMMIT = 35
    const val CMD_SHOOT_PHOTO = 36
    const val CMD_SET_SHOOTING_MODE = 37
    const val CMD_SET_EV = 38
    const val CMD_SET_ISO_LIMIT = 39
    const val CMD_GET_ISO_LIMIT = 40
    const val CMD_SET_FOV = 41
    const val CMD_SET_ZOOM_LENS = 42
    const val CMD_SET_ZOOM_SLEW = 43
    const val CMD_SET_ZOOM_STOP = 44
    const val CMD_GIMBAL_RECENTER = 45
    const val CMD_GIMBAL_FLIP = 46
    const val CMD_GIMBAL_STICK = 47
    const val CMD_SET_TRACKING_BOX = 48
    const val CMD_CLEAR_TRACKING_BOX = 49
    const val CMD_POLL_TRACKING = 50
    const val CMD_SET_FOCUS_TRACK = 51
    const val CMD_GET_FOCUS_TRACK = 52
    const val CMD_GET_GLAMOUR = 53
    const val CMD_SET_GLAMOUR = 54
    const val CMD_EXIT_PLAYBACK = 55
    const val CMD_MEDIA_LIST = 56
    const val CMD_MEDIA_LIST_TRIGGER = 57
    const val CMD_DELETE_MEDIA = 58
    const val CMD_SET_MEDIA_FAVORITE = 59
    const val CMD_NANO_LIVE_VIEW_GATE = 60
    const val CMD_GET_SELFIE_FLIP = 61

    /** DUML set/cmd key the camera ACKs for [kind]. */
    fun waitKey(kind: Int): Int =
        when (kind) {
            CMD_RECORD_START, CMD_RECORD_STOP -> 0x0202
            CMD_SET_EXPO_MODE -> 0x021E
            CMD_SET_SHUTTER -> 0x0228
            CMD_SET_ISO_INDEX -> 0x022A
            CMD_SET_COLOR_MODE -> 0x0242
            CMD_SET_FOCUS_MODE -> 0x0224
            CMD_SET_WB_AUTO, CMD_SET_WB_CUSTOM -> 0x022C
            CMD_GET_AUDIO_CHANNEL, CMD_SET_AUDIO_CHANNEL,
            CMD_GET_VOCAL_BOOST, CMD_SET_VOCAL_BOOST,
            CMD_SET_ISO_LIMIT, CMD_GET_ISO_LIMIT, CMD_SET_FOV,
            CMD_SET_FOCUS_TRACK, CMD_GET_FOCUS_TRACK,
            CMD_GET_GLAMOUR, CMD_SET_GLAMOUR, CMD_GET_SELFIE_FLIP,
            -> 0x028E
            CMD_AUDIO_DSP_GET -> 0x02A0
            CMD_AUDIO_DSP_SET, CMD_AUDIO_DSP_PATCH_WIND, CMD_AUDIO_DSP_PATCH_DIRECTIONAL -> 0x029F
            CMD_SET_VIDEO_FORMAT -> 0x0218
            CMD_TAP_FOCUS_PREPARE -> 0x0222
            CMD_TAP_FOCUS_POINT -> 0x0230
            CMD_TAP_FOCUS_HINT -> 0x0268
            CMD_TAP_FOCUS_COMMIT -> 0x0232
            CMD_SHOOT_PHOTO -> 0x0201
            CMD_SET_SHOOTING_MODE -> 0x02E1
            CMD_SET_EV -> 0x022E
            CMD_SET_ZOOM_LENS, CMD_SET_ZOOM_SLEW, CMD_SET_ZOOM_STOP -> 0x02B8
            CMD_SET_TRACKING_BOX, CMD_CLEAR_TRACKING_BOX -> 0x02A6
            CMD_POLL_TRACKING -> 0x02A5
            CMD_GIMBAL_RECENTER, CMD_GIMBAL_FLIP -> 0x044C
            CMD_EXIT_PLAYBACK -> 0x020C
            CMD_MEDIA_LIST, CMD_MEDIA_LIST_TRIGGER -> 0x0026
            CMD_DELETE_MEDIA -> 0x0028
            CMD_SET_MEDIA_FAVORITE -> 0x02BF
            CMD_NANO_LIVE_VIEW_GATE -> 0x0209
            else -> 0
        }

    const val FLAG_REQUEST = 0x40
    const val FLAG_RESPONSE = 0xC0
    const val FLAG_NOTIFY = 0x00
    const val SENDER_APP = 0x02
    const val RX_GIMBAL = 0x04

    external fun coreVersion(): String

    external fun encodeDuml(
        sender: Int,
        receiver: Int,
        seq: Int,
        flags: Int,
        cmdSet: Int,
        cmdId: Int,
        payload: ByteArray?,
    ): ByteArray?

    external fun scanDuml(data: ByteArray): ByteArray?

    external fun unpackStatusString(payload: ByteArray): String?

    external fun encodeCommand(kind: Int, seq: Int, extra: String?): ByteArray?

    external fun bleAdvertModelId(payload: ByteArray): Int

    external fun resolveCameraModel(modelId: Int, name: String?): String?

    external fun transportHeader(pktType: Int, payloadLen: Int, sessionId: Int, seq: Int): ByteArray?

    external fun routingHeader(seq: Int, cmdCounter: Int, drone: Boolean): ByteArray?

    external fun handshakePayload(baseSeq: Int): ByteArray?

    external fun ackPayload(peerCursor: Int, ackedDataCursor: Int, extraCursor: Int): ByteArray?

    external fun transportSeq(datagram: ByteArray): Int

    external fun applyStatus(cmdSet: Int, cmdId: Int, payload: ByteArray, previousJSON: String): String?

    external fun hevcCsd(annexB: ByteArray): ByteArray?

    external fun hevcNalTypes(annexB: ByteArray): String?

    external fun hevcIsKeyframe(annexB: ByteArray): Boolean

    external fun depacketizerCreate(): Long

    external fun depacketizerFeed(handle: Long, payload: ByteArray): ByteArray?

    external fun depacketizerDropped(handle: Long): Int

    external fun depacketizerReset(handle: Long)

    external fun depacketizerDestroy(handle: Long)

    /** `"1\\u001F{size}\\u001Fcustom:{fileName}"` or empty on reject. */
    external fun validateImportedLut(utf8: ByteArray, fileName: String): String?

    /** Packed-2D RGBA8 cube (`n³ × 4`) for GLES upload. Input-referred LUT exposure. */
    external fun packImportedLut(utf8: ByteArray, exposureStops: Double, colorMode: Int): ByteArray?

    /** Generated Creative look (Mono / Contrast / Warm / Cool). */
    external fun packCreativeLut(title: String, exposureStops: Double, colorMode: Int): ByteArray?

    /** Overlay paint cube for FALSE (`0` PStops / `1` IRE / `2` Limits). */
    external fun packFalseColorPaint(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /** Overlay weight cube paired with [packFalseColorPaint]. */
    external fun packFalseColorWeight(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /**
     * `[highlightNative, midtoneNative, midtoneHalfNative, peakingGateScale]`
     * on encoded camera codes (iOS `ScopeDisplayScale.signalNative`).
     */
    external fun feedAssistScalars(
        colorMode: Int,
        iso: Int,
        highlightIRE: Float,
        midtoneIRE: Float,
    ): FloatArray?

    external fun gimbalStickEncode(
        x: Double,
        y: Double,
        invertPan: Boolean,
        sensitivity: Int,
    ): String?

    external fun camFovChipWrite(currentFactor: Double): String?

    external fun feedWatchdogAction(snapshotJSON: String): String?

    external fun feedWatchdogCreate(): Long

    external fun feedWatchdogTick(handle: Long, snapshotJSON: String): String?

    external fun feedWatchdogReset(handle: Long)

    external fun feedWatchdogDestroy(handle: Long)

    /** Probe JSON for playback conform preview. See `AndroidSessionWire.conformPreviewJSON`. */
    external fun conformPreviewJSON(request: String): String?

    fun command(kind: Int, seq: Int = 0, extra: String? = null): ByteArray {
        check(isAvailable) { "Swift core is not loaded" }
        return encodeCommand(kind, seq and 0xFFFF, extra)
            ?: error("encodeCommand($kind) returned null")
    }

    fun subscribe(key: String, subId: Long, seq: Int = 0): ByteArray =
        command(CMD_SUBSCRIBE, seq, "$key\u001f$subId")
}
