package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GimbalLimitWatchTest {
    @Test
    fun holdWithoutMotionDoesNotPulse() {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var saw = GimbalLimitContact()
        repeat(10) {
            now += 0.1
            saw = saw.union(watch.tick(1.0, 0.0, 0, 0, now, false))
        }
        assertTrue(saw.isEmpty)
    }

    @Test
    fun panPulsesAfterMoveThenStop() {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var yaw = 0
        repeat(4) {
            now += 0.1
            yaw += 40
            assertTrue(watch.tick(1.0, 0.0, yaw, 0, now, false).isEmpty)
        }
        var saw = GimbalLimitContact()
        repeat(5) {
            now += 0.1
            saw = saw.union(watch.tick(1.0, 0.0, yaw, 0, now, false))
        }
        assertTrue(saw.pan)
        assertFalse(saw.tilt)
        now += 0.1
        assertTrue(watch.tick(1.0, 0.0, yaw, 0, now, false).isEmpty)
        yaw += 40
        now += 0.1
        assertTrue(watch.tick(1.0, 0.0, yaw, 0, now, false).isEmpty)
        var again = GimbalLimitContact()
        repeat(5) {
            now += 0.1
            again = again.union(watch.tick(1.0, 0.0, yaw, 0, now, false))
        }
        assertTrue(again.pan)
    }

    @Test
    fun tiltPulsesAfterPitchMovesThenStops() {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var pitch = 0
        repeat(4) {
            now += 0.1
            pitch += 30
            assertTrue(watch.tick(0.0, 1.0, 0, pitch, now, false).isEmpty)
        }
        var saw = GimbalLimitContact()
        repeat(5) {
            now += 0.1
            saw = saw.union(watch.tick(0.0, 1.0, 0, pitch, now, false))
        }
        assertTrue(saw.tilt)
        assertFalse(saw.pan)
        assertEquals(1.0, watch.lastTiltSign)
    }

    @Test
    fun restClearsContact() {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var yaw = 0
        repeat(4) {
            now += 0.1
            yaw += 40
            watch.tick(-1.0, 0.0, yaw, 0, now, false)
        }
        repeat(5) {
            now += 0.1
            watch.tick(-1.0, 0.0, yaw, 0, now, false)
        }
        now += 0.1
        assertTrue(watch.tick(0.0, 0.0, yaw, 0, now, false).isEmpty)
        yaw = 0
        repeat(4) {
            now += 0.1
            yaw -= 40
            watch.tick(-1.0, 0.0, yaw, 0, now, false)
        }
        var saw = GimbalLimitContact()
        repeat(5) {
            now += 0.1
            saw = saw.union(watch.tick(-1.0, 0.0, yaw, 0, now, false))
        }
        assertTrue(saw.pan)
        assertEquals(-1.0, watch.lastPanSign)
    }

    @Test
    fun settling180SkipsPan() {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var yaw = 0
        var saw = GimbalLimitContact()
        repeat(4) {
            now += 0.1
            yaw += 80
            saw = saw.union(watch.tick(1.0, 0.0, yaw, 0, now, true))
        }
        repeat(5) {
            now += 0.1
            saw = saw.union(watch.tick(1.0, 0.0, yaw, 0, now, true))
        }
        assertTrue(saw.isEmpty)
    }

    @Test
    fun missingAttitudeDoesNotPulse() {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var saw = GimbalLimitContact()
        repeat(8) {
            now += 0.1
            saw = saw.union(watch.tick(1.0, 1.0, null, null, now, false))
        }
        assertTrue(saw.isEmpty)
    }

    @Test
    fun analogCurveCrawlsAtHalfThrow() {
        val linearHalf =
            (CameraCommands.GIMBAL_STICK_CENTER + 0.5f * CameraCommands.GIMBAL_STICK_TRAVEL)
                .toInt()
        val half = CameraCommands.gimbalAxis(0.5f)
        assertTrue(half < linearHalf)
        assertTrue(half > CameraCommands.GIMBAL_STICK_CENTER)
        assertEquals(0f, CameraCommands.gimbalAnalogCurve(0f))
        assertEquals(0f, CameraCommands.gimbalLinearThrow(0.04f))
        assertEquals(1f, CameraCommands.gimbalLinearThrow(1f))
        assertEquals(1.0, CamFov.zoomStep(1.0, 0.0, 1.0, 12.0), 0.001)
        assertEquals(1.0 + CamFov.ZOOM_RATE_PER_SECOND, CamFov.zoomStep(1.0, 1.0, 1.0, 12.0), 0.001)
        val crawl = CamFov.zoomStep(1.0, 0.2, 1.0, 12.0)
        val full = CamFov.zoomStep(1.0, 1.0, 1.0, 12.0)
        assertTrue(crawl > 1.0)
        assertTrue(crawl < full)
        assertTrue(CamFov.zoomStep(6.0, -1.0, 1.0, 12.0) < 6.0)
        assertEquals(1.0, CamFov.triggerZoomAxis(0.0, 1.0), 0.001)
        assertEquals(-1.0, CamFov.triggerZoomAxis(1.0, 0.0), 0.001)
        assertEquals(1000, CameraCommands.pitchTenthDeg(byteArrayOf(0, 0, 0, 0, 0, 0, 0xE8.toByte(), 0x03)))
        assertEquals(null, CameraCommands.pitchTenthDeg(byteArrayOf(0, 0, 0, 0, 0, 0)))
    }
}
