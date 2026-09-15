package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class MonitorLayoutPolicyTest {
    @Test
    fun phoneAndTabletPortraitValuesStayAboveSystemActions() {
        val devices = listOf(320f to 568f, 375f to 667f, 393f to 852f, 430f to 932f, 744f to 1133f, 1024f to 1366f)
        for ((width, height) in devices) for (aspect in listOf(16f / 9f, 1f, 9f / 16f)) {
            for (fill in listOf(false, true)) for (visible in listOf(false, true)) {
                val result = MonitorLayoutPolicy.portrait(width, height, if (width < 600) 44f else 0f, 34f,
                    fill, visible, aspect)
                assertTrue(result.values.maxY <= result.system.y - 4f + .01f)
                assertTrue(result.system.maxY <= height)
                assertEquals(width / 2f, result.picture.midX, .01f)
                assertTrue(result.picture.width <= width + .01f)
                assertTrue(result.picture.height > 0f)
                assertTrue(result.controlsFloor <= result.values.y)
                if (!visible) assertEquals(0f, result.values.height)
                if (width >= 600) assertTrue(result.picture.maxY <= result.controlsFloor + .01f)
            }
        }
    }

    @Test
    fun fitPreservesRealSourceAspectAndFillExpandsTheWell() {
        val fit = MonitorLayoutPolicy.portrait(393f, 852f, 44f, 34f, false, true, 16f / 9f)
        val fill = MonitorLayoutPolicy.portrait(393f, 852f, 44f, 34f, true, true, 16f / 9f)
        assertEquals(16f / 9f, fit.picture.width / fit.picture.height, .001f)
        assertEquals(9f / 16f, fill.picture.width / fill.picture.height, .001f)
        assertEquals(fit.values, fill.values)
        assertEquals(fit.system, fill.system)
    }

    @Test
    fun tabletVerticalPictureFitsAvailableHeightWithoutStretching() {
        val layout = MonitorLayoutPolicy.portrait(744f, 1133f, 0f, 34f, true, true, 9f / 16f)
        assertTrue(layout.picture.x > 0f)
        assertEquals(9f / 16f, layout.picture.width / layout.picture.height, .001f)
        assertEquals(layout.status.maxY, layout.picture.y, .01f)
        assertEquals(layout.controlsFloor, layout.picture.maxY, .01f)
    }

    @Test
    fun phoneReadoutsUseThreeColumnsEvenWhenOneCapabilityIsAbsent() {
        assertEquals(3, MonitorLayoutPolicy.valueColumns(320f, true, 6))
        assertEquals(3, MonitorLayoutPolicy.valueColumns(393f, true, 5))
        assertEquals(6, MonitorLayoutPolicy.valueColumns(716f, true, 6))
        assertEquals(6, MonitorLayoutPolicy.valueColumns(420f, false, 6))
    }

    @Test
    fun pageSlotsStayTwoAcrossPortraitAndLandscape() {
        assertTrue(MonitorPageLayoutPolicy.portrait(390f, 844f))
        assertTrue(!MonitorPageLayoutPolicy.portrait(844f, 390f))
        assertEquals("nav", MonitorPageLayoutPolicy.NAV)
        assertEquals("body", MonitorPageLayoutPolicy.BODY)
        assertEquals(170f, MonitorPageLayoutPolicy.LANDSCAPE_NAV_WIDTH)
        val portrait = MonitorPageLayoutPolicy.slots(390f, 844f, 56f)
        val landscape = MonitorPageLayoutPolicy.slots(844f, 390f, 56f)
        assertEquals(0f, portrait.bodyX)
        assertTrue(portrait.bodyH > 0f)
        assertEquals(MonitorPageLayoutPolicy.LANDSCAPE_NAV_WIDTH + MonitorPageLayoutPolicy.GAP, landscape.bodyX)
        assertEquals(390f, landscape.bodyH)
        assertTrue(landscape.bodyW > 0f)
        // 530×500 landscape minus a 54dp Back + 10dp gap leaves 466×500 for regions.
        assertTrue(MonitorPageLayoutPolicy.portrait(466f, 500f))
        val nearSquare = MonitorPageLayoutPolicy.slots(466f, 500f, portrait = false)
        assertEquals(170f, nearSquare.navW, .01f)
        assertEquals(500f, nearSquare.navH, .01f)
        assertEquals(180f, nearSquare.bodyX, .01f)
        assertEquals(0f, nearSquare.bodyY, .01f)
        val media = MonitorPageLayoutPolicy.slots(844f, 390f, 56f, navigationWidth = 206f)
        assertEquals(206f, media.navW, .01f)
        assertEquals(216f, media.bodyX, .01f)
        assertEquals(844f - 206f - MonitorPageLayoutPolicy.GAP, media.bodyW, .01f)
        val mediaNear = MonitorPageLayoutPolicy.slots(466f, 500f, portrait = false, navigationWidth = 206f)
        assertEquals(206f, mediaNear.navW, .01f)
        assertEquals(216f, mediaNear.bodyX, .01f)
        assertEquals(0f, mediaNear.bodyY, .01f)
    }

    @Test
    fun assistHostsUseSharedSystemButtonSide() {
        val phoneSide = MonitorLayoutPolicy.systemButtonSize(false)
        val tabletSide = MonitorLayoutPolicy.systemButtonSize(true)
        val phone = MonitorLayoutPolicy.portraitAssists(800f, false)
        assertEquals(8f, phone.x)
        assertEquals(phoneSide + 8f, phone.width)
        assertEquals(phoneSide + 35f, phone.height)
        assertEquals(800f - 16f, phone.maxY, .01f)
        val tablet = MonitorLayoutPolicy.portraitAssists(800f, true)
        assertEquals(8f, tablet.x)
        assertEquals(tabletSide + 8f, tablet.width)
        assertEquals(tabletSide + 35f, tablet.height)
        assertEquals(800f - 16f, tablet.maxY, .01f)
        val landPhone = MonitorLayoutPolicy.landscapeAssists(390f, false)
        assertEquals(14f, landPhone.x)
        assertEquals(phoneSide + MonitorLayoutPolicy.ASSIST_HORIZONTAL_INSETS, landPhone.width)
        assertEquals(phoneSide * 2f + 11f, landPhone.height)
        assertEquals(390f - 8f, landPhone.maxY, .01f)
        val filter = MonitorLayoutPolicy.mediaFilterPopup(956f, 440f, 0f, 59f, 21f, 59f)
        assertTrue(filter.maxY <= 440f - 21f)
        assertTrue(filter.maxX <= 956f - 59f)
        val zeroedTrailing = MonitorLayoutPolicy.mediaFilterPopup(956f, 440f, 0f, 59f, 21f, 0f)
        assertTrue(zeroedTrailing.maxX <= 956f - 59f)
        assertTrue(zeroedTrailing.maxY <= 440f - 21f)
        val compact = MonitorLayoutPolicy.mediaFilterPopup(852f, 393f, 0f, 59f, 21f, 0f)
        assertTrue(compact.maxX <= 852f - 59f)
        assertTrue(compact.maxY <= 393f - 21f)
        assertTrue(compact.height < MonitorLayoutPolicy.MEDIA_FILTER_PREFERRED_HEIGHT)
        assertEquals(31f, MonitorLayoutPolicy.landscapeBottomClearance(21f))
        val landHome = MonitorLayoutPolicy.landscapeAssists(390f, false, safeBottom = 21f)
        assertEquals(390f - 31f, landHome.maxY, .01f)
        val landTablet = MonitorLayoutPolicy.landscapeAssists(744f, true)
        assertEquals(tabletSide + MonitorLayoutPolicy.ASSIST_HORIZONTAL_INSETS, landTablet.width)
        assertEquals(tabletSide * 2f + 11f, landTablet.height)
        assertEquals(744f - 8f, landTablet.maxY, .01f)
    }

    @Test
    fun invalidAspectFallsBackToCinemaWithoutInvalidGeometry() {
        for (aspect in listOf(0f, -1f, Float.NaN, Float.POSITIVE_INFINITY)) {
            val layout = MonitorLayoutPolicy.portrait(393f, 852f, 44f, 34f, false, true, aspect)
            assertEquals(16f / 9f, layout.picture.width / layout.picture.height, .001f)
        }
    }

    @Test
    fun portraitStatusRowSitsBelowTheSafeTopAndTheFeedCentersOnTheCanvas() {
        val notched = MonitorLayoutPolicy.portrait(393f, 852f, 59f, 34f, false, true, 16f / 9f)
        assertEquals(51f, notched.status.y, .05f)
        assertEquals(44f, notched.status.height, .05f)
        assertTrue(notched.status.maxY <= notched.picture.y + .05f)
        assertEquals(852f / 2f, notched.picture.y + notched.picture.height / 2f, .5f)
        assertTrue(notched.picture.maxY < notched.values.y)

        val classic = MonitorLayoutPolicy.portrait(375f, 667f, 20f, 0f, false, true, 16f / 9f)
        assertEquals(12f, classic.status.y, .05f)
        assertTrue(classic.status.maxY <= classic.picture.y + .05f)

        val maxPhone = MonitorLayoutPolicy.portrait(440f, 956f, 62f, 34f, false, true, 16f / 9f)
        assertEquals(54f, maxPhone.status.y, .05f)
        assertTrue(maxPhone.status.maxY <= maxPhone.picture.y + .05f)
        assertEquals(956f / 2f, maxPhone.picture.y + maxPhone.picture.height / 2f, .5f)
        assertTrue(maxPhone.picture.maxY < maxPhone.values.y)
    }
    @Test
    fun portraitToolsStayAnchoredAcrossFitFillAndSourceAspects() {
        for ((width, height, safeTop) in listOf(Triple(393f, 852f, 59f), Triple(744f, 1133f, 0f))) {
            val tablet = minOf(width, height) >= 600f
            for (valuesVisible in listOf(false, true)) {
                val reference = MonitorLayoutPolicy.portrait(width, height, safeTop, 34f,
                    false, valuesVisible, 16f / 9f)
                val assists = MonitorLayoutPolicy.portraitAssists(reference.controlsFloor, tablet)
                val toggle = MonitorLayoutPolicy.portraitAspect(width, reference.controlsFloor)
                for (aspect in listOf(16f / 9f, 1f, 9f / 16f)) {
                    for (fill in listOf(false, true)) {
                        val layout = MonitorLayoutPolicy.portrait(width, height, safeTop, 34f,
                            fill, valuesVisible, aspect)
                        assertEquals(reference.controlsFloor, layout.controlsFloor, .01f)
                        assertEquals(assists, MonitorLayoutPolicy.portraitAssists(layout.controlsFloor, tablet))
                        assertEquals(toggle, MonitorLayoutPolicy.portraitAspect(width, layout.controlsFloor))
                        assertTrue(assists.maxY < layout.values.y)
                        assertTrue(toggle.maxY < layout.values.y)
                    }
                }
            }
        }
    }

    @Test
    fun fitMaxPhonePlacesToolsBelowThePicture() {
        val layout = MonitorLayoutPolicy.portrait(440f, 956f, 62f, 34f, false, true, 16f / 9f)
        val assists = MonitorLayoutPolicy.portraitAssists(layout.controlsFloor, false)
        val toggle = MonitorLayoutPolicy.portraitAspect(440f, layout.controlsFloor)
        assertTrue(layout.picture.maxY < assists.y)
        assertTrue(layout.picture.maxY < toggle.y)
        assertEquals(layout.values.y - 12f, layout.controlsFloor, .01f)
        assertEquals(220f, toggle.midX, .01f)
    }

    @Test
    fun portraitStickZoomGimbalMatchFieldMonitorLayout() {
        val stick = MonitorLayoutPolicy.portraitStick(393f, 700f)
        val zoom = MonitorLayoutPolicy.portraitZoom(stick)
        val gimbal = MonitorLayoutPolicy.portraitGimbal(stick, zoom)
        val headTrack = MonitorLayoutPolicy.headTrack(stick, zoom)
        assertEquals(MonitorRect(289f, 596f, 88f, 88f), stick)
        assertEquals(MonitorRect(289f, 552f, 44f, 36f), zoom)
        assertEquals(MonitorRect(341f, 552f, 36f, 36f), gimbal)
        assertEquals(MonitorRect(333f, 500f, 44f, 44f), headTrack)
    }

    @Test
    fun playbackAssistsUseTheLiveFieldMonitorSlot() {
        val portrait = MonitorLayoutPolicy.fieldMonitorAssists(393f, 852f, 59f, 34f)
        val portraitLive = MonitorLayoutPolicy.portraitAssists(
            MonitorLayoutPolicy.portrait(393f, 852f, 59f, 34f, false, true, 16f / 9f).controlsFloor,
            false,
        )
        assertEquals(portraitLive, portrait)
        val landscape = MonitorLayoutPolicy.fieldMonitorAssists(852f, 393f, 0f, 21f)
        assertEquals(MonitorLayoutPolicy.landscapeAssists(393f, false, 14f, 21f), landscape)
    }

    @Test
    fun landscapePageMirrorsTheLargerCutoutOntoBothSides() {
        assertEquals(59f to 59f, MonitorLayoutPolicy.pageSideInsets(true, 59f, 0f))
        assertEquals(59f to 59f, MonitorLayoutPolicy.pageSideInsets(true, 0f, 59f))
        assertEquals(0f to 34f, MonitorLayoutPolicy.pageSideInsets(false, 0f, 34f))
        assertEquals(0f to 0f, MonitorLayoutPolicy.pageSideInsets(false, 0f, 0f))
    }

    @Test fun tallPhonePicturesCenterInsideViewportWhenChromeCannotFit() {
        listOf(Triple(375f, 667f, 20f), Triple(393f, 852f, 59f), Triple(320f, 600f, 20f))
            .forEach { (width, height, safeTop) ->
                listOf(9f / 16f to false, 16f / 9f to true).forEach { (aspect, fill) ->
                    val layout = MonitorLayoutPolicy.portrait(width, height, safeTop, 0f,
                        fill, true, aspect)
                    assertTrue(layout.picture.height <= height)
                    assertTrue(layout.picture.y >= 0f)
                    assertTrue(layout.picture.maxY <= height + .001f)
                    assertEquals(height / 2f, layout.picture.y + layout.picture.height / 2f, .001f)
                }
            }
    }

    @Test
    fun landscapeFieldMonitorKeepsValuesWhileMovingOuterControlsTowardEdges() {
        val layout = MonitorLayoutPolicy.fieldMonitor(
            874f, 402f, safeLeading = 59f, showsValues = true,
        )
        assertEquals(70f, layout.record.width, .01f)
        assertEquals(874f - 6f - 70f, layout.record.x, .01f)
        assertEquals(402f - 8f - 70f, layout.record.y, .01f)
        assertEquals(43f, layout.values.height, .01f)
        assertEquals(14f + 70f + 28f, layout.values.x, .01f)
        assertEquals(layout.values.x, 874f - layout.values.maxX, .01f)
        assertEquals(12f, layout.lock.x, .01f)
        assertEquals(49f, layout.gauges.width, .01f)
        assertEquals(52f, layout.gauges.height, .01f)
        assertEquals(44f, layout.zoom.width, .01f)
        assertEquals(36f, layout.zoom.height, .01f)
        assertEquals(layout.stick.x, layout.zoom.x, .01f)
        assertEquals(layout.stick.maxX - 36f, layout.gimbal.x, .01f)
        assertTrue(layout.stick.maxX <= layout.record.x + .05f)
        assertEquals(8f, MonitorLayoutPolicy.landscapeBottomClearance(0f), .01f)
    }

}
