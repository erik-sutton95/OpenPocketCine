package com.opencapture.openpocketcine.session

/**
 * Action 6 aperture strategy: `0x02/0x8E` pid `0x0044`, one byte (core `ApertureStrategy`).
 * Survey 2026-09-21, handbook `devices/action-6/settings`. Raw ids stay `Int` like the
 * other HUD fields; `-1` is unknown.
 */
object ApertureStrategy {
    /** SuperNight "Large Aperture". */
    const val F2 = 0x00
    const val F26 = 0x01
    const val F28 = 0x02
    const val STARBURST = 0x03
    const val AUTO = 0x04

    const val STATE_KEY = "cam_aperture_ctrl_strategy"
    const val CAPABILITY_KEY = "camcap_aperture_ctrl_strategy"

    fun label(raw: Int): String? =
        when (raw) {
            F2 -> "f/2.0"
            F26 -> "f/2.6"
            F28 -> "f/2.8"
            STARBURST -> "Starburst f/4"
            AUTO -> "Auto"
            else -> null
        }

    /** `cam_aperture_ctrl_strategy` `01 00 00 <strategy>`. */
    fun parseState(value: ByteArray): Int? {
        if (value.size < 4 || value[0] != 0x01.toByte()) return null
        return (value[3].toInt() and 0xFF).takeIf { label(it) != null }
    }

    /** `camcap_aperture_ctrl_strategy` `01 <len:u16-LE> <count> <ids…>`. Bytes past `count` are not choices. */
    fun parseCapability(value: ByteArray): List<Int> {
        if (value.size < 5 || value[0] != 0x01.toByte()) return emptyList()
        val inner = (value[1].toInt() and 0xFF) or ((value[2].toInt() and 0xFF) shl 8)
        if (inner < 2 || 3 + inner > value.size) return emptyList()
        val count = value[3].toInt() and 0xFF
        if (count < 1 || 1 + count > inner) return emptyList()
        return value.copyOfRange(4, 4 + count).map { it.toInt() and 0xFF }.filter { label(it) != null }
    }

    /** Captured sets, used until the capability push lands. */
    fun fallback(expoMode: Int, shootingMode: Int): List<Int> =
        when {
            shootingMode == CameraCommands.SHOOT_SUPER_NIGHT -> listOf(F2, F28, STARBURST)
            expoMode == CameraCommands.EXPO_MANUAL -> listOf(F26, F28, STARBURST)
            else -> listOf(AUTO, F28, STARBURST)
        }

    fun choices(status: CameraStatus): List<Int> =
        status.availableApertureStrategies.ifEmpty { fallback(status.expoMode, status.shootingMode) }

    /** Mechanical iris, `cam_expo_param` u16-LE `@13` in hundredths (`290` = f/2.9). */
    fun irisHundredths(expoParam: ByteArray): Int? {
        if (expoParam.size < 15) return null
        val raw = (expoParam[13].toInt() and 0xFF) or ((expoParam[14].toInt() and 0xFF) shl 8)
        return raw.takeIf { it in 100..2_200 }
    }

    fun fNumberLabel(hundredths: Int): String = "f/%.1f".format(java.util.Locale.US, hundredths / 100.0)

    /** Tile value: live iris, else the requested strategy, else a dash. */
    fun tileValue(status: CameraStatus): String =
        when {
            status.irisHundredths > 0 -> fNumberLabel(status.irisHundredths)
            else -> label(status.apertureStrategy) ?: "—"
        }
}
