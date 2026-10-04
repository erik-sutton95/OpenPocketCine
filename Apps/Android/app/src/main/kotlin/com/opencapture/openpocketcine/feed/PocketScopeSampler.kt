package com.opencapture.openpocketcine.feed

typealias ScopePoint = com.opencapture.opencine.media.ScopePoint
typealias ScopeSamples = com.opencapture.opencine.media.ScopeSamples
typealias ScopeHistogramDisplay = com.opencapture.opencine.media.ScopeHistogramDisplay
typealias ScopeAssistBundle = com.opencapture.opencine.media.ScopeAssistBundle
typealias ScopeChroma = com.opencapture.opencine.media.ScopeChroma
typealias VectorscopeRaster = com.opencapture.opencine.media.VectorscopeRaster

object PocketScopeSampler {
    const val MAX_WIDTH = com.opencapture.opencine.media.ScopeSampler.MAX_WIDTH
    const val POINT_STRIDE = com.opencapture.opencine.media.ScopeSampler.POINT_STRIDE
    const val BASE_MIN_INTERVAL_NS = com.opencapture.opencine.media.ScopeSampler.BASE_MIN_INTERVAL_NS
    const val DENSE_MIN_INTERVAL_NS = com.opencapture.opencine.media.ScopeSampler.DENSE_MIN_INTERVAL_NS
    const val DENSE_ASSIST_THRESHOLD = com.opencapture.opencine.media.ScopeSampler.DENSE_ASSIST_THRESHOLD
    const val TRAIL_DECAY = com.opencapture.opencine.media.ScopeSampler.TRAIL_DECAY
    fun tapSize(srcW: Int, srcH: Int, maxWidth: Int = MAX_WIDTH): Pair<Int, Int> =
        com.opencapture.opencine.media.ScopeSampler.tapSize(srcW, srcH, maxWidth)

    fun minIntervalNs(activeScopeCount: Int, thermalMultiplier: Double = 1.0): Long =
        com.opencapture.opencine.media.ScopeSampler.minIntervalNs(activeScopeCount, thermalMultiplier)

    fun chromeSampleIntervalNs(
        activeScopeCount: Int, thermalMultiplier: Double, backdropDemand: Boolean,
        backdropMinimumIntervalNs: Long = BASE_MIN_INTERVAL_NS, inspectorMinimumIntervalNs: Long = 200_000_000L,
    ): Long =
        com.opencapture.opencine.media.ScopeSampler.chromeSampleIntervalNs(activeScopeCount, thermalMultiplier, backdropDemand, backdropMinimumIntervalNs, inspectorMinimumIntervalNs)

    fun thermalMultiplier(androidThermalStatus: Int): Double =
        com.opencapture.opencine.media.ScopeSampler.thermalMultiplier(androidThermalStatus)

    fun minMaxRGB(bytes: ByteArray): Pair<Int, Int> =
        com.opencapture.opencine.media.ScopeSampler.minMaxRGB(bytes)

    fun sample(
        bytes: ByteArray,
        width: Int,
        height: Int,
        bytesPerRow: Int,
        transfer: MonitorTransfer,
        includePoints: Boolean,
        includeVectorPoints: Boolean = false,
        look: com.opencapture.opencine.media.MonitorLUTCube? = null,
        trafficThreshold: Double = ScopeTrafficLights.DEFAULT_THRESHOLD,
        previous: ScopeAssistBundle = ScopeAssistBundle.EMPTY,
        ceiling: com.opencapture.opencine.media.ScopeExposureCeiling = ScopeExposureCeiling.UNOBSERVED,
        iso: Int? = ceiling.resolvedISO(),
    ): ScopeAssistBundle =
        com.opencapture.opencine.media.ScopeSampler.sample(bytes, width, height, bytesPerRow, transfer, includePoints, includeVectorPoints, look, trafficThreshold, previous, ceiling, iso)

    fun monitorPoints(points: List<ScopePoint>, look: com.opencapture.opencine.media.MonitorLUTCube?): List<ScopePoint> =
        com.opencapture.opencine.media.ScopeSampler.monitorPoints(points, look)

    fun histogramDisplay(
        samples: ScopeSamples,
        previous: ScopeHistogramDisplay,
        transfer: MonitorTransfer,
        iso: Int? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): ScopeHistogramDisplay =
        com.opencapture.opencine.media.ScopeSampler.histogramDisplay(samples, previous, transfer, iso, ceiling)

    fun displayChannel(
        native: IntArray,
        previous: FloatArray,
        transfer: MonitorTransfer,
        iso: Int? = null,
        ceiling: com.opencapture.opencine.media.ScopeClipSource = ScopeExposureCeiling.UNOBSERVED,
    ): FloatArray =
        com.opencapture.opencine.media.ScopeSampler.displayChannel(native, previous, transfer, iso, ceiling)

    fun boxBlur(values: FloatArray, radius: Int): FloatArray =
        com.opencapture.opencine.media.ScopeSampler.boxBlur(values, radius)

}
