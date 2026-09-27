package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
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

    /** Drives one watch at 10 Hz: [move] turns the head 4 ticks, [hold] parks it 5 ticks. */
    private class Drive {
        val watch = GimbalLimitWatch()
        var now = 0.0
        var yaw = 0
        var pitch = 0

        fun tick(pan: Double, tilt: Double): GimbalLimitContact {
            now += 0.1
            return watch.tick(pan, tilt, yaw, pitch, now, false)
        }

        fun move(pan: Double, tilt: Double, dYaw: Int, dPitch: Int, quiet: Boolean) = repeat(4) {
            yaw += dYaw
            pitch += dPitch
            val contact = tick(pan, tilt)
            if (quiet) assertTrue(contact.isEmpty, "no pulse while the head still moves")
        }

        fun hold(pan: Double, tilt: Double): GimbalLimitContact {
            var saw = GimbalLimitContact()
            repeat(5) { saw = saw.union(tick(pan, tilt)) }
            return saw
        }
    }

    @Test
    fun eachAxisPulsesAfterMoveThenStop() {
        data class Case(val axis: String, val pan: Double, val tilt: Double, val dYaw: Int, val dPitch: Int)
        for ((axis, pan, tilt, dYaw, dPitch) in listOf(Case("pan", 1.0, 0.0, 40, 0), Case("tilt", 0.0, 1.0, 0, 30))) {
            val drive = Drive()
            drive.move(pan, tilt, dYaw, dPitch, quiet = true)
            val saw = drive.hold(pan, tilt)
            assertEquals(axis == "pan", saw.pan, "$axis stick: pan contact")
            assertEquals(axis == "tilt", saw.tilt, "$axis stick: tilt contact")
            if (axis == "tilt") assertEquals(1.0, drive.watch.lastTiltSign)
        }
    }

    @Test
    fun panPulsesAgainAfterMovingOffTheStop() {
        val drive = Drive()
        drive.move(1.0, 0.0, 40, 0, quiet = true)
        assertTrue(drive.hold(1.0, 0.0).pan)
        assertTrue(drive.tick(1.0, 0.0).isEmpty)
        drive.yaw += 40
        assertTrue(drive.tick(1.0, 0.0).isEmpty)
        assertTrue(drive.hold(1.0, 0.0).pan)
    }

    @Test
    fun restClearsContact() {
        val drive = Drive()
        drive.move(-1.0, 0.0, 40, 0, quiet = false)
        drive.hold(-1.0, 0.0)
        assertTrue(drive.tick(0.0, 0.0).isEmpty)
        drive.yaw = 0
        drive.move(-1.0, 0.0, -40, 0, quiet = false)
        assertTrue(drive.hold(-1.0, 0.0).pan)
        assertEquals(-1.0, drive.watch.lastPanSign)
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
    fun zoomCrawlsAtPartialThrowAndAttitudeBytesDecode() {
        // Stick curve shape lives in VirtualJoystickMappingTest.
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
        assertEquals(null, CameraCommands.pitchTenthDeg(byteArrayOf(0, 0, 0)))
        val lookDown = ByteArray(22)
        lookDown[4] = 0x01
        lookDown[20] = 0xB3.toByte()
        lookDown[21] = 0x01
        assertEquals(1, CameraCommands.yawTenthDeg(lookDown))
        assertEquals(-435, CameraCommands.pitchTenthDeg(lookDown))
    }
}
