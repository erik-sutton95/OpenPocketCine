package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LocalVPNFilterTest {
    @Test
    fun liveHintWaitsForStallWithoutPicture() {
        assertFalse(
            LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive = true,
                hadVideo = false,
                secondsWithoutVideo = 7.0,
            ),
        )
        assertTrue(
            LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive = true,
                hadVideo = false,
                secondsWithoutVideo = 8.0,
            ),
        )
        assertFalse(
            LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive = true,
                hadVideo = true,
                secondsWithoutVideo = 30.0,
            ),
        )
        assertFalse(
            LocalVPNFilter.shouldHintOnLiveWait(
                vpnActive = false,
                hadVideo = false,
                secondsWithoutVideo = 30.0,
            ),
        )
    }

    @Test
    fun operatorCopyDoesNotNameSisterApps() {
        val facing =
            listOf(
                LocalVPNFilter.WIZARD_BANNER,
                LocalVPNFilter.LIVE_HINT,
                LocalVPNFilter.JOIN_WIFI_PHONE_STEP,
            )
        for (text in facing) {
            assertFalse(text.contains("OpenZCine", ignoreCase = true))
            assertFalse(text.contains("Nikon", ignoreCase = true))
            assertFalse(text.contains("Mimo", ignoreCase = true))
            assertFalse(text.contains("AdGuard", ignoreCase = true))
            assertFalse(text.contains("Blokada", ignoreCase = true))
        }
    }
}
