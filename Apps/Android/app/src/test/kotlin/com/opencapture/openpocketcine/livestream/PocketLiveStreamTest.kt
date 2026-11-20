package com.opencapture.openpocketcine.livestream

import com.opencapture.opencine.dji.CameraConnectionSetup
import com.opencapture.opencine.streaming.StreamConnectionRoute
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

/** What the shared stream eligibility rule reads from this app's connection mode and picture. */
class PocketLiveStreamTest {
    @Test
    fun connectionModeMapsToItsStreamRoute() {
        assertEquals(StreamConnectionRoute.CAMERA_WIFI, pocketStreamRoute(true, CameraConnectionSetup.CAMERA_WIFI))
        assertEquals(StreamConnectionRoute.SHARED_WIFI, pocketStreamRoute(true, CameraConnectionSetup.WIFI))
        assertEquals(StreamConnectionRoute.DEVICE_HOTSPOT, pocketStreamRoute(true, CameraConnectionSetup.PHONE_HOTSPOT))
        CameraConnectionSetup.entries.forEach { assertNull(pocketStreamRoute(false, it), "no live camera, $it") }
    }

    @Test
    fun sourceIsTheLivePictureSizeWithoutAStatedRate() {
        val source = pocketStreamSource(hasPicture = true, width = 1920, height = 1080)
        assertEquals(1920, source?.width)
        assertEquals(1080, source?.height)
        assertNull(source?.fpsNum)
        assertNull(pocketStreamSource(hasPicture = false, width = 1280, height = 720))
    }
}
