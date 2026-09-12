package com.opencapture.openpocketcine.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertTrue
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield

class DatalinkOpenLoopTest {
    @Test fun unsolicitedPacketsCannotKeepAnUnansweredHandshakeAliveForever() {
        var now = 0L
        var attempts = 0
        val lifetime = DatalinkOpenLoop({ now }, 100, { false })
        assertFailsWith<DatalinkDriver.DatalinkError.NoHandshake> {
            lifetime.run {
                attempts += 1
                check(attempts <= 20) { "handshake kept retrying past its deadline" }
                now += 10
                false // real KEEP_SOCKET branch: status packets, no handshake ACK
            }
        }
        assertEquals(10, attempts)
    }

    @Test fun cancelInterruptsTheRunningBlockingOpenBeforeItCanPublishLive() = runBlocking {
        val entered = CountDownLatch(1)
        val released = CountDownLatch(1)
        val done = CountDownLatch(1)
        var published = false
        val job = launch {
            interruptibleDatalinkOpen {
                entered.countDown()
                try {
                    released.await()
                    published = true
                } finally { done.countDown() }
            }
        }
        yield()
        assertTrue(entered.await(2, TimeUnit.SECONDS))
        job.cancel()
        val interrupted = done.await(200, TimeUnit.MILLISECONDS)
        released.countDown() // always clean up the pre-fix worker
        job.cancelAndJoin()
        assertTrue(interrupted, "withContext(IO) leaves blocking open alive after cancellation")
        assertTrue(!published, "cancelled open must not publish LIVE")
    }
}
