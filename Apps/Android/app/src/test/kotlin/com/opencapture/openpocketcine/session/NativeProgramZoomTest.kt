package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class NativeProgramZoomTest {
    @Test fun programmedDemandTracksLinearFactorThroughoutTheLeg() {
        for ((from, to) in listOf(3.0 to 6.0, 6.0 to 3.0)) {
            for (fraction in listOf(0.0, 0.1, 0.25, 0.5, 0.75, 0.9, 1.0)) {
                val demand = NativeProgramZoom.demand(from, to, 2.5, fraction * 2.5)
                assertEquals(NativeProgramZoomCommand.Track(from + (to - from) * fraction), demand.command)
                assertContentEquals(CameraCommands.zoomLens(CamFov.lensPosition(from + (to - from) * fraction)),
                    demand.command.payload, "The target must track factor linearly for the entire leg")
            }
        }
    }

    @Test fun preparationAndTrackingUseTheSameLensPayloadAndRockerProtocolRemainsAvailable() {
        assertContentEquals(byteArrayOf(0x0A, 0x4E, 0x8B.toByte(), 2), NativeProgramZoomCommand.Position(3.0).payload)
        assertContentEquals(NativeProgramZoomCommand.Position(3.0).payload, NativeProgramZoomCommand.Track(3.0).payload)
        assertContentEquals(byteArrayOf(0xFF.toByte(), 0, 0, 0), NativeProgramZoomCommand.Stop.payload)
        assertContentEquals(byteArrayOf(1, 72, 1, 0), CameraCommands.zoomRate(72, true))
        assertContentEquals(byteArrayOf(1, 73, 0, 0), CameraCommands.zoomRate(73, false))
    }

    @Test fun longAndTinyLegsStartImmediatelyAndClampAtBothEnds() {
        assertEquals(NativeProgramZoomCommand.Track(3.75), NativeProgramZoom.demand(3.0, 6.0, 60.0, 15.0).command)
        assertEquals(NativeProgramZoomCommand.Track(1.0005), NativeProgramZoom.demand(1.0, 1.001, 1.0, 0.5).command)
        assertEquals("Invalid zoom movement", NativeProgramZoom.demand(3.0, 6.0, 2.5, -1.0).failureReason)
        assertEquals(NativeProgramZoomCommand.Track(6.0), NativeProgramZoom.demand(3.0, 6.0, 2.5, 3.0).command)
        assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(3.0, 3.0, 2.0, 1.0).command)
        val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
        val ready = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL, zoomFactor = 1.0)
        for (zoom in listOf(1.001, 12.0)) {
            assertNull(nativeProgramZoomFailure(GimbalProgram(a, a.copy(zoom = zoom), durationAB = 0.5),
                CameraModel("Osmo Pocket 4 Pro"), ready), "Position tracking has no native gear travel restriction")
        }
    }

    @Test fun invalidDemandCannotEmitALensTarget() {
        for (values in listOf(listOf(Double.NaN, 3.0, 1.0, 0.0), listOf(1.0, Double.POSITIVE_INFINITY, 1.0, 0.0),
                listOf(1.0, 3.0, 0.0, 0.0), listOf(1.0, 3.0, Double.NaN, 0.0), listOf(1.0, 3.0, 1.0, Double.NaN))) {
            assertEquals(NativeProgramZoomCommand.Stop, NativeProgramZoom.demand(values[0], values[1], values[2], values[3]).command)
        }
    }

    @Test fun nativePathRetainsBAndReplansFromMeasuredZoomAfterResume() {
        val a = GimbalWaypoint(0.0, 0.0, 3.0, 175.0)
        val path = GimbalZoomPath(GimbalProgram(a, a.copy(zoom = 6.0), a.copy(zoom = 4.0), 2.5, 2.0))
        for ((time, zoom) in listOf(0.0 to 3.0, 1.25 to 4.5, 2.5 to 6.0, 3.5 to 5.0, 4.5 to 4.0, 5.0 to 4.0)) {
            assertEquals(NativeProgramZoomCommand.Track(zoom), path.nativeDemand(time).command)
        }
        val resumed = path.remaining(1.5, 5.2, quantized = true)
        assertEquals(NativeProgramZoomCommand.Track(5.2), resumed.nativeDemand(0.0).command)
        assertEquals(NativeProgramZoomCommand.Track(5.6), resumed.nativeDemand(0.5).command)
        assertEquals(NativeProgramZoomCommand.Track(6.0), resumed.nativeDemand(1.0).command)
    }

    @Test fun crossingAnEpsilonBeforeBPreservesTheNextLegStart() {
        val a = GimbalWaypoint(0.0, 0.0, 3.0, 175.0)
        val path = GimbalZoomPath(GimbalProgram(a, a.copy(zoom = 6.0), a, 2.5, 2.5))
        assertEquals(path.nativeDemand(2.5), path.nativeDemand(2.5 - 5e-10))
        assertEquals(NativeProgramZoomCommand.Track(6.0), path.nativeDemand(2.5).command)
    }

    @Test fun lateEndpointRemainsUntilATrackingSampleIsAdmitted() {
        val a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0)
        val engine = GimbalMoveEngine()
        assertTrue(engine.start(GimbalProgram(a, a.copy(zoom = 3.0), durationAB = 1.0, loop = true), a))
        repeat(294) { engine.tick(0.01, a) }
        assertTrue((engine.nativeZoomDemand!!.command as NativeProgramZoomCommand.Track).factor < 3.0)
        engine.tick(0.065, a)
        assertEquals("B→A", engine.readout(a)!!.label)
        assertEquals(NativeProgramZoomCommand.Track(3.0), engine.nativeZoomDemand!!.command)
        engine.tick(0.01, a)
        assertEquals(NativeProgramZoomCommand.Track(3.0), engine.consumeNativeZoomDemand()!!.command)
        assertTrue((engine.nativeZoomDemand!!.command as NativeProgramZoomCommand.Track).factor < 3.0)
        assertTrue(engine.pause(a))
        assertNull(engine.nativeZoomDemand)
        engine.cancel()
        assertNull(engine.nativeZoomDemand)
    }

    @Test fun lensReceiptFreshnessRemainsIndependentOfAngularReports() {
        assertNull(nativeProgramZoomFeedbackFailure(0.0, 0.85))
        assertNotNull(nativeProgramZoomFeedbackFailure(1.0, 1.851))
        assertNotNull(nativeProgramZoomFeedbackFailure(null, 1.0))
        assertNotNull(nativeProgramZoomFeedbackFailure(1.0, 0.9))
    }
}
