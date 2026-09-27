package com.opencapture.openpocketcine.multiview

import com.opencapture.openpocketcine.session.DumlFrame
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.runBlocking
import org.junit.Assert.*
import org.junit.Test

class MultiviewExitTest {
    private fun reply(payload: ByteArray, opcode: Int = 0x45) =
        DumlFrame(7, 2, 1202, 0x80, 7, opcode, payload)

    @Test fun firstExitRetriesCapturedReplyAfterClosingTheAttempt() = runBlocking {
        var attempts = 0
        var closes = 0
        var waits = 0
        var apCommands = 0
        val restored = restoreCameraWiFiWithRetry(waitBetween = {
            waits++
            assertEquals(attempts, closes)
        }) {
            attempts++
            try {
                val payload = if (attempts == 1) byteArrayOf(0, 6) else byteArrayOf(0, 1)
                check(acceptsMultiviewPairingReply(reply(payload), 1202))
                apCommands++
                true
            } finally {
                closes++
            }
        }
        assertTrue(restored)
        assertEquals(2, attempts)
        assertEquals(1, waits)
        assertEquals(1, apCommands)
        assertEquals(2, closes)
    }

    @Test fun repeatedDeferralStopsAtThreeAttempts() = runBlocking {
        var attempts = 0
        assertFalse(restoreCameraWiFiWithRetry(waitBetween = {}) {
            attempts++
            acceptsMultiviewPairingReply(reply(byteArrayOf(0, 6)), 1202)
        })
        assertEquals(3, attempts)
    }

    @Test fun otherRejectionsAndFailedAPCommandsDoNotRetry() = runBlocking {
        for (pairingRejected in listOf(true, false)) {
            var attempts = 0
            assertFalse(restoreCameraWiFiWithRetry(waitBetween = { fail("Unexpected retry") }) {
                attempts++
                if (pairingRejected) acceptsMultiviewPairingReply(reply(byteArrayOf(0, 3)), 1202)
                false
            })
            assertEquals(1, attempts)
        }
    }

    @Test fun approvalRequiresMatchingOpcodeSequenceAndExactReply() {
        assertTrue(acceptsMultiviewPairingReply(reply(byteArrayOf(0, 1)), 1202))
        assertFalse(acceptsMultiviewPairingReply(reply(byteArrayOf(0, 1)), 1203))
        assertFalse(acceptsMultiviewPairingReply(reply(byteArrayOf(0, 1), 0x39), 1202))
        assertFalse(acceptsMultiviewPairingReply(reply(byteArrayOf(0, 2)), 1202))
    }

    @Test fun cancellationDoesNotBecomeAReportedSuccess() = runBlocking {
        try {
            restoreCameraWiFiWithRetry(waitBetween = {}) { throw CancellationException() }
            fail("Cancellation must propagate")
        } catch (_: CancellationException) { }
    }
}
