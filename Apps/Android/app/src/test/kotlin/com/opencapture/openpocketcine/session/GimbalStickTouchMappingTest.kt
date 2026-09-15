package com.opencapture.openpocketcine.session

import kotlin.math.hypot
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class GimbalStickTouchMappingTest {
    private val stick = 100f
    private val knob = 40f
    private val outer = stick / 2f
    private val travel = (stick - knob) / 2f
    private val commandRadius = 1.35f * outer

    private fun map(dx: Float, dy: Float, engaged: Boolean = false) =
        CameraCommands.mapGimbalStickTouch(dx, dy, stick, knob, engaged)

    @Test
    fun visibleRingMapsToCommandOverOuterRadius() {
        val ring = map(outer, 0f)
        assertEquals(1f / 1.35f, ring.commandX, 1e-5f)
        assertEquals(0f, ring.commandY, 1e-5f)
        assertEquals(travel, ring.visualX, 1e-5f)
        assertEquals(0f, ring.visualY, 1e-5f)
        assertTrue(ring.emit)
        assertTrue(ring.engaged)
        assertFalse(ring.isTap)
    }

    @Test
    fun fullCommandRadiusIsOneAndVisualStaysAtKnobTravel() {
        val full = map(commandRadius, 0f)
        assertEquals(1f, full.commandX, 1e-5f)
        assertEquals(0f, full.commandY, 1e-5f)
        assertEquals(travel, full.visualX, 1e-5f)
        assertEquals(0f, full.visualY, 1e-5f)

        val ring = map(outer, 0f)
        assertEquals(ring.visualX, full.visualX, 1e-5f)
        assertTrue(ring.commandX < full.commandX)
    }

    @Test
    fun beyondCommandRadiusClampsRadiallyOnDiagonal() {
        val beyond = map(200f, 200f)
        assertEquals(1f, hypot(beyond.commandX, beyond.commandY), 1e-5f)
        assertEquals(0f, beyond.commandX + beyond.commandY, 1e-5f)
        assertTrue(beyond.commandX > 0f)
        assertTrue(beyond.commandY < 0f)
        assertEquals(travel, hypot(beyond.visualX, beyond.visualY), 1e-5f)
        assertTrue(beyond.visualX > 0f)
        assertTrue(beyond.visualY > 0f)
    }

    @Test
    fun responseCurvesDivergeAtVisibleRing() {
        val n = map(outer, 0f).commandX
        val linear =
            CameraCommands.gimbalAnalogCurve(
                n,
                expo = CameraCommands.VirtualJoystickCurve.LINEAR.expo,
            )
        val standard =
            CameraCommands.gimbalAnalogCurve(
                n,
                expo = CameraCommands.VirtualJoystickCurve.STANDARD.expo,
            )
        val fine =
            CameraCommands.gimbalAnalogCurve(
                n,
                expo = CameraCommands.VirtualJoystickCurve.FINE.expo,
            )
        assertTrue(linear < 1f)
        assertTrue(linear > standard)
        assertTrue(standard > fine)
    }

    @Test
    fun engagedReturnToCenterEmitsZero() {
        val slop = travel * CameraCommands.GIMBAL_STICK_TAP_SLOP * 0.5f
        val tap = map(slop, 0f)
        assertTrue(tap.isTap)
        assertFalse(tap.emit)
        assertFalse(tap.engaged)

        val thrown = map(outer, 0f, engaged = tap.engaged)
        assertTrue(thrown.emit)

        val rest = map(0f, 0f, engaged = thrown.engaged)
        assertEquals(0f, rest.commandX, 1e-5f)
        assertEquals(0f, rest.commandY, 1e-5f)
        assertEquals(0f, rest.visualX, 1e-5f)
        assertEquals(0f, rest.visualY, 1e-5f)
        assertTrue(rest.isTap)
        assertTrue(rest.engaged)
        assertTrue(rest.emit)
    }

    @Test
    fun initialTapRemainsTapInsideVisualSlop() {
        val inside = map(travel * CameraCommands.GIMBAL_STICK_TAP_SLOP * 0.5f, 0f)
        assertTrue(inside.isTap)
        assertFalse(inside.emit)
        assertFalse(inside.engaged)

        val edge = map(travel * CameraCommands.GIMBAL_STICK_TAP_SLOP, 0f)
        assertTrue(edge.isTap)
        assertFalse(edge.emit)

        val over = map(travel * CameraCommands.GIMBAL_STICK_TAP_SLOP + 0.01f, 0f)
        assertFalse(over.isTap)
        assertTrue(over.emit)
    }
}
