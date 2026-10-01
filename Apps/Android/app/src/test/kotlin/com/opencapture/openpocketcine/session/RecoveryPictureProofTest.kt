package com.opencapture.openpocketcine.session

import com.opencapture.opencine.media.PresentedFrameClock
import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class RecoveryPictureProofTest {
    @Test fun unseenImageFromBeforeForegroundCannotDismissRecovery() {
        val clock = PresentedFrameClock()
        clock.note(sourceNs = 12, nowMs = 100)
        val resumedAt = clock.beginProbe(sourceNowNs = 20, nowMs = 10_000)
        assertFalse(clock.note(sourceNs = 19, nowMs = 10_001))
        assertFalse(RecoveryPictureProof.isFresh(resumedAt, 10_002, clock.lastPresentedAt, 10_001))
        assertTrue(clock.note(sourceNs = 21, nowMs = 10_003))
        assertTrue(RecoveryPictureProof.isFresh(resumedAt, 10_004, clock.lastPresentedAt, 10_003))
    }

    @Test fun handshakeOrNewAuWithoutNewPresentCannotCompleteRecovery() {
        assertFalse(RecoveryPictureProof.isFresh(100, 200, 99, 199))
        assertFalse(RecoveryPictureProof.isFresh(100, 200, 199, 99))
        assertFalse(RecoveryPictureProof.isFresh(100, 200, null, 199))
        assertTrue(RecoveryPictureProof.isFresh(100, 200, 199, 199))
        assertFalse(RecoveryPictureProof.isFresh(100, 2_200, 199, 2_199))
    }
}
