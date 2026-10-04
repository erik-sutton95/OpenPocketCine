package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.media.MonitorTransfer.Companion as MonitorTransferCompanion

import com.opencapture.opencine.dji.CameraCommands

typealias MonitorTransfer = com.opencapture.opencine.media.MonitorTransfer
typealias ScopeChannelLight = com.opencapture.opencine.media.ScopeChannelLight
typealias ScopeTrafficLightsReading = com.opencapture.opencine.media.ScopeTrafficLightsReading
typealias LiveColorScience = com.opencapture.opencine.media.LiveColorScience
typealias Hlg = com.opencapture.opencine.media.Hlg
typealias DLog = com.opencapture.opencine.media.DLog
typealias DLog2 = com.opencapture.opencine.media.DLog2

/** Raw colour identifiers stay in the source adapter; the renderer receives a neutral curve. */
val MonitorTransfer.colorMode: Int
    get() = when (this) {
        MonitorTransfer.REC709 -> CameraCommands.COLOR_NORMAL
        MonitorTransfer.HDR -> CameraCommands.COLOR_HDR
        MonitorTransfer.DLOG -> CameraCommands.COLOR_DLOG
        MonitorTransfer.DLOG2 -> CameraCommands.COLOR_DLOG2
        MonitorTransfer.DLOGM -> MonitorTransfer.COLOR_DLOG_M
        MonitorTransfer.ILOG -> error("I-Log has no DJI wire color identifier")
    }
val MonitorTransferCompanion.COLOR_DLOG_M: Int get() = 0x00
fun MonitorTransferCompanion.fromColorMode(code: Int): MonitorTransfer = when (code) {
    CameraCommands.COLOR_HDR -> MonitorTransfer.HDR
    CameraCommands.COLOR_DLOG -> MonitorTransfer.DLOG
    COLOR_DLOG_M -> MonitorTransfer.DLOGM
    CameraCommands.COLOR_DLOG2 -> MonitorTransfer.DLOG2
    else -> MonitorTransfer.REC709
}
fun MonitorTransferCompanion.inferred(minByte: Int, maxByte: Int, fallback: MonitorTransfer): MonitorTransfer {
    if (fallback != MonitorTransfer.REC709) return fallback
    if (minByte in 12..22 && maxByte in 180..252) return MonitorTransfer.DLOG2
    if (minByte in 20..30 && maxByte in 160..240) return MonitorTransfer.DLOG
    return fallback
}

/** Supplies the source calibration defaults while common owners retain every scope calculation. */
object ScopeAnchors {
    fun make(transfer: MonitorTransfer, iso: Int? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED
    ): com.opencapture.opencine.media.ScopeAnchors =
        com.opencapture.opencine.media.ScopeAnchors.make(transfer, iso, ceiling)
}

object ScopeDisplayScale {
    const val CRUSH_LEVEL = com.opencapture.opencine.media.ScopeDisplayScale.CRUSH_LEVEL
    const val CLIP_LEVEL = com.opencapture.opencine.media.ScopeDisplayScale.CLIP_LEVEL
    fun waveformLevel(c: Double, transfer: MonitorTransfer, iso: Int? = null, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): Double =
        com.opencapture.opencine.media.ScopeDisplayScale.waveformLevel(c, transfer, iso, ceiling)

    fun level(scaleIRE: Double): Double =
        com.opencapture.opencine.media.ScopeDisplayScale.level(scaleIRE)

    fun monitorPercent(
        c: Double,
        transfer: MonitorTransfer,
        iso: Int? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): Double =
        com.opencapture.opencine.media.ScopeDisplayScale.monitorPercent(c, transfer, iso, ceiling)

    fun signalNative(
        monitorPercent: Double,
        transfer: MonitorTransfer,
        iso: Int? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): Double =
        com.opencapture.opencine.media.ScopeDisplayScale.signalNative(monitorPercent, transfer, iso, ceiling)

}

object WaveformIre {
    fun ire(encoded: Double, transfer: MonitorTransfer, iso: Int? = null, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): Double =
        com.opencapture.opencine.media.WaveformIre.ire(encoded, transfer, iso, ceiling)

    fun remapHistogram(
        bins: IntArray,
        transfer: MonitorTransfer,
        iso: Int? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): IntArray =
        com.opencapture.opencine.media.WaveformIre.remapHistogram(bins, transfer, iso, ceiling)

    fun levelTable(transfer: MonitorTransfer, iso: Int? = null, ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED): FloatArray =
        com.opencapture.opencine.media.WaveformIre.levelTable(transfer, iso, ceiling)

    fun middleGrayIRE(transfer: MonitorTransfer): Double =
        com.opencapture.opencine.media.WaveformIre.middleGrayIRE(transfer)

}

object ScopeTrafficLights {
    const val DEFAULT_THRESHOLD = com.opencapture.opencine.media.ScopeTrafficLights.DEFAULT_THRESHOLD
    const val HOLD_RATIO = com.opencapture.opencine.media.ScopeTrafficLights.HOLD_RATIO
    fun reading(
        red: IntArray,
        green: IntArray,
        blue: IntArray,
        transfer: MonitorTransfer,
        threshold: Double = DEFAULT_THRESHOLD,
        previous: ScopeTrafficLightsReading? = null,
        luma: IntArray? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): ScopeTrafficLightsReading =
        com.opencapture.opencine.media.ScopeTrafficLights.reading(red, green, blue, transfer, threshold, previous, luma, ceiling)

    fun edgeEnergy(bins: IntArray, from: Int, to: Int): Double =
        com.opencapture.opencine.media.ScopeTrafficLights.edgeEnergy(bins, from, to)

    fun latched(now: Boolean, was: Boolean, energy: Double, threshold: Double): Boolean =
        com.opencapture.opencine.media.ScopeTrafficLights.latched(now, was, energy, threshold)

    fun balance(level: Double, midLevel: Double): Double =
        com.opencapture.opencine.media.ScopeTrafficLights.balance(level, midLevel)

}
