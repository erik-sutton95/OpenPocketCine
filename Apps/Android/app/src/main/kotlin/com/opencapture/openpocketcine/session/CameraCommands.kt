package com.opencapture.openpocketcine.session

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
    const val PID_VOCAL_BOOST = 0x004C

    const val RES_1080 = 0x0A
    const val RES_4K = 0x10

    const val COLOR_NORMAL = 0x3F
    const val COLOR_HDR = 0x3C
    const val COLOR_DLOG = 0x17
    const val COLOR_DLOG2 = 0x41

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

    fun expoMode(manual: Boolean): ByteArray =
        byteArrayOf(if (manual) EXPO_MANUAL.toByte() else EXPO_AUTO.toByte(), 0x00)

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

    /** `[mode][kelvin/100 u16-LE][tint i16-LE]`. */
    fun whiteBalance(mode: Int, kelvin: Int, tint: Int): ByteArray {
        val k = (kelvin / 100).coerceIn(0, 0xFFFF)
        val t = tint.coerceIn(-100, 100)
        return byteArrayOf(
            mode.toByte(),
            (k and 0xFF).toByte(),
            ((k shr 8) and 0xFF).toByte(),
            (t and 0xFF).toByte(),
            ((t shr 8) and 0xFF).toByte(),
        )
    }

    fun whiteBalanceAuto(): ByteArray = byteArrayOf(0x00, 0x00, 0x00, 0x00, 0x00)

    fun focusMode(continuous: Boolean): ByteArray =
        byteArrayOf(if (continuous) FOCUS_CONTINUOUS.toByte() else FOCUS_SINGLE.toByte())

    fun colorMode(mode: Int): ByteArray = byteArrayOf(mode.toByte())

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

    fun audioDspGet(): ByteArray = ByteArray(0)

    fun audioDspSet(blob: ByteArray, at2: Int): ByteArray {
        val out = blob.copyOf()
        if (out.size > 2) out[2] = at2.toByte()
        return out
    }

    fun tapPrepare(): ByteArray = byteArrayOf(0x02)

    fun tapPoint(x: Float, y: Float): ByteArray = floatLE(x) + floatLE(y) + ByteArray(12)

    fun tapHint(): ByteArray = byteArrayOf(0x08)

    fun tapCommit(x: Float, y: Float): ByteArray =
        byteArrayOf(0x00, 0x02, 0x01, 0x00) + floatLE(x) + floatLE(y) + ByteArray(8)

    const val GIMBAL_STICK_CENTER = 1024
    const val GIMBAL_STICK_TRAVEL = 550
    const val GIMBAL_STICK_MIN = 474
    const val GIMBAL_STICK_MAX = 1574
    const val GIMBAL_STICK_DEADZONE = 0.08f

    /** `x` −1…1 left…right → pan (axis1). `y` −1…1 down…up → tilt (axis0). */
    fun gimbalAxis(normalized: Float): Int {
        val n = normalized.coerceIn(-1f, 1f)
        if (kotlin.math.abs(n) < GIMBAL_STICK_DEADZONE) return GIMBAL_STICK_CENTER
        return (GIMBAL_STICK_CENTER + n * GIMBAL_STICK_TRAVEL)
            .toInt()
            .coerceIn(GIMBAL_STICK_MIN, GIMBAL_STICK_MAX)
    }

    fun gimbalAxes(x: Float, y: Float, invertPan: Boolean = false): Pair<Int, Int> =
        gimbalAxis(y) to gimbalAxis(if (invertPan) -x else x)

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

    fun fpsIndex(fps: Int): Int? =
        when (fps) {
            24 -> 1
            25 -> 2
            30 -> 3
            48 -> 4
            50 -> 5
            60 -> 6
            else -> null
        }

    fun fpsFromIndex(index: Int): Int? =
        when (index) {
            1 -> 24
            2 -> 25
            3 -> 30
            4 -> 48
            5 -> 50
            6 -> 60
            else -> null
        }

    fun resolutionLabel(code: Int): String =
        when (code) {
            RES_1080 -> "1080p"
            RES_4K -> "4K"
            else -> "—"
        }

    fun colorLabel(mode: Int): String =
        when (mode) {
            COLOR_NORMAL -> "Normal"
            COLOR_HDR -> "HDR"
            COLOR_DLOG -> "D-Log"
            COLOR_DLOG2 -> "D-Log2"
            else -> "—"
        }

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

    /**
     * Native base ISO for the operator's current color / transfer.
     * Decoration only — the chip list stays `camcap_iso`.
     * D-Log = 400, D-Log2 = 1600. Rec.709 / HLG / unknown: none.
     * Uses `cam_image_effect` `@2`, not a tele hop SET.
     */
    fun baseIsoLabel(colorMode: Int): String? =
        when (colorMode) {
            COLOR_DLOG -> "400"
            COLOR_DLOG2 -> "1600"
            else -> null
        }

    /** OpenZCine drum: `" ★"` after the native base, same color as the number. */
    fun isoChipLabel(label: String, colorMode: Int): String {
        val base = baseIsoLabel(colorMode)
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

    fun parseIsoIndices(value: ByteArray): List<Int> {
        if (value.size < 5 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 2 || 3 + inner > value.size) return emptyList()
        val body = value.copyOfRange(3, 3 + inner)
        val count = body[1].toInt() and 0xFF
        if (body[0].toInt() != 0 || count < 1 || body.size < 2 + count) return emptyList()
        return body.copyOfRange(2, 2 + count).map { it.toInt() and 0xFF }
    }

    fun shutterWheelDenoms(available: List<Int>, current: Int): List<Int> {
        if (available.isNotEmpty()) return available
        return if (current in 1..16_000) listOf(current) else emptyList()
    }

    val kelvinPresets = listOf(2000, 3200, 4000, 5000, 5600, 6500, 8000, 10000)

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
