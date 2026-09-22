package com.opencapture.openpocketcine.session

import kotlin.math.abs

/** Initial preparation is separate from the timed linear tracking samples. */
internal sealed interface NativeProgramZoomCommand {
    data class Position(val factor: Double) : NativeProgramZoomCommand
    data class Track(val factor: Double) : NativeProgramZoomCommand
    data object Stop : NativeProgramZoomCommand

    val payload: ByteArray
        get() = when (this) {
            is Position -> CameraCommands.zoomLens(CamFov.lensPosition(factor))
            is Track -> CameraCommands.zoomLens(CamFov.lensPosition(factor))
            Stop -> CameraCommands.zoomStop()
        }
}

internal data class NativeProgramZoomDemand(val command: NativeProgramZoomCommand, val destination: Double,
    val failureReason: String? = null, val nextChange: Double = Double.POSITIVE_INFINITY)

/** Linear factor throughout the full leg, on the existing transport scheduler. */
internal object NativeProgramZoom {
    const val INTERVAL = 0.02

    fun demand(from: Double, to: Double, duration: Double, elapsed: Double): NativeProgramZoomDemand {
        if (!from.isFinite() || !to.isFinite() || !duration.isFinite() || !elapsed.isFinite() ||
            from < 1.0 || to < 1.0 || duration <= 0 || elapsed < 0) {
            return NativeProgramZoomDemand(NativeProgramZoomCommand.Stop, to, failureReason = "Invalid zoom movement")
        }
        if (abs(from - to) <= 1e-6) return NativeProgramZoomDemand(NativeProgramZoomCommand.Stop, to)
        val fraction = minOf(1.0, elapsed / duration)
        return NativeProgramZoomDemand(NativeProgramZoomCommand.Track(from + (to - from) * fraction), to,
            nextChange = if (elapsed < duration) duration - elapsed else Double.POSITIVE_INFINITY)
    }
}
