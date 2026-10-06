package com.opencapture.openpocketcine.pairing

import com.opencapture.opencine.dji.DjiFailures
import com.opencapture.opencine.vocabulary.ConnectionPhase
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** The vendor-app tip reaches the pair page, the scan hint and the failure cards (SHELL-02). */
class StartupConnectionCopyTest {
    private val tip = "Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera."

    @Test
    fun aCameraThatNeverAnswersNamesFrameTapAndMimo() {
        assertEquals(tip, DjiFailures.DJI_APPS_TIP)
        assertTrue(StartupConnectionCopy.PAIRING_PRECHECK.contains("DJI Frame Tap") && StartupConnectionCopy.PAIRING_PRECHECK.contains("DJI Mimo"))
        assertTrue(StartupConnectionCopy.STILL_LOOKING.startsWith(tip))
        val card = DjiFailures.classify(null, ConnectionPhase.OPENING_DATALINK, "camera never answered the datalink handshake")
        assertEquals("Camera never answered the datalink handshake. $tip", card.message)
        assertTrue(DjiFailures.classify(null, ConnectionPhase.AWAITING_APPROVAL, "pairing timed out").message.endsWith(tip))
    }

    @Test
    fun otherFailuresKeepTheirCopy() {
        assertFalse(DjiFailures.classify(null, ConnectionPhase.JOINING_WIFI, "the camera disconnected").message.contains("Frame Tap"))
    }
}
