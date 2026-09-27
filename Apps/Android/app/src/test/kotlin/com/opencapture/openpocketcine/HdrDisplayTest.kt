package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HdrDisplayTest {
    @Test
    fun screenCaptureDisablesEffectiveHdr() {
        assertTrue(HdrDisplay.isEffective(preferred = true, screenCaptured = false))
        assertFalse(HdrDisplay.isEffective(preferred = true, screenCaptured = true))
        assertFalse(HdrDisplay.isEffective(preferred = false, screenCaptured = false))
    }
}
