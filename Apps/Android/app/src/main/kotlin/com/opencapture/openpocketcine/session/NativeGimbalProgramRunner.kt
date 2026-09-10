package com.opencapture.openpocketcine.session

import java.util.concurrent.atomic.AtomicLong

/** One immutable camera observation, timestamped before any UI delivery. */
internal data class NativeGimbalFeedback(val pose: GimbalWaypoint, val receivedAt: Double) {
    companion object {
        fun from(frame: DumlFrame, receivedAt: Double): NativeGimbalFeedback? {
            if (frame.cmdSet != 0x04 || frame.cmdId != 0x05 || frame.payload.size < 22) return null
            val payload = frame.payload
            val nativePitch = ((payload[0].toInt() and 0xFF) or
                ((payload[1].toInt() and 0xFF) shl 8)).toShort().toInt()
            val pose = GimbalWaypoint.from(CameraCommands.yawTenthDeg(payload),
                CameraCommands.pitchTenthDeg(payload), 1.0, nativePitch) ?: return null
            return NativeGimbalFeedback(pose, receivedAt)
        }
    }
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
) {
    data class Progress(val token: Long, val program: GimbalProgram, val live: GimbalWaypoint?,
        val readout: GimbalMoveEngine.Readout?, val failure: String?, val finished: Boolean,
        val paused: Boolean = false, val note: String? = null, val epoch: Long = 0,
        val verificationInterruptedByPause: Boolean = false)

    private data class Run(val token: Long, val program: GimbalProgram, val engine: GimbalMoveEngine,
        val publish: (Progress) -> Unit, var lastTick: Double, var lastPublish: Double = Double.NEGATIVE_INFINITY,
        val stability: NativePauseStability = NativePauseStability())

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
                val run = Run(token, program, engine, publish, current)
                active = run
                publish(run, sample.pose, finished = false, force = true)
                wake(run, current + engine.nextWakeInterval)
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
                    run = Run(token, saved.program, engine, saved.publish, now())
                    active = run
                }
            }
            if (run == null || sample == null || !run.engine.pause(sample.pose)) {
                stop()
                saved.publish(Progress(token, saved.program, sample?.pose, null,
                    "Move interrupted — camera feedback lost", true, epoch = epoch))
                releaseRequest(token)
                active = null
                return@schedule
            }
            stop()
            run.stability.reset(now())
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
            run.stability.observe(feedback())
            val sample = run.stability.ready(now())
            if (sample == null || !run.engine.resume(sample.pose)) {
                run.publish(Progress(token, run.program, feedback()?.pose, feedback()?.pose?.let { run.engine.readout(it) },
                    null, false, paused = true, note = "Hold the camera still before resuming", epoch = epoch,
                    verificationInterruptedByPause = run.engine.verificationInterruptedByPause))
                return@schedule
            }
            callbackEpoch.incrementAndGet()
            run.lastTick = now()
            publish(run, sample.pose, false, force = true)
            wake(run, run.lastTick + 0.000001)
        }
        return true
    }

    private fun watchPaused(run: Run, epoch: Long) {
        schedule(0.04) {
            if (generation.get() != run.token || callbackEpoch.get() != epoch || active !== run || !run.engine.isPaused) return@schedule
            run.stability.observe(feedback())
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
            val out = run.engine.tick(current - run.lastTick, sample.pose, current - sample.receivedAt)
            run.lastTick = current
            if (out == null) {
                fail(run, sample.pose, "Move interrupted — timing or camera feedback lost")
                return@schedule
            }
            if (generation.get() != run.token || callbackEpoch.get() != epoch) return@schedule
            if (out.stop) stop()
            if (out.target != null && !send(out.target, out.duration)) {
                fail(run, sample.pose, "Set reachable gimbal points again")
                return@schedule
            }
            if (out.finished) {
                active = null
                releaseRequest(run.token)
            }
            publish(run, sample.pose, out.finished, force = out.finished)
            if (!out.finished) wake(run, current + run.engine.nextWakeInterval)
        }
    }

    private fun fail(run: Run, live: GimbalWaypoint?, reason: String) {
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
