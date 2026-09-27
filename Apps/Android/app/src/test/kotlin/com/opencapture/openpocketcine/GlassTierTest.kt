package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.feed.GpuLiveLayout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Pure-JVM checks of the hardware glass gate. No runtime demote. */
class GlassTierTest {
    private data class TierCase(
        val name: String,
        val sdkInt: Int,
        val override: String? = null,
        val isLowRamDevice: Boolean = false,
        val totalRamBytes: Long = Long.MAX_VALUE,
        val expected: GlassTier,
    )

    @Test
    fun resolveTierHonoursCeilingRamAndLowerOnlyOverrides() {
        val gb = 1024L * 1024 * 1024
        val cases = listOf(
            // Platform ceiling picks the tier.
            TierCase("api33 6GB", 33, totalRamBytes = 6 * gb, expected = GlassTier.FULL),
            TierCase("api36 8GB", 36, totalRamBytes = 8 * gb, expected = GlassTier.FULL),
            TierCase("api31", 31, expected = GlassTier.FLAT),
            TierCase("api32", 32, expected = GlassTier.FLAT),
            TierCase("api29", 29, expected = GlassTier.FLAT),
            // Low-end devices stay flat even on API 33.
            TierCase("api33 3GB", 33, totalRamBytes = 3 * gb, expected = GlassTier.FLAT),
            TierCase("api33 lowRam", 33, isLowRamDevice = true, totalRamBytes = 8 * gb, expected = GlassTier.FLAT),
            TierCase("api33 min full RAM", 33, totalRamBytes = MIN_FULL_GLASS_RAM_BYTES, expected = GlassTier.FULL),
            // Override lowers but never raises.
            TierCase("flat override", 33, "flat", totalRamBytes = 8 * gb, expected = GlassTier.FLAT),
            TierCase("blur override", 33, "blur", totalRamBytes = 8 * gb, expected = GlassTier.FLAT),
            TierCase("full override api31", 31, "full", expected = GlassTier.FLAT),
            TierCase("full override api29", 29, "full", expected = GlassTier.FLAT),
            TierCase("full override 3GB", 33, "full", totalRamBytes = 3 * gb, expected = GlassTier.FLAT),
            TierCase(
                "full override lowRam", 33, "full", isLowRamDevice = true, totalRamBytes = 8 * gb,
                expected = GlassTier.FLAT,
            ),
            // Unknown override falls back to the ceiling.
            TierCase("unknown override", 33, "chrome", totalRamBytes = 8 * gb, expected = GlassTier.FULL),
            TierCase("null override", 33, null, totalRamBytes = 8 * gb, expected = GlassTier.FULL),
        )
        for (case in cases) {
            val actual = resolveTier(case.sdkInt, case.override, case.isLowRamDevice, case.totalRamBytes)
            assertEquals(case.expected, actual, case.name)
        }
    }

    @Test
    fun scopePlateMatchesTheGpuPanelFill() {
        assertEquals(LiveDesign.scopePlate.red, GpuLiveLayout.PANEL_FILL_R, 0.001f)
        assertEquals(LiveDesign.scopePlate.alpha, GpuLiveLayout.PANEL_FILL_A, 0.01f)
    }

    @Test
    fun feedContentRectFitsAndFillsLikeTheRenderer() {
        val fit = requireNotNull(liveFeedContentRect(400f, 600f, 1_920, 1_080, aspectFill = false))
        val fill = requireNotNull(liveFeedContentRect(400f, 600f, 1_920, 1_080, aspectFill = true))
        assertTrue(fit.top > 0)
        assertEquals(400, fit.width)
        assertTrue(fill.left < 0)
        assertEquals(600, fill.height)

        val wellH = 390f * 16f / 9f
        val content = portraitFillCropContent(ChromeRect(0f, 0f, 390f, wellH))
        val portrait = requireNotNull(liveFeedContentRect(390f, wellH, 1_280, 720, aspectFill = true))
        assertTrue(portrait.left < 0)
        assertEquals(wellH.toInt(), portrait.height)
        assertEquals(content.height.toInt(), portrait.height)
        assertTrue(portrait.width > 390)
    }
}
