package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals

class LiveChromeThrottleTest {
    private val base = CameraStatus()

    @Test fun telemetryMetersAndTimecodeWaitForTheHudInterval() {
        val next = base.copy(timecode = "01:02:03:04", audioMetersLeft = -12.0, batteryPercent = 80, iso = 800)
        assertEquals(150L, LiveChromeThrottle.holdMs(base, next, fromTelemetry = true, publishedAtMs = 1_000, nowMs = 1_050))
        assertEquals(0L, LiveChromeThrottle.holdMs(base, next, fromTelemetry = true, publishedAtMs = 1_000, nowMs = 1_200))
    }

    @Test fun operatorFieldsBypassTheInterval() {
        listOf(
            base.copy(isRecording = true),
            base.copy(shootingMode = 2),
            base.copy(colorMode = 0x41),
            base.copy(zoomFactorRaw = 3072),
            base.copy(evComp = 0x12),
            base.copy(availableShutterDenoms = listOf(50, 100)),
        ).forEach { next ->
            assertEquals(0L, LiveChromeThrottle.holdMs(base, next, fromTelemetry = true, publishedAtMs = 1_000, nowMs = 1_001))
        }
    }

    @Test fun controlWritesAreNeverHeld() {
        val optimisticIso = base.copy(isoIndex = 5)
        assertEquals(0L, LiveChromeThrottle.holdMs(base, optimisticIso, fromTelemetry = false, publishedAtMs = 1_000, nowMs = 1_001))
    }
}
