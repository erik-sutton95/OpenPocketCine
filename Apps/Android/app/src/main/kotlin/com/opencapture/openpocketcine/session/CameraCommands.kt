package com.opencapture.openpocketcine.session

import kotlin.math.roundToInt

/**
 * Documented Pocket 4 payloads only (`docs/protocol-notes.md`).
 * No invented `0xE1` values. No 1 Hz `0x09/0xa8`.
 */
object CameraCommands {
    const val SET = 0x02
    const val SENDER_APP = 0x02
    const val RX_CAMERA = 0x01
    const val FLAG_REQUEST = 0x40

    const val CMD_RECORD = 0x02
    const val CMD_EXPO = 0x1E
    const val CMD_FOCUS = 0x24
    const val CMD_SHUTTER = 0x28
    const val CMD_ISO = 0x2A
    const val CMD_WB = 0x2C
    const val CMD_RES_FPS = 0x18
    const val CMD_COLOR = 0x42
    const val CMD_PARAM = 0x8E
    const val CMD_AUDIO_DSP_SET = 0x9F
    const val CMD_AUDIO_DSP_GET = 0xA0
    const val CMD_TAP_PREPARE = 0x22
    const val CMD_TAP_POINT = 0x30
    const val CMD_TAP_HINT = 0x68
    const val CMD_TAP_COMMIT = 0x32

    const val PID_AUDIO_CHANNEL = 0x0020
    const val PID_FOCUS_TRACK = 0x003B
    const val PID_VOCAL_BOOST = 0x004C

    const val RES_1080 = 0x0A
    const val RES_4K = 0x10

    const val COLOR_NORMAL = 0x3F
    const val COLOR_HDR = 0x3C
    const val COLOR_DLOG = 0x17
    const val COLOR_DLOG2 = 0x41
    /** Nano `camcap_color_mode` `3D` — Normal 10-bit. */
    const val COLOR_NORMAL10 = 0x3D
    /** Nano `camcap_color_mode` `00` — D-Log M 10-bit. */
    const val COLOR_DLOG_M = 0x00

    const val EXPO_AUTO = 0x01
    const val EXPO_MANUAL = 0x04

    const val FOCUS_SINGLE = 0x01
    const val FOCUS_CONTINUOUS = 0x02

    const val WB_AUTO = 0x00
    const val WB_CUSTOM = 0x06

    const val AUDIO_MONO = 0x01
    const val AUDIO_STEREO = 0x02
    const val AUDIO_SPATIAL = 0x03

    const val WIND_ON = 0x1A
    const val WIND_OFF = 0x18
    const val DIR_ALL = 0xDA
    const val DIR_FRONT = 0x3A
    const val DIR_FRONT_BACK = 0xBA

    fun recordStart(): ByteArray = byteArrayOf(0x01)

    fun recordStop(): ByteArray = byteArrayOf(0x00)

    /** JNI extra for `CommandKind.setExpoMode`. */
    fun expoWireExtra(mode: Int): String? =
        when (mode) {
            EXPO_AUTO -> "auto"
            EXPO_MANUAL -> "manual"
            else -> null
        }

    /** SET `0x02/0x1E` — iOS `ExpoMode.setPayload` (`01 00` auto, `04 00` manual). */
    fun expoMode(mode: Int): ByteArray =
        when (mode) {
            EXPO_AUTO, EXPO_MANUAL -> byteArrayOf(mode.toByte(), 0x00)
            else -> byteArrayOf()
        }

    fun expoMode(manual: Boolean): ByteArray = expoMode(if (manual) EXPO_MANUAL else EXPO_AUTO)

    fun isoIndex(index: Int): ByteArray = byteArrayOf(index.toByte())

    /** `01` + u16-LE `(denom | 0x8000)` + `00 00 00 40`. */
    fun shutter(denom: Int): ByteArray {
        val coded = (denom and 0xFFFF) or 0x8000
        return byteArrayOf(
            0x01,
            (coded and 0xFF).toByte(),
            ((coded shr 8) and 0xFF).toByte(),
            0x00,
            0x00,
            0x00,
            0x40,
        )
    }

    /** `[mode][kelvin/100 u16-LE][tint i16-LE]`. Matches iOS `WhiteBalance.setPayload`. */
    fun whiteBalance(mode: Int, kelvin: Int, tint: Int): ByteArray {
        val k = (kelvin.coerceAtLeast(0) / 100).coerceIn(0, 0xFFFF)
        val t = tint.coerceIn(-100, 100)
        val tu = t and 0xFFFF
        return byteArrayOf(
            mode.toByte(),
            (k and 0xFF).toByte(),
            ((k shr 8) and 0xFF).toByte(),
            (tu and 0xFF).toByte(),
            ((tu shr 8) and 0xFF).toByte(),
        )
    }

    fun whiteBalanceAuto(): ByteArray = whiteBalance(WB_AUTO, 0, 0)

    fun whiteBalanceCustom(kelvin: Int, tint: Int): ByteArray {
        val (k, t) = clampWhiteBalanceCustom(kelvin, tint)
        return whiteBalance(WB_CUSTOM, k, t)
    }

    /** iOS `CameraSession.setWhiteBalanceCustom` clamp. */
    fun clampWhiteBalanceCustom(kelvin: Int, tint: Int): Pair<Int, Int> =
        kelvin.coerceIn(2_000, 10_000) to tint.coerceIn(-100, 100)

    fun focusMode(continuous: Boolean): ByteArray =
        byteArrayOf(if (continuous) FOCUS_CONTINUOUS.toByte() else FOCUS_SINGLE.toByte())

    fun colorMode(mode: Int): ByteArray = byteArrayOf(mode.toByte())

    /**
     * D-Log2 cannot zoom. Any step off 1× hops the body to D-Log.
     * ISO star still follows `status.colorMode` after the body reports — this
     * guess must not flip the wheel marker while `@2` is still D-Log2.
     */
    fun colorModeForZoom(factor: Double, current: Int): Int? =
        CamFov.colorModeForZoom(factor, current)

    /** iOS `CamFov.shouldRestoreDLog2` — only park back at 1×, not 2.9×. */
    fun shouldRestoreDLog2(factor: Double): Boolean = CamFov.shouldRestoreDLog2(factor)

    /** `[res][fps_idx] 00 00 00`. */
    fun resolutionFps(res: Int, fpsIndex: Int): ByteArray =
        byteArrayOf(res.toByte(), fpsIndex.toByte(), 0x00, 0x00, 0x00)

    fun paramGet(pid: Int): ByteArray =
        byteArrayOf(0x00, 0x01, (pid and 0xFF).toByte(), ((pid shr 8) and 0xFF).toByte())

    fun paramSet(pid: Int, value: Int): ByteArray =
        byteArrayOf(
            0x01,
            0x01,
            (pid and 0xFF).toByte(),
            ((pid shr 8) and 0xFF).toByte(),
            0x01,
            value.toByte(),
        )

    const val AUDIO_DSP_SIZE = 26

    fun audioDspGet(): ByteArray = ByteArray(0)

    /** SET payload is the GET blob with only `@2` rewritten. Do not invent other bytes. */
    fun audioDspSet(blob: ByteArray, at2: Int): ByteArray {
        val out = blob.copyOf()
        if (out.size > 2) out[2] = at2.toByte()
        return out
    }

    /** Wind off is only `18`. Captured directional bytes already include wind-on. */
    fun patchWind(blob: ByteArray, on: Boolean): ByteArray {
        if (!on) return audioDspSet(blob, WIND_OFF)
        val raw = if (blob.size > 2) blob[2].toInt() and 0xFF else -1
        if (directionalFrom(raw) >= 0) return audioDspSet(blob, raw)
        return audioDspSet(blob, WIND_ON)
    }

    fun patchDirectional(blob: ByteArray, mode: Int): ByteArray =
        audioDspSet(
            blob,
            when (mode) {
                1 -> DIR_FRONT
                2 -> DIR_FRONT_BACK
                else -> DIR_ALL
            },
        )

    /** `0` off, `1` on, `-1` leave. Directional bytes count as on. */
    fun windFrom(raw: Int): Int =
        when (raw) {
            WIND_OFF -> 0
            WIND_ON, DIR_ALL, DIR_FRONT, DIR_FRONT_BACK -> 1
            else -> -1
        }

    /** `0` All / `1` Front / `2` Front+back / `-1` not a directional byte. */
    fun directionalFrom(raw: Int): Int =
        when (raw) {
            DIR_ALL -> 0
            DIR_FRONT -> 1
            DIR_FRONT_BACK -> 2
            else -> -1
        }

    fun audioDspHex(blob: ByteArray): String =
        buildString(blob.size * 2) {
            for (b in blob) append("%02x".format(b.toInt() and 0xFF))
        }

    fun audioDspBytes(hex: String): ByteArray? {
        if (hex.length < 6 || hex.length % 2 != 0) return null
        val out = ByteArray(hex.length / 2)
        for (i in out.indices) {
            val b = hex.substring(i * 2, i * 2 + 2).toIntOrNull(16) ?: return null
            out[i] = b.toByte()
        }
        return out
    }

    fun audioChannelLabel(value: Int): String? =
        when (value) {
            AUDIO_MONO -> "Mono"
            AUDIO_STEREO -> "Stereo"
            AUDIO_SPATIAL -> "Spatial"
            else -> null
        }

    fun audioDirLabel(mode: Int): String? =
        when (mode) {
            0 -> "All"
            1 -> "Front"
            2 -> "Front+back"
            else -> null
        }

    fun tapPrepare(): ByteArray = byteArrayOf(0x02)

    fun tapPoint(x: Float, y: Float): ByteArray = floatLE(x) + floatLE(y) + ByteArray(12)

    fun tapHint(): ByteArray = byteArrayOf(0x08)

    fun tapCommit(x: Float, y: Float): ByteArray =
        byteArrayOf(0x00, 0x02, 0x01, 0x00) + floatLE(x) + floatLE(y) + ByteArray(8)

    const val RX_GIMBAL = 0x04
    const val LIVE_VIEW_ENABLE_RECEIVER_POCKET = 0x08
    const val LIVE_VIEW_ENABLE_RECEIVER_NANO = 0x41

    const val CMD_PHOTO = 0x01
    const val CMD_EV = 0x2E
    const val CMD_ZOOM = 0xB8
    const val CMD_TRACK_SET = 0xA6
    const val CMD_TRACK_POLL = 0xA5
    const val CMD_PLAYBACK = 0x0C
    const val CMD_GIMBAL_MODE = 0x4C
    const val CMD_MEDIA_LIST = 0x26
    const val CMD_MEDIA_DELETE = 0x28
    const val CMD_MEDIA_FAVORITE = 0xBF
    const val CMD_NANO_GATE = 0x09
    const val CMD_LIVE_VIEW = 0xA8

    const val PID_ISO_LIMIT = 0x000F

    const val ZOOM_LENS_1X = 217
    const val ZOOM_LENS_3X = 651
    const val ZOOM_LENS_6X = 1302
    const val ZOOM_LENS_12X = 2604
    const val ZOOM_SLEW_TELE = 100
    const val ZOOM_SLEW_WIDE = 300

    const val SHOOT_PHOTO = 0x05
    const val SHOOT_PHOTO_POCKET4 = 0x17
    const val SHOOT_SUPER_NIGHT = 0x28

    fun isPhotoMode(shootingMode: Int): Boolean =
        shootingMode == SHOOT_PHOTO ||
            shootingMode == SHOOT_PHOTO_POCKET4 ||
            shootingMode == SHOOT_SUPER_NIGHT

    fun shootPhoto(): ByteArray = byteArrayOf(0x01)

    /** `0x02/0x2E` 1-byte EV. `0x10` = 0.0; ⅓-stop steps, −9…+9 thirds. */
    fun ev(thirds: Int): ByteArray {
        val t = thirds.coerceIn(-9, 9)
        return byteArrayOf((0x10 + t).toByte())
    }

    fun isoLimit(raw: Int): ByteArray = paramSet(PID_ISO_LIMIT, raw)

    fun zoomLens(position: Int): ByteArray {
        val p = position.coerceIn(0, 0xFFFF)
        return byteArrayOf(0x0A, 0x4E, (p and 0xFF).toByte(), ((p shr 8) and 0xFF).toByte())
    }

    fun zoomSlew(value: Int): ByteArray {
        val v = value.coerceIn(0, 0xFFFF)
        return byteArrayOf(0x03, 0x00, (v and 0xFF).toByte(), ((v shr 8) and 0xFF).toByte())
    }

    fun zoomStop(): ByteArray = byteArrayOf(0xFF.toByte(), 0x00, 0x00, 0x00)

    /** Chip 1× / 3× / 6× / 12× land on 217 / 651 / 1302 / 2604. */
    fun lensForZoomFactor(factor: Double): Int =
        when (val write = CamFov.chipWrite(factor)) {
            is CamFov.ChipWrite.Lens -> write.position
            else -> CamFov.lensPosition(factor)
        }

    fun zoomForFactor(factor: Double): ByteArray = zoomLens(lensForZoomFactor(factor))

    fun gimbalRecenter(): ByteArray = byteArrayOf(0xFE.toByte(), 0x08)

    fun gimbalFlip(): ByteArray = byteArrayOf(0xFE.toByte(), 0x09)

    fun liveViewEnablePayload(): ByteArray =
        byteArrayOf(0x00, 0x04, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00)

    /** Nano `0x02/0x09` start `…03` / stop `…04`. Do not send on Pocket. */
    fun nanoLiveViewGate(start: Boolean): ByteArray =
        ByteArray(11).also { it[10] = if (start) 0x03 else 0x04 }

    fun enterPlayback(): ByteArray = byteArrayOf(0x01, 0x01, 0x00, 0x01)

    fun exitPlayback(): ByteArray = byteArrayOf(0x01, 0x01, 0x00, 0x00)

    fun trackingBox(id: Int, x: Float, y: Float, width: Float, height: Float): ByteArray {
        val uid = id and 0xFFFF
        return byteArrayOf(0x01, 0x00, 0x00) +
            u16LE(uid) +
            floatLE(x) +
            floatLE(y) +
            floatLE(width) +
            floatLE(height)
    }

    fun clearTracking(): ByteArray = ByteArray(21)

    fun pollTracking(): ByteArray = byteArrayOf(0x00)

    fun mediaList(counter: Int, cursor: Int): ByteArray {
        val payload = MEDIA_LIST_TEMPLATE.copyOf()
        payload[4] = (counter and 0xFF).toByte()
        payload[10] = (cursor and 0xFF).toByte()
        payload[11] = ((cursor shr 8) and 0xFF).toByte()
        payload[12] = ((cursor shr 16) and 0xFF).toByte()
        payload[13] = ((cursor shr 24) and 0xFF).toByte()
        return payload
    }

    fun mediaListTrigger(): ByteArray =
        byteArrayOf(
            0x4A, 0x04, 0x0E, 0x10,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
        )

    fun deleteMedia(handle: Int, counter: Int): ByteArray =
        byteArrayOf(0x01) +
            u32LE(handle) +
            u32LE(counter) +
            byteArrayOf(0x00) +
            u32LE(1) +
            byteArrayOf(0x01, 0x01, 0x00, 0x00)

    fun setMediaFavorite(handle: Int, on: Boolean, counter: Int): ByteArray =
        byteArrayOf(0x01, 0x01) +
            u32LE(handle) +
            u32LE(counter) +
            byteArrayOf(0x00, if (on) 0x01 else 0x00, 0x00, 0x00, 0x00)

    const val GIMBAL_STICK_CENTER = 1024
    const val GIMBAL_STICK_TRAVEL = 550
    const val GIMBAL_STICK_MIN = 474
    const val GIMBAL_STICK_MAX = 1574
    const val GIMBAL_STICK_DEADZONE = 0.08f

    const val GIMBAL_STICK_DEFAULT_SENSITIVITY = 4

    /** 4 = 1.0 (captured ±550 throw). 5 saturates earlier; 1–3 never reach full throw. */
    fun gimbalSensitivityGain(sensitivity: Int): Float =
        sensitivity.coerceIn(1, 5) / GIMBAL_STICK_DEFAULT_SENSITIVITY.toFloat()

    /** `x` −1…1 left…right → pan (axis1). `y` −1…1 down…up → tilt (axis0). */
    fun gimbalAxis(normalized: Float, sensitivity: Int = GIMBAL_STICK_DEFAULT_SENSITIVITY): Int {
        val n = normalized.coerceIn(-1f, 1f)
        if (kotlin.math.abs(n) < GIMBAL_STICK_DEADZONE) return GIMBAL_STICK_CENTER
        val scaled = (n * gimbalSensitivityGain(sensitivity)).coerceIn(-1f, 1f)
        return (GIMBAL_STICK_CENTER + scaled * GIMBAL_STICK_TRAVEL)
            .roundToInt()
            .coerceIn(GIMBAL_STICK_MIN, GIMBAL_STICK_MAX)
    }

    fun gimbalAxes(
        x: Float,
        y: Float,
        invertPan: Boolean = false,
        sensitivity: Int = GIMBAL_STICK_DEFAULT_SENSITIVITY,
    ): Pair<Int, Int> =
        gimbalAxis(y, sensitivity) to gimbalAxis(if (invertPan) -x else x, sensitivity)

    /** `0x04/0x01` payload: two u16-LE axes + trailer `00 80 22 00`. */
    fun gimbalStickPayload(axis0: Int, axis1: Int): ByteArray {
        val a0 = axis0.coerceIn(GIMBAL_STICK_MIN, GIMBAL_STICK_MAX)
        val a1 = axis1.coerceIn(GIMBAL_STICK_MIN, GIMBAL_STICK_MAX)
        return byteArrayOf(
            (a0 and 0xFF).toByte(),
            ((a0 shr 8) and 0xFF).toByte(),
            0x00,
            0x00,
            (a1 and 0xFF).toByte(),
            ((a1 shr 8) and 0xFF).toByte(),
            0x00,
            0x80.toByte(),
            0x22,
            0x00,
        )
    }

    fun fpsIndex(fps: Int): Int? = VideoFrameRate.fromFps(fps)?.rawValue

    fun fpsFromIndex(index: Int): Int? = VideoFrameRate.fromRaw(index)?.fps

    /**
     * iOS `CameraStatusDecoder.fps(index:)` — subscribe display table.
     * SET still uses [VideoFrameRate] only (no 120 / 240 / 100 / 96 / 15).
     */
    fun fpsFromSubscribeIndex(index: Int): Int? =
        when (index) {
            1 -> 24
            2 -> 25
            3 -> 30
            4 -> 48
            5 -> 50
            6 -> 60
            7 -> 120
            8 -> 240
            10 -> 100
            11 -> 96
            29 -> 15
            else -> null
        }

    fun resolutionLabel(code: Int): String = VideoResolution.fromRaw(code)?.label ?: "—"

    fun colorLabel(mode: Int, family: String = "pocket"): String =
        when (mode) {
            COLOR_NORMAL -> if (family == "nano") "Normal 8-bit" else "Normal"
            COLOR_HDR -> "HDR"
            COLOR_DLOG -> "D-Log"
            COLOR_DLOG2 -> "D-Log2"
            COLOR_NORMAL10 -> "Normal 10-bit"
            COLOR_DLOG_M -> "D-Log M 10-bit"
            else -> "—"
        }

    /** `IsoIndex.allCases` raw bytes. Unknown camcap entries are dropped. */
    val ISO_INDEX_BYTES = setOf(0x00, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B)

    fun isoLabel(index: Int): String =
        when (index) {
            0x00 -> "Auto"
            0x03 -> "100"
            0x04 -> "200"
            0x05 -> "400"
            0x06 -> "800"
            0x07 -> "1600"
            0x08 -> "3200"
            0x09 -> "6400"
            0x0A -> "12800"
            0x0B -> "25600"
            else -> "—"
        }

    /** nil for Auto / unknown — matches Swift `IsoIndex.isoValue`. */
    fun isoValue(index: Int): Int? =
        when (index) {
            0x03 -> 100
            0x04 -> 200
            0x05 -> 400
            0x06 -> 800
            0x07 -> 1600
            0x08 -> 3200
            0x09 -> 6400
            0x0A -> 12800
            0x0B -> 25600
            else -> null
        }

    fun isoIndexFromValue(iso: Int): Int? =
        when (iso) {
            100 -> 0x03
            200 -> 0x04
            400 -> 0x05
            800 -> 0x06
            1600 -> 0x07
            3200 -> 0x08
            6400 -> 0x09
            12800 -> 0x0A
            25600 -> 0x0B
            else -> null
        }

    /** D-Log2 has no Auto ISO. Unknown color is treated as Normal. */
    fun offersIsoAuto(colorMode: Int): Boolean = colorMode != COLOR_DLOG2

    /** GET `0x8E` pid `0x000F` only when Auto ISO exists. */
    fun shouldGetIsoLimit(colorMode: Int): Boolean = offersIsoAuto(colorMode)

    fun isoWheelIndices(available: List<Int>, fallback: List<Int>): List<Int> =
        if (available.isEmpty()) fallback else available

    /**
     * Native base ISO for D-Log ↔ D-Log2 hops. Rec.709 / HLG / D-Log M / unknown:
     * none. Hop uses this, not [markedIsoLabel] (D-Log M stars 400 but does not hop).
     */
    fun baseIsoLabel(colorMode: Int): String? =
        when (colorMode) {
            COLOR_DLOG -> "400"
            COLOR_DLOG2 -> "1600"
            else -> null
        }

    /**
     * If the operator is still on [from]'s native ISO, hop to [to]'s native.
     * Off-base or Auto stays put. Rec.709 / HDR / D-Log M have no native — no hop.
     */
    fun nativeIsoHop(from: Int, to: Int, currentIndex: Int, hopEnabled: Boolean): Int? {
        if (!hopEnabled || from == to) return null
        val fromBase = baseIsoLabel(from)?.toIntOrNull() ?: return null
        val toBase = baseIsoLabel(to)?.toIntOrNull() ?: return null
        val current = isoValue(currentIndex) ?: return null
        if (current != fromBase) return null
        return isoIndexFromValue(toBase)
    }

    /**
     * Star on the ISO wheel. Follows `cam_image_effect` `@2` after the body
     * reports, mapped like iOS `MonitorTransfer` — D-Log / D-Log M = 400,
     * D-Log2 = 1600. Rec.709 / HLG / unknown: none. Not a tele hop SET.
     */
    fun markedIsoLabel(colorMode: Int): String? =
        when (colorMode) {
            COLOR_DLOG, COLOR_DLOG_M -> "400"
            COLOR_DLOG2 -> "1600"
            else -> null
        }

    /** OpenZCine drum: `" ★"` after the native base, same color as the number. */
    fun isoChipLabel(label: String, colorMode: Int): String {
        val base = markedIsoLabel(colorMode)
        return if (base != null && label == base) "$label ★" else label
    }

    fun isoChoices(colorMode: Int): List<Pair<Int, String>> {
        val all =
            listOf(
                0x00 to "Auto",
                0x03 to "100",
                0x04 to "200",
                0x05 to "400",
                0x06 to "800",
                0x07 to "1600",
                0x08 to "3200",
                0x09 to "6400",
                0x0A to "12800",
                0x0B to "25600",
            )
        val allowed =
            when (colorMode) {
                COLOR_DLOG2 -> setOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08)
                COLOR_DLOG -> setOf(0x00, 0x05, 0x06, 0x07, 0x08, 0x09)
                else -> setOf(0x00, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x0A, 0x0B)
            }
        return all.filter { it.first in allowed }
    }

    fun parseShutterDenoms(value: ByteArray): List<Int> {
        if (value.size < 13 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 10 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[9].toInt() and 0xFF
        val payload = body.copyOfRange(10, body.size)
        if (count <= 0 || payload.size != count * 3) return emptyList()
        val out = ArrayList<Int>(count)
        val seen = HashSet<Int>()
        var i = 0
        while (i + 2 < payload.size) {
            val raw = (payload[i].toInt() and 0xFF) or ((payload[i + 1].toInt() and 0xFF) shl 8)
            if (raw and 0x8000 != 0) {
                val denom = raw and 0x7FFF
                if (denom in 1..16_000 && seen.add(denom)) out.add(denom)
            }
            i += 3
        }
        return out
    }

    /**
     * Nano `camcap_color_mode` (Mimo 2026-08-18): `01 04 00 03 00 3F 3D`.
     * Pocket never published this table in our takes. Unknown bytes dropped.
     */
    fun parseColorModes(value: ByteArray): List<Int> {
        if (value.size < 5 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 2 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[0].toInt() and 0xFF
        if (count < 1 || body.size < 1 + count) return emptyList()
        val known =
            setOf(COLOR_NORMAL, COLOR_HDR, COLOR_DLOG, COLOR_DLOG2, COLOR_NORMAL10, COLOR_DLOG_M)
        return body.copyOfRange(1, 1 + count).map { it.toInt() and 0xFF }.filter { it in known }
    }

    fun parseIsoIndices(value: ByteArray): List<Int> {
        if (value.size < 5 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 2 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[1].toInt() and 0xFF
        if (body[0].toInt() != 0 || count < 1 || body.size < 2 + count) return emptyList()
        return body.copyOfRange(2, 2 + count).map { it.toInt() and 0xFF }.filter { it in ISO_INDEX_BYTES }
    }

    fun shutterWheelDenoms(available: List<Int>, current: Int): List<Int> {
        if (available.isNotEmpty()) return available
        return if (current in 1..16_000) listOf(current) else emptyList()
    }

    val kelvinPresets = listOf(2000, 3200, 4000, 5000, 5600, 6500, 8000, 10000)

    private val MEDIA_LIST_TEMPLATE =
        byteArrayOf(
            0x4A, 0x00, 0x2A, 0x10,
            0x01, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x01, 0x00, 0x00, 0x00,
            0x2D, 0x00, 0x0D, 0x01, 0x00,
            0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(),
            0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(), 0xFF.toByte(),
            0x00, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00,
            0x00, 0x00, 0x00, 0x00, 0x00,
        )

    private fun u16LE(value: Int): ByteArray =
        byteArrayOf((value and 0xFF).toByte(), ((value shr 8) and 0xFF).toByte())

    private fun u32LE(value: Int): ByteArray =
        byteArrayOf(
            (value and 0xFF).toByte(),
            ((value shr 8) and 0xFF).toByte(),
            ((value shr 16) and 0xFF).toByte(),
            ((value shr 24) and 0xFF).toByte(),
        )

    private fun floatLE(value: Float): ByteArray {
        val bits = value.toRawBits()
        return byteArrayOf(
            (bits and 0xFF).toByte(),
            ((bits shr 8) and 0xFF).toByte(),
            ((bits shr 16) and 0xFF).toByte(),
            ((bits shr 24) and 0xFF).toByte(),
        )
    }
}

/** AF-C submenu. `0x02/0x8E` pid `0x003B`. SET/GET value is `01 <mode>`. */
enum class FocusTrackMode(val raw: Int, val label: String) {
    DEFAULT(0x00, "Default"),
    PRODUCT_SHOWCASE(0x01, "Product Showcase"),
    SUBJECT_LOCK(0x02, "Subject Lock Tracking"),
    REGISTERED_PRIORITY(0x03, "Registered Subject Priority"),
    ;

    companion object {
        /** Camera can pause HEVC while switching AF-C intelligence. */
        const val VIDEO_GRACE_SEC = 4.0

        fun fromRaw(raw: Int): FocusTrackMode? = entries.firstOrNull { it.raw == raw }

        fun shouldHoldWatchdog(secondsSinceSet: Double?): Boolean {
            val s = secondsSinceSet ?: return false
            return s >= 0.0 && s < VIDEO_GRACE_SEC
        }

        /** GET reply `00 00 01 3B 00 02 01 <mode>`. */
        fun parseReply(payload: ByteArray): FocusTrackMode? {
            if (payload.size < 8) return null
            if (payload[0] != 0.toByte() || payload[1] != 0.toByte() || payload[2] != 0x01.toByte()) {
                return null
            }
            val pid = (payload[3].toInt() and 0xFF) or ((payload[4].toInt() and 0xFF) shl 8)
            if (pid != CameraCommands.PID_FOCUS_TRACK) return null
            val len = payload[5].toInt() and 0xFF
            if (len != 2 || payload.size < 8 || payload[6] != 0x01.toByte()) return null
            return fromRaw(payload[7].toInt() and 0xFF)
        }
    }
}

/** FOCUS picker + capture-strip chip. Single is `0x24`. The rest are AF-C + pid `0x003B`. */
enum class FocusOption(val chip: String) {
    SINGLE("AF-S"),
    CONTINUOUS_DEFAULT("AF-C"),
    PRODUCT_SHOWCASE("Showcase"),
    SUBJECT_LOCK("Lock"),
    REGISTERED_PRIORITY("Priority"),
    ;

    companion object {
        fun resolve(mode: Int, track: Int): FocusOption? =
            when (mode) {
                CameraCommands.FOCUS_SINGLE -> SINGLE
                CameraCommands.FOCUS_CONTINUOUS ->
                    when (FocusTrackMode.fromRaw(track)) {
                        FocusTrackMode.PRODUCT_SHOWCASE -> PRODUCT_SHOWCASE
                        FocusTrackMode.SUBJECT_LOCK -> SUBJECT_LOCK
                        FocusTrackMode.REGISTERED_PRIORITY -> REGISTERED_PRIORITY
                        FocusTrackMode.DEFAULT, null -> CONTINUOUS_DEFAULT
                    }
                else -> null
            }
    }
}

/**
 * Drop GET / subscribe snapshots that still show the pre-SET audio row.
 * Mirrors iOS `CameraSession.AudioPin` (2 s).
 */
data class AudioPin(
    val channel: Int? = null,
    val vocal: Int? = null,
    val wind: Int? = null,
    val directional: Int? = null,
    val deadlineElapsedMs: Long,
) {
    fun isEmpty(): Boolean =
        channel == null && vocal == null && wind == null && directional == null

    fun absorb(
        incoming: CameraStatus,
        current: CameraStatus,
        nowElapsedMs: Long,
    ): Pair<CameraStatus, AudioPin?> {
        if (nowElapsedMs >= deadlineElapsedMs) return incoming to null
        var next = incoming
        var channel = this.channel
        var vocal = this.vocal
        var wind = this.wind
        var directional = this.directional
        if (channel != null) {
            when {
                incoming.audioChannel == channel -> channel = null
                incoming.audioChannel >= 0 -> next = next.copy(audioChannel = current.audioChannel)
            }
        }
        if (vocal != null) {
            when {
                incoming.vocalBoost == vocal -> vocal = null
                incoming.vocalBoost >= 0 -> next = next.copy(vocalBoost = current.vocalBoost)
            }
        }
        if (wind != null) {
            when {
                incoming.windNr == wind -> wind = null
                incoming.windNr >= 0 -> next = next.copy(windNr = current.windNr)
            }
        }
        if (directional != null) {
            when {
                incoming.directionalAudio == directional -> directional = null
                incoming.directionalAudio >= 0 ->
                    next = next.copy(directionalAudio = current.directionalAudio)
            }
        }
        val pin =
            AudioPin(
                channel = channel,
                vocal = vocal,
                wind = wind,
                directional = directional,
                deadlineElapsedMs = deadlineElapsedMs,
            )
        return next to pin.takeUnless { it.isEmpty() }
    }

    companion object {
        const val TTL_MS = 2_000L
    }
}
