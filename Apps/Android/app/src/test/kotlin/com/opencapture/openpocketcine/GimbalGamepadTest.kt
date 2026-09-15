package com.opencapture.openpocketcine

import android.view.KeyEvent
import com.opencapture.openpocketcine.session.CameraCommands
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class GimbalGamepadTest {
    @Test
    fun discussion159FaceShoulderAndDpad() {
        assertEquals(GamepadOperatorAction.RECORD, GamepadOperatorMap.face(GamepadFaceButton.A))
        assertEquals(GamepadOperatorAction.RECENTER, GamepadOperatorMap.face(GamepadFaceButton.B))
        assertEquals(GamepadOperatorAction.FLIP, GamepadOperatorMap.face(GamepadFaceButton.X))
        assertEquals(GamepadOperatorAction.TRACK, GamepadOperatorMap.face(GamepadFaceButton.Y))
        assertEquals(GamepadOperatorAction.ZOOM_CHIP_OUT, GamepadOperatorMap.shoulder(GamepadShoulder.LEFT))
        assertEquals(GamepadOperatorAction.ZOOM_CHIP_IN, GamepadOperatorMap.shoulder(GamepadShoulder.RIGHT))
        assertEquals(GamepadOperatorAction.ISO_UP, GamepadOperatorMap.dpad(GamepadDpad.UP))
        assertEquals(GamepadOperatorAction.ISO_DOWN, GamepadOperatorMap.dpad(GamepadDpad.DOWN))
        assertEquals(GamepadOperatorAction.SHUTTER_OPEN, GamepadOperatorMap.dpad(GamepadDpad.LEFT))
        assertEquals(GamepadOperatorAction.SHUTTER_CLOSE, GamepadOperatorMap.dpad(GamepadDpad.RIGHT))
    }

    @Test
    fun keysMatchDiscussion159() {
        assertEquals(GamepadOperatorAction.RECORD, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_A))
        assertEquals(GamepadOperatorAction.RECENTER, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_B))
        assertEquals(GamepadOperatorAction.FLIP, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_X))
        assertEquals(GamepadOperatorAction.TRACK, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_Y))
        assertEquals(GamepadOperatorAction.ZOOM_CHIP_OUT, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_L1))
        assertEquals(GamepadOperatorAction.ZOOM_CHIP_IN, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_R1))
        assertEquals(GamepadOperatorAction.ISO_UP, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_DPAD_UP))
        assertEquals(GamepadOperatorAction.ISO_DOWN, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_DPAD_DOWN))
        assertEquals(GamepadOperatorAction.SHUTTER_OPEN, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_DPAD_LEFT))
        assertEquals(GamepadOperatorAction.SHUTTER_CLOSE, GimbalGamepad.actionForKey(KeyEvent.KEYCODE_DPAD_RIGHT))
        assertNull(GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_START))
        assertNull(GimbalGamepad.actionForKey(KeyEvent.KEYCODE_BUTTON_L2))
    }

    @Test
    fun hatMapsDpad() {
        assertEquals(GamepadDpad.LEFT, GimbalGamepad.hatDpad(-1f, 0f))
        assertEquals(GamepadDpad.RIGHT, GimbalGamepad.hatDpad(1f, 0f))
        assertEquals(GamepadDpad.UP, GimbalGamepad.hatDpad(0f, -1f))
        assertEquals(GamepadDpad.DOWN, GimbalGamepad.hatDpad(0f, 1f))
        assertNull(GimbalGamepad.hatDpad(0f, 0f))
        assertNull(GimbalGamepad.hatDpad(0.2f, -0.2f))
    }

    @Test
    fun restUsesAnalogDeadzone() {
        assertTrue(GimbalGamepad.isRest(0f, 0f))
        assertTrue(GimbalGamepad.isRest(0.04f, -0.04f))
        assertFalse(GimbalGamepad.isRest(0.5f, 0f))
        assertTrue(CameraCommands.gimbalAnalogCurve(0.04f) == 0f)
        assertTrue(CameraCommands.gimbalAnalogCurve(0.5f) != 0f)
    }

    @Test
    fun gimbalStickDefaultsLeftAndIgnoresTheOtherAxes() {
        assertEquals(GamepadGimbalStick.DEFAULT, GamepadGimbalStick.LEFT)
        assertEquals(GamepadGimbalStick.LEFT, GamepadGimbalStick.parse(null))
        assertEquals(GamepadGimbalStick.RIGHT, GamepadGimbalStick.parse("right"))
        val left = GamepadGimbalStick.LEFT.axes(0.8f, -0.2f, -1f, 1f)
        assertEquals(0.8f, left.first)
        assertEquals(-0.2f, left.second)
        val right = GamepadGimbalStick.RIGHT.axes(0.8f, -0.2f, -1f, 1f)
        assertEquals(-1f, right.first)
        assertEquals(1f, right.second)
        assertTrue(GamepadGimbalStick.restHeldMotion(GamepadGimbalStick.LEFT, GamepadGimbalStick.RIGHT, true))
        assertFalse(GamepadGimbalStick.restHeldMotion(GamepadGimbalStick.LEFT, GamepadGimbalStick.LEFT, true))
        assertFalse(GamepadGimbalStick.restHeldMotion(GamepadGimbalStick.LEFT, GamepadGimbalStick.RIGHT, false))
    }

    @Test
    fun shutterHudUsesLiveDenomWhenPreferredDoesNotMap() {
        val available = listOf(24, 48, 50, 60, 120)
        assertEquals(
            "180°",
            GamepadShutterSync.angleLabel(48, 24, available, 180.0),
        )
        assertEquals(
            "72°",
            GamepadShutterSync.angleLabel(120, 24, available, 180.0),
        )
        assertTrue(GamepadShutterSync.shouldPersistPreferredAngle(true, false, false))
        assertFalse(GamepadShutterSync.shouldPersistPreferredAngle(true, true, false))
        assertFalse(GamepadShutterSync.shouldPersistPreferredAngle(true, false, true))
        val speedStops = listOf(16000, 120, 60, 50, 48, 24)
        assertEquals(24, CameraCommands.shutterSteppedDenom(48, 1, speedStops))
        assertEquals(50, CameraCommands.shutterSteppedDenom(48, -1, speedStops))
        val next = CameraCommands.shutterSteppedDenom(48, -1, speedStops)!!
        val synced = GamepadShutterSync.preferredAngle(next, 24)
        assertEquals(172.0, synced)
        assertEquals("172°", GamepadShutterSync.angleLabel(next, 24, speedStops, synced))
        assertTrue(ShutterAngle.denom(synced, 60) != ShutterAngle.denom(180.0, 60))
    }
}
