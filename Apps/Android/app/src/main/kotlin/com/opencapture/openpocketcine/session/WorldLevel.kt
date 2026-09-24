package com.opencapture.openpocketcine.session

import java.util.Locale
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.asin
import kotlin.math.atan2
import kotlin.math.sqrt

/**
 * Camera attitude against gravity from the `0x04/0x05` push. Mirrors iOS core
 * `WorldLevel.swift`: `@24…@39` float32 LE `x, w, y, z` of a unit quaternion
 * mapping world to camera (camera x forward, y up; gravity −y). Fit on 1,014
 * captured frames: tilt matches `−@20` (p50 0.02°). Roll sign is unconfirmed
 * on a rolled handle.
 */
object WorldLevel {
    data class Quat(val w: Double, val x: Double, val y: Double, val z: Double) {
        operator fun times(r: Quat) = Quat(
            w * r.w - x * r.x - y * r.y - z * r.z,
            w * r.x + x * r.w + y * r.z - z * r.y,
            w * r.y - x * r.z + y * r.w + z * r.x,
            w * r.z + x * r.y - y * r.x + z * r.w,
        )

        fun rotate(vx: Double, vy: Double, vz: Double): Vec {
            val r = this * Quat(0.0, vx, vy, vz) * Quat(w, -x, -y, -z)
            return Vec(r.x, r.y, r.z)
        }
    }

    data class Vec(val x: Double, val y: Double, val z: Double)

    fun attitude(payload: ByteArray): Quat? {
        if (payload.size < 40) return null
        fun f32(o: Int): Double {
            val bits = (payload[o].toInt() and 0xFF) or ((payload[o + 1].toInt() and 0xFF) shl 8) or
                ((payload[o + 2].toInt() and 0xFF) shl 16) or ((payload[o + 3].toInt() and 0xFF) shl 24)
            return Float.fromBits(bits).toDouble()
        }
        val q = Quat(f32(28), f32(24), f32(32), f32(36))
        val norm = sqrt(q.w * q.w + q.x * q.x + q.y * q.y + q.z * q.z)
        if (!norm.isFinite() || abs(norm - 1) > 1e-3) return null
        return q
    }

    /** Unit gravity (down) in the camera frame. */
    fun gravity(q: Quat): Vec = q.rotate(0.0, -1.0, 0.0)

    internal fun deg(r: Double) = r * 180 / PI
    internal fun asinDeg(v: Double) = deg(asin(v.coerceIn(-1.0, 1.0)))
}

sealed interface LevelMode {
    data object Unavailable : LevelMode
    /** Picture roll and look-up tilt from the horizon, degrees. */
    data class Gauges(val rollDeg: Double, val tiltDeg: Double) : LevelMode
    /** Lens offset from plumb in picture axes (x right, y up), degrees. */
    data class Bubble(val xDeg: Double, val yDeg: Double) : LevelMode
}

/**
 * Smoothed world level for the LEVEL assist and the Double-tap Level snap.
 * Written on the session thread, read by the overlay on main: synchronized.
 */
class LevelReading {
    private var g: WorldLevel.Vec? = null
    private var acceptedAt = Double.NEGATIVE_INFINITY
    private var bubble = false

    @Synchronized
    fun ingest(payload: ByteArray, now: Double) {
        val q = WorldLevel.attitude(payload) ?: return
        if (!now.isFinite()) return
        val sample = WorldLevel.gravity(q)
        // After a gap, start over: pre-gap gravity must not bleed into a new pose.
        if (now - acceptedAt > STALE_AFTER) {
            g = null
            bubble = false
        }
        val prev = g
        g = if (prev == null) sample else {
            if (now - acceptedAt < MIN_INTERVAL) return
            val x = prev.x * (1 - SMOOTHING) + sample.x * SMOOTHING
            val y = prev.y * (1 - SMOOTHING) + sample.y * SMOOTHING
            val z = prev.z * (1 - SMOOTHING) + sample.z * SMOOTHING
            val n = sqrt(x * x + y * y + z * z)
            if (n > 0) WorldLevel.Vec(x / n, y / n, z / n) else sample
        }
        acceptedAt = now
        val tilt = abs(tilt(g!!))
        bubble = if (bubble) tilt >= BUBBLE_EXIT_DEG else tilt >= BUBBLE_ENTER_DEG
    }

    /** Smoothed look-up tilt, or null when stale. */
    @Synchronized
    fun tiltDeg(now: Double): Double? {
        val g = g ?: return null
        return if (now - acceptedAt <= STALE_AFTER) tilt(g) else null
    }

    /**
     * Signed pitch-plane angle, look-up positive, unfolded past ±90° (lens past
     * nadir reads −92, not −88). The snap plans and judges on this; null when stale.
     */
    @Synchronized
    fun pitchDeg(now: Double): Double? {
        val g = g ?: return null
        return if (now - acceptedAt <= STALE_AFTER) WorldLevel.deg(atan2(-g.x, -g.y)) else null
    }

    /** [viewFlip]: TT180 XOR MIRROR (picture-relative, like the stick). */
    @Synchronized
    fun mode(now: Double, viewFlip: Boolean): LevelMode {
        val g = g ?: return LevelMode.Unavailable
        if (now - acceptedAt > STALE_AFTER) return LevelMode.Unavailable
        val side = if (viewFlip) -1.0 else 1.0
        return if (bubble) {
            LevelMode.Bubble(side * -WorldLevel.asinDeg(g.z), -WorldLevel.asinDeg(g.y))
        } else {
            LevelMode.Gauges(side * WorldLevel.deg(atan2(g.z, -g.y)), tilt(g))
        }
    }

    private fun tilt(g: WorldLevel.Vec) = -WorldLevel.asinDeg(g.x)

    companion object {
        const val STALE_AFTER = 1.0
        const val MIN_INTERVAL = 0.08
        const val SMOOTHING = 0.3
        const val BUBBLE_ENTER_DEG = 65.0
        const val BUBBLE_EXIT_DEG = 60.0
    }
}

enum class WorldLevelTarget(val tiltDeg: Double, val successNote: String) {
    HORIZON(0.0, "Leveled to world"),
    PLUMB_DOWN(-90.0, "Leveled top-down"),
    PLUMB_UP(90.0, "Leveled straight up"),
    ;

    companion object {
        fun nearest(tiltDeg: Double): WorldLevelTarget = when {
            abs(tiltDeg) < 45 -> HORIZON
            tiltDeg < 0 -> PLUMB_DOWN
            else -> PLUMB_UP
        }
    }
}

sealed interface SnapOutcome {
    data object Pending : SnapOutcome
    data object Arrived : SnapOutcome
    /** Judged more than a stale window past the deadline (attitude stopped): drop silently. */
    data object Expired : SnapOutcome
    /** Remaining error to 0.1°, or null when the reading went stale. */
    data class Failed(val errorDeg: Double?) : SnapOutcome
}

/** One-shot `0x04/0x14` move to the nearest world target. Roll is not commanded. */
data class WorldLevelSnap(val target: WorldLevelTarget, val deadline: Double) {
    /** [tiltDeg] is the unfolded [LevelReading.pitchDeg]. */
    fun evaluate(tiltDeg: Double?, now: Double): SnapOutcome {
        if (now - deadline > LevelReading.STALE_AFTER) return SnapOutcome.Expired
        tiltDeg ?: return SnapOutcome.Failed(null)
        val error = abs(tiltDeg - target.tiltDeg)
        if (error <= TOLERANCE_DEG) return SnapOutcome.Arrived
        return if (now >= deadline) SnapOutcome.Failed(roundAway(error * 10) / 10) else SnapOutcome.Pending
    }

    companion object {
        const val TOLERANCE_DEG = 0.5
        const val SETTLE_GRACE = 1.5
        const val NO_LEVEL_DATA = "No level data"
        const val FPV_ROLL_NOTE = " · roll follows the handle in FPV"
        /** No live native pitch, or yaw in the unreachable pan gap. */
        const val UNREACHABLE_NOTE = "Couldn't level from this pose"

        /** 0.1 s per 2°, clamped 0.5…3.0 s on the 0.1 s wire grid. */
        fun duration(distanceDeg: Double): Double = (roundAway(abs(distanceDeg) * 0.5) / 10).coerceIn(0.5, 3.0)

        /** Native pitch moves opposite to look-up tilt (`native = 180 − tilt`). */
        fun plan(tiltDeg: Double, pose: GimbalWaypoint, now: Double): Pair<WorldLevelSnap, ByteArray>? {
            val native = pose.nativePitchDeg ?: return null
            if (!tiltDeg.isFinite() || !native.isFinite()) return null
            val target = WorldLevelTarget.nearest(tiltDeg)
            val error = target.tiltDeg - tiltDeg
            var goal = native - error
            while (goal > 180) goal -= 360
            while (goal < -180) goal += 360
            val duration = duration(error)
            val payload = CameraCommands.gimbalTimedTarget(pose.yawDeg, roundAway(goal * 10) / 10, duration)
                ?: return null
            return WorldLevelSnap(target, now + duration + SETTLE_GRACE) to payload
        }

        fun failureNote(errorDeg: Double?): String =
            if (errorDeg == null) NO_LEVEL_DATA else String.format(Locale.ROOT, "Couldn't level: %.1f° off", errorDeg)
    }
}

/** Swift `.rounded()`: half away from zero (Kotlin `round` is half-even). */
internal fun roundAway(value: Double): Double = Math.copySign(kotlin.math.floor(abs(value) + 0.5), value)
