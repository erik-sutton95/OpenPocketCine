package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class PortraitVerticalPictureTest {
    @Test
    fun verticalCameraFitsWholeInsideThePortraitWell() {
        // Narrow phone well (S25 portrait): height-only sizing was 452 dp wide in a 360 dp well.
        val phone = portraitVerticalPicture(ChromeRect(0f, 60f, 360f, 804f))
        assertTrue(phone.x >= 0f && phone.x + phone.width <= 360.01f)
        assertEquals(360f, phone.width, 0.01f)
        assertEquals(864f, phone.y + phone.height, 0.01f, "rests on the bottom of the well")
        // Tablet well: height-limited, pillarboxed, still whole.
        val tablet = portraitVerticalPicture(ChromeRect(0f, 80f, 800f, 1000f))
        assertEquals(1000f, tablet.height, 0.01f)
        assertEquals(400f, tablet.x + tablet.width / 2f, 0.01f)
    }
}
