package com.opencapture.openpocketcine.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.test.Test
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class DatalinkTxLifetimeTest {
    @Test fun timedOutQueuedBindNeverRunsAfterTheExecutorRecovers() {
        val executor = Executors.newSingleThreadExecutor()
        val blocked = CountDownLatch(1)
        val release = CountDownLatch(1)
        val mutated = AtomicBoolean(false)
        try {
            executor.submit { blocked.countDown(); release.await() }
            assertTrue(blocked.await(1, TimeUnit.SECONDS))
            assertFailsWith<DatalinkHandshakeException> {
                awaitDatalinkTx(executor, { true }, timeoutMs = 20) { mutated.set(true) }
            }
            release.countDown()
            executor.submit {}.get(1, TimeUnit.SECONDS)
            assertFalse(mutated.get(), "expired bind must be removed from the TX queue")
        } finally { release.countDown(); executor.shutdownNow() }
    }

    @Test fun replacementEpochRejectsAnOldQueuedBind() {
        val executor = Executors.newSingleThreadExecutor()
        val mutated = AtomicBoolean(false)
        try {
            assertFailsWith<DatalinkHandshakeException> {
                awaitDatalinkTx(executor, { false }) { mutated.set(true) }
            }
            assertFalse(mutated.get())
        } finally { executor.shutdownNow() }
    }

    @Test fun interruptedCallerCancelsItsQueuedBind() {
        val executor = Executors.newSingleThreadExecutor()
        val release = CountDownLatch(1)
        val entered = CountDownLatch(1)
        val mutated = AtomicBoolean(false)
        val interrupted = AtomicBoolean(false)
        val caller = Thread {
            try {
                entered.countDown()
                awaitDatalinkTx(executor, { true }) { mutated.set(true) }
            } catch (_: InterruptedException) { interrupted.set(true) }
        }
        try {
            executor.submit { release.await() }
            caller.start()
            assertTrue(entered.await(1, TimeUnit.SECONDS))
            caller.interrupt()
            caller.join(1_000)
            release.countDown()
            executor.submit {}.get(1, TimeUnit.SECONDS)
            assertTrue(interrupted.get())
            assertFalse(mutated.get())
        } finally { release.countDown(); caller.interrupt(); executor.shutdownNow() }
    }
}
