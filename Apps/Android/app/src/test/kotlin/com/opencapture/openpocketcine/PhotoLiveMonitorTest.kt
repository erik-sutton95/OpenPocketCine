package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.lut.LutCatalog
import com.opencapture.openpocketcine.lut.PlaybackLutColor
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PhotoLiveMonitorTest {
    @Test
    fun photoAndLivePhotoForceRec709WithoutMutatingRawColor() {
        val dlog2 = CameraStatus(colorMode = CameraCommands.COLOR_DLOG2, shootingMode = CameraCommands.SHOOT_VIDEO)
        assertEquals(CameraCommands.COLOR_DLOG2, dlog2.monitorColorMode)
        assertFalse(dlog2.isPhoto)

        for (mode in listOf(
            CameraCommands.SHOOT_PHOTO,
            CameraCommands.SHOOT_PHOTO_POCKET4,
            CameraCommands.SHOOT_LIVE_PHOTO,
        )) {
            val photo = dlog2.copy(shootingMode = mode)
            assertTrue(photo.isPhoto)
            assertEquals(CameraCommands.COLOR_NORMAL, photo.monitorColorMode)
            assertEquals(CameraCommands.COLOR_DLOG2, photo.colorMode)
        }

        val night = dlog2.copy(shootingMode = CameraCommands.SHOOT_SUPER_NIGHT)
        assertFalse(night.isPhoto)
        assertEquals(CameraCommands.COLOR_DLOG2, night.monitorColorMode)
    }

    @Test
    fun playbackClipColorWinsWhileCameraStaysPhoto() {
        val photo =
            CameraStatus(
                colorMode = CameraCommands.COLOR_DLOG2,
                shootingMode = CameraCommands.SHOOT_PHOTO_POCKET4,
            )
        assertEquals(CameraCommands.COLOR_NORMAL, photo.monitorColorMode)
        assertEquals(
            CameraCommands.COLOR_DLOG2,
            PlaybackLutColor.resolve(
                clip = CameraCommands.COLOR_DLOG2,
                live = photo.colorMode,
                last = CameraCommands.COLOR_DLOG,
            ),
        )
        assertEquals(
            CameraCommands.COLOR_NORMAL,
            PlaybackLutColor.resolve(
                clip = CameraCommands.COLOR_NORMAL,
                live = photo.colorMode,
                last = CameraCommands.COLOR_DLOG2,
            ),
        )
    }

    @Test
    fun photoCatalogKeepsGenericExtraCubes() {
        val photo =
            LutCatalog.djiEntries(
                listOf("DJI_Official_Pocket4P_DLog2_Rec709_33.cube", "Film.cube"),
                isPhotoLive = true,
            )
        assertEquals(listOf("djiAuto", "asset:Film.cube"), photo.map { it.id })
    }
}
