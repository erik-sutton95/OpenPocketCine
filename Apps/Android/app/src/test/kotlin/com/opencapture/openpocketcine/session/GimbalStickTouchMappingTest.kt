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
    fun commandScalesOverOuterRadiusWhileVisualStaysAtKnobTravel() {
        // The visible ring commands 1/1.35; full command sits 1.35x further out.
        for ((dx, command) in listOf(outer to 1f / 1.35f, commandRadius to 1f)) {
            val mapped = map(dx, 0f)
            assertEquals(command, mapped.commandX, 1e-5f, "dx=$dx")
            assertEquals(0f, mapped.commandY, 1e-5f, "dx=$dx")
            assertEquals(travel, mapped.visualX, 1e-5f, "dx=$dx")
            assertEquals(0f, mapped.visualY, 1e-5f, "dx=$dx")
        }
        val ring = map(outer, 0f)
        assertTrue(ring.emit)
        assertTrue(ring.engaged)
        assertFalse(ring.isTap)
        assertTrue(ring.commandX < map(commandRadius, 0f).commandX)
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
    fun engagedReturnToCenterEmitsZero() {
        // A tap inside the slop does not engage (initialTapRemainsTapInsideVisualSlop).
        val thrown = map(outer, 0f, engaged = false)
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
