package com.opencapture.openpocketcine.pairing

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class StationNetworkCredentialsTest {
    @Test fun openWifiIsAllowedButHotspotRequiresAPassphrase() {
        assertTrue(validStationCredentials("Test network", "", false))
        assertFalse(validStationCredentials("Test hotspot", "", true))
        assertFalse(validStationCredentials("Test network", "short", false))
        assertTrue(validStationCredentials("Test hotspot", "test-passphrase", true))
    }

    @Test fun namesAndPasswordsRespectWireByteBounds() {
        assertFalse(validStationCredentials("", "test-passphrase", false))
        assertTrue(validStationCredentials("é".repeat(16), "a".repeat(63), false))
        assertFalse(validStationCredentials("é".repeat(17), "test-passphrase", false))
        assertFalse(validStationCredentials("Test network", "é".repeat(32), false))
    }
}
