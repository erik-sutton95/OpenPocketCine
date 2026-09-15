package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class VirtualJoystickMappingTest {
    @Test
    fun defaultMappingMatchesLegacyAxes() {
        val mapping = CameraCommands.VirtualJoystickMapping.DEFAULT
        assertFalse(mapping.invertPan)
        assertFalse(mapping.invertTilt)
        assertEquals(CameraCommands.GIMBAL_STICK_DEADZONE, mapping.deadzone)
        assertEquals(CameraCommands.VirtualJoystickCurve.STANDARD, mapping.curve)
        assertEquals(CameraCommands.GIMBAL_STICK_ANALOG_EXPO, mapping.curve.expo)
        assertTrue(mapping.isDefault)
        val samples = floatArrayOf(-1f, -0.7f, -0.5f, -0.08f, 0f, 0.08f, 0.5f, 0.7f, 1f)
        val expected =
            mapOf(
                1 to intArrayOf(887, 962, 995, 1024, 1024, 1024, 1053, 1086, 1162),
                4 to intArrayOf(474, 774, 909, 1024, 1024, 1024, 1139, 1274, 1574),
                5 to intArrayOf(474, 712, 881, 1024, 1024, 1024, 1167, 1336, 1574),
            )
        for ((sensitivity, wire) in expected) {
            val axes = samples.map { CameraCommands.gimbalAxis(it, sensitivity) }
            assertEquals(wire.toList(), axes)
            val mapped = samples.map { CameraCommands.gimbalAxis(it, sensitivity, mapping) }
            assertEquals(wire.toList(), mapped)
            val pan = samples.map { CameraCommands.gimbalAxes(it, 0f, sensitivity = sensitivity).second }
            assertEquals(wire.toList(), pan)
        }
        assertEquals(
            CameraCommands.GIMBAL_STICK_CENTER to CameraCommands.GIMBAL_STICK_CENTER,
            CameraCommands.gimbalAxes(0.04f, -0.04f),
        )
    }

    @Test
    fun operatorInvertComposesPictureInvertOnce() {
        val right = CameraCommands.gimbalAxes(1f, 0f)
        val picture = CameraCommands.gimbalAxes(1f, 0f, invertPan = true)
        val opPan =
            CameraCommands.gimbalAxes(
                1f,
                0f,
                mapping = CameraCommands.VirtualJoystickMapping(invertPan = true),
            )
        val both =
            CameraCommands.gimbalAxes(
                1f,
                0f,
                invertPan = true,
                mapping = CameraCommands.VirtualJoystickMapping(invertPan = true),
            )
        assertEquals(CameraCommands.GIMBAL_STICK_MIN, picture.second)
        assertEquals(CameraCommands.GIMBAL_STICK_MIN, opPan.second)
        assertEquals(right.second, both.second)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, both.first)
        val opTilt =
            CameraCommands.gimbalAxes(
                0f,
                1f,
                mapping = CameraCommands.VirtualJoystickMapping(invertTilt = true),
            )
        assertEquals(CameraCommands.GIMBAL_STICK_MIN, opTilt.first)
        assertEquals(CameraCommands.GIMBAL_STICK_CENTER, opTilt.second)
    }

    @Test
    fun linearPathIgnoresVirtualMapping() {
        val mapped =
            CameraCommands.VirtualJoystickMapping(
                invertPan = true,
                invertTilt = true,
                deadzone = 0.25f,
                curve = CameraCommands.VirtualJoystickCurve.FINE,
            )
        val linear =
            CameraCommands.gimbalAxes(1f, 1f, invertPan = false, mapping = mapped, linear = true)
        val plain = CameraCommands.gimbalAxes(1f, 1f, linear = true)
        assertEquals(plain, linear)
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, linear.first)
        assertEquals(CameraCommands.GIMBAL_STICK_MAX, linear.second)
    }

    @Test
    fun deadzoneBoundariesAndCorruptPercent() {
        assertEquals(0f, CameraCommands.VirtualJoystickMapping.clampedDeadzone(-1f))
        assertEquals(0.25f, CameraCommands.VirtualJoystickMapping.clampedDeadzone(0.5f))
        assertEquals(
            CameraCommands.GIMBAL_STICK_DEADZONE,
            CameraCommands.VirtualJoystickMapping.clampedDeadzone(Float.NaN),
        )
        assertEquals(0, CameraCommands.VirtualJoystickMapping.clampedDeadzonePercent(-4))
        assertEquals(25, CameraCommands.VirtualJoystickMapping.clampedDeadzonePercent(99))
        assertEquals(8, CameraCommands.VirtualJoystickMapping.resolvedDeadzonePercent(null))
        assertEquals(25, CameraCommands.VirtualJoystickMapping.resolvedDeadzonePercent(99))
        assertEquals(0, CameraCommands.VirtualJoystickMapping.resolvedDeadzonePercent(-3))
        assertEquals(0f, CameraCommands.VirtualJoystickMapping.deadzoneFromPercent(0))
        assertEquals(0.25f, CameraCommands.VirtualJoystickMapping.deadzoneFromPercent(25))
        assertEquals(
            CameraCommands.GIMBAL_STICK_DEADZONE,
            CameraCommands.VirtualJoystickMapping.deadzoneFromPercent(8),
        )
        assertEquals(0f, CameraCommands.gimbalAnalogCurve(0.2f, deadzone = 0.25f))
        assertEquals(
            CameraCommands.GIMBAL_STICK_CENTER,
            CameraCommands.gimbalAxis(
                0.2f,
                mapping = CameraCommands.VirtualJoystickMapping(deadzone = 0.25f),
            ),
        )
        assertEquals(
            CameraCommands.GIMBAL_STICK_MAX,
            CameraCommands.gimbalAxis(
                1f,
                mapping = CameraCommands.VirtualJoystickMapping(deadzone = 0.25f),
            ),
        )
        assertTrue(CameraCommands.gimbalAnalogCurve(0.04f, deadzone = 0f) != 0f)
        assertEquals(0f, CameraCommands.gimbalAnalogCurve(0f, deadzone = 0f))
    }

    @Test
    fun curvesAreMonotonicBoundedAndCorruptCurveDefaults() {
        for (curve in CameraCommands.VirtualJoystickCurve.entries) {
            var previous = -1.01f
            for (step in 0..20) {
                val x = step / 20f
                val y = CameraCommands.gimbalAnalogCurve(x, expo = curve.expo)
                assertTrue(y + 1e-5f >= previous)
                assertTrue(y in 0f..1f)
                previous = y
                val axis =
                    CameraCommands.gimbalAxis(
                        x,
                        mapping = CameraCommands.VirtualJoystickMapping(curve = curve),
                    )
                assertTrue(axis in CameraCommands.GIMBAL_STICK_MIN..CameraCommands.GIMBAL_STICK_MAX)
                assertEquals(-y, CameraCommands.gimbalAnalogCurve(-x, expo = curve.expo), 1e-5f)
            }
            assertEquals(1f, CameraCommands.gimbalAnalogCurve(1f, expo = curve.expo))
            assertEquals(0f, CameraCommands.gimbalAnalogCurve(0f, expo = curve.expo))
        }
        val mid = 0.5f
        val linear = kotlin.math.abs(CameraCommands.gimbalAnalogCurve(mid, expo = 1.0))
        val standard = kotlin.math.abs(CameraCommands.gimbalAnalogCurve(mid, expo = 2.0))
        val fine = kotlin.math.abs(CameraCommands.gimbalAnalogCurve(mid, expo = 3.0))
        assertTrue(linear > standard)
        assertTrue(standard > fine)
        assertEquals(
            CameraCommands.VirtualJoystickCurve.STANDARD,
            CameraCommands.VirtualJoystickCurve.parse(null),
        )
        assertEquals(
            CameraCommands.VirtualJoystickCurve.STANDARD,
            CameraCommands.VirtualJoystickCurve.parse("cubic"),
        )
        assertEquals(
            CameraCommands.VirtualJoystickCurve.FINE,
            CameraCommands.VirtualJoystickCurve.parse("FINE"),
        )
        assertEquals(
            CameraCommands.VirtualJoystickCurve.LINEAR,
            CameraCommands.VirtualJoystickCurve.fromLabel("Linear"),
        )
        assertEquals(
            CameraCommands.VirtualJoystickCurve.STANDARD,
            CameraCommands.VirtualJoystickCurve.fromLabel("nope"),
        )
    }

    @Test
    fun wireStaysInsideTravel() {
        val mapping =
            CameraCommands.VirtualJoystickMapping(
                invertPan = true,
                invertTilt = true,
                deadzone = 0f,
                curve = CameraCommands.VirtualJoystickCurve.LINEAR,
            )
        var x = -1.2f
        while (x <= 1.2f) {
            var y = -1.2f
            while (y <= 1.2f) {
                val axes =
                    CameraCommands.gimbalAxes(
                        x,
                        y,
                        invertPan = true,
                        sensitivity = 5,
                        mapping = mapping,
                    )
                assertTrue(axes.first in CameraCommands.GIMBAL_STICK_MIN..CameraCommands.GIMBAL_STICK_MAX)
                assertTrue(axes.second in CameraCommands.GIMBAL_STICK_MIN..CameraCommands.GIMBAL_STICK_MAX)
                y += 0.2f
            }
            x += 0.2f
        }
        assertEquals(
            CameraCommands.GIMBAL_STICK_CENTER to CameraCommands.GIMBAL_STICK_CENTER,
            CameraCommands.gimbalAxes(0f, 0f, mapping = mapping),
        )
    }
}
