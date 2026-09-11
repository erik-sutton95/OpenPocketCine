package com.opencapture.openpocketcine.session

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.tan
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GimbalProgramTest {
    private val a = GimbalWaypoint(0.0, 0.0, 1.0)
    private val b = GimbalWaypoint(30.0, 10.0, 3.0)

    @Test
    fun directionLockUsesVerifiedCommandAndSurvivesTiltReplies() {
        assertTrue(CameraCommands.gimbalDirectionLock().contentEquals(byteArrayOf(0x00, 0x08)))
        var mode = GimbalControl.modeFromFamily(0, GimbalMode.FOLLOW)
        assertEquals(GimbalMode.DIRECTION_LOCK, mode)
        mode = GimbalControl.modeFromGet(true, mode)
        assertEquals(GimbalMode.DIRECTION_LOCK, mode)
        mode = GimbalControl.modeFromFamily(2, mode)
        assertEquals(GimbalMode.FOLLOW, mode)
        assertEquals(GimbalMode.TILT_LOCKED, GimbalControl.modeFromFamily(2, GimbalMode.TILT_LOCKED))
        assertEquals(GimbalMode.FPV, GimbalControl.modeFromFamily(1, mode))
        assertEquals(mode, GimbalControl.modeFromFamily(3, mode))
        assertFalse(StatusExtras.isGimbalParamsReply(byteArrayOf(0, 0)))
        assertTrue(StatusExtras.isGimbalParamsReply(byteArrayOf(0, 1, 4, 1, 1, 5, 1, 0)))
    }

    @Test
    fun periodicReadbackCorrectsLateModeReportsAndPhysicalTiltChanges() {
        var poll = GimbalParamPoll()
        assertTrue(poll.shouldRequest(0))
        var mode = GimbalControl.modeFromFamily(0, GimbalMode.TILT_LOCKED)
        mode = GimbalControl.modeFromFamily(2, mode)
        for (tick in 1..9) assertFalse(poll.shouldRequest(tick * 100L))
        assertTrue(poll.shouldRequest(1_000))
        mode = GimbalControl.modeFromGet(true, mode)
        assertEquals(GimbalMode.TILT_LOCKED, mode)
        mode = GimbalControl.modeFromFamily(2, mode)
        assertTrue(poll.shouldRequest(2_000))
        mode = GimbalControl.modeFromGet(false, mode)
        assertEquals(GimbalMode.FOLLOW, mode)
        poll = GimbalParamPoll()
        assertTrue(poll.shouldRequest(2_100))
    }

    @Test
    fun runNeedsAAndB() {
        var program = GimbalProgram()
        assertFalse(program.canRun)
        program = program.copy(a = a, b = b)
        assertTrue(program.canRun)
    }

    @Test
    fun lerpIsLinear() {
        val mid = GimbalMoveEngine.lerp(a, b, 0.5)
        assertEquals(15.0, mid.yawDeg, 1e-9)
        assertEquals(5.0, mid.pitchDeg, 1e-9)
    }

    @Test
    fun unwrapYawPastTheGap() {
        assertEquals(-48.0, GimbalWaypoint.unwrapYaw(-48.0), 1e-9)
        assertEquals(225.0, GimbalWaypoint.unwrapYaw(-135.0), 1e-9)
        assertEquals(180.0, GimbalWaypoint.unwrapYaw(-180.0), 1e-9)
        assertEquals(180.0, GimbalWaypoint.unwrapYaw(180.0), 1e-9)
    }

    @Test
    fun measuredYawIsNotClampedIntoFakeEndpoints() {
        assertEquals(90.0, GimbalWaypoint.unwrapYaw(90.0), 1e-9)
        assertEquals(100.0, GimbalWaypoint.unwrapYaw(100.0), 1e-9)
        assertEquals(-80.0, GimbalWaypoint.unwrapYaw(-80.0), 1e-9)
        assertEquals(260.0, GimbalWaypoint.unwrapYaw(-100.0), 1e-9)
    }

    @Test
    fun overlayCentersWhenPoseMatches() {
        val (nx, ny, onScreen) = GimbalMoveEngine.project(a, a, 16.0 / 9.0)
        assertEquals(0.5, nx, 1e-9)
        assertEquals(0.5, ny, 1e-9)
        assertTrue(onScreen)
    }

    @Test
    fun overlayFollowsLiveYawOnTheSphere() {
        val point = GimbalWaypoint(20.0, 0.0, 1.0)
        val atOrigin = GimbalMoveEngine.project(point, GimbalWaypoint(0.0, 0.0, 1.0), 16.0 / 9.0)
        val afterPan = GimbalMoveEngine.project(point, GimbalWaypoint(20.0, 0.0, 1.0), 16.0 / 9.0)
        assertTrue(atOrigin.first > 0.5)
        assertEquals(0.5, afterPan.first, 1e-9)
    }

    @Test
    fun overlayIsRectilinear() {
        val (nx, _, onScreen) =
            GimbalMoveEngine.project(GimbalWaypoint(30.0, 0.0, 1.0), a, 16.0 / 9.0)
        val expected = 0.5 + tan(30 * PI / 180) / (2 * tan(42 * PI / 180))
        assertEquals(expected, nx, 1e-9)
        assertTrue(onScreen)
    }

    @Test
    fun overlayDrawsLookUpAboveCenter() {
        val (_, ny, _) = GimbalMoveEngine.project(GimbalWaypoint(0.0, 10.0, 1.0), a, 16.0 / 9.0)
        assertTrue(ny < 0.5)
    }


    @Test
    fun cameraExecutesABCOncePerLegWithSparseFeedback() {
        val a = GimbalWaypoint(-20.0, 1.5, 1.0)
        val b = GimbalWaypoint(25.3, -28.2, 1.0)
        val c = GimbalWaypoint(24.6, -0.5, 1.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = a, b = b, c = c, durationAB = 5.0, durationBC = 4.0), a))
        var live = a
        var reported = a
        var reportAt = 0.0
        var motionStart = a
        var motionTarget = a
        var motionAt = 0.0
        var motionDuration = 1.0
        val sends = mutableListOf<Triple<Double, GimbalWaypoint, Double>>()
        for (step in 0..<400) {
            val now = step * 0.04
            live = GimbalMoveEngine.lerp(motionStart, motionTarget, (now - motionAt) / motionDuration)
            if (((now + 1e-6) * 10).toInt() > ((reportAt + 1e-6) * 10).toInt()) {
                reported = live
                reportAt = now
            }
            val out = engine.tick(0.04, reported, now - reportAt) ?: break
            out.target?.let { target ->
                sends += Triple(now, target, out.duration)
                motionStart = live
                motionTarget = target
                motionAt = now
                motionDuration = out.duration
            }
            if (out.finished) break
        }
        assertEquals(null, engine.failure)
        assertFalse(engine.running)
        assertEquals(2, sends.size)
        assertEquals(b, sends[0].second)
        assertEquals(c, sends[1].second)
        assertEquals(5.0, sends[0].third)
        assertEquals(4.0, sends[1].third)
        assertEquals(5.0, sends[1].first - sends[0].first, 0.040001)
        assertTrue(GimbalMoveEngine.angularDistance(live, c) <= 0.15)
    }

    @Test
    fun approachUsesOneNativeTargetWithoutCalibration() {
        val live = GimbalWaypoint(-24.6, -0.5, 1.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = a, b = b), live))
        val command = engine.tick(0.04, live)!!
        assertEquals(a, command.target)
        assertEquals(GimbalProgram.MIN_DURATION, command.duration)
        val targets = mutableListOf<GimbalWaypoint>()
        repeat(80) { engine.tick(0.04, a)?.target?.let { targets += it } }
        assertEquals(listOf(b), targets)
        assertEquals(null, engine.failure)
        assertEquals("RUN", engine.readout(a)?.phase)
    }

    @Test
    fun blockedCameraCannotPretendApproachSucceeded() {
        val live = GimbalWaypoint(-24.6, -0.5, 1.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = a, b = b), live))
        var last: GimbalMoveEngine.Output? = null
        repeat(100) { engine.tick(0.04, live)?.let { last = it } }
        assertTrue(last?.stop == true && last?.finished == true)
        assertEquals("Camera did not reach A", engine.failure)
        assertEquals("A", engine.readout(live)?.label)
    }

    @Test
    fun minimumDurationUsesUiFloorWithoutArtificialSpeedCap() {
        val from = GimbalWaypoint(100.0, -40.0, 1.0)
        assertEquals(0.5, GimbalProgram.minTravelDuration(from, a))
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = from, b = a, durationAB = 0.5), from))
        assertFalse(engine.start(GimbalProgram(a = a, b = b, durationAB = 1.01), a))
        assertEquals(8.0, GimbalProgram(a = a, b = b, durationAB = 8.0).withPoint(GimbalWaypointSlot.B, a).durationAB)
    }

    @Test
    fun feedbackLossAndSchedulerStallsStopNativeMotion() {
        for ((dt, age) in listOf(0.04 to 0.31, 0.04 to Double.NaN, 0.04 to Double.POSITIVE_INFINITY,
            0.13 to 0.0, Double.NaN to 0.0)) {
            val engine = GimbalMoveEngine()
            assertTrue(engine.start(GimbalProgram(a = a, b = b), a))
            val out = engine.tick(dt, a, age)!!
            assertTrue(out.stop && out.finished)
        }
    }

    @Test
    fun cancellationCannotSendAnotherNativeTarget() {
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = a, b = b), b))
        engine.tick(0.04, b)
        engine.cancel()
        assertEquals(null, engine.tick(0.04, b))
    }

    @Test
    fun nativePacketUsesCapturedNativePitchAndExactTenthsSeconds() {
        kotlin.test.assertContentEquals(byteArrayOf(253.toByte(), 0, 0, 0, 60, 250.toByte(), 5, 50),
            CameraCommands.gimbalTimedTarget(25.3, -147.6, 5.0))
        kotlin.test.assertContentEquals(byteArrayOf(0, 0, 0, 0, 0, 0, 4, 1), CameraCommands.gimbalTimedStop())
        assertEquals(null, CameraCommands.gimbalTimedTarget(999.0, 0.0, 1.0))
        assertEquals(null, CameraCommands.gimbalTimedTarget(0.0, 0.0, Double.NaN))
        assertEquals(null, CameraCommands.gimbalTimedTarget(0.0, 0.0, 1.01))
    }

    @Test
    fun reachingBEarlyDoesNotVerifyItsDeadline() {
        val end = GimbalWaypoint(10.0, 0.0, 1.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = a, b = end, c = a, durationAB = 1.0, durationBC = 1.0), a))
        for (step in 1..120) {
            val now = step * 0.04
            var yaw = if (now <= 2) 0.0 else if (now <= 3) (now - 2) * 10 else kotlin.math.max(0.0, (4 - now) * 10)
            if (abs(now - 2.92) < 0.001) yaw = 10.0
            if (now >= 2.96 && now < 3.5) yaw -= 1
            engine.tick(0.04, GimbalWaypoint(yaw, 0.0, 1.0))
        }
        assertEquals("Camera waypoint could not be verified", engine.failure)
    }

    @Test
    fun lateBoundaryCannotSilentlyStretchTheTake() {
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = a, b = b, c = a, durationAB = 5.0, durationBC = 4.0), a))
        repeat(50) { engine.tick(0.04, a) }
        repeat(124) { engine.tick(0.04, b) }
        val out = engine.tick(0.08, b)!!
        assertTrue(out.stop)
        assertEquals(null, out.target)
        assertEquals("Move interrupted — waypoint dispatch was late", engine.failure)
    }

    @Test
    fun nativePitchWrapUsesShortestArcAndKeepsOverlayPitch() {
        val from = GimbalWaypoint(0.0, -10.0, 1.0, 179.0)
        val to = GimbalWaypoint(0.0, -12.0, 1.0, -179.0)
        assertEquals(2.0, GimbalMoveEngine.angularDistance(from, to), 1e-9)
        assertEquals(-180.0, GimbalMoveEngine.lerp(from, to, 0.5).nativePitchDeg)
        assertEquals(-11.0, GimbalMoveEngine.lerp(from, to, 0.5).pitchDeg)
        assertEquals(-2.0, GimbalMoveEngine.pitchDelta(to, from), 1e-9)
        assertEquals(from, from.clamped())
        assertEquals(-147.6, GimbalWaypoint.from(253, -282, 1.0, -1476)?.nativePitchDeg)
        assertEquals(-28.2, GimbalWaypoint.from(253, -282, 1.0, -1476)?.pitchDeg)
        val engine = GimbalMoveEngine()
        assertFalse(engine.start(GimbalProgram(a = from, b = to.copy(nativePitchDeg = Double.NaN)), from))
        assertFalse(engine.start(GimbalProgram(a = from, b = to.copy(nativePitchDeg = 181.0)), from))
        assertEquals(null, CameraCommands.gimbalTimedTarget(0.0, 181.0, 1.0))
    }

    @Test
    fun nativeMovesRejectMixedCoordinatesAndLostNativeFeedback() {
        val nativeA = a.copy(nativePitchDeg = -170.0)
        val nativeB = b.copy(nativePitchDeg = -150.0)
        val engine = GimbalMoveEngine()
        assertFalse(engine.start(GimbalProgram(a = nativeA, b = b), nativeA))
        assertEquals("Set gimbal points from fresh camera feedback", engine.failure)
        assertFalse(engine.start(GimbalProgram(a = nativeA, b = nativeB), a))
        for (invalid in listOf(null, Double.NaN, Double.POSITIVE_INFINITY, 181.0)) {
            assertTrue(engine.start(GimbalProgram(a = nativeA, b = nativeB), nativeA))
            val out = engine.tick(0.04, nativeA.copy(nativePitchDeg = invalid))!!
            assertTrue(out.stop && out.finished)
            assertEquals("Move interrupted — timing or camera feedback lost", engine.failure)
        }
    }

    @Test
    fun oppositeNativePitchErrorsCannotInterpolateToSuccess() {
        val origin = a.copy(nativePitchDeg = 0.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = origin, b = origin, c = origin,
            durationAB = 1.0, durationBC = 1.0), origin))
        for (step in 1..110) {
            val native = when (step) {
                74, 75 -> 179.9
                76 -> -179.9
                else -> 0.0
            }
            engine.tick(0.04, origin.copy(nativePitchDeg = native), if (step == 75) 0.04 else 0.0)
        }
        assertEquals("Camera waypoint could not be verified", engine.failure)
    }

    @Test
    fun bodyTiltEdgesAreAllowedButOutsideTelemetryIsNotClampedIntoThem() {
        val lower = GimbalWaypoint(0.0, -44.0, 1.0, -140.0)
        val upper = GimbalWaypoint(0.0, 70.0, 1.0, 106.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = lower, b = upper, durationAB = 5.0), lower))
        assertTrue(CameraCommands.gimbalTimedTarget(lower, 5.0) != null)
        assertTrue(CameraCommands.gimbalTimedTarget(upper, 5.0) != null)
        for (pitch in listOf(-44.1, 70.1, -90.0, 120.0)) {
            val observed = GimbalWaypoint.from(0, kotlin.math.round(pitch * 10).toInt(), 1.0, -1400)!!
            assertEquals(pitch, observed.pitchDeg, 1e-9)
            assertTrue(observed != observed.clamped())
            assertFalse(engine.start(GimbalProgram(a = lower, b = observed), lower))
            assertFalse(engine.start(GimbalProgram(a = lower, b = upper), observed))
            assertEquals(null, CameraCommands.gimbalTimedTarget(observed, 5.0))
        }
        // The native coordinate range is an encoding domain, not the body tilt envelope.
        assertTrue(CameraCommands.gimbalTimedTarget(lower.copy(nativePitchDeg = -179.0), 5.0) != null)
        assertTrue(CameraCommands.gimbalTimedTarget(upper.copy(nativePitchDeg = 179.0), 5.0) != null)
    }

    @Test
    fun longPositivePanArcStaysUnwrappedThroughItsWaypointsAndPacket() {
        val from = GimbalWaypoint(-48.0, 0.0, 1.0, -170.0)
        val to = GimbalWaypoint(225.0, 0.0, 1.0, -170.0)
        assertEquals(88.5, GimbalMoveEngine.lerp(from, to, 0.5).yawDeg, 1e-9)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a = from, b = to, durationAB = 6.0), from))
        val packet = CameraCommands.gimbalTimedTarget(to, 6.0)!!
        assertEquals(202, packet[0].toInt() and 0xFF)
        assertEquals(8, packet[1].toInt() and 0xFF)
        for (raw in listOf(-80.0, -100.0)) {
            val invalid = from.copy(yawDeg = GimbalWaypoint.unwrapYaw(raw))
            assertFalse(engine.start(GimbalProgram(a = from, b = invalid), from))
            assertEquals(null, CameraCommands.gimbalTimedTarget(invalid, 6.0))
        }
    }

    @Test
    fun finalPositionUsesFreshSettledReports() {
        for ((feedbackDelay, miss, succeeds) in listOf(Triple(0.06, 0.0, true), Triple(0.06, 0.4, false), Triple(0.5, 0.0, false))) {
            val origin = GimbalWaypoint(0.0, 0.0, 1.0, -175.0)
            val end = GimbalWaypoint(100.0, 20.0, 1.0, 165.0)
            val engine = GimbalMoveEngine()
            assertTrue(engine.start(GimbalProgram(a = origin, b = end, durationAB = 5.0), origin))
            var reported = origin
            var reportAt = 0.0
            var motionAt: Double? = null
            for (step in 1..800) {
                val now = step * 0.01
                if (step % 10 == 6) {
                    motionAt?.let { start ->
                        reported = GimbalMoveEngine.lerp(origin, end, (now - feedbackDelay - start) / 5)
                        if (now - feedbackDelay >= start + 5) reported = reported.copy(yawDeg = reported.yawDeg - miss)
                    }
                    reportAt = now
                }
                val out = engine.tick(0.01, reported, now - reportAt)
                if (out?.target != null) motionAt = now
                if (out?.finished == true) break
            }
            assertFalse(engine.running)
            assertEquals(succeeds, engine.failure == null, "delay=$feedbackDelay miss=$miss failure=${engine.failure}")
        }
    }

    @Test
    fun overlayExtrapolatesMeasuredMotionOnlyWithinItsShortHorizon() {
        val motion = GimbalOverlayMotion()
        val first = GimbalWaypoint(10.0, 0.0, 2.0, -170.0)
        motion.observe(first, 1.0)
        motion.observe(first.copy(yawDeg = 12.0, pitchDeg = 1.0), 1.1)
        val halfway = motion.pose(1.15)!!
        assertEquals(13.0, halfway.yawDeg, 1e-9)
        assertEquals(1.5, halfway.pitchDeg, 1e-9)
        assertEquals(null, halfway.nativePitchDeg)
        assertEquals(14.0, motion.pose(1.3)!!.yawDeg, 1e-9)
        assertEquals(null, motion.pose(1.401))
        motion.reset()
        assertEquals(null, motion.pose(1.2))
    }

    @Test
    fun overlayUsesWrappedMeasuredYawAndIgnoresInvalidOrReorderedSamples() {
        val motion = GimbalOverlayMotion()
        motion.observe(GimbalWaypoint(179.0, 0.0, 1.0), 1.0)
        motion.observe(GimbalWaypoint(-179.0, 0.0, 1.0), 1.1)
        motion.observe(GimbalWaypoint(0.0, 0.0, 1.0), 1.05)
        motion.observe(GimbalWaypoint(Double.NaN, 0.0, 1.0), 1.2)
        assertEquals(-178.0, motion.pose(1.15)!!.yawDeg, 1e-9)
        assertEquals(null, motion.pose(1.05))
        assertEquals(null, motion.pose(Double.NaN))
    }

    private fun curveProgram(smoothness: Double) = GimbalProgram(
        a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0),
        b = GimbalWaypoint(30.0, 0.0, 1.0, 175.0),
        c = GimbalWaypoint(30.0, 20.0, 1.0, 155.0),
        durationAB = 3.0, durationBC = 2.0, smoothness = smoothness,
    )

    @Test
    fun curveKeepsEndpointsAndRoundsBWithContinuousVelocity() {
        assertEquals(null, GimbalProgramCurve.create(curveProgram(0.0)))
        val program = curveProgram(1.0)
        val wide = GimbalProgramCurve.create(program)!!
        val tight = GimbalProgramCurve.create(curveProgram(0.2))!!
        assertEquals(program.a, wide.position(0.0))
        assertEquals(program.c, wide.position(5.0))
        assertTrue(GimbalMoveEngine.angularDistance(wide.position(3.0), program.b!!) >
            GimbalMoveEngine.angularDistance(tight.position(3.0), program.b))
        assertEquals(27.5, wide.position(3.0).yawDeg, 1e-9)
        assertEquals(2.5, wide.position(3.0).pitchDeg, 1e-9)
        assertTrue(wide.samples().all { it == it.clamped() })
        val epsilon = 0.0001
        for (time in listOf(2.0, 4.0)) {
            val left = wide.position(time - epsilon)
            val mid = wide.position(time)
            val right = wide.position(time + epsilon)
            assertTrue(abs((mid.yawDeg - left.yawDeg) / epsilon -
                (right.yawDeg - mid.yawDeg) / epsilon) < 0.001)
            assertTrue(abs((mid.pitchDeg - left.pitchDeg) / epsilon -
                (right.pitchDeg - mid.pitchDeg) / epsilon) < 0.001)
        }
    }

    @Test
    fun curveStreamsThroughBAndSchedulesFinalTargetBeforeDeadline() {
        val program = curveProgram(1.0)
        val engine = GimbalMoveEngine()
        var live = program.a!!
        var start = live
        var target = live
        var motionAt = 0.0
        val sends = mutableListOf<Pair<Double, GimbalWaypoint>>()
        assertTrue(engine.start(program, live))
        for (step in 1..800) {
            val now = step * 0.01
            live = GimbalMoveEngine.lerp(start, target, (now - motionAt) / 0.1)
            val out = engine.tick(0.01, live) ?: break
            out.target?.let {
                assertEquals(0.1, out.duration)
                assertEquals(it, it.clamped())
                sends += now to it
                start = live
                target = it
                motionAt = now
            }
            if (out.finished) break
        }
        assertEquals(null, engine.failure)
        assertEquals("DONE", engine.readout(live)?.phase)
        assertEquals(99, sends.size)
        assertEquals(4.9, sends.last().first - sends.first().first, 1e-8)
        assertEquals(program.c, sends.last().second)
        sends.zipWithNext().forEach { (first, second) ->
            assertEquals(0.05, second.first - first.first, 1e-8)
        }
        assertFalse(sends.any { it.second == program.b })
    }

    @Test
    fun curveStopsAfterStalledScheduler() {
        val program = curveProgram(1.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(program, program.a!!))
        repeat(200) { engine.tick(0.01, program.a) }
        val late = engine.tick(0.09, program.a)
        assertEquals(true, late?.stop)
        assertEquals(null, late?.target)
    }
    @Test
    fun schedulerCannotSkipFinalC() {
        val program = curveProgram(1.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(program, program.a!!))
        repeat(689) { engine.tick(0.01, program.a) }
        val late = engine.tick(0.11, program.c!!)
        assertEquals(true, late?.stop)
        assertEquals(null, late?.target)
    }
    @Test
    fun boundaryFitsBoundedFeedbackDelayWithoutWideningPositionTolerance() {
        data class Case(val delay: Double, val miss: Double, val succeeds: Boolean,
            val lateOnly: Boolean = false, val fast: Boolean = false)
        for ((delay, miss, succeeds, lateOnly, fast) in listOf(Case(0.06, 0.0, true), Case(0.12, 0.0, true),
            Case(0.06, 0.4, false), Case(0.3, 0.0, false), Case(0.06, 0.4, false, lateOnly = true),
            Case(0.0605, 0.0, true, fast = true))) {
            val origin = GimbalWaypoint(if (fast) 0.0 else 20.0, 0.0, 1.0, 175.0)
            val middle = GimbalWaypoint(if (fast) 200.0 else 60.0, 0.0, 1.0, 175.0)
            val end = GimbalWaypoint(if (fast) 0.0 else 100.0, 0.0, 1.0, 175.0)
            val engine = GimbalMoveEngine()
            val duration = if (fast) 0.5 else 2.0
            assertTrue(engine.start(GimbalProgram(origin, middle, end, duration, duration), origin))
            data class Segment(val at: Double, val from: GimbalWaypoint, val to: GimbalWaypoint, val duration: Double)
            val segments = mutableListOf(Segment(0.0, origin, origin, 1.0))
            fun physical(time: Double): GimbalWaypoint {
                val leg = segments.lastOrNull { it.at <= time } ?: segments[0]
                return GimbalMoveEngine.lerp(leg.from, leg.to, (time - leg.at) / leg.duration)
            }
            var reported = origin
            var reportAt = 0.0
            for (step in 1..800) {
                val now = step * 0.01
                if (step % 10 == 6) {
                    reported = physical(now - delay)
                    if (now >= 3.7 && (!lateOnly || now in 4.2..4.3)) {
                        reported = reported.copy(nativePitchDeg = 175 + miss)
                    }
                    reportAt = now
                }
                val out = engine.tick(0.01, reported, now - reportAt)
                out?.target?.let { segments += Segment(now, physical(now), it, out.duration) }
                if (out?.finished == true) break
            }
            assertFalse(engine.running)
            assertEquals(succeeds, engine.failure == null, "delay=$delay miss=$miss lateOnly=$lateOnly fast=$fast")
        }
    }
}
