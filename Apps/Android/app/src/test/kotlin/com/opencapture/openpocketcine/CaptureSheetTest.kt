package com.opencapture.openpocketcine

import com.opencapture.opencine.cameracontrols.CaptureLists
import com.opencapture.opencine.dji.parseIsoIndices
import com.opencapture.opencine.dji.parseShutterDenoms
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraStatus
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

class CaptureSheetTest {
    @Test
    fun shutterWheelUsesCameraListNotHardcoded24pTable() {
        val status =
            CameraStatus(
                fps = 60,
                shutterDenom = 50,
                availableShutterDenoms = CameraCommands.parseShutterDenoms(hex(SHUTTER_60P)),
            )
        val denoms = CaptureLists.shutterDenoms(status)
        assertTrue(denoms.contains(50), "4K 60p payload includes 1/50")
        assertTrue(!denoms.contains(25), "60p payload does not offer 1/25")
        assertEquals(status.availableShutterDenoms, denoms)
        assertTrue(!denoms.contains(13), "wheel cannot invent a 24p-only stop")
    }

    @Test
    fun shutterWheelOmitsSpeedsMissingFromPayload() {
        val status =
            CameraStatus(
                fps = 25,
                shutterDenom = 50,
                availableShutterDenoms = CameraCommands.parseShutterDenoms(hex(SHUTTER_25P)),
            )
        val denoms = CaptureLists.shutterDenoms(status)
        val other = CameraCommands.parseShutterDenoms(hex(SHUTTER_60P))
        assertTrue(denoms != other)
        assertTrue(denoms.contains(25))
        assertTrue(denoms.contains(50))
        for (extra in listOf(13, 15, 20, 125, 250, 10_000, 13_000)) {
            assertTrue(!denoms.contains(extra), "do not offer 1/$extra — not in payload")
        }
    }

    @Test
    fun isoWheelUsesCamcapAndStarsBaseForTransfer() {
        val dlog2 =
            CameraStatus(
                colorMode = CameraCommands.COLOR_DLOG2,
                availableIsoIndices = CameraCommands.parseIsoIndices(hex("0108000006030405060708")),
            )
        assertEquals(listOf("100", "200", "400", "800", "1600", "3200"), CaptureLists.isoDrumLabels(dlog2))
        assertEquals(setOf("1600"), CaptureLists.isoMarkedLabels(dlog2))

        val dlog =
            CameraStatus(
                colorMode = CameraCommands.COLOR_DLOG,
                availableIsoIndices = CameraCommands.parseIsoIndices(hex("0108000006000506070809")),
            )
        assertEquals(
            dlog.availableIsoIndices.filter { it != 0 }.map { CameraCommands.isoLabel(it) },
            CaptureLists.isoDrumLabels(dlog),
        )
        assertEquals(setOf("400"), CaptureLists.isoMarkedLabels(dlog))
        assertTrue(!CaptureLists.isoMarkedLabels(dlog).contains("1600"))

        val rec709 =
            CameraStatus(
                colorMode = CameraCommands.COLOR_NORMAL,
                availableIsoIndices = dlog2.availableIsoIndices,
            )
        assertTrue(CaptureLists.isoMarkedLabels(rec709).isEmpty())
        assertEquals(CaptureLists.isoDrumLabels(dlog2), CaptureLists.isoDrumLabels(rec709))
    }

    @Test
    fun applyDrumSpeedUsesCamcapNeverInvented24pStops() {
        val status =
            CameraStatus(
                fps = 60,
                shutterDenom = 50,
                availableShutterDenoms = CameraCommands.parseShutterDenoms(hex(SHUTTER_60P)),
            )
        assertEquals(
            CaptureLists.ShutterDrumCommand.SetShutter(50),
            CaptureLists.applyShutterDrum("1/50", false, false, false, status),
        )
        assertEquals(
            CaptureLists.ShutterDrumCommand.Ignored,
            CaptureLists.applyShutterDrum("1/13", false, false, false, status),
        )
        assertEquals(
            CaptureLists.ShutterDrumCommand.Ignored,
            CaptureLists.applyShutterDrum("1/25", false, false, false, status),
        )
    }

    companion object {
        private const val SHUTTER_25P =
            "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
        private const val SHUTTER_60P =
            "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"

        private fun hex(s: String): ByteArray =
            ByteArray(s.length / 2) { i -> s.substring(i * 2, i * 2 + 2).toInt(16).toByte() }
    }
}
