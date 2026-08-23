package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.GpuLiveLayout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Pure-JVM checks of the hardware glass gate. No runtime demote. */
class GlassTierTest {
    @Test
    fun glassChromeMustNotSitInsideTheLayerItSamples() {
        assertTrue(kyantWouldLoop(chromeInsideRecordedLayer = true))
        assertFalse(kyantWouldLoop(chromeInsideRecordedLayer = false))
    }

    @Test
    fun liveLiquidGlassProbeForcesFlatOverride() {
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, "flat", totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
    }

    @Test
    fun platformCeilingPicksTheTier() {
        assertEquals(GlassTier.FULL, resolveTier(33, totalRamBytes = 6L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FULL, resolveTier(36, totalRamBytes = 8L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FLAT, resolveTier(31))
        assertEquals(GlassTier.FLAT, resolveTier(32))
        assertEquals(GlassTier.FLAT, resolveTier(29))
    }

    @Test
    fun lowEndDevicesStayFlatEvenOnApi33() {
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, totalRamBytes = 3L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, isLowRamDevice = true, totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FULL,
            resolveTier(33, totalRamBytes = MIN_FULL_GLASS_RAM_BYTES),
        )
    }

    @Test
    fun overrideLowersButNeverRaises() {
        assertEquals(GlassTier.FLAT, resolveTier(33, "flat", totalRamBytes = 8L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FLAT, resolveTier(33, "blur", totalRamBytes = 8L * 1024 * 1024 * 1024))
        assertEquals(GlassTier.FLAT, resolveTier(31, "full"))
        assertEquals(GlassTier.FLAT, resolveTier(29, "full"))
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, "full", totalRamBytes = 3L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FLAT,
            resolveTier(33, "full", isLowRamDevice = true, totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
    }

    @Test
    fun unknownOverrideFallsBackToTheCeiling() {
        assertEquals(
            GlassTier.FULL,
            resolveTier(33, "chrome", totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
        assertEquals(
            GlassTier.FULL,
            resolveTier(33, null, totalRamBytes = 8L * 1024 * 1024 * 1024),
        )
    }

    @Test
    fun scopePlateIsDjiBlackAtSeventyTwoPercent() {
        assertEquals(20 / 255f, LiveDesign.scopePlate.red, 0.001f)
        assertEquals(20 / 255f, LiveDesign.scopePlate.green, 0.001f)
        assertEquals(20 / 255f, LiveDesign.scopePlate.blue, 0.001f)
        assertEquals(0.72f, LiveDesign.scopePlate.alpha, 0.01f)
        assertEquals(LiveDesign.scopePlate.red, GpuLiveLayout.PANEL_FILL_R, 0.001f)
        assertEquals(LiveDesign.scopePlate.alpha, GpuLiveLayout.PANEL_FILL_A, 0.01f)
    }

    @Test
    fun playbackBarPlateIsHalfHudNd() {
        assertEquals(LiveDesign.chromePlate.alpha * 0.5f, LiveDesign.playbackBarPlate.alpha, 0.01f)
        assertEquals(LiveDesign.chromeTint.alpha * 0.5f, LiveDesign.playbackBarTint.alpha, 0.01f)
    }

    @Test
    fun shareSheetPlateIsDjiBlackAndNearlyOpaque() {
        assertEquals(20 / 255f, LiveDesign.sheetPlate.red, 0.001f)
        assertEquals(20 / 255f, LiveDesign.sheetPlate.green, 0.001f)
        assertEquals(20 / 255f, LiveDesign.sheetPlate.blue, 0.001f)
        assertEquals(0.94f, LiveDesign.sheetPlate.alpha, 0.01f)
        assertTrue(LiveDesign.sheetPlate.alpha > LiveDesign.scopePlate.alpha)
        assertEquals(0.48f, LiveDesign.sheetScrim.alpha, 0.01f)
        assertTrue(LiveDesign.sheetScrim.alpha > 0.18f)
    }

    @Test
    fun pickerNdIsATadDenserThanHudPlate() {
        assertEquals(0.20f, LiveDesign.pickerNd.alpha, 0.01f)
        assertTrue(LiveDesign.pickerNd.alpha > 0f)
        assertTrue(LiveDesign.pickerNd.alpha < LiveDesign.chromeTint.alpha)
    }

    @Test
    fun backdropUsesTheFeedRenderersFitAndFillTransforms() {
        val fit = requireNotNull(glassBackdropContentRect(400f, 600f, 1_920, 1_080, false))
        val fill = requireNotNull(glassBackdropContentRect(400f, 600f, 1_920, 1_080, true))

        assertTrue(fit.top > 0)
        assertEquals(400, fit.width)
        assertTrue(fill.left < 0)
        assertEquals(600, fill.height)
    }

    @Test
    fun portraitFillCenterCropsSixteenNineIntoANineSixteenWell() {
        val wellH = 390f * 16f / 9f
        val content = portraitFillCropContent(ChromeRect(0f, 0f, 390f, wellH))
        val fill = requireNotNull(liveFeedContentRect(390f, wellH, 1_280, 720, aspectFill = true))
        assertTrue(fill.left < 0)
        assertEquals(wellH.toInt(), fill.height)
        assertEquals(content.height.toInt(), fill.height)
        assertTrue(fill.width > 390)
        assertEquals(16f / 9f, content.width / content.height, 0.001f)
    }

}
