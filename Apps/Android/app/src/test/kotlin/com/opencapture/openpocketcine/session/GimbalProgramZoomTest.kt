package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GimbalProgramZoomTest {
    private val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
    private val b = GimbalWaypoint(20.0, 0.0, 3.0, 175.0)
    private val c = GimbalWaypoint(20.0, 20.0, 2.0, 155.0)
    private val program = GimbalProgram(a, b, c, durationAB = 1.0, durationBC = 2.0, loop = true)
    private val pro = CameraModel("Osmo Pocket 4 Pro")
    private val ready = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0)

    @Test fun onlyDifferentSavedZoomAmountsEnableAutomaticZoom() {
        assertFalse(GimbalProgram().changesZoom)
        assertFalse(program.copy(b = b.copy(zoom = 1.0), c = null).changesZoom)
        assertFalse(program.copy(b = b.copy(zoom = 1.0 + 0.5e-6), c = null).changesZoom)
        assertTrue(program.changesZoom)
        assertTrue(program.copy(b = b.copy(zoom = 1.0)).changesZoom)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(program.copy(b = b.copy(zoom = 1.0), c = null), a))
        assertNull(engine.programmedZoomTarget)
    }

    @Test fun zoomVisitsBExactlyWithClippedLookAheadAndResumeUsesMeasuredZoom() {
        val path = GimbalZoomPath(program)
        assertEquals(1.1, path.position(0.0), 1e-9)
        assertEquals(3.0, path.position(0.97), 1e-9)
        assertEquals(2.975, path.position(1.0), 1e-9)
        assertEquals(2.0, path.position(3.0), 1e-9)
        val remaining = path.remaining(1.23, 1.7, quantized = true)
        assertEquals(1.8, remaining.duration, 1e-9)
        assertEquals(1.7 + 0.3 * 0.05 / 1.8, remaining.position(0.0), 1e-9)
        assertEquals(1.77, path.remaining(1.23, 1.7, quantized = false).duration, 1e-9)
        val nearB = path.remaining(0.96, 1.7, quantized = false)
        assertEquals(2.04, nearB.duration, 1e-9)
        assertEquals(0.04, nearB.legs.first().duration, 1e-9)
        assertEquals(3.0, nearB.position(0.0), 1e-9)
    }

    @Test fun engineZoomTracksExactAndSmoothLoopPassesAndRestoresFullPathAfterPause() {
        for (smoothness in listOf(0.0, 1.0)) {
            val saved = program.copy(smoothness = smoothness)
            val engine = GimbalMoveEngine()
            assertTrue(engine.start(saved, a))
            var now = 0.0
            var origin = a
            var target = a
            var motionAt = 0.0
            var motionDuration = 1.0
            fun physical() = GimbalMoveEngine.lerp(origin, target, (now - motionAt) / motionDuration)
            var pass = -1
            var passAt = 0.0
            var expected = GimbalZoomPath(saved)
            var zoomAt = 0.0
            var paused = false
            var resumeCommand = false
            repeat(1_500) {
                now += 0.01
                if (resumeCommand) {
                    zoomAt += 0.01
                    resumeCommand = false
                }
                val live = physical()
                val before = engine.readout(live)!!
                val out = engine.tick(0.01, live)!!
                val after = engine.readout(live)!!
                val turn = (before.label == "B→C" && after.label == "C→B") ||
                    (before.label == "B→A" && after.label == "A→B")
                if ((before.phase == "HOLD" && after.phase == "RUN") || turn) {
                    pass++
                    passAt = now
                    zoomAt = now
                    expected = if (pass % 2 == 0) GimbalZoomPath(saved) else
                        GimbalZoomPath(saved.copy(a = c, c = a, durationAB = 2.0, durationBC = 1.0))
                }
                out.target?.let {
                    origin = live
                    target = it
                    motionAt = now
                    motionDuration = out.duration
                }
                assertNull(engine.failure, "smoothness=$smoothness time=$now")
                val crossedB = (before.label == "A→B" && after.label == "B→C") ||
                    (before.label == "C→B" && after.label == "B→A")
                val expectedZoom = when {
                    pass < 0 -> a.zoom
                    crossedB -> b.zoom
                    turn -> if (pass % 2 == 1) c.zoom else a.zoom
                    else -> expected.position(now - zoomAt)
                }
                assertEquals(expectedZoom, engine.consumeProgrammedZoomTarget()!!, 1e-7)
                if (!paused && pass == 1 && now - passAt >= 0.43 - 1e-9) {
                    val measured = live.copy(zoom = 1.7)
                    assertTrue(engine.pause(measured))
                    assertNull(engine.programmedZoomTarget)
                    expected = expected.remaining(now - zoomAt, measured.zoom, quantized = smoothness == 0.0)
                    zoomAt = now
                    assertTrue(engine.resume(measured))
                    assertEquals(expected.position(0.0), engine.programmedZoomTarget!!, 1e-7)
                    origin = measured
                    target = measured
                    motionAt = now
                    paused = true
                    resumeCommand = true
                }
            }
            assertTrue(pass >= 3)
            assertTrue(paused)
            engine.cancel()
            assertNull(engine.programmedZoomTarget)
        }
    }

    @Test fun dlog2UnknownColorMissingFeedbackAndFormatCeilingBlockOnlyZoomChangingMoves() {
        for (recording in listOf(false, true)) {
            val status = ready.copy(colorMode = CameraCommands.COLOR_DLOG2, isRecording = recording)
            assertEquals("Zoom moves are unavailable in D-Log2", nativeProgramZoomFailure(program, pro, status))
            assertNull(nativeProgramZoomFailure(program.copy(b = b.copy(zoom = 1.0), c = null), pro, status))
        }
        assertEquals("Wait for camera color mode before a zoom move", nativeProgramZoomFailure(program, pro, ready.copy(colorMode = -1)))
        assertEquals("Wait for camera color mode before a zoom move", nativeProgramZoomFailure(program, pro, ready.copy(colorMode = 0x7F)))
        assertEquals("Wait for camera zoom feedback", nativeProgramZoomFailure(program, pro, ready.copy(zoomFactor = null)))
        assertEquals("Saved zoom exceeds the current FORMAT limit",
            nativeProgramZoomFailure(program, CameraModel("Osmo Pocket 3"), ready.copy(resolutionCode = 0x10)))
        assertNull(nativeProgramZoomFailure(program, pro, ready))
        assertEquals("Wait for camera zoom feedback", nativeProgramZoomFailure(program, pro,
            ready.copy(shootingMode = CameraCommands.SHOOT_SLOWMO, zoomFactor = 12.0)))
        assertEquals("Wait for camera zoom feedback", nativeProgramZoomFailure(program, pro,
            ready.copy(shootingMode = CameraCommands.SHOOT_SLOWMO), target = 3.1))
    }

    @Test fun acceptedLateTurnaroundRetainsEndpointUntilTheNextAdmittedLensSample() {
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true), a))
        repeat(294) { engine.tick(0.01, a) }
        assertTrue(engine.consumeProgrammedZoomTarget()!! < 3.0)
        val out = engine.tick(0.065, a)!!
        assertFalse(out.finished)
        assertEquals("B→A", engine.readout(a)!!.label)
        assertEquals(3.0, engine.programmedZoomTarget)
        engine.tick(0.01, a)
        assertEquals(3.0, engine.consumeProgrammedZoomTarget())
        assertTrue(engine.programmedZoomTarget!! < 3.0)
        assertNull(engine.failure)
    }

    @Test fun zoomResumeNeedsItsOwnFreshStableReceiptsAndCannotAccumulateDrift() {
        fun lens(position: Int): DumlFrame {
            val payload = ByteArray(16).also { it[14] = position.toByte(); it[15] = (position shr 8).toByte() }
            return DumlFrame(0, 0, 1, 0, 0, 0x99, StatusExtras.packSubscribe("cam_lens_state", payload))
        }
        val attitude = DumlFrame(0, 0, 1, 0, 4, 5, ByteArray(22))
        var observed = NativeProgramZoomObservation(ready).observing(lens(217), pro, 1.0).notePause(1.1)
        observed = observed.observing(attitude, pro, 1.5)
        assertEquals(1.0, observed.receivedAt)
        assertFalse(observed.canResume(1.5))
        observed = observed.observing(lens(217), pro, 1.6)
        observed = observed.observing(lens(218), pro, 1.7)
        observed = observed.observing(lens(219), pro, 1.8)
        assertFalse(observed.canResume(1.81), "Two one-tick drifts must reset the fixed anchor")
        observed = observed.observing(lens(219), pro, 2.01)
        assertTrue(observed.canResume(2.01))
        val fov = DumlFrame(0, 0, 1, 0, 0, 0x99,
            StatusExtras.packSubscribe("cam_fov", byteArrayOf(0xFF.toByte(), 0x2F, 0, 0)))
        observed = observed.observing(fov, pro, 2.4).observing(attitude, pro, 2.5)
        assertEquals(2.01, observed.receivedAt, "FOV cannot refresh a preferred lens measurement")
        assertFalse(observed.canResume(2.5))
        var fovOnly = NativeProgramZoomObservation(ready).notePause(1.0)
        fovOnly = fovOnly.observing(fov, pro, 1.1).observing(fov, pro, 1.31)
        assertTrue(fovOnly.canResume(1.31))
        var gap = NativeProgramZoomObservation(ready).notePause(1.0)
        gap = gap.observing(lens(651), pro, 1.1).observing(lens(651), pro, 5.0)
        assertFalse(gap.canResume(5.0), "A fresh report after a long gap must begin a new stable interval")
        gap = gap.observing(lens(651), pro, 5.21)
        assertTrue(gap.canResume(5.21))
        val paused = NativeZoomPauseStability()
        paused.reset(1.0)
        paused.observe(NativeGimbalFeedback(a.copy(zoom = 3.0), 1.1, 1.1))
        paused.observe(NativeGimbalFeedback(a.copy(zoom = 3.0), 5.0, 5.0))
        assertFalse(paused.ready(5.0))
        paused.observe(NativeGimbalFeedback(a.copy(zoom = 3.0), 5.21, 5.21))
        assertTrue(paused.ready(5.21))
    }

    @Test fun receivedStatusChangesTakeEffectBeforeAnyUiMerge() {
        fun subscribe(name: String, value: ByteArray) = DumlFrame(0, 0, 1, 0, 0, 0x99, StatusExtras.packSubscribe(name, value))
        var status = ready
        status = nativeProgramZoomStatus(subscribe("cam_image_effect", byteArrayOf(0, 0, 0x41, 0, 0)), status, pro)
        assertEquals("Zoom moves are unavailable in D-Log2", nativeProgramZoomFailure(program, pro, status))
        status = nativeProgramZoomStatus(subscribe("cam_image_effect", byteArrayOf(0, 0, 0x3F, 0, 0)), status, pro)
        val lens = ByteArray(16).also { it[14] = 0x8B.toByte(); it[15] = 0x02 }
        status = nativeProgramZoomStatus(subscribe("cam_lens_state", lens), status, pro)
        assertEquals(3.0, status.zoomFactor)
        val mode = ByteArray(58).also { it[57] = CameraCommands.SHOOT_SLOWMO.toByte() }
        status = nativeProgramZoomStatus(DumlFrame(0, 0, 1, 0, 2, 0x80, mode), status, pro)
        assertEquals("Saved zoom exceeds the current FORMAT limit",
            nativeProgramZoomFailure(program.copy(b = b.copy(zoom = 6.0)), pro, status))
        status = nativeProgramZoomStatus(subscribe("cam_video_param_v2", byteArrayOf(0x10, 0x02)), status, pro)
        assertEquals(0x10, status.resolutionCode)
        val pitch = ByteArray(22)
        val measured = NativeGimbalFeedback.from(DumlFrame(0, 0, 1, 0, 4, 5, pitch), 12.0, status.zoomFactor!!)!!
        assertTrue(abs(measured.pose.zoom - 3.0) < 1e-9)
    }

    @Test fun nativeResumeAllowsTheMeasuredLensCadenceButStillNeedsRecentStableFeedback() {
        val payload = ByteArray(16).also { it[14] = 0x8B.toByte(); it[15] = 0x02 }
        val lens = DumlFrame(0, 0, 1, 0, 0, 0x99, StatusExtras.packSubscribe("cam_lens_state", payload))
        var native = NativeProgramZoomObservation(ready).notePause(1.0)
        native = native.observing(lens, pro, 1.2).observing(lens, pro, 1.6)
        assertTrue(native.canResume(1.7), "Two distinct 2.5 Hz lens receipts can prove a settled zoom")
        assertFalse(native.canResume(1.91), "Resume still needs a receipt no older than 300 ms")
        native = native.observing(lens, pro, 2.5)
        assertFalse(native.canResume(2.5), "A gap beyond 850 ms resets stability")
        val other = NativeProgramZoomObservation(ready).notePause(1.0)
            .observing(lens, CameraModel("Osmo Pocket 3"), 1.2)
            .observing(lens, CameraModel("Osmo Pocket 3"), 1.6)
        assertFalse(other.canResume(1.6), "Unmeasured bodies retain the previous continuity threshold")
        val stability = NativeZoomPauseStability(maximumGap = 0.85)
        stability.reset(1.0)
        stability.observe(NativeGimbalFeedback(a.copy(zoom = 3.0), 1.2, 1.2))
        stability.observe(NativeGimbalFeedback(a.copy(zoom = 3.0), 1.6, 1.6))
        assertTrue(stability.ready(1.7))
        stability.observe(NativeGimbalFeedback(a.copy(zoom = 3.0), 2.5, 2.5))
        assertFalse(stability.ready(2.5))
    }
}
