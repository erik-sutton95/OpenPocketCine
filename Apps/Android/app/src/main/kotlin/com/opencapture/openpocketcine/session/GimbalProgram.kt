package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin
import kotlin.math.tan

data class GimbalWaypoint(
    val yawDeg: Double,
    val pitchDeg: Double,
    val zoom: Double,
    val nativePitchDeg: Double? = null,
) {
    companion object {
        const val PAN_MIN_DEG = -48.0
        const val PAN_MAX_DEG = 225.0
        const val GAP_MID_DEG = (PAN_MAX_DEG + PAN_MIN_DEG - 360.0) / 2
        const val TILT_MIN_DEG = -44.0
        const val TILT_MAX_DEG = 70.0

        fun unwrapYaw(rawDeg: Double): Double {
            val unwrapped = if (rawDeg < GAP_MID_DEG) rawDeg + 360.0 else rawDeg
            return unwrapped
        }

        fun from(yawTenth: Int?, pitchTenth: Int?, zoom: Double, nativePitchTenth: Int? = null): GimbalWaypoint? {
            if (yawTenth == null || pitchTenth == null) return null
            return GimbalWaypoint(
                unwrapYaw(yawTenth / 10.0),
                pitchTenth / 10.0,
                max(1.0, zoom),
                nativePitchTenth?.div(10.0),
            )
        }
    }

    fun clamped(): GimbalWaypoint =
        GimbalWaypoint(
            yawDeg.coerceIn(PAN_MIN_DEG, PAN_MAX_DEG),
            pitchDeg.coerceIn(TILT_MIN_DEG, TILT_MAX_DEG),
            zoom,
            nativePitchDeg,
        )
}

enum class GimbalWaypointSlot(val letter: String) {
    A("A"),
    B("B"),
    C("C"),
}

enum class GimbalMode(val label: String) {
    FOLLOW("Follow"),
    TILT_LOCKED("Tilt locked"),
    FPV("FPV"),
    DIRECTION_LOCK("Direction Lock"),
    ;

    companion object {
        val pickerOrder = listOf(FOLLOW, TILT_LOCKED, FPV, DIRECTION_LOCK)
    }
}

/** Refresh tilt/speed from attitude receipts, capped at one GET per second. */
class GimbalParamPoll {
    private var lastRequestAt: Long? = null

    fun shouldRequest(nowMs: Long): Boolean {
        if (lastRequestAt?.let { nowMs - it < 1_000L } == true) return false
        lastRequestAt = nowMs
        return true
    }
}

enum class GimbalSpeed(val wire: Int, val label: String) {
    FAST(0, "Fast"),
    DEFAULT(1, "Default"),
    SLOW(2, "Slow"),
    ;

    companion object {
        val pickerOrder = listOf(SLOW, DEFAULT, FAST)

        fun fromWire(value: Int): GimbalSpeed? = entries.firstOrNull { it.wire == value }
    }
}

enum class GimbalRamp(val raw: Int, val label: String, val tau: Double) {
    OFF(0, "Off", 0.0),
    SOFT(1, "Soft", 0.35),
    MEDIUM(2, "Medium", 0.18),
    ;

    companion object {
        val pickerOrder = listOf(OFF, SOFT, MEDIUM)

        fun fromRaw(value: Int): GimbalRamp = entries.firstOrNull { it.raw == value } ?: OFF
    }
}

data class GimbalProgram(
    val a: GimbalWaypoint? = null,
    val b: GimbalWaypoint? = null,
    val c: GimbalWaypoint? = null,
    val durationAB: Double = DEFAULT_DURATION,
    val durationBC: Double = DEFAULT_DURATION,
    val smoothness: Double = 0.0,
) {
    val canRun: Boolean get() = a != null && b != null

    val summary: String
        get() =
            when {
                a != null && b != null && c != null -> "A·B·C"
                a != null && b != null -> "A·B"
                a != null || b != null || c != null -> "Partial"
                else -> "Not set"
            }

    fun point(slot: GimbalWaypointSlot): GimbalWaypoint? =
        when (slot) {
            GimbalWaypointSlot.A -> a
            GimbalWaypointSlot.B -> b
            GimbalWaypointSlot.C -> c
        }

    fun withPoint(
        slot: GimbalWaypointSlot,
        point: GimbalWaypoint?,
    ): GimbalProgram {
        val next =
            when (slot) {
                GimbalWaypointSlot.A -> copy(a = point)
                GimbalWaypointSlot.B -> copy(b = point)
                GimbalWaypointSlot.C -> copy(c = point)
            }
        return if (point != null) next.seedTravelDurations() else next
    }

    fun seedTravelDurations(): GimbalProgram {
        var next = this
        if (a != null && b != null) next = next.copy(durationAB = max(durationAB, minTravelDuration(a, b)))
        if (b != null && c != null) next = next.copy(durationBC = max(durationBC, minTravelDuration(b, c)))
        return next
    }

    companion object {
        const val DURATION_STEP = 0.5
        const val MIN_DURATION = 0.5
        const val MAX_DURATION = 120.0
        const val DEFAULT_DURATION = 5.0
        val durationStops = listOf(2.0, 5.0, 10.0)

        fun snapDuration(value: Double): Double {
            val clamped = value.coerceIn(MIN_DURATION, MAX_DURATION)
            return (kotlin.math.round(clamped / DURATION_STEP) * DURATION_STEP)
        }

        fun minTravelDuration(
            from: GimbalWaypoint?,
            to: GimbalWaypoint?,
        ): Double {
            if (from == null || to == null) return DEFAULT_DURATION
            return MIN_DURATION
        }

        fun steppedDuration(value: Double, delta: Double, floor: Double): Double =
            snapDuration(max(floor, value + delta))

        fun durationLabel(value: Double): String {
            val snap = snapDuration(value)
            return if (abs(snap - kotlin.math.round(snap)) < 0.05) {
                "${snap.toInt()}s"
            } else {
                String.format(java.util.Locale.US, "%.1fs", snap)
            }
        }
    }
}

object GimbalControl {
    fun modeFromGet(tiltLocked: Boolean, commanded: GimbalMode): GimbalMode =
        when (commanded) {
            GimbalMode.FPV, GimbalMode.DIRECTION_LOCK -> commanded
            GimbalMode.FOLLOW, GimbalMode.TILT_LOCKED ->
                if (tiltLocked) GimbalMode.TILT_LOCKED else GimbalMode.FOLLOW
        }

    fun modeFromFamily(family: Int, current: GimbalMode): GimbalMode =
        when (family) {
            0 -> GimbalMode.DIRECTION_LOCK
            1 -> GimbalMode.FPV
            2 -> if (current == GimbalMode.TILT_LOCKED) current else GimbalMode.FOLLOW
            else -> current
        }
}

class GimbalRampFilter {
    var x = 0.0
    var y = 0.0

    fun reset() {
        x = 0.0
        y = 0.0
    }

    fun tick(targetX: Double, targetY: Double, ramp: GimbalRamp, dt: Double): Pair<Double, Double> {
        val tau = ramp.tau
        if (tau <= 0.0 || dt <= 0.0) {
            x = targetX
            y = targetY
            return x to y
        }
        val alpha = 1 - exp(-dt / tau)
        x += (targetX - x) * alpha
        y += (targetY - y) * alpha
        return x to y
    }
}

/** Time-preserving quadratic fillet at B; A/C exact, B rounded when smoothness > 0. */
class GimbalProgramCurve private constructor(program: GimbalProgram) {
    val a = program.a!!
    val b = program.b!!
    val c = program.c!!
    var durationAB = program.durationAB
        private set
    var durationBC = program.durationBC
        private set
    val halfCornerDuration = min(durationAB, durationBC) * 0.5 * min(program.smoothness, 1.0)
    val duration: Double get() = durationAB + durationBC

    private data class Piece(val from: GimbalWaypoint, val control: GimbalWaypoint?, val to: GimbalWaypoint, val duration: Double)
    private var pieces: List<Piece> = run {
        val p = GimbalMoveEngine.lerp(a, b, 1 - halfCornerDuration / durationAB)
        val q = GimbalMoveEngine.lerp(b, c, halfCornerDuration / durationBC)
        listOf(Piece(a, null, p, durationAB - halfCornerDuration),
            Piece(p, b, q, 2 * halfCornerDuration), Piece(q, null, c, durationBC - halfCornerDuration))
    }
    private val originalProgram = program

    fun position(time: Double): GimbalWaypoint {
        if (time <= 0) return pieces.first().from
        if (time >= duration) return c
        var remaining = time
        for (piece in pieces) {
            if (remaining <= piece.duration) {
                val u = remaining / piece.duration
                val control = piece.control
                return if (control == null) GimbalMoveEngine.lerp(piece.from, piece.to, u)
                else GimbalMoveEngine.lerp(GimbalMoveEngine.lerp(piece.from, control, u),
                    GimbalMoveEngine.lerp(control, piece.to, u), u)
            }
            remaining -= piece.duration
        }
        return c
    }

    fun remaining(time: Double, pose: GimbalWaypoint): GimbalProgramCurve {
        val result = GimbalProgramCurve(originalProgram)
        var consumed = max(0.0, time)
        var rest = emptyList<Piece>()
        for ((index, piece) in pieces.withIndex()) {
            if (consumed >= piece.duration) { consumed -= piece.duration; continue }
            val u = consumed / piece.duration
            val cut = piece.copy(from = pose,
                control = piece.control?.let { GimbalMoveEngine.lerp(it, piece.to, u) },
                duration = piece.duration - consumed)
            rest = listOf(cut) + pieces.drop(index + 1)
            break
        }
        if (rest.isEmpty()) rest = listOf(Piece(pose, null, c, 0.1))
        val total = rest.sumOf { it.duration }
        if (total < 0.1) rest = listOf(rest[0].copy(duration = rest[0].duration + 0.1 - total)) + rest.drop(1)
        result.pieces = rest
        result.durationAB = max(0.0, durationAB - max(0.0, time))
        result.durationBC = rest.sumOf { it.duration } - result.durationAB
        return result
    }

    fun samples(count: Int = 80): List<GimbalWaypoint> {
        val size = max(2, count)
        return (0 until size).map { position(duration * it / (size - 1)) }
    }

    companion object {
        fun create(program: GimbalProgram): GimbalProgramCurve? {
            if (program.a == null || program.b == null || program.c == null ||
                !program.smoothness.isFinite() || program.smoothness <= 0 ||
                !program.durationAB.isFinite() || !program.durationBC.isFinite() ||
                program.durationAB <= 0 || program.durationBC <= 0) return null
            return GimbalProgramCurve(program)
        }
    }
}

/** Camera-executed timed targets, lockstep with Swift GimbalMoveEngine. */
class GimbalMoveEngine {
    data class Output(val target: GimbalWaypoint? = null, val duration: Double = 0.0,
        val stop: Boolean = false, val finished: Boolean = false)
    data class Readout(val label: String, val phase: String, val setDuration: Double,
        val elapsed: Double, val liveYaw: Double, val livePitch: Double,
        val targetYaw: Double, val targetPitch: Double, val remainingDeg: Double)
    private data class Leg(val label: String, val from: GimbalWaypoint, val to: GimbalWaypoint, val duration: Double)
    private data class Observation(val time: Double, val pose: GimbalWaypoint)
    private data class Checkpoint(val time: Double, val incoming: Leg, val outgoing: Leg?, val outgoingAt: Double)

    var running = false
        private set
    var isPaused = false
        private set
    var verificationInterruptedByPause = false
        private set
    private var resumeNeedsCommand = false
    var failure: String? = null
        private set
    private var program = GimbalProgram()
    private var legs: List<Leg> = emptyList()
    private var index = 0
    private var phase = "HOLD"
    private var clock = 0.0
    private var elapsed = 0.0
    private var approachDuration = 0.0
    private val approachTargets = mutableListOf<GimbalWaypoint>()
    private var needsCommand = false
    private val observations = mutableListOf<Observation>()
    private val checkpoints = mutableListOf<Checkpoint>()
    private var lastReadout: Readout? = null
    private var curve: GimbalProgramCurve? = null
    private var nextCurveCommand = 0.0

    fun start(program: GimbalProgram, live: GimbalWaypoint): Boolean {
        cancel()
        this.program = program
        verificationInterruptedByPause = false
        failure = null
        lastReadout = null
        val a = program.a
        val b = program.b
        if (a == null || b == null) {
            failure = "Set A and B before running"
            return false
        }
        if (!program.smoothness.isFinite() || program.smoothness !in 0.0..1.0) return false
        val points = listOfNotNull(a, b, live, program.c)
        if (!points.all {
                it.yawDeg.isFinite() && it.pitchDeg.isFinite() && it.zoom.isFinite() && it == it.clamped() &&
                    (it.nativePitchDeg == null || (it.nativePitchDeg.isFinite() && it.nativePitchDeg in -180.0..180.0)) }) {
            failure = "Set reachable gimbal points again"
            return false
        }
        if (points.any { it.nativePitchDeg != null } && !points.all { it.nativePitchDeg != null }) {
            failure = "Set gimbal points from fresh camera feedback"
            return false
        }
        val next = mutableListOf(Leg("A→B", a, b, program.durationAB))
        program.c?.let { next += Leg("B→C", b, it, program.durationBC) }
        if (!next.all { it.duration.isFinite() && it.duration in GimbalProgram.MIN_DURATION..GimbalProgram.MAX_DURATION &&
                abs(it.duration * 10 - kotlin.math.round(it.duration * 10)) < 1e-6 }) {
            failure = "Increase the move duration"
            return false
        }
        legs = next
        curve = GimbalProgramCurve.create(program)
        nextCurveCommand = 0.0
        index = 0
        clock = 0.0
        elapsed = 0.0
        observations.clear()
        checkpoints.clear()
        val approachSteps = max(1, kotlin.math.ceil(abs(a.yawDeg - live.yawDeg) / 120).toInt())
        approachTargets.clear()
        approachTargets += (1..approachSteps).map { lerp(live, a, it.toDouble() / approachSteps) }
        approachDuration = max(GimbalProgram.MIN_DURATION,
            kotlin.math.ceil(angularDistance(live, a) / approachSteps / 120 * 10) / 10)
        needsCommand = angularDistance(live, a) > ARRIVE_DEG
        phase = if (needsCommand) "APPROACH" else "HOLD"
        running = true
        return true
    }

    fun pause(live: GimbalWaypoint): Boolean {
        if (!running || isPaused) return false
        verificationInterruptedByPause = verificationInterruptedByPause || checkpoints.isNotEmpty()
        checkpoints.clear()
        observations.clear()
        isPaused = true
        lastReadout = snapshot(live)
        return true
    }

    fun resume(live: GimbalWaypoint): Boolean {
        if (!running || !isPaused || !live.yawDeg.isFinite() || !live.pitchDeg.isFinite() ||
            !live.zoom.isFinite() || live != live.clamped() ||
            (legs[0].from.nativePitchDeg != null && live.nativePitchDeg == null) ||
            (live.nativePitchDeg != null && (!live.nativePitchDeg.isFinite() || live.nativePitchDeg !in -180.0..180.0))) return false
        if (phase == "APPROACH" || phase == "HOLD") {
            val interrupted = verificationInterruptedByPause
            if (!start(program, live)) return false
            verificationInterruptedByPause = interrupted
            resumeNeedsCommand = true
            return true
        }
        val activeCurve = curve
        if (activeCurve != null && phase == "RUN") {
            curve = activeCurve.remaining(elapsed, live)
            index = if (curve!!.durationAB > 0) 0 else 1
        } else {
            curve = null
            val remaining = if (phase == "VERIFY") 0.1 else max(0.0, legs[index].duration - elapsed)
            legs = legs.toMutableList().also { it[index] = it[index].copy(from = live,
                duration = max(0.1, kotlin.math.ceil((remaining - 1e-9) * 10) / 10)) }
        }
        phase = "RUN"
        clock = 0.0
        elapsed = 0.0
        nextCurveCommand = 0.0
        checkpoints.clear()
        observations.clear()
        isPaused = false
        resumeNeedsCommand = true
        return true
    }

    fun cancel() {
        if (running) lastReadout = lastReadout?.copy(phase = "STOP")
        running = false
        isPaused = false
        resumeNeedsCommand = false
        needsCommand = false
        checkpoints.clear()
        observations.clear()
    }

    val nextWakeInterval: Double
        get() {
            if (!running) return 0.04
            val activeCurve = curve
            if (activeCurve != null && phase == "RUN") {
                val boundary = min(nextCurveCommand, activeCurve.duration)
                return if (boundary > elapsed + 1e-9) min(0.04, boundary - elapsed) else 0.04
            }
            if (phase == "RUN" && (abs(legs[index].to.yawDeg - legs[index].from.yawDeg) >= 180 || legs[index].duration > 25.5)) {
                val boundary = min(nextCurveCommand, legs[index].duration)
                return if (boundary > elapsed + 1e-9) min(0.04, boundary - elapsed) else 0.04
            }
            val end = if (phase == "RUN") legs[index].duration else if (phase == "HOLD") HOLD_SECONDS else 0.0
            return if (end > elapsed) min(0.04, end - elapsed) else 0.04
        }

    fun tick(dt: Double, live: GimbalWaypoint, telemetryAge: Double = 0.0): Output? {
        if (!running || isPaused) return null
        if (!dt.isFinite() || dt <= 0 || dt > 0.12 || !telemetryAge.isFinite() || telemetryAge !in 0.0..0.3 ||
            !live.yawDeg.isFinite() || !live.pitchDeg.isFinite() ||
            (legs[0].from.nativePitchDeg != null && live.nativePitchDeg == null) ||
            (live.nativePitchDeg != null && (!live.nativePitchDeg.isFinite() || live.nativePitchDeg !in -180.0..180.0))) {
            return stop(live, "Move interrupted — timing or camera feedback lost")
        }
        if (resumeNeedsCommand) {
            resumeNeedsCommand = false
            if (phase == "RUN") {
                val activeCurve = curve
                if (activeCurve != null) {
                    nextCurveCommand = if (activeCurve.duration <= 0.1) activeCurve.duration else min(0.05, activeCurve.duration - 0.1)
                    return output(live, activeCurve.position(0.1), 0.1)
                }
                return startExactLeg(live)
            }
            if (phase == "APPROACH") {
                needsCommand = false
                return output(live, approachTargets.firstOrNull(), approachDuration)
            }
            return output(live)
        }
        clock += dt
        elapsed += dt
        val sampleTime = clock - telemetryAge
        if (sampleTime > (observations.lastOrNull()?.time ?: Double.NEGATIVE_INFINITY) + 1e-9) {
            observations += Observation(sampleTime, live)
        }
        observations.removeAll { it.time < clock - 0.8 }
        checkpoints.removeAll { checkpointIsConsistent(it) }
        if (checkpoints.any { clock - it.time > 0.4 }) return stop(live, "Camera waypoint could not be verified")
        val a = legs[0].from
        if (phase == "APPROACH") {
            val approachTarget = approachTargets.firstOrNull() ?: a
            if (needsCommand) {
                needsCommand = false
                elapsed = 0.0
                return output(live, approachTarget, approachDuration)
            }
            if (elapsed >= approachDuration && angularDistance(live, approachTarget) <= ARRIVE_DEG) {
                approachTargets.removeAt(0)
                elapsed = 0.0
                approachTargets.firstOrNull()?.let { return output(live, it, approachDuration) }
                phase = "HOLD"
            } else if (elapsed > approachDuration + 0.5) return stop(live, "Camera did not reach A")
            return output(live)
        }
        if (phase == "HOLD") {
            if (angularDistance(live, a) > ARRIVE_DEG) return stop(live, "Camera moved before the take")
            if (elapsed + 1e-9 < HOLD_SECONDS) return output(live)
            phase = "RUN"
            elapsed = 0.0
            curve?.let {
                nextCurveCommand = 0.05
                return output(live, it.position(0.1), 0.1)
            }
            return startExactLeg(live)
        }
        if (phase == "RUN") curve?.let { return tickCurve(it, live) }
        if (phase == "RUN") {
            val leg = legs[index]
            val streamed = abs(leg.to.yawDeg - leg.from.yawDeg) >= 180 || leg.duration > 25.5
            if (elapsed + 1e-9 < leg.duration) return if (streamed) tickLinearLeg(live) else output(live)
            if (streamed && nextCurveCommand < leg.duration) return stop(live, "Move interrupted — waypoint dispatch was late")
            if (elapsed - leg.duration > 0.02 + 1e-9) return stop(live, "Move interrupted — waypoint dispatch was late")
            checkpoints += Checkpoint(clock - (elapsed - leg.duration), leg, legs.getOrNull(index + 1), clock)
            if (index + 1 < legs.size) {
                index += 1
                elapsed = 0.0
                return startExactLeg(live)
            }
            phase = "VERIFY"
            elapsed = 0.0
            return output(live)
        }
        if (phase == "VERIFY" && elapsed >= 0.3 && checkpoints.isEmpty()) {
            if (angularDistance(live, legs[index].to) > ARRIVE_DEG) return stop(live, "Camera missed its final position")
            phase = "DONE"
            running = false
            return output(live, finished = true)
        }
        return output(live)
    }

    private fun startExactLeg(live: GimbalWaypoint): Output {
        val leg = legs[index]
        if (abs(leg.to.yawDeg - leg.from.yawDeg) >= 180 || leg.duration > 25.5) {
            nextCurveCommand = 0.0
            return sendRoutedLegPart(live)
        }
        return output(live, leg.to, leg.duration)
    }

    private fun tickLinearLeg(live: GimbalWaypoint): Output {
        if (elapsed + 1e-9 < nextCurveCommand) return output(live)
        if (elapsed - nextCurveCommand > 0.02 + 1e-9) return stop(live, "Move interrupted — waypoint dispatch was late")
        return sendRoutedLegPart(live)
    }

    private fun sendRoutedLegPart(live: GimbalWaypoint): Output {
        val leg = legs[index]
        val parts = max(1, max(kotlin.math.ceil(abs(leg.to.yawDeg - leg.from.yawDeg) / 120).toInt(),
            kotlin.math.ceil(leg.duration / 25.5).toInt()))
        val ticks = kotlin.math.round(leg.duration * 10).toInt()
        var endTicks = 0
        val start = nextCurveCommand
        for (part in 0 until parts) {
            val partTicks = ticks / parts + if (part < ticks % parts) 1 else 0
            endTicks += partTicks
            val end = endTicks / 10.0
            if (end <= start + 1e-9) continue
            nextCurveCommand = end
            val target = if (part == parts - 1) leg.to else lerp(leg.from, leg.to, end / leg.duration)
            return output(live, target, partTicks / 10.0)
        }
        return stop(live, "Move interrupted — waypoint dispatch was late")
    }

    private fun tickCurve(curve: GimbalProgramCurve, live: GimbalWaypoint): Output {
        index = if (elapsed >= curve.durationAB) 1 else 0
        if (elapsed + 1e-9 >= curve.duration) {
            if (nextCurveCommand < curve.duration) return stop(live, "Move interrupted — waypoint dispatch was late")
            checkpoints += Checkpoint(clock - (elapsed - curve.duration), legs[1], null, clock)
            phase = "VERIFY"
            elapsed = 0.0
            return output(live)
        }
        if (elapsed + 1e-9 < nextCurveCommand) return output(live)
        if (elapsed - nextCurveCommand > 0.02 + 1e-9) return stop(live, "Move interrupted — waypoint dispatch was late")
        val lastCommandAt = curve.duration - 0.1
        val target = if (nextCurveCommand >= lastCommandAt - 1e-9) curve.c
            else curve.position(min(curve.duration, nextCurveCommand + 0.1))
        nextCurveCommand = if (nextCurveCommand >= lastCommandAt - 1e-9) curve.duration
            else min(lastCommandAt, nextCurveCommand + 0.05)
        return output(live, target, 0.1)
    }

    /** Fit one bounded feedback delay across all nearby reports without relaxing angular error. */
    private fun checkpointIsConsistent(check: Checkpoint): Boolean {
        if (check.outgoing == null) {
            val settled = observations.filter { it.time >= check.time && it.time <= check.time + 0.4 }
                .asReversed().takeWhile { angularDistance(it.pose, check.incoming.to) <= ARRIVE_DEG }
            return settled.size >= 2 && settled.first().time - settled.last().time >= 0.08 - 1e-9
        }
        val outgoing = check.outgoing ?: return false
        if (clock + 1e-9 < check.time + 0.3) return false
        val nearby = observations.filter { it.time >= check.time - 0.3 && it.time <= check.time + 0.3 }
        if (nearby.size < 3) return false
        // References are affine between delay breakpoints. Intersect the error
        // circles with each interval so submillisecond delays remain representable.
        val low = max(0.0, nearby.first().time - check.time)
        val high = min(0.2, nearby.last().time - check.time)
        if (low > high) return false
        fun reference(sample: Observation, delay: Double): GimbalWaypoint {
            val time = sample.time - delay
            return if (time < check.time) {
                lerp(check.incoming.from, check.incoming.to,
                    1 + (time - check.time) / check.incoming.duration)
            } else {
                lerp(outgoing.from, outgoing.to, (time - check.outgoingAt) / outgoing.duration)
            }
        }
        val knots = mutableListOf(low, high)
        for (sample in nearby) {
            for (time in listOf(check.time - check.incoming.duration, check.time,
                check.outgoingAt, check.outgoingAt + outgoing.duration)) {
                val delay = sample.time - time
                if (delay > low && delay < high) knots += delay
            }
        }
        knots.sort()
        if (low == high) return nearby.all {
            angularDistance(it.pose, reference(it, low)) <= ARRIVE_DEG
        }
        for ((lower, upper) in knots.zipWithNext()) {
            if (upper - lower <= 1e-12) continue
            val span = upper - lower
            var feasibleLow = 0.0
            var feasibleHigh = span
            for (sample in nearby) {
                val first = reference(sample, lower)
                val last = reference(sample, upper)
                val ey = sample.pose.yawDeg - first.yawDeg
                val ep = pitchDelta(first, sample.pose)
                val vy = -(last.yawDeg - first.yawDeg) / span
                val vp = -pitchDelta(first, last) / span
                val aa = vy * vy + vp * vp
                val bb = 2 * (ey * vy + ep * vp)
                val cc = ey * ey + ep * ep - ARRIVE_DEG * ARRIVE_DEG
                if (aa < 1e-12) {
                    if (cc > 1e-10) { feasibleHigh = -1.0; break }
                    continue
                }
                val discriminant = bb * bb - 4 * aa * cc
                if (discriminant < -1e-9) { feasibleHigh = -1.0; break }
                val root = kotlin.math.sqrt(max(0.0, discriminant))
                feasibleLow = max(feasibleLow, (-bb - root) / (2 * aa))
                feasibleHigh = min(feasibleHigh, (-bb + root) / (2 * aa))
                if (feasibleLow > feasibleHigh) break
            }
            if (feasibleLow <= feasibleHigh) {
                val delay = lower + (feasibleLow + feasibleHigh) / 2
                if (nearby.all { angularDistance(it.pose, reference(it, delay)) <= ARRIVE_DEG + 1e-9 }) {
                    return true
                }
            }
        }
        return false
    }

    private fun stop(live: GimbalWaypoint, reason: String): Output {
        failure = reason
        lastReadout = snapshot(live)?.copy(phase = "STOP")
        phase = "STOP"
        isPaused = false
        running = false
        return Output(stop = true, finished = true)
    }

    private fun output(live: GimbalWaypoint, target: GimbalWaypoint? = null,
        duration: Double = 0.0, finished: Boolean = false): Output {
        if (target != null && !canSendNativeTarget(live, target)) {
            return stop(live, "Camera moved outside the safe rotation path")
        }
        lastReadout = snapshot(live)
        return Output(target, duration, finished = finished)
    }

    private fun snapshot(live: GimbalWaypoint): Readout? {
        if (index >= legs.size) return lastReadout
        val leg = legs[index]
        val atA = phase == "APPROACH" || phase == "HOLD"
        val target = if (atA) legs[0].from else leg.to
        return Readout(if (atA) "A" else leg.label, if (isPaused) "PAUSED" else phase,
            if (phase == "APPROACH") approachDuration else if (phase == "HOLD") HOLD_SECONDS else leg.duration,
            if (phase == "VERIFY" || phase == "DONE") leg.duration
            else if (curve != null && phase == "RUN" && index == 1) elapsed - curve!!.durationAB else elapsed,
            live.yawDeg, live.pitchDeg, target.yawDeg, target.pitchDeg, angularDistance(live, target))
    }

    fun readout(live: GimbalWaypoint): Readout? = if (running) snapshot(live) else lastReadout
    fun hudText(live: GimbalWaypoint?): String = hudText(program, live)
    fun hudText(program: GimbalProgram, live: GimbalWaypoint?): String =
        formatDebug(program, live, live?.let { readout(it) } ?: lastReadout)

    companion object {
        const val ARRIVE_DEG = 0.15
        const val HOLD_SECONDS = 2.0
        fun canSendNativeTarget(live: GimbalWaypoint, target: GimbalWaypoint): Boolean =
            live.yawDeg.isFinite() && live.pitchDeg.isFinite() && target.yawDeg.isFinite() && target.pitchDeg.isFinite() &&
                live == live.clamped() && target == target.clamped() &&
                abs(java.lang.Math.copySign(kotlin.math.floor(abs(target.yawDeg * 10) + 0.5), target.yawDeg) / 10 - live.yawDeg) < 180

        const val DEBUG_HUD = true
        const val WIDE_HFOV = 84.0
        const val PITCH_UP_SIGN = 1.0

        fun formatHud(row: Readout): String = formatDebug(GimbalProgram(), null, row)
        fun formatDebug(program: GimbalProgram, live: GimbalWaypoint?, row: Readout?): String {
            fun xy(name: String, point: GimbalWaypoint?): String = if (point == null) "$name  --"
                else String.format(java.util.Locale.US, "%s  X%+7.1f  Y%+7.1f", name, point.yawDeg, point.pitchDeg)
            val lines = mutableListOf(xy("A", program.a), xy("B", program.b), xy("C", program.c), xy("now", live))
            if (row != null) {
                lines += "${row.label}  ${row.phase}"
                lines += String.format(java.util.Locale.US, "set %4.1fs  t %5.2fs", row.setDuration, row.elapsed)
                lines += String.format(java.util.Locale.US, "tgt  X%+7.1f  Y%+7.1f", row.targetYaw, row.targetPitch)
                lines += String.format(java.util.Locale.US, "rem %5.1f°", row.remainingDeg)
            }
            return lines.joinToString("\n")
        }

        fun wrapAngle(value: Double): Double = ((value + 180) % 360 + 360) % 360 - 180
        fun pitchDelta(from: GimbalWaypoint, to: GimbalWaypoint): Double =
            if (from.nativePitchDeg != null && to.nativePitchDeg != null) wrapAngle(to.nativePitchDeg - from.nativePitchDeg)
            else to.pitchDeg - from.pitchDeg
        fun angularDistance(a: GimbalWaypoint, b: GimbalWaypoint): Double = hypot(b.yawDeg - a.yawDeg, pitchDelta(a, b))
        fun lerp(a: GimbalWaypoint, b: GimbalWaypoint, u: Double): GimbalWaypoint {
            val t = u.coerceIn(0.0, 1.0)
            return GimbalWaypoint(a.yawDeg + (b.yawDeg - a.yawDeg) * t,
                a.pitchDeg + (b.pitchDeg - a.pitchDeg) * t, a.zoom + (b.zoom - a.zoom) * t,
                if (a.nativePitchDeg != null && b.nativePitchDeg != null) wrapAngle(a.nativePitchDeg + pitchDelta(a, b) * t) else null)
        }
        fun tanHalfHFov(zoom: Double): Double = tan(WIDE_HFOV / 2 * Math.PI / 180) / max(zoom, 1.0)

        fun project(waypoint: GimbalWaypoint, live: GimbalWaypoint, aspect: Double): Triple<Double, Double, Boolean> {
            val tanH = tanHalfHFov(live.zoom)
            val tanV = tanH / max(aspect, 0.1)
            val dYaw = (waypoint.yawDeg - live.yawDeg) * Math.PI / 180
            val tp = PITCH_UP_SIGN * waypoint.pitchDeg * Math.PI / 180
            val cp = PITCH_UP_SIGN * live.pitchDeg * Math.PI / 180
            val x = sin(dYaw) * cos(tp)
            val y = sin(tp)
            val z = cos(dYaw) * cos(tp)
            val yc = y * cos(cp) - z * sin(cp)
            val zc = y * sin(cp) + z * cos(cp)
            if (zc <= 1e-6) return Triple(if (x >= 0) 1.0 else 0.0, 0.5, false)
            val nx = 0.5 + (x / zc) / (2 * tanH)
            val ny = 0.5 - (yc / zc) / (2 * tanV)
            val onScreen = nx in 0.0..1.0 && ny in 0.0..1.0
            return Triple(nx.coerceIn(0.0, 1.0), ny.coerceIn(0.0, 1.0), onScreen)
        }
    }
}

/** Display-only measured-velocity interpolation; never a motor or capture input. */
class GimbalOverlayMotion {
    private data class Sample(val pose: GimbalWaypoint, val time: Double)
    private var previous: Sample? = null
    private var latest: Sample? = null

    fun reset() {
        previous = null
        latest = null
    }

    fun observe(pose: GimbalWaypoint, time: Double) {
        if (!time.isFinite() || !pose.yawDeg.isFinite() || !pose.pitchDeg.isFinite() || !pose.zoom.isFinite() ||
            time <= (latest?.time ?: Double.NEGATIVE_INFINITY)) return
        previous = latest
        latest = Sample(pose, time)
    }

    fun pose(time: Double): GimbalWaypoint? {
        val last = latest ?: return null
        if (!time.isFinite() || time < last.time || time - last.time > STALE_AFTER) return null
        val result = last.pose.copy(nativePitchDeg = null)
        val before = previous ?: return result
        val interval = last.time - before.time
        if (interval < 0.02 || interval > STALE_AFTER) return result
        val ahead = min(time - last.time, PREDICTION_HORIZON)
        val yawDelta = GimbalMoveEngine.wrapAngle(last.pose.yawDeg - before.pose.yawDeg)
        return result.copy(yawDeg = result.yawDeg + yawDelta * ahead / interval,
            pitchDeg = result.pitchDeg + (last.pose.pitchDeg - before.pose.pitchDeg) * ahead / interval)
    }

    companion object {
        const val PREDICTION_HORIZON = 0.1
        const val STALE_AFTER = 0.3
    }
}

object GimbalHudCopy {
    const val POSE_NOT_READY = "Gimbal pose not ready"
    const val NEED_AB = "Set A and B to run"
    const val HOLD_STILL = "Hold the gimbal still"
    const val TITLE = "Gimbal"
    const val MODE = "Mode"
    const val SPEED = "Speed"
    const val RAMP = "Ramp"
    const val PROGRAMMED = "Motion Control"
    const val RUN = "Start"
    const val STOP = "Stop"
}
