package com.opencapture.openpocketcine.session

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.atan2
import kotlin.math.cos
import kotlin.math.sin
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Mirrors `WorldLevelTests.swift` on the same captured frames. */
class WorldLevelTest {
    private val fixtures = listOf(
        "F606000006008600FAFF00020E6DBE041EBA0000EAFF0400EA71193910F57F3F41C41B3C7F917FBC00000000010000000000" to 1.788,
        "5B0500002AFF8600D3000002965BC9057BBD000056FE0200382CF83C23B86D3F15519F3DBC22B9BE00000000000000000005" to 42.552,
        "5EF900000E008600F4FF0002D20CBF0470BE00006A0035006FF1173C92967DBFC5AFD6BD7077B3BD00000000000000000005" to -10.111,
        "0807000000008600000000020219CD05B3C5000000000200AA10D73532D7763F15BB873E1FB8B43600000000010000000000" to -0.001,
    )

    private fun bytes(hex: String) = ByteArray(hex.length / 2) { hex.substring(it * 2, it * 2 + 2).toInt(16).toByte() }

    private fun axis(x: Double, y: Double, z: Double, deg: Double): WorldLevel.Quat {
        val half = deg * PI / 360
        return WorldLevel.Quat(cos(half), x * sin(half), y * sin(half), z * sin(half))
    }

    private fun payload(q: WorldLevel.Quat, count: Int = 50): ByteArray {
        val p = ByteArray(count)
        for ((offset, v) in listOf(24 to q.x, 28 to q.w, 32 to q.y, 36 to q.z)) {
            if (offset + 4 > count) continue
            val bits = v.toFloat().toRawBits()
            for (k in 0 until 4) p[offset + k] = (bits ushr (8 * k)).toByte()
        }
        return p
    }

    private fun payload(tilt: Double, roll: Double = 0.0, count: Int = 50) =
        payload(axis(1.0, 0.0, 0.0, -roll).times(axis(0.0, 0.0, 1.0, -tilt)), count)

    @Test
    fun capturedFramesDecodeToFittedTiltWithLevelRoll() {
        for ((hex, tilt) in fixtures) {
            val reading = LevelReading()
            reading.ingest(bytes(hex), 1.0)
            val g = assertIs<LevelMode.Gauges>(reading.mode(1.0, viewFlip = false))
            assertTrue(abs(g.tiltDeg - tilt) < 0.01, "tilt ${g.tiltDeg} vs $tilt")
            assertTrue(abs(g.rollDeg) < 0.01)
        }
    }

    @Test
    fun rejectsShortNonFiniteAndNonUnitQuaternions() {
        assertNull(WorldLevel.attitude(payload(0.0, count = 39)))
        assertNull(WorldLevel.attitude(payload(WorldLevel.Quat(Double.NaN, 0.0, 0.0, 0.0))))
        assertNull(WorldLevel.attitude(payload(WorldLevel.Quat(1.01, 0.0, 0.0, 0.0))))
        assertNotNull(WorldLevel.attitude(payload(0.0)))
    }

    @Test
    fun rollFollowsThePictureFlip() {
        val reading = LevelReading()
        reading.ingest(payload(0.0, roll = 5.0), 1.0)
        assertEquals(5.0, assertIs<LevelMode.Gauges>(reading.mode(1.0, false)).rollDeg, 0.01)
        assertEquals(-5.0, assertIs<LevelMode.Gauges>(reading.mode(1.0, true)).rollDeg, 0.01)
    }

    @Test
    fun bubbleTakesOverNearPlumbWithHysteresis() {
        val reading = LevelReading()
        var t = 0.0
        fun feed(tilt: Double): LevelMode {
            repeat(40) {
                t += 0.1
                reading.ingest(payload(tilt), t)
            }
            return reading.mode(t, false)
        }
        assertIs<LevelMode.Gauges>(feed(-59.0))
        assertIs<LevelMode.Gauges>(feed(-62.0))
        assertIs<LevelMode.Bubble>(feed(-70.0))
        assertIs<LevelMode.Bubble>(feed(-62.0))
        assertIs<LevelMode.Gauges>(feed(-59.0))
    }

    @Test
    fun bubbleReadsOffsetFromPlumbInPictureAxes() {
        for ((tilt, y) in listOf(-88.0 to 2.0, -92.0 to -2.0, 88.0 to 2.0)) {
            val reading = LevelReading()
            reading.ingest(payload(tilt), 1.0)
            val b = assertIs<LevelMode.Bubble>(reading.mode(1.0, false))
            assertEquals(0.0, b.xDeg, 0.01)
            assertEquals(y, b.yDeg, 0.01)
        }
        val lateral = LevelReading()
        lateral.ingest(payload(axis(0.0, 1.0, 0.0, 3.0).times(axis(0.0, 0.0, 1.0, 90.0))), 1.0)
        val plain = assertIs<LevelMode.Bubble>(lateral.mode(1.0, false))
        val flipped = assertIs<LevelMode.Bubble>(lateral.mode(1.0, true))
        assertTrue(abs(plain.xDeg) > 2.9)
        assertEquals(0.0, plain.xDeg + flipped.xDeg, 1e-9)
    }

    @Test
    fun goesUnavailableWithoutFreshSamples() {
        val reading = LevelReading()
        assertEquals(LevelMode.Unavailable, reading.mode(0.0, false))
        reading.ingest(payload(0.0), 10.0)
        assertIs<LevelMode.Gauges>(reading.mode(10.9, false))
        assertEquals(LevelMode.Unavailable, reading.mode(11.01, false))
        assertNull(reading.tiltDeg(11.01))
        reading.ingest(payload(0.0, count = 30), 11.5)
        assertEquals(LevelMode.Unavailable, reading.mode(11.5, false))
    }

    @Test
    fun smoothingMovesThirtyPercentTowardANewSampleAtMostTenHertz() {
        val reading = LevelReading()
        reading.ingest(payload(0.0), 1.0)
        reading.ingest(payload(10.0), 1.02)
        assertEquals(0.0, reading.tiltDeg(1.02)!!, 1e-6)
        reading.ingest(payload(10.0), 1.1)
        val r = 10 * PI / 180
        val expected = atan2(0.3 * sin(r), 0.7 + 0.3 * cos(r)) * 180 / PI
        assertEquals(expected, reading.tiltDeg(1.1)!!, 1e-3)
    }

    @Test
    fun nearestTargetSplitsAtFortyFiveDegrees() {
        assertEquals(WorldLevelTarget.HORIZON, WorldLevelTarget.nearest(44.9))
        assertEquals(WorldLevelTarget.HORIZON, WorldLevelTarget.nearest(-44.9))
        assertEquals(WorldLevelTarget.PLUMB_DOWN, WorldLevelTarget.nearest(-45.0))
        assertEquals(WorldLevelTarget.PLUMB_UP, WorldLevelTarget.nearest(45.0))
    }

    @Test
    fun snapPlansOneTimedTargetFromTheLiveNativePitch() {
        val (snap, frame) = assertNotNull(
            WorldLevelSnap.plan(-60.0, GimbalWaypoint(12.0, -60.0, 1.0, -120.0), 5.0))
        assertEquals(WorldLevelTarget.PLUMB_DOWN, snap.target)
        assertContentEquals(CameraCommands.gimbalTimedTarget(12.0, -90.0, 1.5), frame)
        assertEquals(5 + 1.5 + 1.5, snap.deadline, 1e-9)

        val (_, level) = assertNotNull(WorldLevelSnap.plan(2.0, GimbalWaypoint(0.0, 2.0, 1.0, 178.0), 0.0))
        assertContentEquals(CameraCommands.gimbalTimedTarget(0.0, 180.0, 0.5), level)

        assertEquals(WorldLevelTarget.PLUMB_UP,
            assertNotNull(WorldLevelSnap.plan(80.0, GimbalWaypoint(0.0, 80.0, 1.0, 100.0), 0.0)).first.target)
    }

    @Test
    fun snapRefusesWithoutNativePitchOrReachableYaw() {
        assertNull(WorldLevelSnap.plan(3.0, GimbalWaypoint(0.0, 0.0, 1.0), 0.0))
        assertNull(WorldLevelSnap.plan(3.0, GimbalWaypoint(-100.0, 0.0, 1.0, 180.0), 0.0))
    }

    @Test
    fun snapJudgesArrivalTimeoutAndStaleReadings() {
        val snap = assertNotNull(
            WorldLevelSnap.plan(-80.0, GimbalWaypoint(0.0, -80.0, 1.0, -100.0), 0.0)).first
        assertEquals(SnapOutcome.Pending, snap.evaluate(-85.0, 0.5))
        assertEquals(SnapOutcome.Arrived, snap.evaluate(-89.6, 0.6))
        assertEquals(SnapOutcome.Failed(2.3), snap.evaluate(-87.7, snap.deadline))
        assertEquals(SnapOutcome.Failed(null), snap.evaluate(null, 0.7))
        assertEquals("Couldn't level: 2.3° off", WorldLevelSnap.failureNote(2.3))
    }

    @Test
    fun doubleTapDefaultsToRecenter() {
        assertEquals(listOf(GimbalDoubleTap.RECENTER, GimbalDoubleTap.LEVEL), GimbalDoubleTap.pickerOrder)
        assertEquals(GimbalDoubleTap.RECENTER, GimbalDoubleTap.fromRaw(7))
        assertEquals("Level", GimbalDoubleTap.LEVEL.label)
    }

    @Test
    fun freshSampleAfterAGapIsNotBlendedWithStaleGravity() {
        val reading = LevelReading()
        reading.ingest(payload(0.0), 1.0)
        reading.ingest(payload(10.0), 3.0)
        assertEquals(10.0, reading.tiltDeg(3.0)!!, 1e-6)
        val bubble = LevelReading()
        bubble.ingest(payload(-70.0), 1.0)
        bubble.ingest(payload(-62.0), 3.0)
        assertIs<LevelMode.Gauges>(bubble.mode(3.0, false))
    }

    @Test
    fun pitchIsUnfoldedPastPlumbForTheSnap() {
        val reading = LevelReading()
        reading.ingest(payload(-92.0), 1.0)
        assertEquals(-88.0, reading.tiltDeg(1.0)!!, 0.01)
        val pitch = reading.pitchDeg(1.0)!!
        assertEquals(-92.0, pitch, 0.01)
        assertNull(reading.pitchDeg(2.5))
        val (snap, frame) = assertNotNull(WorldLevelSnap.plan(pitch, GimbalWaypoint(0.0, -92.0, 1.0, -88.0), 0.0))
        assertEquals(WorldLevelTarget.PLUMB_DOWN, snap.target)
        assertContentEquals(CameraCommands.gimbalTimedTarget(0.0, -90.0, 0.5), frame)
        assertEquals(SnapOutcome.Arrived, snap.evaluate(-90.3, 0.2))
    }

    @Test
    fun snapExpiresInsteadOfJudgingLongAfterItsDeadline() {
        val snap = assertNotNull(
            WorldLevelSnap.plan(-80.0, GimbalWaypoint(0.0, -80.0, 1.0, -100.0), 0.0)).first
        assertEquals(SnapOutcome.Failed(5.0), snap.evaluate(-85.0, snap.deadline + 0.5))
        assertEquals(SnapOutcome.Expired, snap.evaluate(-85.0, snap.deadline + 1.01))
        assertEquals(SnapOutcome.Expired, snap.evaluate(-90.0, snap.deadline + 60))
    }
}
