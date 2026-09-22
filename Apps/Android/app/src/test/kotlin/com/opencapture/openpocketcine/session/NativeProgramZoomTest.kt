package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.ln
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NativeProgramZoomTest {
    @Test fun rockerPayloadsMatchTheSuccessfulMimoCapture() {
        assertContentEquals(byteArrayOf(1, 0x48, 1, 0), NativeProgramZoomCommand.Rate(72, true).payload)
        assertContentEquals(byteArrayOf(1, 0x49, 0, 0), NativeProgramZoomCommand.Rate(73, false).payload)
        assertContentEquals(byteArrayOf(0xFF.toByte(), 0, 0, 0), NativeProgramZoomCommand.Stop.payload)
        assertContentEquals(byteArrayOf(0x0A, 0x4E, 0x8B.toByte(), 2), NativeProgramZoomCommand.Position(3.0).payload)
        assertContentEquals(byteArrayOf(1, 72, 1, 0), CameraCommands.zoomRate(0, true))
        assertContentEquals(byteArrayOf(1, 78, 0, 0), CameraCommands.zoomRate(255, false))
    }

    @Test fun timedLegBlendsTwoSpeedsWithoutPositionStepsOrStopPulses() {
        val dt = 0.0005
        var distance = 0.0
        val commands = mutableListOf<NativeProgramZoomCommand>()
        repeat(5_000) {
            val command = NativeProgramZoom.demand(3.0, 6.0, 2.5, it * dt).command
            assertTrue(command is NativeProgramZoomCommand.Rate)
            assertTrue(command.increasing)
            distance += (command.speed - 71) * NativeProgramZoom.SLOWEST_LOG_RATE * dt
            if (commands.lastOrNull() != command) commands += command
        }
        assertEquals(listOf<NativeProgramZoomCommand>(NativeProgramZoomCommand.Rate(72, true), NativeProgramZoomCommand.Rate(73, true),
            NativeProgramZoomCommand.Rate(72, true)), commands)
        assertTrue(abs(3 * exp(distance) - 6) < 0.002)
        assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(3.0, 6.0, 2.5, 2.5).command)
    }

    @Test fun longLegWaitsThenZoomsContinuouslyToItsDeadline() {
        val delay = 10.0 - ln(2.0) / NativeProgramZoom.SLOWEST_LOG_RATE
        assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(6.0, 3.0, 10.0, delay - 0.001).command)
        assertEquals(NativeProgramZoomCommand.Rate(72, false), NativeProgramZoom.demand(6.0, 3.0, 10.0, delay + 0.001).command)
        assertEquals(NativeProgramZoomCommand.Rate(72, false), NativeProgramZoom.demand(6.0, 3.0, 10.0, 9.99).command)
        assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(3.0, 3.0, 2.0, 1.0).command)
        assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(1.0, 12.0, 0.5, 0.25).command)
        assertEquals("Increase the move duration for this zoom range", NativeProgramZoom.demand(1.0, 12.0, 0.5, 0.25).failureReason)
    }

    @Test fun nativePathRetainsBAndReplansFromMeasuredZoomAfterResume() {
        val a = GimbalWaypoint(0.0, 0.0, 3.0, 175.0)
        val path = GimbalZoomPath(GimbalProgram(a, a.copy(zoom = 6.0), a.copy(zoom = 4.0), 2.5, 2.0))
        assertEquals(6.0, path.nativeDemand(2.499).destination)
        assertEquals(4.0, path.nativeDemand(2.5).destination)
        assertEquals(NativeProgramZoomCommand.Stop, path.nativeDemand(2.5).command)
        assertEquals(NativeProgramZoomCommand.Rate(72, false), path.nativeDemand(4.0).command)
        val resumed = path.remaining(1.5, 5.2, quantized = true)
        assertEquals(5.2, resumed.legs.first().from)
        assertEquals(1.0, resumed.legs.first().duration)
        assertEquals(NativeProgramZoomCommand.Stop, resumed.nativeDemand(0.0).command)
        assertEquals(NativeProgramZoomCommand.Rate(72, true), resumed.nativeDemand(0.9).command)
    }

    @Test fun minimumTimingAppliesOnlyToTheMeasuredBodyAndLensReceiptIsIndependent() {
        val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
        val program = GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 0.5)
        val ready = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0)
        assertEquals("Increase the move duration for this zoom range",
            nativeProgramZoomFailure(program, CameraModel("Osmo Pocket 4 Pro"), ready))
        assertNull(nativeProgramZoomFailure(program, CameraModel("Osmo Pocket 3"), ready))
        assertNull(nativeProgramZoomFeedbackFailure(0.0, 0.85))
        assertNotNull(nativeProgramZoomFeedbackFailure(1.0, 1.851))
        assertNotNull(nativeProgramZoomFeedbackFailure(null, 1.0))
        assertNotNull(nativeProgramZoomFeedbackFailure(1.0, 0.9))
    }

    @Test fun tinySpansAreRejectedBeforePreparationIncludingResumedRemainders() {
        val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
        val ready = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0)
        val tiny = GimbalProgram(a, a.copy(zoom = 1.01), durationAB = 1.0)
        assertEquals("Increase the zoom difference between points",
            nativeProgramZoomFailure(tiny, CameraModel("Osmo Pocket 4 Pro"), ready))
        assertNull(nativeProgramZoomFailure(tiny, CameraModel("Osmo Pocket 3"), ready))
        val resumed = GimbalZoomPath(tiny.copy(b = a.copy(zoom = 3.0))).remaining(0.8, 2.99, quantized = true)
        assertEquals("Increase the zoom difference between points", resumed.nativeDemand(0.0).failureReason)
    }

    @Test fun crossingAnEpsilonBeforeBReversesInsteadOfCreatingANegativeElapsedStop() {
        val a = GimbalWaypoint(0.0, 0.0, 3.0, 175.0)
        val path = GimbalZoomPath(GimbalProgram(a, a.copy(zoom = 6.0), a, 2.5, 2.5))
        val demand = path.nativeDemand(2.5 - 5e-10)
        assertEquals(NativeProgramZoomCommand.Rate(72, false), demand.command)
        assertNull(demand.failureReason)
        assertTrue(demand.nextChange > 0)
    }

    @Test fun shortGearSegmentsAreCoalescedAndCarryExactDeadlines() {
        for ((duration, distanceInSlowSeconds) in listOf(1.0 to 1.01, 0.5 to 0.93, 0.5 to 0.98, 0.5 to 3.495)) {
            val to = 3.0 * exp(distanceInSlowSeconds * NativeProgramZoom.SLOWEST_LOG_RATE)
            var elapsed = 0.0
            var logDistance = 0.0
            var rates = 0
            while (elapsed < duration - 1e-9) {
                val demand = NativeProgramZoom.demand(3.0, to, duration, elapsed)
                assertNull(demand.failureReason)
                assertTrue(demand.nextChange > 0)
                val command = demand.command
                if (command is NativeProgramZoomCommand.Rate) {
                    assertTrue(demand.nextChange >= 0.05 - 1e-9, "Every planned gear must survive one dispatch interval")
                    logDistance += (command.speed - 71) * NativeProgramZoom.SLOWEST_LOG_RATE * demand.nextChange
                    rates++
                }
                elapsed += demand.nextChange
            }
            assertEquals(duration, elapsed, 1e-9)
            assertEquals(to, 3 * exp(logDistance), 1e-9)
            assertTrue(rates in 1..3)
        }
    }
}
