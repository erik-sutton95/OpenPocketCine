package com.opencapture.openpocketcine.session

/**
 * OpenPocketViewCore `EncoderPresentPath` — Pocket screen flip / vertical mode
 * restarts the encoder with new VPS/SPS/PPS.
 */
object EncoderPresentPath {
    fun parameterSetsChanged(
        hadFormat: Boolean,
        previousCsd: ByteArray?,
        nextCsd: ByteArray?,
    ): Boolean {
        if (!hadFormat) return false
        if (previousCsd == null || nextCsd == null) return previousCsd != null || nextCsd != null
        return !previousCsd.contentEquals(nextCsd)
    }

    fun feedAspect(width: Int, height: Int, fallback: Double = 16.0 / 9.0): Double {
        if (width <= 1 || height <= 1) return fallback
        return width.toDouble() / height.toDouble()
    }

    fun isVertical(width: Int, height: Int): Boolean = width > 1 && height > 1 && height > width

    fun shouldRequestEnableAfterParameterChange(
        accessUnitHasIDR: Boolean,
        udpReceiveAlive: Boolean = false,
        secondsSinceLastEnable: Double? = null,
    ): Boolean {
        if (accessUnitHasIDR) return false
        if (udpReceiveAlive) return false
        if (secondsSinceLastEnable != null && secondsSinceLastEnable < 5.0) return false
        return true
    }
}
