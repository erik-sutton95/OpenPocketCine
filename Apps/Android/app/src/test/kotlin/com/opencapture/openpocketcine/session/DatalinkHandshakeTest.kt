package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.pairing.CameraApJoiner
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class DatalinkHandshakeTest {
    @Test
    fun handshakeMissIsRecoverableExceptionNotIllegalState() {
        val error = DatalinkDriver.handshakeTimeoutFailure()
        assertTrue(error !is IllegalStateException, "must not be Kotlin error()")
        assertTrue(
            error is DatalinkDriver.DatalinkError.NoHandshake,
            "iOS throws DatalinkError.noHandshake — Android must not use error()/IllegalStateException",
        )
        assertEquals("camera never answered the datalink handshake", error.message)
    }

    @Test
    fun processBindStaysReadyDuringReassociationGrace() {
        assertTrue(CameraApJoiner.isPathReady(hasBoundNetwork = true, inReassociationGrace = false))
        assertTrue(
            CameraApJoiner.isPathReady(hasBoundNetwork = false, inReassociationGrace = true),
            "SoftAP onLost nulls the Network object; process bind + grace is still the camera path",
        )
        assertTrue(!CameraApJoiner.isPathReady(hasBoundNetwork = false, inReassociationGrace = false))
    }

    @Test
    fun handshakeMissWhileGraceArmedRebindsInsteadOfFailing() {
        val pathReady =
            CameraApJoiner.isPathReady(hasBoundNetwork = false, inReassociationGrace = true)
        assertEquals(
            LiveViewEnablePolicy.HandshakeTimeoutStep.REBIND_UDP,
            LiveViewEnablePolicy.handshakeTimeoutStep(
                pathReady = pathReady,
                rebindsUsed = 0,
                inboundDatagrams = 0,
            ),
        )
        assertTrue(!LiveViewEnablePolicy.shouldKickAfterHandshakeTimeout(pathReady))
    }

    @Test
    fun handshakeMissAfterPathGoneIsKickNotCrashType() {
        val pathReady =
            CameraApJoiner.isPathReady(hasBoundNetwork = false, inReassociationGrace = false)
        assertEquals(
            LiveViewEnablePolicy.HandshakeTimeoutStep.FAIL,
            LiveViewEnablePolicy.handshakeTimeoutStep(
                pathReady = pathReady,
                rebindsUsed = 0,
                inboundDatagrams = 0,
            ),
        )
        assertTrue(LiveViewEnablePolicy.shouldKickAfterHandshakeTimeout(pathReady))
        assertTrue(DatalinkDriver.handshakeTimeoutFailure() !is IllegalStateException)
    }
}
