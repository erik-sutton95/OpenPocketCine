@file:OptIn(kotlinx.coroutines.ExperimentalCoroutinesApi::class)

package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.currentTime
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest

class SessionRecoveryBudgetTest {
    @Test fun slowCameraApJoinCanFinishAfterTheAdvertisementDeadline() = runTest {
        var recovered = false
        val completed = withinAutomaticRecoveryBudget {
            recovered = recoverAfterAdvertisement(
                scan = { delay(1_000); "camera" },
                reconnect = {
                    delay(90_000) // supported DFS/Wi-Fi join allowance
                    delay(34_500) // full datalink open allowance
                    delay(8_000) // fresh-picture grace
                    true
                },
            )
        }
        assertTrue(completed)
        assertTrue(recovered)
        assertEquals(133_500, currentTime)
    }

    @Test fun cameraAbsentFromScanCannotSpendTheWholeEpisodeWaitingForAdvertisement() = runTest {
        var reconnects = 0
        val recovered = recoverAfterAdvertisement(
            scan = { delay(Long.MAX_VALUE); "absent" },
            reconnect = { reconnects++; true },
        )
        assertFalse(recovered)
        assertEquals(30_000, currentTime)
        assertEquals(0, reconnects)
    }

    @Test fun totalBudgetCancelsAnInFlightAttemptAndItsBackoff() = runTest {
        var cancelled = false
        val completed = withinAutomaticRecoveryBudget {
            try {
                delay(120_000) // scan and joining
                delay(80_000) // another handshake or backoff
            } finally { cancelled = true }
        }
        assertFalse(completed)
        assertTrue(cancelled)
        assertEquals(180_000, currentTime)
    }

    @Test fun operatorCancellationDoesNotPublishBudgetExhaustionForANewSession() = runTest {
        var exhausted = false
        val job = launch {
            exhausted = !withinAutomaticRecoveryBudget { delay(Long.MAX_VALUE) }
        }
        runCurrent()
        job.cancelAndJoin()
        assertFalse(exhausted)
    }
}
