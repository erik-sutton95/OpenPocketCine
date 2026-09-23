package com.opencapture.openpocketcine.session

import java.util.PriorityQueue
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class NativeGimbalProgramRunnerTest {
    private class Tx {
        data class Task(val at: Double, val order: Int, val action: () -> Unit)
        val pending = PriorityQueue<Task>(compareBy<Task> { it.at }.thenBy { it.order })
        var now = 0.0
        private var order = 0
        fun schedule(delay: Double, action: () -> Unit) { pending += Task(now + delay, order++, action) }
        fun through(until: Double) {
            while (pending.peek()?.at?.let { it <= until } == true) {
                val task = pending.remove()
                now = maxOf(now, task.at)
                task.action()
            }
            now = maxOf(now, until)
        }
    }

    private val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
    private val b = GimbalWaypoint(30.0, 0.0, 1.0, 175.0)
    private val c = GimbalWaypoint(30.0, 20.0, 1.0, 155.0)

    @Test
    fun pauseFencesTimersAndResumeNeedsStableReceiptsWithoutCountdown() {
        val tx = Tx()
        var sample = NativeGimbalFeedback(a, 0.0)
        val sent = mutableListOf<Pair<Double, GimbalWaypoint>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { point, _ ->
            sent += tx.now to point; true
        }, { stops++ })
        fun receive() {
            sample = NativeGimbalFeedback(a, tx.now)
            if (tx.now < 4.0) tx.schedule(0.05) { receive() }
        }
        receive()
        val token = runner.start(GimbalProgram(a, b, durationAB = 4.0)) { updates += it }
        tx.through(2.5)
        assertEquals(1, sent.size)
        val oldProgress = updates.last()
        assertTrue(runner.pause(token))
        assertFalse(runner.isCurrentProgress(oldProgress))
        tx.through(2.51)
        assertEquals(1, stops)
        assertTrue(updates.last().paused)
        assertTrue(runner.resume(token))
        tx.through(2.52)
        assertTrue(updates.last().paused)
        assertTrue(updates.last().note != null)
        tx.through(2.9)
        assertEquals(1, sent.size, "paused timers cannot send another target")
        val pausedProgress = updates.last()
        assertTrue(runner.resume(token))
        tx.through(2.91)
        assertEquals(2, sent.size, "stable resume sends immediately without preparation/countdown")
        assertFalse(updates.last().paused)
        assertFalse(runner.isCurrentProgress(pausedProgress))
        assertTrue(runner.pause(token))
        tx.through(2.92)
        assertTrue(runner.cancel(token))
        assertFalse(runner.resume(token))
        tx.through(4.0)
        assertEquals(2, sent.size)
    }

    @Test
    fun continuousCurveCompletesWhileUiNeverDrainsItsCallbackQueue() {
        val tx = Tx()
        var sample = NativeGimbalFeedback(a, 0.0)
        var origin = a
        var target = a
        var motionAt = 0.0
        var duration = 1.0
        fun physical() = GimbalMoveEngine.lerp(origin, target, (tx.now - motionAt) / duration)
        fun receive() {
            sample = NativeGimbalFeedback(physical(), tx.now)
            if (tx.now < 8.0) tx.schedule(0.01) { receive() }
        }
        val sends = mutableListOf<Pair<Double, GimbalWaypoint>>()
        val queuedUi = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { next, seconds ->
            origin = physical()
            target = next
            motionAt = tx.now
            duration = seconds
            sends += tx.now to next
            true
        }, { stops++ })
        receive()
        runner.start(GimbalProgram(a, b, c, 3.0, 2.0, 1.0)) { queuedUi += it }
        tx.through(8.0) // No UI callbacks are consumed during the entire take.
        assertEquals(99, sends.size)
        assertEquals(4.9, sends.last().first - sends.first().first, 0.00001)
        assertEquals(c, sends.last().second)
        assertEquals(0, stops)
        assertTrue(queuedUi.last().finished)
        assertEquals(null, queuedUi.last().failure)
        assertEquals("DONE", queuedUi.last().readout?.phase)
        assertTrue(queuedUi.size <= 40, "progress must stay within 5 Hz plus start/finish")
    }

    @Test
    fun startReadsNewFeedbackAfterPreparationAndRejectsOldReceipt() {
        val tx = Tx()
        var sample = NativeGimbalFeedback(a, 0.0)
        var stops = 0
        val sent = mutableListOf<GimbalWaypoint>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { point, _ ->
            sent += point; true
        }, { stops++ })
        // A blocked preparation queue advances clock before the start task can run.
        tx.schedule(0.0) { tx.now = 1.0 }
        runner.start(GimbalProgram(a, b)) { updates += it }
        tx.through(1.5)
        assertTrue(sent.isEmpty())
        assertTrue(updates.last().finished)
        assertTrue(updates.last().failure != null)
        assertEquals(1, stops)
        // A fresh post-preparation observation replaces the old UI-cached A pose.
        sample = NativeGimbalFeedback(c, tx.now)
        runner.start(GimbalProgram(a, b)) { updates += it }
        tx.schedule(0.24) { sample = NativeGimbalFeedback(c, tx.now) }
        tx.through(1.9)
        assertEquals(a, sent.first())
        assertEquals("APPROACH", updates.last().readout?.phase)
    }

    @Test
    fun cancelBeforePreparationFencesStartAndStopPrecedesManualCommand() {
        val tx = Tx()
        val events = mutableListOf<String>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now) }, { _, _ -> events += "target"; true }, { events += "stop" })
        val token = runner.start(GimbalProgram(a, b)) { events += "progress" }
        assertTrue(runner.cancel(token))
        assertFalse(runner.cancel(token))
        tx.schedule(0.0) { events += "manual" }
        tx.through(1.0)
        assertEquals(listOf("stop", "manual"), events)
    }

    @Test
    fun oldCancellationCannotStopNewRunAndMissingFeedbackStopsActiveRun() {
        val tx = Tx()
        var sample: NativeGimbalFeedback? = NativeGimbalFeedback(a, 0.0)
        var stops = 0
        val progress = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule, { sample }, { _, _ -> true }, { stops++ })
        val old = runner.start(GimbalProgram(a, b)) { progress += it }
        runner.cancel(old)
        val current = runner.start(GimbalProgram(a, b)) { progress += it }
        assertFalse(runner.cancel(old))
        tx.schedule(0.24) { sample = NativeGimbalFeedback(a, tx.now) }
        tx.through(0.26)
        assertEquals(current, progress.last().token)
        sample = null
        tx.through(0.4)
        assertTrue(progress.last().finished)
        assertTrue(progress.last().failure != null)
        assertEquals(2, stops)
    }

    @Test
    fun directWireFeedbackRetainsSamePacketRawPitchAndReceipt() {
        val bytes = ByteArray(22)
        fun i16(at: Int, value: Int) {
            bytes[at] = value.toByte()
            bytes[at + 1] = (value shr 8).toByte()
        }
        i16(0, -1718)
        i16(4, 330)
        i16(20, 89)
        val frame = DumlFrame(0, 0, 1, 0, 4, 5, bytes)
        val sample = NativeGimbalFeedback.from(frame, 12.34)!!
        assertEquals(12.34, sample.receivedAt)
        assertEquals(-171.8, sample.pose.nativePitchDeg)
        assertEquals(-8.9, sample.pose.pitchDeg)
        assertEquals(33.0, sample.pose.yawDeg)
        assertEquals(null, NativeGimbalFeedback.from(frame.copy(payload = bytes.copyOf(21)), 12.35))
    }
    @Test
    fun rebindInterruptsPendingPreparationAndActiveTimerWithoutStoppingReplacementSocket() {
        for (duringPreparation in listOf(true, false)) {
            val tx = Tx()
            val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
            var targets = 0
            var stops = 0
            val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                { NativeGimbalFeedback(a, tx.now) }, { _, _ -> targets++; true }, { stops++ })
            runner.start(GimbalProgram(a, b)) { updates += it }
            tx.through(if (duringPreparation) 0.1 else 0.5)
            runner.interrupt()
            tx.through(3.0)
            assertEquals(0, targets)
            assertEquals(0, stops, "rebind cleanup must not STOP a replacement connection")
            assertTrue(updates.last().finished)
            assertEquals("Move interrupted — camera connection changed", updates.last().failure)
        }
    }

    @Test
    fun rejectedSocketWriteStopsRunInsteadOfClaimingTargetWasDispatched() {
        val tx = Tx()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var rejectedTargets = 0
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(c, tx.now) }, { _, _ -> rejectedTargets++; false }, { stops++ })
        runner.start(GimbalProgram(a, b)) { updates += it }
        tx.through(1.0)
        assertEquals(1, rejectedTargets)
        assertEquals(1, stops)
        assertTrue(updates.last().finished)
        assertTrue(updates.last().failure != null)
    }
    @Test
    fun lastMileYawGateRejectsLongShortcutAndExactlyHalfTurn() {
        val selfie = NativeGimbalFeedback(a.copy(yawDeg = 225.0), 1.0)
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 28.7), selfie, 1.1))
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 45.0), selfie, 1.1))
        assertTrue(nativeGimbalTargetIsSafe(a.copy(yawDeg = 45.1), selfie, 1.1))
        assertTrue(nativeGimbalTargetIsSafe(a.copy(yawDeg = 126.85), selfie, 1.1))
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 126.85), selfie, 1.31))
        assertFalse(nativeGimbalTargetIsSafe(a.copy(yawDeg = 260.0), selfie, 1.1))
        assertFalse(nativeGimbalTargetIsSafe(a, selfie.copy(pose = a.copy(pitchDeg = -60.0)), 1.1))
    }

    @Test
    fun loopKeepsOneTokenAndCancelFencesTargetsBeforeOrAfterTurnaround() {
        for (cancelAfterReturn in listOf(false, true)) {
            val tx = Tx()
            var origin = a
            var target = a
            var motionAt = 0.0
            var duration = 1.0
            fun physical() = GimbalMoveEngine.lerp(origin, target, (tx.now - motionAt) / duration)
            val sends = mutableListOf<Pair<Double, GimbalWaypoint>>()
            val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
            val events = mutableListOf<String>()
            val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                { NativeGimbalFeedback(physical(), tx.now) }, { next, seconds ->
                    origin = physical()
                    target = next
                    motionAt = tx.now
                    duration = seconds
                    sends += tx.now to next
                    events += "target"
                    true
                }, { events += "stop" })
            val token = runner.start(GimbalProgram(a, b, durationAB = 1.0, loop = true)) { updates += it }
            // Preparation + A hold + one-second move; reverse is dispatched at 3.25s.
            tx.through(if (cancelAfterReturn) 3.3 else 3.2)
            assertEquals(if (cancelAfterReturn) listOf(b, a) else listOf(b), sends.map { it.second })
            assertTrue(updates.all { it.token == token && !it.finished && it.failure == null })
            val countAtCancel = sends.size
            assertTrue(runner.cancel(token))
            tx.schedule(0.0) { events += "manual" }
            tx.through(10.0)
            assertEquals(countAtCancel, sends.size)
            assertEquals(listOf("stop", "manual"), events.takeLast(2))
            assertFalse(runner.resume(token))
        }
    }

    @Test
    fun loopingRunnerReversesWithoutAnotherPreparationCountdownOrHold() {
        val tx = Tx()
        var origin = a
        var target = a
        var motionAt = 0.0
        var duration = 1.0
        fun physical() = GimbalMoveEngine.lerp(origin, target, (tx.now - motionAt) / duration)
        val sends = mutableListOf<Pair<Double, GimbalWaypoint>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(physical(), tx.now) }, { next, seconds ->
                origin = physical()
                target = next
                motionAt = tx.now
                duration = seconds
                sends += tx.now to next
                true
            }, { stops++ })
        val token = runner.start(GimbalProgram(a, b, durationAB = 1.0, loop = true)) { updates += it }
        tx.through(13.0)
        assertTrue(sends.count { it.second == b } >= 3)
        assertTrue(updates.all { it.token == token && !it.finished && it.failure == null })
        assertEquals(0, stops)
        val firstReturn = sends.first { it.second == a }.first
        val nextTake = sends.first { it.first > firstReturn && it.second == b }.first
        assertEquals(1.0, nextTake - firstReturn, 1e-8, "Turnaround adds no verification hold")
        sends.zipWithNext().forEach { (first, next) ->
            assertEquals(if (first.second == a) b else a, next.second)
            assertEquals(1.0, next.first - first.first, 1e-8)
        }
        assertTrue(updates.size <= 67, "Loop progress retains the existing 5 Hz publication bound")
        assertTrue(runner.cancel(token))
        tx.through(13.1)
        assertEquals(1, stops)
    }

    @Test fun zoomPreparationAndLoopUseDistinctTwentyHzLensTargetsWithoutMoreUiProgress() {
        val tx = Tx()
        val zooms = mutableListOf<Pair<Double, Int>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var measuredZoom = 1.7
        val program = GimbalProgram(a, a.copy(zoom = 3.0), a.copy(zoom = 2.0), 1.0, 2.0, loop = true)
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a.copy(zoom = measuredZoom), tx.now) }, { _, _ -> true }, {},
            sendZoom = { lens, _ ->
                zooms += tx.now to lens
                measuredZoom = CamFov.factorFromLens(lens)!!
                true
            })
        runner.start(program) { updates += it }
        tx.through(2.24)
        assertEquals(listOf(0.25 to CamFov.LENS_1X), zooms, "Preparation applies A once; hold is deduplicated")
        tx.through(11.3)
        zooms.zipWithNext().forEach { (first, next) ->
            assertTrue(next.first - first.first >= 0.05 - 1e-8)
            assertTrue(first.second != next.second)
        }
        for ((time, factor) in listOf(3.2 to 3.0, 5.2 to 2.0, 7.2 to 3.0, 8.2 to 1.0, 9.2 to 3.0, 11.2 to 2.0)) {
            assertTrue(zooms.any { kotlin.math.abs(it.first - time) < 1e-7 && it.second == CamFov.pinchLens(factor) },
                "Saved endpoint $factor must be requested 50 ms before $time + 50 ms")
        }
        assertTrue(updates.size <= 58, "Zoom adds no 20 Hz UI callbacks")
        assertTrue(updates.none { it.finished || it.failure != null })
    }

    @Test fun pauseResumeUsesMeasuredZoomAndCancellationFencesEveryLensCallback() {
        val tx = Tx()
        var measuredZoom = 1.0
        val zooms = mutableListOf<Pair<Double, Int>>()
        val events = mutableListOf<String>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a.copy(zoom = measuredZoom), tx.now, zoomReceivedAt = tx.now) }, { _, _ -> true }, { events += "gimbal stop" },
            sendZoom = { lens, _ -> zooms += tx.now to lens; measuredZoom = CamFov.factorFromLens(lens)!!; true },
            stopZoom = { events += "zoom stop" })
        val token = runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true)) {}
        tx.through(2.65)
        assertTrue(runner.pause(token))
        tx.through(2.66)
        assertEquals(1, events.count { it == "zoom stop" })
        val pausedCount = zooms.size
        measuredZoom = 1.7
        tx.through(3.1)
        assertEquals(pausedCount, zooms.size)
        assertTrue(runner.resume(token))
        tx.through(3.11)
        assertEquals(CamFov.pinchLens(1.7 + (3.0 - 1.7) * 0.05 / 0.6), zooms.last().second)
        val beforeCancel = zooms.size
        assertTrue(runner.cancel(token))
        tx.schedule(0.0) { events += "manual zoom" }
        tx.through(10.0)
        assertEquals(beforeCancel, zooms.size)
        assertEquals(listOf("zoom stop", "gimbal stop", "manual zoom"), events.takeLast(3))
        zooms.zipWithNext().forEach { (first, next) -> assertTrue(next.first - first.first >= 0.05 - 1e-8) }
    }

    @Test fun resumeCombinesStableAttitudeWithNewerVerifiedLensFeedback() {
        val tx = Tx()
        var measuredZoom = 2.0
        var attitudeAt: Double? = null
        var lastAttitudeAt = 0.0
        var lensAt: Double? = null
        val zooms = mutableListOf<Int>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            {
                lastAttitudeAt = attitudeAt ?: tx.now
                NativeGimbalFeedback(a.copy(zoom = measuredZoom), lastAttitudeAt, lensAt ?: tx.now)
            },
            { _, _ -> true }, {}, sendZoom = { lens, _ -> zooms += lens; true })
        val token = runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true)) { updates += it }
        tx.through(2.60)
        assertTrue(runner.pause(token))
        tx.through(2.86)
        attitudeAt = lastAttitudeAt
        lensAt = 2.86
        // The angular stability proof remains fresh, but the lens changes independently.
        tx.through(2.87)
        measuredZoom = 1.0
        lensAt = 2.87
        tx.through(3.08)
        lensAt = 3.08
        assertTrue(runner.resume(token))
        tx.through(3.081)
        assertFalse(updates.last().paused)
        assertEquals(1.0, updates.last().live?.zoom)
        assertEquals(CamFov.pinchLens(1.0 + (3.0 - 1.0) * 0.05 / 0.7), zooms.last(),
            "Resume must use the newer settled lens value, not the angular sample's cached zoom")
    }

    @Test fun rawColorOrFormatChangeStopsZoomEvenWhileTargetIsDeduplicated() {
        for (recording in listOf(false, true)) {
            for (changeColor in listOf(false, true)) {
                val tx = Tx()
                var status = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0, isRecording = recording)
                val model = CameraModel("Osmo Pocket 4 Pro")
                val program = GimbalProgram(a, a.copy(zoom = 6.0), durationAB = 2.0)
                val zooms = mutableListOf<Int>()
                val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
                var stops = 0
                val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                    { NativeGimbalFeedback(a, tx.now) }, { _, _ -> true }, {},
                    zoomFailure = { nativeProgramZoomFailure(it, model, status) },
                    sendZoom = { lens, _ -> zooms += lens; true }, stopZoom = { stops++ })
                runner.start(program) { updates += it }
                tx.through(0.5)
                status = if (changeColor) status.copy(colorMode = CameraCommands.COLOR_DLOG2)
                    else status.copy(shootingMode = CameraCommands.SHOOT_SLOWMO)
                tx.through(0.6)
                assertEquals(listOf(CamFov.LENS_1X), zooms)
                assertEquals(1, stops)
                assertTrue(updates.last().finished)
                assertEquals(if (changeColor) "Zoom moves are unavailable in D-Log2" else
                    "Saved zoom exceeds the current FORMAT limit", updates.last().failure)
                tx.through(5.0)
                assertEquals(1, zooms.size)
            }
        }
    }

    @Test fun blockedPreparationAndStaleFeedbackNeverEmitFurtherZoom() {
        for (blockedAtStart in listOf(false, true)) {
            val tx = Tx()
            var fresh = true
            var zooms = 0
            var zoomStops = 0
            val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
            val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                { if (fresh) NativeGimbalFeedback(a, tx.now) else null }, { _, _ -> true }, {},
                zoomFailure = { if (blockedAtStart) "Zoom moves are unavailable in D-Log2" else null },
                sendZoom = { _, _ -> zooms++; true }, stopZoom = { zoomStops++ })
            runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0)) { updates += it }
            tx.through(0.5)
            fresh = false
            tx.through(5.0)
            assertEquals(if (blockedAtStart) 0 else 1, zooms)
            assertEquals(if (blockedAtStart) 0 else 1, zoomStops)
            assertTrue(updates.last().finished)
            assertTrue(updates.last().failure != null)
        }
    }

    @Test fun rawColorChangeBeforeFinalVerificationCompletesStillInvalidatesTake() {
        val tx = Tx()
        var status = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0)
        val model = CameraModel("Osmo Pocket 4 Pro")
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now) }, { _, _ -> true }, {},
            zoomFailure = { nativeProgramZoomFailure(it, model, status) }, sendZoom = { _, _ -> true })
        runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0)) { updates += it }
        tx.through(3.545)
        assertTrue(updates.none { it.finished })
        status = status.copy(colorMode = CameraCommands.COLOR_DLOG2)
        tx.through(4.0)
        assertTrue(updates.last().finished)
        assertEquals("Zoom moves are unavailable in D-Log2", updates.last().failure)
    }

    @Test fun highRateZoomTracksLinearABCAndLoopLegsAtFiftyHzWithoutExtraUiProgress() {
        for (smoothness in listOf(0.0, 1.0)) {
            val tx = Tx()
            val commands = mutableListOf<Pair<Double, NativeProgramZoomCommand>>()
            val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
            val events = mutableListOf<String>()
            val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                { NativeGimbalFeedback(a, tx.now, tx.now) }, { _, _ -> true }, { events += "gimbal stop" },
                stopZoom = { events += "zoom stop" }, usesHighRateZoom = true,
                sendNativeZoom = { command, _ -> commands += tx.now to command; true })
            val token = runner.start(GimbalProgram(a, a.copy(zoom = 3.0), a.copy(zoom = 2.0),
                1.1, 1.3, smoothness = smoothness, loop = true)) { updates += it }
            tx.through(2.24)
            assertEquals(listOf<Pair<Double, NativeProgramZoomCommand>>(0.25 to NativeProgramZoomCommand.Position(1.0)), commands)
            tx.through(12.0)
            val tracked = commands.filter { it.second is NativeProgramZoomCommand.Track }
            assertTrue(tracked.size > 400)
            assertEquals(2.27, tracked.first().first, 1e-8, "The first changed target follows RUN by just one sample")
            assertEquals(1.0 + 2.0 * 0.02 / 1.1, (tracked.first().second as NativeProgramZoomCommand.Track).factor, 1e-8)
            val boundaries = listOf(3.35 to 3.0, 4.65 to 2.0, 5.95 to 3.0, 7.05 to 1.0,
                8.15 to 3.0, 9.45 to 2.0, 10.75 to 3.0, 11.85 to 1.0)
            for ((time, command) in tracked) {
                var elapsed = (time - 2.25) % 4.8
                var expected = 1.0
                for ((from, to, duration) in listOf(Triple(1.0, 3.0, 1.1), Triple(3.0, 2.0, 1.3),
                        Triple(2.0, 3.0, 1.3), Triple(3.0, 1.0, 1.1))) {
                    if (elapsed <= duration + 1e-8) { expected = from + (to - from) * (elapsed / duration).coerceIn(0.0, 1.0); break }
                    elapsed -= duration
                }
                val actual = (command as NativeProgramZoomCommand.Track).factor
                assertTrue(kotlin.math.abs(expected - actual) < 1e-7 || boundaries.any {
                    time - it.first in -1e-8..0.02000001 && kotlin.math.abs(actual - it.second) < 1e-8
                }, "time=$time expected=$expected actual=$actual smoothness=$smoothness")
            }
            for ((time, zoom) in boundaries) assertTrue(tracked.any {
                it.first - time in -1e-8..0.02000001 && kotlin.math.abs((it.second as NativeProgramZoomCommand.Track).factor - zoom) < 1e-8
            }, "Every endpoint must be admitted within one sample: $time $zoom")
            tracked.zipWithNext().forEach { (first, next) ->
                assertTrue(next.first - first.first >= 0.02 - 1e-8)
                assertTrue(CamFov.pinchLens((first.second as NativeProgramZoomCommand.Track).factor) !=
                    CamFov.pinchLens((next.second as NativeProgramZoomCommand.Track).factor))
            }
            assertTrue(updates.size <= 61, "Zoom adds no 50 Hz UI callbacks")
            assertTrue(updates.none { it.finished || it.failure != null })
            val count = commands.size
            assertTrue(runner.cancel(token))
            tx.schedule(0.0) { events += "manual" }
            tx.through(14.0)
            assertEquals(count, commands.size)
            assertEquals(listOf("zoom stop", "gimbal stop", "manual"), events)
        }
    }

    @Test fun highRateZoomReachesTheFinalSavedLensBeforeNormalCompletionStopsIt() {
        val tx = Tx()
        val commands = mutableListOf<Pair<Double, NativeProgramZoomCommand>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now, tx.now) }, { _, _ -> true }, {},
            usesHighRateZoom = true, sendNativeZoom = { command, _ -> commands += tx.now to command; true }, stopZoom = { stops++ })
        runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0)) { updates += it }
        tx.through(5.0)
        assertTrue(updates.last().finished)
        assertEquals(null, updates.last().failure)
        assertEquals(NativeProgramZoomCommand.Track(3.0), commands.last().second)
        assertTrue(commands.last().first in 3.25 - 1e-8..3.27 + 1e-8)
        assertEquals(1, stops)
    }

    @Test fun duplicateLensSamplesAdvanceTheDeadlineAndReleasePendingB() {
        val tx = Tx()
        var reads = 0
        val commands = mutableListOf<Pair<Double, NativeProgramZoomCommand>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { reads++; NativeGimbalFeedback(a, tx.now, tx.now) }, { _, _ -> true }, {},
            usesHighRateZoom = true, sendNativeZoom = { command, _ -> commands += tx.now to command; true })
        runner.start(GimbalProgram(a, a.copy(zoom = 1.001), a.copy(zoom = 3.0), 1.0, 1.0)) { updates += it }
        tx.through(3.25)
        assertEquals(1, commands.size, "All A-B samples share the prepared lens tick")
        tx.through(5.0)
        assertTrue(updates.last().finished)
        assertEquals(null, updates.last().failure)
        assertEquals(NativeProgramZoomCommand.Track(3.0), commands.last().second)
        assertTrue(reads < 1_000, "Duplicate targets and retained endpoints cannot create busy polling")
        commands.zipWithNext().forEach { (first, next) -> assertTrue(next.first - first.first >= 0.02 - 1e-8) }
    }

    @Test fun freshAngularReportsCannotKeepHighRateZoomAliveAfterLensReportsStop() {
        val tx = Tx()
        val commands = mutableListOf<NativeProgramZoomCommand>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now, minOf(tx.now, 2.5)) }, { _, _ -> true }, {},
            usesHighRateZoom = true, sendNativeZoom = { command, _ -> commands += command; true }, stopZoom = { stops++ })
        runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true)) { updates += it }
        tx.through(3.4)
        assertTrue(updates.last().finished)
        assertEquals("Move interrupted — camera zoom feedback lost", updates.last().failure)
        assertEquals(1, stops)
        val count = commands.size
        tx.through(8.0)
        assertEquals(count, commands.size)
    }

    @Test fun highRatePauseStopsAndResumeTracksLinearlyFromMeasuredZoom() {
        val tx = Tx()
        var measured = 3.0
        val start = a.copy(zoom = measured)
        val commands = mutableListOf<Pair<Double, NativeProgramZoomCommand>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(start.copy(zoom = measured), tx.now, kotlin.math.floor(tx.now / 0.4) * 0.4) }, { _, _ -> true }, {},
            usesHighRateZoom = true, sendNativeZoom = { command, _ -> commands += tx.now to command; true }, stopZoom = { stops++ })
        val token = runner.start(GimbalProgram(start, start.copy(zoom = 6.0), durationAB = 2.5)) { updates += it }
        tx.through(3.75)
        assertTrue(runner.pause(token))
        tx.through(3.76)
        assertEquals(1, stops)
        val paused = updates.last().readout!!
        val remaining = kotlin.math.ceil((paused.setDuration - paused.elapsed - 1e-9) * 10) / 10
        val count = commands.size
        measured = 5.2
        tx.through(4.5)
        assertEquals(count, commands.size)
        assertTrue(runner.resume(token))
        tx.through(4.71)
        assertFalse(updates.last().paused)
        val resumed = commands.drop(count)
        assertEquals(NativeProgramZoomCommand.Track(5.2), resumed.first().second)
        for ((time, command) in resumed) {
            val expected = 5.2 + 0.8 * (time - resumed.first().first) / remaining
            assertEquals(expected, (command as NativeProgramZoomCommand.Track).factor, 1e-7)
        }
        assertEquals(1, commands.count { it.second is NativeProgramZoomCommand.Position })
        assertTrue(runner.cancel(token))
        tx.through(4.72)
        assertEquals(2, stops)
    }

    @Test fun rejectedTrackingWriteStopsPriorOwnedZoomAndFencesFurtherWrites() {
        val tx = Tx()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val commands = mutableListOf<NativeProgramZoomCommand>()
        var stops = 0
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now, tx.now) }, { _, _ -> true }, {}, usesHighRateZoom = true,
            sendNativeZoom = { command, _ -> commands += command; command !is NativeProgramZoomCommand.Track }, stopZoom = { stops++ })
        runner.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0)) { updates += it }
        tx.through(5.0)
        assertEquals(2, commands.size)
        assertEquals(1, stops)
        assertEquals("Move interrupted — zoom command failed", updates.last().failure)
        assertTrue(updates.last().finished)
    }

    @Test fun unconfirmedStartingZoomFailsBeforeTimedMotion() {
        for (duration in listOf(2.5, 10.0)) {
            val tx = Tx()
            val start = a.copy(zoom = 3.0)
            val commands = mutableListOf<NativeProgramZoomCommand>()
            val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
            var targets = 0
            var stops = 0
            val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
                { NativeGimbalFeedback(start.copy(zoom = 1.0), tx.now, tx.now) }, { _, _ -> targets++; true }, {},
                usesHighRateZoom = true, sendNativeZoom = { command, _ -> commands += command; true }, stopZoom = { stops++ })
            runner.start(GimbalProgram(start, start.copy(zoom = 6.0), durationAB = duration)) { updates += it }
            tx.through(3.0)
            assertEquals(0, targets)
            assertEquals(listOf<NativeProgramZoomCommand>(NativeProgramZoomCommand.Position(3.0)), commands)
            assertEquals("Move interrupted — camera did not reach the starting zoom", updates.last().failure)
            assertTrue(updates.last().finished)
            assertEquals(1, stops)
        }
    }

    @Test fun equalZoomLegStopsUntilTheNextChangingLegAndTinyResumeStillTracks() {
        val tx = Tx()
        val commands = mutableListOf<Pair<Double, NativeProgramZoomCommand>>()
        val updates = mutableListOf<NativeGimbalProgramRunner.Progress>()
        val runner = NativeGimbalProgramRunner({ tx.now }, tx::schedule,
            { NativeGimbalFeedback(a, tx.now, tx.now) }, { _, _ -> true }, {}, usesHighRateZoom = true,
            sendNativeZoom = { command, _ -> commands += tx.now to command; true })
        runner.start(GimbalProgram(a, a, a.copy(zoom = 3.0), 1.0, 1.0)) { updates += it }
        tx.through(3.24)
        assertEquals(NativeProgramZoomCommand.Stop, commands.last().second)
        tx.through(5.0)
        assertEquals(NativeProgramZoomCommand.Track(3.0), commands.last().second)
        assertTrue(updates.last().finished)
        assertEquals(null, updates.last().failure)
    }
}
