package com.opencapture.openpocketcine.feed

import com.opencapture.opencine.dji.DjiScopeExposureCeiling as ScopeExposureCeiling
import com.opencapture.opencine.media.LiveColorScience
import com.opencapture.opencine.media.MonitorTransfer


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
        previous: com.opencapture.opencine.media.ScopeTrafficLightsReading? = null,
        luma: IntArray? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): com.opencapture.opencine.media.ScopeTrafficLightsReading =
        com.opencapture.opencine.media.ScopeTrafficLights.reading(red, green, blue, transfer, threshold, previous, luma, ceiling)

    fun edgeEnergy(bins: IntArray, from: Int, to: Int): Double =
        com.opencapture.opencine.media.ScopeTrafficLights.edgeEnergy(bins, from, to)

    fun latched(now: Boolean, was: Boolean, energy: Double, threshold: Double): Boolean =
        com.opencapture.opencine.media.ScopeTrafficLights.latched(now, was, energy, threshold)

    fun balance(level: Double, midLevel: Double): Double =
        com.opencapture.opencine.media.ScopeTrafficLights.balance(level, midLevel)

}
