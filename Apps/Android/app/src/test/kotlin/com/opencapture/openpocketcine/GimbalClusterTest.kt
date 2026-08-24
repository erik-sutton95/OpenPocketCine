package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** Lockstep with `GimbalClusterTests.swift`. */
class GimbalClusterTest {
    private val well = ChromeRect(0f, 0f, 714f, 402f)
    private val canvasMaxY = 402f

    @Test
    fun zoomStacksAboveTheStickTrailingAligned() {
        val cluster = GimbalCluster.inTrailingBottom(well, floorY = 330f, canvasMaxY = canvasMaxY)
        assertEquals(cluster.stick.maxX, cluster.zoom.maxX, 0.05f)
        assertEquals(cluster.stick.minY - GimbalCluster.GAP, cluster.zoom.maxY, 0.05f)
        assertEquals(well.maxX - GimbalCluster.INSET, cluster.stick.maxX, 0.05f)
        assertEquals(330f, cluster.stick.maxY, 0.05f)
        assertEquals(0f, cluster.controls.width, 0.05f)
        assertTrue(cluster.zoom.minY >= well.minY)
        assertEquals(cluster.stick.maxY, cluster.bounds.maxY, 0.05f)
        assertEquals(cluster.zoom.minY, cluster.bounds.minY, 0.05f)
    }

    @Test
    fun recordOnTheFloorLiftsTheClusterAboveAndKeepsTheTrailingEdge() {
        val record = ChromeRect(620f, 300f, 83f, 83f)
        val cluster =
            GimbalCluster.inTrailingBottom(well, floorY = 330f, canvasMaxY = canvasMaxY, avoid = record)
        assertFalse(cluster.bounds.intersects(record.inset(-1f, -1f)))
        assertEquals(cluster.stick.maxX, cluster.zoom.maxX, 0.05f)
        assertEquals(cluster.stick.minY - GimbalCluster.GAP, cluster.zoom.maxY, 0.05f)
        assertEquals(well.maxX - GimbalCluster.INSET, cluster.stick.maxX, 0.05f)
        assertEquals(record.minY - GimbalCluster.GAP, cluster.stick.maxY, 0.05f)
    }

    @Test
    fun iPadMiniLetterboxParksTheClusterAboveRecordOnTheRightEdge() {
        val feed = ChromeRect(0f, 53.34f, 1133f, 637.31f)
        val record = ChromeRect(1032.2f, 647.2f, 82.8f, 82.8f)
        val cluster =
            GimbalCluster.inTrailingBottom(feed, floorY = 664f, canvasMaxY = 744f, avoid = record)
        assertEquals(feed.maxX - GimbalCluster.INSET, cluster.stick.maxX, 0.05f)
        assertEquals(record.minY - GimbalCluster.GAP, cluster.stick.maxY, 0.05f)
        assertEquals(cluster.stick.maxX, cluster.zoom.maxX, 0.05f)
        assertTrue(cluster.zoom.maxY <= cluster.stick.minY + 0.05f)
        assertFalse(cluster.stick.intersects(record.inset(-1f, -1f)))
        assertFalse(cluster.zoom.intersects(record.inset(-1f, -1f)))
    }

    @Test
    fun controlsGrowLeadingOfTheStickWithoutMovingIt() {
        val bare = GimbalCluster.inTrailingBottom(well, floorY = 330f, canvasMaxY = canvasMaxY)
        val withControls =
            GimbalCluster.inTrailingBottom(well, floorY = 330f, canvasMaxY = canvasMaxY, controlsWidth = 72f)
        assertEquals(bare.stick.minX, withControls.stick.minX, 0.05f)
        assertEquals(bare.stick.minY, withControls.stick.minY, 0.05f)
        assertEquals(bare.zoom.minX, withControls.zoom.minX, 0.05f)
        assertEquals(withControls.stick.minX - GimbalCluster.GAP, withControls.controls.maxX, 0.05f)
        assertEquals(withControls.stick.minY, withControls.controls.minY, 0.05f)
        assertEquals(withControls.stick.height, withControls.controls.height, 0.05f)
        assertEquals(72f, withControls.controls.width, 0.05f)
    }

    @Test
    fun belowWellKeepsZoomUnderTheStrip() {
        val strip = ChromeRect(0f, 200f, 390f, 220f)
        val cluster = GimbalCluster.belowWell(strip, floorY = 620f)
        assertTrue(cluster.zoom.minY >= strip.maxY + GimbalCluster.GAP - 0.05f)
        assertTrue(cluster.stick.minY >= cluster.zoom.maxY - 0.05f)
        assertEquals(strip.maxX - GimbalCluster.INSET, cluster.stick.maxX, 0.05f)
        assertEquals(cluster.stick.maxX, cluster.zoom.maxX, 0.05f)
        assertEquals(620f - GimbalCluster.INSET, cluster.stick.maxY, 0.05f)
    }
}

private fun assertEquals(expected: Float, actual: Float, delta: Float) {
    kotlin.test.assertEquals(expected, actual, delta)
}
