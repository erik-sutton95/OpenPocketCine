package com.opencapture.monitorui

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Assert.assertNull
import org.junit.Test

class MonitorZoomGeometryTest {
    @Test fun growsTenPercentWhenPortraitOrTabletHasRoom() {
        assertEquals(286f, MonitorZoomGeometry.layout(393f, 852f).radius, .001f)
        assertEquals(363f, MonitorZoomGeometry.layout(1194f, 834f).radius, .001f)
    }

    @Test fun shortLandscapeAndNarrowWindowsStayInsideViewport() {
        listOf(Triple(852f, 393f, 65f), Triple(220f, 800f, 20f), Triple(180f, 180f, 0f))
            .forEach { (width, height, inset) ->
                val disc = MonitorZoomGeometry.layout(width, height, inset)
                assertTrue(disc.height <= height)
                assertTrue(disc.width <= width)
                assertTrue(disc.radius > 0f)
            }
        assertEquals(196.5f, MonitorZoomGeometry.layout(852f, 393f).radius, .001f)
    }

    @Test fun flatEdgeReachesPhysicalEdgeAndKeepsReadoutBeforeCutout() {
        val disc = MonitorZoomGeometry.layout(852f, 393f, 65f)
        val originX = 852f - disc.width
        assertEquals(852f, originX + disc.width, .001f)
        assertEquals(787f, originX + disc.radius, .001f)
        assertTrue(originX + disc.radius * .96f < 787f)
        listOf(0f, disc.radius, disc.height).forEach { y ->
            assertTrue(disc.contains(disc.radius + 32f, y))
            assertTrue(disc.contains(disc.width, y))
        }
    }

    @Test fun hitShapeRejectsTransparentCornersAndOwnsMaterial() {
        val disc = MonitorZoomGeometry.layout(852f, 393f, 65f)
        assertFalse(disc.contains(1f, 1f))
        assertFalse(disc.contains(1f, disc.height - 1f))
        assertTrue(disc.contains(0f, disc.radius))
        assertTrue(disc.contains(disc.radius * .5f, disc.radius))
        assertFalse(disc.contains(disc.width + 1f, disc.radius))
        assertFalse(disc.contains(Float.NaN, 0f))
    }

    @Test fun extrusionPreservesTheDiscRadialOrigin() {
        val plain = MonitorZoomGeometry.layout(852f, 393f)
        val inset = MonitorZoomGeometry.layout(852f, 393f, 65f)
        listOf(20f, 120f, 260f, 380f).forEach { y ->
            assertEquals(plain.angle(100f, y), inset.angle(100f, y), .000001)
            assertFalse(inset.canStartZoom(inset.width, y))
        }
        val invalid = MonitorZoomGeometry.layout(Float.NaN, Float.POSITIVE_INFINITY, Float.NaN)
        assertEquals(0f, invalid.width, 0f)
        assertFalse(invalid.contains(0f, 0f))
    }
    @Test fun materialExtensionCannotArmOrRetargetARejectedPointer() {
        val disc = MonitorZoomGeometry.layout(852f, 393f, 65f)
        val pointer = MonitorZoomRadialGesture(disc, disc.radius + 32f, disc.radius - 1f)
        assertFalse(pointer.isArmed)
        assertNull(pointer.angleDelta(disc.radius + 32f, disc.radius + 1f))
        assertNull(pointer.angleDelta(100f, 230f))
    }

    @Test fun extrusionCrossingAndReentryNeverApplyTheMissingArc() {
        val disc = MonitorZoomGeometry.layout(852f, 393f, 65f)
        val pointer = MonitorZoomRadialGesture(disc, 100f, 160f)
        assertTrue(pointer.isArmed)
        val before = checkNotNull(pointer.angleDelta(100f, 170f))
        assertEquals(disc.angle(100f, 170f) - disc.angle(100f, 160f), before, 1e-9)
        assertNull(pointer.angleDelta(disc.radius + 32f, disc.radius - 1f))
        assertNull(pointer.angleDelta(disc.radius + 32f, disc.radius + 1f))
        assertNull(pointer.angleDelta(100f, 230f))
        val after = checkNotNull(pointer.angleDelta(100f, 231f))
        val expectedStep = disc.angle(100f, 231f) - disc.angle(100f, 230f)
        assertEquals(expectedStep, after - before, 1e-9)
        assertTrue(kotlin.math.abs((after - before) / (210 * Math.PI / 180)) < .01)
    }

    @Test fun portraitBottomDiscSitsInTheWidthAndLeavesBottomChrome() {
        val disc = MonitorZoomGeometry.layout(393f, 650f, attachment = MonitorZoomAttachment.Bottom)
        assertEquals(196.5f, disc.radius, .001f)
        assertEquals(disc.radius * 2f, disc.width, .001f)
        assertEquals(disc.radius, disc.height, .001f)
        assertFalse(disc.canStartZoom(disc.radius, disc.radius + 1f))
        assertTrue(disc.canStartZoom(disc.radius, disc.radius * .4f))
        assertFalse(disc.contains(1f, 1f))
        assertTrue(disc.contains(disc.radius, 1f))
    }

    @Test fun bottomExtensionCannotArmAndReentryDoesNotJump() {
        val disc = MonitorZoomGeometry.layout(
            393f, 650f, bottomInset = 80f, attachment = MonitorZoomAttachment.Bottom)
        assertEquals(disc.radius + 80f, disc.height, .001f)
        val pointer = MonitorZoomRadialGesture(disc, disc.radius, disc.radius * .4f)
        assertTrue(pointer.isArmed)
        val before = checkNotNull(pointer.angleDelta(disc.radius + 8f, disc.radius * .4f))
        assertNull(pointer.angleDelta(disc.radius, disc.radius + 20f))
        assertNull(pointer.angleDelta(disc.radius + 8f, disc.radius * .4f))
        val after = checkNotNull(pointer.angleDelta(disc.radius + 8f, disc.radius * .41f))
        val expected = disc.angle(disc.radius + 8f, disc.radius * .41f) -
            disc.angle(disc.radius + 8f, disc.radius * .4f)
        assertEquals(expected, after - before, 1e-9)
    }

}
