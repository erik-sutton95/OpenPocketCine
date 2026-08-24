package com.opencapture.openpocketcine.session

/**
 * Operator HUD copy for control replies. Matches iOS `ControlHud` /
 * `CameraReply` / `Duml.shouldHoldReply`. Probe GET names stay in the journal.
 */
object ControlHud {
    const val TOAST_HOLD_SECONDS = 2.0
    const val TOAST_OPACITY = 0.72
    const val TOAST_OFFSET_FROM_FEED_TOP = 22.0

    /** Chip / pinch / color drum while rolling in D-Log2. No opcode names. */
    const val RECORDING_COLOR_LOCK_NOTE =
        "Can't change color while recording — D-Log2 can't zoom"

    /** SET / GET timeout copy. iOS `requestCamera` and `fireCamera` pass announce=false. */
    fun timeoutNote(name: String, announce: Boolean): String? =
        if (announce) "$name timed out" else null

    /**
     * Center Y for the control toast. Parks under a mounted top bar when that
     * bar overlays the feed (DISP 1). Falls back to the feed edge when the bar
     * is off or already sits above the picture (DISP 2 / portrait).
     */
    fun toastCenterY(feedMinY: Double, chromeBottomY: Double? = null): Double {
        val edge =
            if (chromeBottomY != null && chromeBottomY > feedMinY + 0.5) chromeBottomY
            else feedMinY
        return edge + TOAST_OFFSET_FROM_FEED_TOP
    }
}

/** Reply oracle from Osmosis camera-control (payload first byte). */
sealed class CameraReply {
    data object Ok : CameraReply()
    data object WrongState : CameraReply()
    data object BadParameter : CameraReply()
    data object Unsupported : CameraReply()
    data class Other(val code: Int) : CameraReply()

    val isSuccess: Boolean get() = this is Ok

    val message: String
        get() =
            when (this) {
                Ok -> "ok"
                WrongState -> "camera rejected that in this mode"
                BadParameter -> "camera rejected that value"
                Unsupported -> "camera does not support that command"
                is Other -> "camera reply 0x%02X".format(code)
            }

    companion object {
        fun parse(payload: ByteArray): CameraReply {
            val b = payload.firstOrNull()?.toInt()?.and(0xFF) ?: return Other(0xFF)
            return when (b) {
                0x00 -> Ok
                0xD9 -> WrongState
                0xDF, 0xE3, 0xEE -> BadParameter
                0xE0 -> Unsupported
                else -> Other(b)
            }
        }
    }
}

/**
 * Pairing / Wi-Fi / live-control replies that can land before the waiter.
 * Mirrors `Duml.shouldHoldReply` plus Android-only opcodes the shell still waits on.
 */
object DumlHold {
    fun isLiveCameraControl(set: Int, cmd: Int): Boolean {
        if ((set and 0xFF) != 0x02) return false
        return when (cmd and 0xFF) {
            0x01, 0x02, 0x0C, 0x1E, 0x18, 0x22, 0x24, 0x28, 0x2A, 0x2C, 0x2E,
            0x30, 0x32, 0x42, 0x68, 0x8E, 0x9F, 0xA0, 0xA5, 0xA6, 0xB8, 0xBF, 0xE1,
            -> true
            else -> false
        }
    }

    fun shouldHoldReply(set: Int, cmd: Int): Boolean {
        val s = set and 0xFF
        val c = cmd and 0xFF
        if (s == 0x07 && (c == 0x45 || c == 0x46 || c == 0x07 || c == 0x0E)) return true
        if (s == 0x53 && c == 0x10) return true
        if (isLiveCameraControl(s, c)) return true
        return when ((s shl 8) or c) {
            0x0209, 0x044C, 0x0026, 0x0028, 0x09A8 -> true
            else -> false
        }
    }
}
