package com.opencapture.openpocketcine.pairing

import com.opencapture.openpocketcine.SettingsHelpCopy
import com.opencapture.openpocketcine.session.LocalVPNFilter
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

    @Test
    fun joinWifiNamesVpnWithoutProductBrands() {
        assertEquals(
            "Pause VPNs and ad blockers, or exclude this app",
            LocalVPNFilter.JOIN_WIFI_PHONE_STEP,
        )
        assertFalse(LocalVPNFilter.JOIN_WIFI_PHONE_STEP.contains("AdGuard", ignoreCase = true))
    }
}
