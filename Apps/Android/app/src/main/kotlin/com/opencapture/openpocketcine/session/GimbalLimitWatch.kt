package com.opencapture.openpocketcine.session

/** Rising-edge pulse when a commanded axis moves then stops at a mechanical end. */
data class GimbalLimitContact(val pan: Boolean = false, val tilt: Boolean = false) {
    val isEmpty: Boolean
        get() = !pan && !tilt

    fun union(other: GimbalLimitContact) =
        GimbalLimitContact(pan = pan || other.pan, tilt = tilt || other.tilt)
}

class GimbalLimitWatch {
    data class Axis(
        val active: Boolean = false,
        val sign: Double = 0.0,
        val lastAttitude: Int? = null,
        val lastMovedAt: Double? = null,
        val seenMotion: Boolean = false,
        val contacting: Boolean = false,
    )

    var lastPanSign: Double = 0.0
        private set

    var lastTiltSign: Double = 0.0
        private set

    private var pan = Axis()
    private var tilt = Axis()

    fun reset() {
        pan = Axis()
        tilt = Axis()
        lastPanSign = 0.0
        lastTiltSign = 0.0
    }

    fun tick(
        x: Double,
        y: Double,
        yawTenthDeg: Int?,
        pitchTenthDeg: Int?,
        now: Double,
        settling180: Boolean,
    ): GimbalLimitContact {
        val (nextPan, panHit) = tickAxis(pan, if (settling180) 0.0 else x, yawTenthDeg, now)
        pan = nextPan
        if (panHit) lastPanSign = pan.sign
        val (nextTilt, tiltHit) = tickAxis(tilt, y, pitchTenthDeg, now)
        tilt = nextTilt
        if (tiltHit) lastTiltSign = tilt.sign
        return GimbalLimitContact(pan = panHit, tilt = tiltHit)
    }

    private fun tickAxis(
        axis: Axis,
        command: Double,
        attitude: Int?,
        now: Double,
    ): Pair<Axis, Boolean> {
        val curved = CameraCommands.gimbalAnalogCurve(command.toFloat()).toDouble()
        if (curved == 0.0) return Axis() to false
        val sign = if (curved > 0.0) 1.0 else -1.0
        if (!axis.active || axis.sign != sign) {
            return Axis(
                active = true,
                sign = sign,
                lastAttitude = attitude,
                lastMovedAt = null,
                seenMotion = false,
                contacting = false,
            ) to false
        }
        if (attitude == null) return axis to false
        val last = axis.lastAttitude
        if (last != null && kotlin.math.abs(attitude - last) > STALL_TENTH_DEG) {
            return axis.copy(
                lastMovedAt = now,
                lastAttitude = attitude,
                seenMotion = true,
                contacting = false,
            ) to false
        }
        val advanced = axis.copy(lastAttitude = attitude)
        if (!advanced.seenMotion) return advanced to false
        val movedAt = advanced.lastMovedAt ?: return advanced to false
        if (now - movedAt < STALL_SECONDS) return advanced to false
        if (advanced.contacting) return advanced to false
        return advanced.copy(contacting = true) to true
    }

    companion object {
        const val STALL_SECONDS = 0.35
        const val STALL_TENTH_DEG = 3
    }
}
