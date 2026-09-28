package com.opencapture.openpocketcine.pairing

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StartupConnectionCopyTest {
    private val tip = "Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera."

    @Test
    fun aCameraThatNeverAnswersNamesFrameTapAndMimo() {
        assertEquals(
            "The camera didn't respond in time. Check Bluetooth and try again. $tip",
            StartupConnectionCopy.friendly("pairing timed out, tap Approve on the camera if it asked"),
        )
        assertEquals(
            "The camera never answered the video link. $tip",
            StartupConnectionCopy.friendly("camera never answered the datalink handshake"),
        )
        val saved = SavedCamera("a", "Pocket", "Osmo Pocket 4 Pro", "Pocket", 1L)
        val card = SavedCameraSetupPresentation.failure(
            "camera never answered the datalink handshake", CameraConnectionSetup.CAMERA_WIFI, saved, false,
        )
        assertTrue(card.message.endsWith(tip))
    }

    @Test
    fun otherFailuresKeepTheirCopy() {
        assertEquals(
            "The camera didn't respond in time. Check Bluetooth and try again.",
            StartupConnectionCopy.friendly("Bluetooth connect timed out"),
        )
        assertFalse(StartupConnectionCopy.friendly("disconnected").contains("Frame Tap"))
        assertTrue(StartupConnectionCopy.STILL_LOOKING.startsWith(tip))
    }
}
