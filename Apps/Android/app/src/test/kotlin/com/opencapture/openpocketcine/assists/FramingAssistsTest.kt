package com.opencapture.openpocketcine.assists

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class FramingAssistsTest {
    @Test
    fun filmAndSocialListsMatchIos() {
        assertEquals(
            listOf("2.76:1", "2.39:1", "2.35:1", "2.00:1", "1.85:1", "16:9", "1.66:1", "1.43:1", "4:3"),
            GuideAspect.film.map { it.label },
        )
        assertEquals(
            listOf("9:16", "4:5", "1:1", "2:3", "16:9", "1.91:1"),
            GuideAspect.social.map { it.label },
        )
        assertEquals(2.39f, GuideAspect.CINEMA.ratio, 1e-5f)
        assertEquals(0.5625f, GuideAspect.VERTICAL.ratio, 1e-5f)
        assertEquals(GuidesAssist.PANEL_WIDTH_DP, 472f)
        assertEquals("2.39:1", GuidesAssist.summaryLabel(setOf(GuideAspect.CINEMA)))
        assertEquals("2 ratios", GuidesAssist.summaryLabel(setOf(GuideAspect.CINEMA, GuideAspect.WIDE)))
        assertEquals("—", GuidesAssist.summaryLabel(emptySet()))
    }

    @Test
    fun rectForRatioLetterboxesAndPillarboxes() {
        val feed = AssistRect(10f, 20f, 1920f, 1080f)
        val wide = GuidesAssist.rectForRatio(feed, 2.39f)
        assertEquals(1920f, wide.width, 0.02f)
        assertEquals(1920f / 2.39f, wide.height, 0.02f)
        assertEquals(feed.midX, wide.midX, 0.02f)
        assertEquals(feed.midY, wide.midY, 0.02f)

        val tallFeed = AssistRect(0f, 0f, 1920f, 1080f)
        val tall = GuidesAssist.rectForRatio(tallFeed, 9f / 16f)
        assertEquals(1080f, tall.height, 0.02f)
        assertEquals(1080f * 9f / 16f, tall.width, 0.02f)
        assertEquals(tallFeed.midX, tall.midX, 0.02f)
    }

    @Test
    fun gridThirdsPhiAndDiagonalMatchOpenZcine() {
        assertEquals(1f / 3f, GridAssist.thirdsFractions[0], 1e-6f)
        assertEquals(2f / 3f, GridAssist.thirdsFractions[1], 1e-6f)
        assertEquals(0.382f, GridAssist.phiFractions[0], 1e-6f)
        assertEquals(0.618f, GridAssist.phiFractions[1], 1e-6f)
        assertEquals(0.22f, GridAssist.STROKE_OPACITY, 0.0001f)

        val feed = AssistRect(10f, 20f, 900f, 600f)
        val thirds = GridAssist.segments(feed, thirds = true, phi = false, diagonal = false)
        assertEquals(4, thirds.size)
        assertEquals(310f, thirds[0].from.x, 0.01f)
        assertEquals(20f, thirds[0].from.y, 0.01f)
        assertEquals(310f, thirds[0].to.x, 0.01f)
        assertEquals(620f, thirds[0].to.y, 0.01f)

        val phi = GridAssist.segments(AssistRect(0f, 0f, 1000f, 1000f), thirds = false, phi = true, diagonal = false)
        assertEquals(4, phi.size)
        assertEquals(382f, phi[0].from.x, 0.01f)
        assertEquals(618f, phi[2].from.x, 0.01f)

        val diag = GridAssist.segments(AssistRect(0f, 0f, 100f, 50f), thirds = false, phi = false, diagonal = true)
        assertEquals(AssistPoint(0f, 0f), diag[0].from)
        assertEquals(AssistPoint(100f, 50f), diag[0].to)
        assertEquals(AssistPoint(100f, 0f), diag[1].from)
        assertEquals(AssistPoint(0f, 50f), diag[1].to)

        assertTrue(
            GridAssist.segments(AssistRect(0f, 0f, 100f, 100f), thirds = false, phi = false, diagonal = false).isEmpty(),
        )
    }

    @Test
    fun crosshairConstantsMatchIos() {
        assertEquals(40f, CrosshairAssist.ARM_LENGTH_DP)
        assertEquals(1.4f, CrosshairAssist.STROKE_WIDTH_DP)
        assertEquals(0.65f, CrosshairAssist.OPACITY)
        val feed = AssistRect(10f, 20f, 200f, 100f)
        assertEquals(110f, feed.midX)
        assertEquals(70f, feed.midY)
    }
}
