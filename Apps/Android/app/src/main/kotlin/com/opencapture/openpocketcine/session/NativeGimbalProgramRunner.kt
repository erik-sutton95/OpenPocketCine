package com.opencapture.openpocketcine.session

import java.util.concurrent.atomic.AtomicLong
import kotlin.math.abs

/** One immutable camera observation, timestamped before any UI delivery. */
internal data class NativeGimbalFeedback(val pose: GimbalWaypoint, val receivedAt: Double, val zoomReceivedAt: Double? = null) {
    companion object {
        fun from(frame: DumlFrame, receivedAt: Double, zoom: Double = 1.0): NativeGimbalFeedback? {
            if (frame.cmdSet != 0x04 || frame.cmdId != 0x05 || frame.payload.size < 22) return null
            val payload = frame.payload
            val nativePitch = ((payload[0].toInt() and 0xFF) or
                ((payload[1].toInt() and 0xFF) shl 8)).toShort().toInt()
            val pose = GimbalWaypoint.from(CameraCommands.yawTenthDeg(payload),
                CameraCommands.pitchTenthDeg(payload), zoom, nativePitch) ?: return null
            return NativeGimbalFeedback(pose, receivedAt)
        }
    }
}

internal data class NativeProgramZoomObservation(val status: CameraStatus = CameraStatus(), val receivedAt: Double? = null,
    private val pausedAt: Double? = null, private val stableSince: Double? = null, private val stableLens: Int? = null) {
    fun observing(frame: DumlFrame, model: CameraModel, now: Double): NativeProgramZoomObservation {
        val next = nativeProgramZoomStatus(frame, status, model)
        val item = if (frame.cmdSet == 0 && frame.cmdId == 0x99) StatusExtras.parseSubscribe(frame.payload) else null
        val measured = when (item?.name) {
            "cam_lens_state" -> CamFov.lensAt14(item.value) != null
            "cam_fov" -> status.zoomLens < 0 && (CamFov.rawAt0(item.value) ?: 0) != 0
            else -> false
        }
        if (!measured || !now.isFinite() || now <= (receivedAt ?: Double.NEGATIVE_INFINITY) || next.zoomFactor == null) {
            return copy(status = next)
        }
        val lens = CamFov.pinchLens(next.zoomFactor)
        val gap = receivedAt?.let { now - it } ?: Double.POSITIVE_INFINITY
        val maximumGap = if (CameraModel.looksLikePocket4Pro(model.name)) 0.85 else 0.3
        val changed = (stableLens == null || gap > maximumGap || abs(stableLens - lens) > 1) && (pausedAt == null || now > pausedAt)
        return copy(status = next, receivedAt = now,
            stableSince = if (changed) now else stableSince, stableLens = if (changed) lens else stableLens)
    }

    fun notePause(now: Double): NativeProgramZoomObservation = copy(pausedAt = now, stableSince = null, stableLens = null)

    fun canResume(now: Double): Boolean {
        val stopped = pausedAt ?: return false
        val latest = receivedAt ?: return false
        val first = stableSince ?: return false
        return latest > stopped && first > stopped && now - latest in 0.0..0.3 && latest - first >= 0.2 - 1e-9
    }
}

/** Only distinct lens reports after STOP can establish stable zoom for Resume. */
internal class NativeZoomPauseStability(private val maximumGap: Double = 0.3) {
    private var pausedAt = Double.POSITIVE_INFINITY
    private var latestAt: Double? = null
    private var stableSince: Double? = null
    private var anchorLens: Int? = null

    fun reset(now: Double) {
        pausedAt = now
        latestAt = null
        stableSince = null
        anchorLens = null
    }

    fun observe(sample: NativeGimbalFeedback?) {
        val receipt = sample?.zoomReceivedAt ?: return
        if (!receipt.isFinite() || receipt <= pausedAt || receipt <= (latestAt ?: Double.NEGATIVE_INFINITY)) return
        if (!sample.pose.zoom.isFinite()) return
        val lens = CamFov.pinchLens(sample.pose.zoom)
        val gap = latestAt?.let { receipt - it } ?: Double.POSITIVE_INFINITY
        if (anchorLens == null || gap > maximumGap || abs(lens - anchorLens!!) > 1) {
            anchorLens = lens
            stableSince = receipt
        }
        latestAt = receipt
    }

    fun ready(now: Double): Boolean {
        val latest = latestAt ?: return false
        val first = stableSince ?: return false
        return now - latest in 0.0..0.3 && latest - first >= 0.2 - 1e-9
    }
}

/** Unpinned camera reports govern automated zoom; a motion take never changes color mode. */
internal fun nativeProgramZoomFailure(program: GimbalProgram, model: CameraModel, status: CameraStatus, target: Double? = null): String? {
    if (!program.changesZoom) return null
    if (status.colorMode == CameraCommands.COLOR_DLOG2) return "Zoom moves are unavailable in D-Log2"
    if (status.colorMode !in setOf(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_NORMAL10,
            CameraCommands.COLOR_HDR, CameraCommands.COLOR_DLOG, CameraCommands.COLOR_DLOG_M)) {
        return "Wait for camera color mode before a zoom move"
    }
    val ceiling = model.activeZoomStops(status.resolutionCode, status.shootingMode).lastOrNull() ?: 1.0
    if (listOfNotNull(program.a, program.b, program.c).any { !it.zoom.isFinite() || it.zoom < 1.0 || it.zoom > ceiling }) {
        return "Saved zoom exceeds the current FORMAT limit"
    }
    if (status.zoomFactor?.let { it.isFinite() && it in 1.0..ceiling } != true ||
        target?.let { !it.isFinite() || it !in 1.0..ceiling } == true) return "Wait for camera zoom feedback"
    return null
}

/** Angular reports cannot refresh the lens report's independent 2.5 Hz evidence. */
internal fun nativeProgramZoomFeedbackFailure(receivedAt: Double?, now: Double): String? =
    if (receivedAt != null && now.isFinite() && now >= receivedAt && now - receivedAt <= 0.85) null
    else "Move interrupted — camera zoom feedback lost"

/** Existing subscribe/status frames are consumed before the main-thread status callback. */
internal fun nativeProgramZoomStatus(frame: DumlFrame, status: CameraStatus, model: CameraModel): CameraStatus {
    val next = StatusExtras.apply(frame, status, model.name, model.family)
    return if (StatusExtras.reportsShootingMode(frame)) next.copy(shootingMode = frame.payload[57].toInt() and 0xFF) else next
}

/** Firmware may take the forbidden yaw shortcut for an absolute target half a turn away. */
internal fun nativeGimbalTargetIsSafe(target: GimbalWaypoint, feedback: NativeGimbalFeedback?, now: Double): Boolean {
    val current = feedback ?: return false
    if (!now.isFinite() || now - current.receivedAt !in 0.0..0.3) return false
    fun reachable(point: GimbalWaypoint): Boolean = point == point.clamped() &&
        point.yawDeg.isFinite() && point.pitchDeg.isFinite() &&
        point.nativePitchDeg?.let { it.isFinite() && it in -180.0..180.0 } == true
    return reachable(target) && reachable(current.pose) && GimbalMoveEngine.canSendNativeTarget(current.pose, target)
}

/** Engine and socket commands share one serial monotonic scheduler, independent of UI work. */
internal class NativeGimbalProgramRunner(
    private val now: () -> Double,
    private val schedule: (Double, () -> Unit) -> Unit,
    private val feedback: () -> NativeGimbalFeedback?,
    private val send: (GimbalWaypoint, Double) -> Boolean,
    private val stop: () -> Unit,
    private val zoomFailure: (GimbalProgram) -> String? = { null },
    private val zoomTargetFailure: (Double, GimbalProgram) -> String? = { _, _ -> null },
    private val sendZoom: (Int, GimbalProgram) -> Boolean = { _, _ -> false },
    private val stopZoom: () -> Unit = {},
    private val noteZoomPause: (Double) -> Unit = {},
    private val zoomResumeReady: (Double) -> Boolean = { true },
    private val usesHighRateZoom: Boolean = false,
    private val sendNativeZoom: (NativeProgramZoomCommand, GimbalProgram) -> Boolean = { _, _ -> false },
) {
    data class Progress(val token: Long, val program: GimbalProgram, val live: GimbalWaypoint?,
        val readout: GimbalMoveEngine.Readout?, val failure: String?, val finished: Boolean,
        val paused: Boolean = false, val note: String? = null, val epoch: Long = 0,
        val verificationInterruptedByPause: Boolean = false)

    private data class Run(val token: Long, val program: GimbalProgram, val engine: GimbalMoveEngine,
        val publish: (Progress) -> Unit, var lastTick: Double, var lastPublish: Double = Double.NEGATIVE_INFINITY,
        val stability: NativePauseStability = NativePauseStability(),
        val zoomStability: NativeZoomPauseStability = NativeZoomPauseStability(),
        var nextZoomAt: Double = lastTick, var lastZoomLens: Int? = null, var ownsZoom: Boolean = false,
        var lastNativeZoom: NativeProgramZoomCommand? = null,
        var lastNativeSampleAt: Double = Double.NEGATIVE_INFINITY,
        var preparationZoom: Double? = null, var preparationSentAt: Double? = null)

    private data class Request(val token: Long, val program: GimbalProgram, val publish: (Progress) -> Unit)
    private val controlLock = Any()
    private var request: Request? = null
    private val generation = AtomicLong(0)
    private val callbackEpoch = AtomicLong(0)
    // Only the scheduled TX executor reads or mutates the active engine.
    private var active: Run? = null

    fun start(program: GimbalProgram, publish: (Progress) -> Unit): Long {
        val token = synchronized(controlLock) {
            generation.incrementAndGet().also { request = Request(it, program, publish) }
        }
        val epoch = callbackEpoch.incrementAndGet()
        // This first task follows the queued Fast/unlock preparation writes. The
        // settle delay starts after those writes, rather than while TX is blocked.
        schedule(0.0) {
            if (generation.get() == token && callbackEpoch.get() == epoch) schedule(0.25) {
                if (generation.get() != token || callbackEpoch.get() != epoch) return@schedule
                val sample = feedback()
                val current = now()
                if (sample == null || current - sample.receivedAt !in 0.0..0.3) {
                    stop()
                    releaseRequest(token)
                    publish(Progress(token, program, sample?.pose, null,
                        "Move interrupted — timing or camera feedback lost", true, epoch = epoch))
                    return@schedule
                }
                val engine = GimbalMoveEngine()
                if (!engine.start(program, sample.pose)) {
                    stop()
                    releaseRequest(token)
                    publish(Progress(token, program, sample.pose, null,
                        engine.failure ?: "Set reachable gimbal points again", true, epoch = epoch))
                    return@schedule
                }
                val run = Run(token, program, engine, publish, current,
                    zoomStability = NativeZoomPauseStability(if (usesHighRateZoom) 0.85 else 0.3))
                active = run
                if (!sampleZoom(run, current, epoch)) return@schedule
                if (generation.get() != token || callbackEpoch.get() != epoch) return@schedule
                publish(run, sample.pose, finished = false, force = true)
                wakeNext(run, current)
            }
        }
        return token
    }

    /** Fence pending timers immediately; serialized cleanup/STOP precedes subsequent TX commands. */
    fun cancel(token: Long): Boolean {
        synchronized(controlLock) {
            if (!generation.compareAndSet(token, token + 1)) return false
            request = null
            callbackEpoch.incrementAndGet()
        }
        schedule(0.0) {
            if (active?.token == token) {
                stopOwnedZoom(active!!)
                active?.engine?.cancel()
                active = null
            }
            stop()
        }
        return true
    }

    fun invalidate() {
        synchronized(controlLock) {
            generation.incrementAndGet()
            callbackEpoch.incrementAndGet()
            request = null
        }
    }

    /** A discarded connection cannot resume on its replacement. No delayed STOP is sent to the new socket. */
    fun interrupt() {
        val interrupted = synchronized(controlLock) {
            generation.incrementAndGet()
            callbackEpoch.incrementAndGet()
            request.also { request = null }
        } ?: return
        schedule(0.0) {
            val run = active?.takeIf { it.token == interrupted.token }
            run?.engine?.cancel()
            if (run != null) active = null
            val live = feedback()?.pose
            interrupted.publish(Progress(interrupted.token, interrupted.program, live,
                live?.let { run?.engine?.readout(it) }, "Move interrupted — camera connection changed", true, epoch = callbackEpoch.get()))
        }
    }

    fun isCurrentProgress(progress: Progress): Boolean = callbackEpoch.get() == progress.epoch

    fun pause(token: Long): Boolean {
        val epoch = synchronized(controlLock) {
            if (generation.get() != token || request == null) return false
            callbackEpoch.incrementAndGet()
        }
        schedule(0.0) {
            if (generation.get() != token || callbackEpoch.get() != epoch) return@schedule
            val sample = feedback()
            val saved = synchronized(controlLock) { request?.takeIf { it.token == token } } ?: return@schedule
            var run = active?.takeIf { it.token == token }
            if (run == null && sample != null) {
                val engine = GimbalMoveEngine()
                if (engine.start(saved.program, sample.pose)) {
                    run = Run(token, saved.program, engine, saved.publish, now(),
                        zoomStability = NativeZoomPauseStability(if (usesHighRateZoom) 0.85 else 0.3))
                    active = run
                }
            }
            if (run == null || sample == null || !run.engine.pause(sample.pose)) {
                stop()
                run?.let(::stopOwnedZoom)
                saved.publish(Progress(token, saved.program, sample?.pose, null,
                    "Move interrupted — camera feedback lost", true, epoch = epoch))
                releaseRequest(token)
                active = null
                return@schedule
            }
            stop()
            stopOwnedZoom(run)
            if (run.program.changesZoom) noteZoomPause(now())
            run.stability.reset(now())
            run.zoomStability.reset(now())
            publish(run, sample.pose, false, force = true)
            watchPaused(run, epoch)
        }
        return true
    }

    fun resume(token: Long): Boolean {
        if (generation.get() != token) return false
        val epoch = callbackEpoch.get()
        schedule(0.0) {
            if (generation.get() != token || callbackEpoch.get() != epoch) return@schedule
            val run = active?.takeIf { it.token == token && it.engine.isPaused } ?: return@schedule
            zoomFailure(run.program)?.let { fail(run, feedback()?.pose, it); return@schedule }
            val current = feedback()
            run.stability.observe(current)
            run.zoomStability.observe(current)
            val sample = run.stability.ready(now())
            // Lens reports can advance while the still-fresh angular receipt is unchanged.
            val pose = if (run.program.changesZoom) current?.let { sample?.pose?.copy(zoom = it.pose.zoom) } else sample?.pose
            if (pose == null || (run.program.changesZoom && (!run.zoomStability.ready(now()) || !zoomResumeReady(now()))) ||
                !run.engine.resume(pose)) {
                run.publish(Progress(token, run.program, current?.pose, current?.pose?.let { run.engine.readout(it) },
                    null, false, paused = true, note = "Hold the camera still before resuming", epoch = epoch,
                    verificationInterruptedByPause = run.engine.verificationInterruptedByPause))
                return@schedule
            }
            callbackEpoch.incrementAndGet()
            run.lastTick = now()
            run.nextZoomAt = run.lastTick
            run.lastZoomLens = null
            run.lastNativeZoom = null
            run.lastNativeSampleAt = Double.NEGATIVE_INFINITY
            run.preparationZoom = null
            run.preparationSentAt = null
            publish(run, pose, false, force = true)
            wake(run, run.lastTick + 0.000001)
        }
        return true
    }

    private fun watchPaused(run: Run, epoch: Long) {
        schedule(0.04) {
            if (generation.get() != run.token || callbackEpoch.get() != epoch || active !== run || !run.engine.isPaused) return@schedule
            zoomFailure(run.program)?.let { fail(run, feedback()?.pose, it); return@schedule }
            run.stability.observe(feedback())
            run.zoomStability.observe(feedback())
            watchPaused(run, epoch)
        }
    }

    private fun releaseRequest(token: Long) {
        synchronized(controlLock) {
            if (request?.token == token) request = null
        }
    }

    private fun wake(run: Run, deadline: Double) {
        val epoch = callbackEpoch.get()
        schedule((deadline - now()).coerceAtLeast(0.000001)) {
            if (generation.get() != run.token || callbackEpoch.get() != epoch || active !== run || run.engine.isPaused) return@schedule
            val current = now()
            val sample = feedback()
            if (sample == null) {
                fail(run, null, "Move interrupted — camera feedback lost")
                return@schedule
            }
            zoomFailure(run.program)?.let { fail(run, sample.pose, it); return@schedule }
            if (usesHighRateZoom && run.program.changesZoom) {
                nativeProgramZoomFeedbackFailure(sample.zoomReceivedAt, current)?.let {
                    fail(run, sample.pose, it); return@schedule
                }
            }
            val out = run.engine.tick(current - run.lastTick, sample.pose, current - sample.receivedAt)
            run.lastTick = current
            if (out == null) {
                fail(run, sample.pose, "Move interrupted — timing or camera feedback lost")
                return@schedule
            }
            if (generation.get() != run.token || callbackEpoch.get() != epoch) return@schedule
            if (!out.finished && !sampleZoom(run, current, epoch)) return@schedule
            if (generation.get() != run.token || callbackEpoch.get() != epoch) return@schedule
            if (out.stop) stop()
            if (out.stop || out.finished) stopOwnedZoom(run)
            if (out.target != null && !send(out.target, out.duration)) {
                fail(run, sample.pose, "Set reachable gimbal points again")
                return@schedule
            }
            if (out.finished) {
                active = null
                releaseRequest(run.token)
            }
            publish(run, sample.pose, out.finished, force = out.finished)
            if (!out.finished) wakeNext(run, current)
        }
    }

    private fun wakeNext(run: Run, current: Double) {
        val zoomDelay = if (run.program.changesZoom) (run.nextZoomAt - current).coerceAtLeast(0.000001) else Double.POSITIVE_INFINITY
        wake(run, current + minOf(run.engine.nextWakeInterval, zoomDelay))
    }

    private fun sampleZoom(run: Run, current: Double, epoch: Long): Boolean {
        if (!run.program.changesZoom) return true
        zoomFailure(run.program)?.let { fail(run, feedback()?.pose, it); return false }
        if (usesHighRateZoom) {
            nativeProgramZoomFeedbackFailure(feedback()?.zoomReceivedAt, current)?.let {
                fail(run, feedback()?.pose, it); return false
            }
        }
        if (usesHighRateZoom) return sampleNativeZoom(run, current, epoch)
        if (current + 1e-9 < run.nextZoomAt) return true
        val target = run.engine.consumeProgrammedZoomTarget() ?: return true
        run.nextZoomAt = current + 0.05
        zoomTargetFailure(target, run.program)?.let { fail(run, feedback()?.pose, it); return false }
        val lens = CamFov.pinchLens(target)
        if (run.lastZoomLens == lens) return true
        if (generation.get() != run.token || callbackEpoch.get() != epoch) return false
        if (!sendZoom(lens, run.program)) {
            fail(run, feedback()?.pose, zoomFailure(run.program) ?: "Move interrupted — zoom command failed")
            return false
        }
        run.lastZoomLens = lens
        run.ownsZoom = true
        return true
    }

    private fun sampleNativeZoom(run: Run, current: Double, epoch: Long): Boolean {
        val demand = run.engine.nativeZoomDemand ?: return true
        demand.failureReason?.let { fail(run, feedback()?.pose, it); return false }
        zoomTargetFailure(demand.destination, run.program)?.let { fail(run, feedback()?.pose, it); return false }
        val command = demand.command
        if (command !is NativeProgramZoomCommand.Position) {
            val expected = run.preparationZoom
            val sentAt = run.preparationSentAt
            if (expected != null && sentAt != null) {
                val sample = feedback()
                val verified = sample != null && sample.zoomReceivedAt?.let { it > sentAt } == true &&
                    abs(sample.pose.zoom - expected) <= 2.0 / 217.0 + 1e-9
                if (!verified) {
                    fail(run, sample?.pose, "Move interrupted — camera did not reach the starting zoom")
                    return false
                }
            }
        }
        run.nextZoomAt = current + demand.nextChange
        when (command) {
            is NativeProgramZoomCommand.Position -> if (command == run.lastNativeZoom) return true
            is NativeProgramZoomCommand.Track -> {
                zoomTargetFailure(command.factor, run.program)?.let { fail(run, feedback()?.pose, it); return false }
                val due = run.lastNativeSampleAt + NativeProgramZoom.INTERVAL
                if (current < due - 1e-9) {
                    run.nextZoomAt = due
                    return true
                }
            }
            NativeProgramZoomCommand.Stop -> if (!run.ownsZoom || command == run.lastNativeZoom) return true
        }
        when (command) {
            is NativeProgramZoomCommand.Position -> {
                run.preparationZoom = command.factor
                run.preparationSentAt = current
                run.lastNativeSampleAt = current
            }
            is NativeProgramZoomCommand.Track -> {
                run.lastNativeSampleAt = current
                run.nextZoomAt = current + NativeProgramZoom.INTERVAL
                run.preparationZoom = null
                run.preparationSentAt = null
                // Admission consumes a pending endpoint even if its quantized
                // lens tick was already sent. Duplicates still advance the clock.
                run.engine.consumeNativeZoomDemand()
                if (run.lastZoomLens == CamFov.pinchLens(command.factor)) {
                    return true
                }
            }
            NativeProgramZoomCommand.Stop -> Unit
        }
        if (generation.get() != run.token || callbackEpoch.get() != epoch) return false
        if (!sendNativeZoom(command, run.program)) {
            fail(run, feedback()?.pose, zoomFailure(run.program) ?: "Move interrupted — zoom command failed")
            return false
        }
        run.lastNativeZoom = command
        when (command) {
            is NativeProgramZoomCommand.Position -> run.lastZoomLens = CamFov.pinchLens(command.factor)
            is NativeProgramZoomCommand.Track -> run.lastZoomLens = CamFov.pinchLens(command.factor)
            NativeProgramZoomCommand.Stop -> Unit
        }
        run.ownsZoom = true
        return true
    }

    private fun stopOwnedZoom(run: Run) {
        if (!run.ownsZoom) return
        run.ownsZoom = false
        stopZoom()
    }

    private fun fail(run: Run, live: GimbalWaypoint?, reason: String) {
        stopOwnedZoom(run)
        run.engine.cancel()
        active = null
        releaseRequest(run.token)
        stop()
        run.publish(Progress(run.token, run.program, live, live?.let { run.engine.readout(it) }, reason, true, epoch = callbackEpoch.get()))
    }

    private fun publish(run: Run, live: GimbalWaypoint, finished: Boolean, force: Boolean = false) {
        val current = now()
        if (!force && current - run.lastPublish < 0.2) return
        run.lastPublish = current
        run.publish(Progress(run.token, run.program, live, run.engine.readout(live), run.engine.failure, finished, paused = run.engine.isPaused,
            epoch = callbackEpoch.get(), verificationInterruptedByPause = run.engine.verificationInterruptedByPause))
    }
}
