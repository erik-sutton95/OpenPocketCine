package com.opencapture.openpocketcine.pairing

import com.opencapture.openpocketcine.SettingsHelpCopy
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PairingCopyTest {
    @Test
    fun shareDiagnosticsMatchesSettingsTitle() {
        assertEquals("Share Diagnostics", StartupConnectionCopy.SHARE_DIAGNOSTICS)
        assertFalse(StartupConnectionCopy.SHARE_DIAGNOSTICS.contains("OpenZCine", ignoreCase = true))
        assertFalse(StartupConnectionCopy.SHARE_DIAGNOSTICS.contains("Nikon", ignoreCase = true))
        assertTrue(SettingsHelpCopy.SHARE_DIAGNOSTICS.contains("No name"))
    }
}
