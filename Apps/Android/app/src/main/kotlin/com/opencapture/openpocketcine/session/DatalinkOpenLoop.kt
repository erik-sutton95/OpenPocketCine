package com.opencapture.openpocketcine.session

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible

/** Blocking handshake lifetime, independent of a particular UDP bind. */
internal class DatalinkOpenLoop(
    private val nowMs: () -> Long,
    private val timeoutMs: Long,
    private val cancelled: () -> Boolean,
) {
    private val startedAt = nowMs()

    fun ensureActive() {
        if (cancelled() || Thread.currentThread().isInterrupted) throw InterruptedException("datalink open cancelled")
        if (nowMs() - startedAt >= timeoutMs) throw DatalinkDriver.DatalinkError.NoHandshake()
    }

    fun run(attempt: () -> Boolean) {
        while (true) {
            ensureActive()
            if (attempt()) return
        }
    }
}

internal suspend fun <T> interruptibleDatalinkOpen(block: () -> T): T =
    runInterruptible(Dispatchers.IO) { block() }

/** Cancellation removes work that is still queued; a previous bind cannot mutate a replacement. */
internal fun awaitDatalinkTx(
    executor: java.util.concurrent.ExecutorService,
    isCurrent: () -> Boolean,
    timeoutMs: Long = 3_000,
    work: () -> Unit,
) {
    val future = executor.submit {
        if (!isCurrent()) throw DatalinkHandshakeException("datalink generation changed")
        work()
    }
    try {
        future.get(timeoutMs, java.util.concurrent.TimeUnit.MILLISECONDS)
    } catch (error: InterruptedException) {
        future.cancel(false)
        throw error
    } catch (error: java.util.concurrent.TimeoutException) {
        future.cancel(false)
        throw DatalinkHandshakeException("datalink TX did not respond within ${timeoutMs}ms")
    } catch (error: java.util.concurrent.ExecutionException) {
        throw error.cause ?: error
    }
}
