package com.opencapture.openpocketcine.session

import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.yield

class DatalinkPokeTest {
    private class PokeSocket : AutoCloseable {
        @Volatile var closed = false
        override fun close() { closed = true }
    }

    @Test fun cancellationDuringPokeSettleCannotContinueIntoUdpOrPublishSocket() = runBlocking {
        val socket = PokeSocket()
        val entered = CountDownLatch(1)
        val finished = CountDownLatch(1)
        var published = false
        var continuedIntoUdp = false
        val job = launch {
            interruptibleDatalinkOpen {
                try {
                    openDatalinkPoke(socket, {}, {},
                        settle = { entered.countDown(); Thread.sleep(5_000) },
                        publish = { published = true }, onFailure = {})
                    continuedIntoUdp = true
                } finally { finished.countDown() }
            }
        }
        yield()
        assertTrue(entered.await(2, TimeUnit.SECONDS))
        job.cancel()
        assertTrue(finished.await(1, TimeUnit.SECONDS))
        job.cancelAndJoin()
        assertFalse(continuedIntoUdp)
        assertFalse(published)
        assertTrue(socket.closed)
    }

    @Test fun closeDuringTcpConnectClosesLocalSocketBeforePublication() {
        val socket = PokeSocket()
        var active = true
        var published = false
        var pairingPinWrites = 0
        assertFailsWith<InterruptedException> {
            openDatalinkPoke(socket,
                ensureActive = { if (!active) throw InterruptedException("driver closed") },
                connect = { active = false },
                initialize = { pairingPinWrites++ }, settle = {},
                publish = { published = true }, onFailure = {})
        }
        assertFalse(published)
        assertTrue(socket.closed)
        assertEquals(0, pairingPinWrites, "closed driver must not emit its pairing PIN after connect returns")
    }

    @Test fun ordinaryOptionalPokeFailureClosesSocketAndStillAllowsUdp() {
        val socket = PokeSocket()
        var failures = 0
        assertFalse(openDatalinkPoke(socket, {}, { throw java.io.IOException("refused") }, {}, {}, { failures++ }))
        assertTrue(socket.closed)
        assertEquals(1, failures)
    }
}
