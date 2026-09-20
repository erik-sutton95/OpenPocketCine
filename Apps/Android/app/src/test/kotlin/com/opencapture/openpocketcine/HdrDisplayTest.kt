package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HdrDisplayTest {
    @Test
    fun requestedHeadroomMatchesIos() {
        assertEquals(3f, HdrDisplay.REQUESTED_HEADROOM)
    }

    @Test
    fun helpCopyDisambiguatesCameraHdr() {
        assertTrue(SettingsHelpCopy.HDR_DISPLAY.contains("HDR/HLG"))
        assertTrue(SettingsHelpCopy.HDR_DISPLAY.contains("Off by default"))
        assertTrue(SettingsHelpCopy.HDR_DISPLAY.contains("decoded camera signal"))
        assertTrue(SettingsHelpCopy.HDR_DISPLAY.contains("Screen recording"))
        assertFalse(SettingsHelpCopy.HDR_DISPLAY.contains("OpenZCine"))
        assertFalse(SettingsHelpCopy.HDR_DISPLAY.contains("Nikon"))
    }

    @Test
    fun screenCaptureDisablesEffectiveHdr() {
        assertTrue(HdrDisplay.isEffective(preferred = true, screenCaptured = false))
        assertFalse(HdrDisplay.isEffective(preferred = true, screenCaptured = true))
        assertFalse(HdrDisplay.isEffective(preferred = false, screenCaptured = false))
    }
}
