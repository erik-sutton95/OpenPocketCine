package com.opencapture.openpocketcine.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MediaDeliveryDestinationTest {
    @Test
    fun shareListsUpcomingDestinationsWithoutMakingThemDeliverable() {
        assertEquals(listOf(MediaDeliveryDestination.NATIVE_SHARE), MediaDeliveryDestination.entries)
        assertEquals(
            listOf(
                "Google Drive",
                "Dropbox",
                "NAS (SMB)",
                "LucidLink",
                "Backblaze B2",
                "Vimeo Review",
            ),
            MediaDeliveryUpcoming.titles,
        )
        assertEquals("Share", MediaDeliveryDestination.NATIVE_SHARE.actionTitle)
        assertTrue(MediaDeliveryUpcoming.titles.none { it.equals("Share", ignoreCase = true) })
    }
}
