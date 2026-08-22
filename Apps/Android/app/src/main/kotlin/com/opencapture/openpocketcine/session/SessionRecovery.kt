package com.opencapture.openpocketcine.session

/**
 * Whether an interrupted camera session is being recovered, and how the operator is told.
 *
 * The monitor stays up on the last frame, automatic retries run bounded, and when the
 * budget is spent the operator — not the app — decides what happens next.
 */
sealed class SessionRecoveryUi {
    data object Idle : SessionRecoveryUi()

    /** An automatic reconnect is running (or waiting out its backoff). [attempt] is 1-based. */
    data class Retrying(val attempt: Int, val maxAttempts: Int) : SessionRecoveryUi()

    /** The automatic budget is spent. The operator chooses: retry, or leave the monitor. */
    data class WaitingForOperator(val attemptsMade: Int) : SessionRecoveryUi()

    /** Reconnects kept succeeding but the session kept dying young. */
    data class PausedAfterDrops(val drops: Int) : SessionRecoveryUi()

    val isRecovering: Boolean get() = this !is Idle
}

/** Cross-run damping for sessions that reconnect cleanly but keep dying. */
class SessionDropStormGuard {
    private val dropTimesMs = ArrayList<Long>()

    fun noteDrop(nowMs: Long): Boolean {
        dropTimesMs.add(nowMs)
        dropTimesMs.removeAll { nowMs - it > WINDOW_MS }
        return dropTimesMs.size >= PAUSE_AFTER_DROPS
    }

    val dropsInWindow: Int get() = dropTimesMs.size

    fun reset() {
        dropTimesMs.clear()
    }

    companion object {
        const val WINDOW_MS = 120_000L
        const val PAUSE_AFTER_DROPS = 3
    }
}

sealed class SessionRecoveryDecision {
    data class Retry(val afterMs: Long) : SessionRecoveryDecision()

    data object Stop : SessionRecoveryDecision()
}

/**
 * Jittered exponential backoff for reconnect retries.
 * Attempt 0 is [baseMs]; each step doubles up to [maxMs].
 */
class ReconnectBackoff(
    val baseMs: Long = 500,
    val maxMs: Long = 8_000,
    val multiplier: Double = 2.0,
    val jitterFraction: Double = 0.3,
) {
    fun delayMs(attempt: Int, jitter: Double): Long {
        val exponent = maxOf(0, attempt).toDouble()
        val capped = minOf(maxMs.toDouble(), baseMs * Math.pow(multiplier, exponent))
        val clampedJitter = jitter.coerceIn(0.0, 1.0)
        val signedSpread = (clampedJitter * 2 - 1) * jitterFraction
        val jittered = capped * (1 + signedSpread)
        return minOf(maxMs, maxOf(0L, jittered.toLong()))
    }
}

/**
 * Shared reconnect rule: when to retry a dropped camera session, how long to back off,
 * and when to stop and ask the operator.
 */
class SessionRecoveryPolicy(
    val backoff: ReconnectBackoff = ReconnectBackoff(),
    val maxAutomaticAttempts: Int = 8,
) {
    /**
     * Retry at once, then 0.5s → 8s jittered, giving up after 8 attempts.
     * Long enough to ride out a camera power cycle; short enough that a
     * camera that is gone stops burning the radio.
     */
    fun decision(afterFailedAttempts: Int, jitter: Double): SessionRecoveryDecision {
        val failed = maxOf(0, afterFailedAttempts)
        if (failed >= maxAutomaticAttempts) return SessionRecoveryDecision.Stop
        if (failed == 0) return SessionRecoveryDecision.Retry(0)
        return SessionRecoveryDecision.Retry(backoff.delayMs(failed - 1, jitter))
    }

    fun state(afterFailedAttempts: Int): SessionRecoveryUi {
        val failed = maxOf(0, afterFailedAttempts)
        if (failed >= maxAutomaticAttempts) {
            return SessionRecoveryUi.WaitingForOperator(failed)
        }
        return SessionRecoveryUi.Retrying(attempt = failed + 1, maxAttempts = maxAutomaticAttempts)
    }

    companion object {
        val monitor = SessionRecoveryPolicy()
    }
}

/** Operator-facing recovery copy. Never names a sister app or another brand. */
object SessionRecoveryCopy {
    const val RETRY_CONNECTION = "Retry connection"
    const val OPERATOR_MENU = "Operator menu"
    const val HELD_FRAME_BADGE = "NO LINK"

    fun title(state: SessionRecoveryUi): String =
        when (state) {
            SessionRecoveryUi.Idle -> ""
            is SessionRecoveryUi.Retrying -> "Reconnecting…"
            is SessionRecoveryUi.WaitingForOperator -> "Camera disconnected"
            is SessionRecoveryUi.PausedAfterDrops -> "Connection keeps dropping"
        }

    fun detail(state: SessionRecoveryUi, deviceName: String): String {
        val name = deviceName.trim()
        val camera = if (name.isEmpty()) "The camera" else name
        return when (state) {
            SessionRecoveryUi.Idle -> ""
            is SessionRecoveryUi.Retrying ->
                "$camera dropped off. Holding the last frame — attempt ${state.attempt} of ${state.maxAttempts}."
            is SessionRecoveryUi.WaitingForOperator -> {
                val tries = if (state.attemptsMade == 1) "1 try" else "${state.attemptsMade} tries"
                "$camera didn't come back after $tries. The frame below is held, not live."
            }
            is SessionRecoveryUi.PausedAfterDrops ->
                "$camera reconnected but dropped ${state.drops} times in quick succession. Automatic retries are paused to protect the camera. The frame below is held, not live."
        }
    }
}
