package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.ln

/** Camera-owned continuous zoom; positions are used only to prepare the take. */
internal sealed interface NativeProgramZoomCommand {
    data class Position(val factor: Double) : NativeProgramZoomCommand
    data class Rate(val speed: Int, val increasing: Boolean) : NativeProgramZoomCommand
    data object Stop : NativeProgramZoomCommand

    val payload: ByteArray
        get() = when (this) {
            is Position -> CameraCommands.zoomLens(CamFov.lensPosition(factor))
            is Rate -> CameraCommands.zoomRate(speed, increasing)
            Stop -> CameraCommands.zoomStop()
        }
}

internal data class NativeProgramZoomDemand(val command: NativeProgramZoomCommand, val destination: Double,
    val failureReason: String? = null, val nextChange: Double = Double.POSITIVE_INFINITY)

/** One native gear per moving leg avoids visible speed jumps; same schedule as the portable core. */
internal object NativeProgramZoom {
    const val SLOWEST_LOG_RATE = 0.208
    const val SLOWEST_SPEED = 72
    const val FASTEST_SPEED = 78
    const val INTERVAL = 0.05

    fun minimumDuration(from: Double, to: Double): Double {
        if (!from.isFinite() || !to.isFinite() || from < 1.0 || to < 1.0) return Double.POSITIVE_INFINITY
        return abs(ln(to / from)) / (7 * SLOWEST_LOG_RATE)
    }

    fun timingFailure(from: Double, to: Double, duration: Double): String? {
        if (!(abs(from - to) > 1e-6)) return null
        if (duration + 1e-9 < minimumDuration(from, to)) {
            return "Increase the move duration for this zoom range"
        }
        if (abs(ln(to / from)) / SLOWEST_LOG_RATE < INTERVAL - 1e-9 || duration < INTERVAL - 1e-9) {
            return "Increase the zoom difference between points"
        }
        return null
    }

    fun demand(from: Double, to: Double, duration: Double, elapsed: Double): NativeProgramZoomDemand {
        val stopped = NativeProgramZoomDemand(NativeProgramZoomCommand.Stop, to,
            failureReason = timingFailure(from, to, duration), nextChange = maxOf(0.0, duration - elapsed))
        if (!from.isFinite() || !to.isFinite() || !duration.isFinite() || !elapsed.isFinite() ||
            from < 1.0 || to < 1.0 || duration <= 0 || elapsed < 0 || elapsed >= duration ||
            abs(from - to) <= 1e-6 || stopped.failureReason != null) return stopped
        val distance = abs(ln(to / from))
        // Select the slowest gear that can reach the waypoint by its deadline.
        // Waiting preserves the gimbal duration without a mid-zoom speed change.
        val gear = ceil(distance / (SLOWEST_LOG_RATE * duration) - 1e-9).toInt().coerceIn(1, 7)
        val movingDuration = distance / (gear * SLOWEST_LOG_RATE)
        if (movingDuration < INTERVAL - 1e-9) {
            return stopped.copy(failureReason = "Increase the zoom difference between points")
        }
        val delay = maxOf(0.0, duration - movingDuration)
        if (elapsed < delay - 1e-9) return stopped.copy(nextChange = delay - elapsed)
        return NativeProgramZoomDemand(NativeProgramZoomCommand.Rate(71 + gear, to > from), to,
            nextChange = duration - elapsed)
    }
}
