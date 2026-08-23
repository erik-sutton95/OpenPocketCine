package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue

class CamFovTest {
    @Test
    fun raw12287IsOneXNotTwelve() {
        assertEquals(1.0, CamFov.factor(12_287), 0.01)
        assertEquals("1×", CamFov.displayLabel(12_287))
        assertEquals(
            "1×",
            CamFov.displayLabel(CamFov.readout(live = CamFov.factor(12_287), preview = null, fallback = 12.0)),
        )
        val status = CamFov.absorb(CameraStatus(zoomFactorRaw = 12_287))
        assertEquals(1.0, status.zoomFactor ?: 0.0, 0.01)
    }

    @Test
    fun displayTenthsAndLabelsMatchIos() {
        assertEquals("2.3×", CamFov.displayLabel(2.29))
        assertEquals("5.3×", CamFov.displayLabel(5.3))
        assertEquals("5.3×", CamFov.displayLabel(5.34))
        assertEquals("5.4×", CamFov.displayLabel(5.36))
        assertEquals("2.9×", CamFov.displayLabel(2.89))
        assertEquals("2.9×", CamFov.displayLabel(2.9))
        assertEquals("3×", CamFov.displayLabel(2.95))
        assertEquals(2.3, CamFov.displayTenths(2.286), 0.001)
        assertEquals(50L, CamFov.SLIDER_COALESCE_MS)
        assertEquals(2.9, CamFov.displayTenths(2.9), 0.001)
        assertEquals(3.0, CamFov.displayTenths(2.95), 0.001)
        assertEquals(5.3, CamFov.displayTenths(5.34), 0.001)
        assertEquals(5.4, CamFov.displayTenths(5.36), 0.001)
    }

    @Test
    fun chipJumpsAndWritesMatchIos() {
        assertEquals(3.0, CamFov.nextJump(1.0), 0.0)
        assertEquals(3.0, CamFov.nextJump(2.3), 0.0)
        assertEquals(3.0, CamFov.nextJump(2.89), 0.0)
        assertEquals(3.0, CamFov.nextJump(2.9), 0.0)
        assertEquals(6.0, CamFov.nextJump(3.0), 0.0)
        assertEquals(6.0, CamFov.nextJump(5.4), 0.0)
        assertEquals(12.0, CamFov.nextJump(6.0), 0.0)
        assertEquals(1.0, CamFov.nextJump(12.0), 0.0)
        assertEquals(CamFov.ChipWrite.Lens(CamFov.LENS_1X), CamFov.chipWrite(1.0))
        assertEquals(CamFov.ChipWrite.Lens(CamFov.LENS_3X), CamFov.chipWrite(3.0))
        assertEquals(CamFov.ChipWrite.Lens(CamFov.LENS_6X), CamFov.chipWrite(6.0))
        assertEquals(CamFov.ChipWrite.Lens(CamFov.LENS_12X), CamFov.chipWrite(12.0))
        assertEquals(217, CamFov.lensPosition(1.0))
        assertEquals(651, CamFov.lensPosition(3.0))
        assertEquals(1_302, CamFov.lensPosition(6.0))
        assertEquals(2_604, CamFov.lensPosition(12.0))
        assertEquals(477, CamFov.lensPosition(2.2))
        assertEquals(1_454, CamFov.lensPosition(6.7))
        assertTrue(CamFov.isJumpStop(1.0) && CamFov.isJumpStop(3.0))
        assertTrue(CamFov.isJumpStop(6.0) && CamFov.isJumpStop(12.0))
        assertTrue(!CamFov.isJumpStop(2.3) && !CamFov.isJumpStop(5.4))
    }

    @Test
    fun pinchHybridMatchesIos() {
        assertEquals(2.53, CamFov.pinchFactor(2.3, 1.1), 0.001)
        assertEquals(2.5, CamFov.pinchPreview(2.3, 1.1), 0.001)
        assertEquals(2.3, CamFov.pinchPreview(2.3, 1.0), 0.001)
        assertEquals(2.9, CamFov.pinchPreview(2.3, 1.261), 0.001)
        assertEquals(2.9, CamFov.pinchPreview(1.0, 2.9), 0.001)
        assertEquals(3.0, CamFov.pinchPreview(1.0, 3.0), 0.001)
        assertEquals(477, CamFov.pinchLens(2.2))
        assertEquals(1_454, CamFov.pinchLens(6.7))
        assertTrue(CamFov.pinchLens(2.53) != CamFov.pinchLens(2.5))
        assertTrue(CamFov.pinchLens(2.9) != CamFov.pinchLens(3.0))
        assertEquals(5.4, CamFov.readout(live = 5.36, preview = null, fallback = 1.0), 0.001)
        assertEquals(5.3, CamFov.readout(live = 2.29, preview = 5.3, fallback = 1.0), 0.001)
        assertEquals(1.0, CamFov.readout(live = null, preview = null, fallback = 1.0), 0.001)
        assertTrue(CamFov.matches(1.0, 1.0))
        assertTrue(!CamFov.matches(3.0, 12.0))
        assertTrue(!CamFov.usesTelephoto(2.9))
        assertTrue(CamFov.usesTelephoto(3.0))
    }

    @Test
    fun dLog2DropsOffOneX() {
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CamFov.colorModeForZoom(1.1, CameraCommands.COLOR_DLOG2),
        )
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CamFov.colorModeForZoom(2.9, CameraCommands.COLOR_DLOG2),
        )
        assertNull(CamFov.colorModeForZoom(1.0, CameraCommands.COLOR_DLOG2))
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CamFov.colorModeForZoom(1.06, CameraCommands.COLOR_DLOG2),
        )
        assertNull(CamFov.colorModeForZoom(3.0, CameraCommands.COLOR_DLOG))
        assertTrue(CamFov.shouldRestoreDLog2(1.0))
        assertTrue(!CamFov.shouldRestoreDLog2(2.9))
    }

    @Test
    fun zoomPayloadsMatchIosBytes() {
        assertTrue(CameraCommands.zoomLens(217).contentEquals(byteArrayOf(0x0A, 0x4E, 0xD9.toByte(), 0x00)))
        assertTrue(CameraCommands.zoomLens(651).contentEquals(byteArrayOf(0x0A, 0x4E, 0x8B.toByte(), 0x02)))
        assertTrue(CameraCommands.zoomLens(1_302).contentEquals(byteArrayOf(0x0A, 0x4E, 0x16, 0x05)))
        assertTrue(CameraCommands.zoomLens(2_604).contentEquals(byteArrayOf(0x0A, 0x4E, 0x2C, 0x0A)))
        assertTrue(CameraCommands.zoomSlew(100).contentEquals(byteArrayOf(0x03, 0x00, 0x64, 0x00)))
        assertTrue(CameraCommands.zoomSlew(300).contentEquals(byteArrayOf(0x03, 0x00, 0x2C, 0x01)))
        assertTrue(CameraCommands.zoomStop().contentEquals(byteArrayOf(0xFF.toByte(), 0x00, 0x00, 0x00)))
        val pinch22 = CameraCommands.zoomLens(CamFov.lensPosition(2.2))
        assertTrue(pinch22.contentEquals(byteArrayOf(0x0A, 0x4E, 0xDD.toByte(), 0x01)))
        val pinch67 = CameraCommands.zoomLens(CamFov.lensPosition(6.7))
        assertTrue(pinch67.contentEquals(byteArrayOf(0x0A, 0x4E, 0xAE.toByte(), 0x05)))
    }

    @Test
    fun lensAt14AndFovSubscribeSetHybridFactor() {
        val fov =
            byteArrayOf(
                0xFF.toByte(), 0x2F, 0x00, 0x00, 0x00, 0x1B, 0x00, 0x00, 0x01, 0x00,
                0x00, 0x00, 0xA8.toByte(), 0x1B, 0x00, 0x00, 0x01, 0x99.toByte(), 0x31,
                0x00, 0x00, 0x00, 0x1C, 0x00, 0x00,
            )
        val fromFov = StatusExtras.applyFov(fov, CameraStatus())
        assertEquals(12_287, fromFov.zoomFactorRaw)
        assertEquals(1.0, fromFov.zoomFactor ?: 0.0, 0.01)
        val lensBlob = ByteArray(16)
        lensBlob[14] = (217 and 0xFF).toByte()
        lensBlob[15] = ((217 shr 8) and 0xFF).toByte()
        val fromLens = StatusExtras.applyLens(lensBlob, fromFov)
        assertEquals(217, fromLens.zoomLens)
        assertEquals(1.0, fromLens.zoomFactor ?: 0.0, 0.01)
        lensBlob[14] = (651 and 0xFF).toByte()
        lensBlob[15] = ((651 shr 8) and 0xFF).toByte()
        val at3 = StatusExtras.applyLens(lensBlob, fromFov)
        assertEquals(651, at3.zoomLens)
        assertEquals(3.0, at3.zoomFactor ?: 0.0, 0.02)
    }
}
