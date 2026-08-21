package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
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
    fun dLog2HasNoIsoAuto() {
        val status = CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)
        assertTrue(!CaptureLists.offersIsoAuto(status))
        assertTrue(CaptureLists.isoAutoLabels(status).isEmpty())
        assertTrue(!CaptureLists.isoFallback(status.colorMode).contains(0))
    }

    @Test
    fun dLogIsoAutoRanges() {
        val status = CameraStatus(colorMode = CameraCommands.COLOR_DLOG)
        val dash = "\u2013"
        assertEquals(
            listOf("400${dash}800", "400${dash}1600", "400${dash}3200", "400${dash}6400"),
            CaptureLists.isoAutoLabels(status),
        )
        assertEquals(listOf(0x04, 0x05, 0x06, 0x07), CaptureLists.isoAutoLimits(status.colorMode).map { it.rawValue })
        assertEquals(IsoLimit.Max1600, CaptureLists.isoLimit("400${dash}1600", status))
        assertTrue(CaptureLists.offersIsoAuto(status))
    }

    @Test
    fun normalAndHdrIsoAutoRanges() {
        val dash = "\u2013"
        val expected =
            listOf(
                "100${dash}200",
                "100${dash}400",
                "100${dash}800",
                "100${dash}1600",
                "100${dash}3200",
                "100${dash}6400",
                "100${dash}12800",
                "100${dash}25600",
            )
        val normal = CameraStatus(colorMode = CameraCommands.COLOR_NORMAL)
        val hdr = CameraStatus(colorMode = CameraCommands.COLOR_HDR)
        assertEquals(expected, CaptureLists.isoAutoLabels(normal))
        assertEquals(expected, CaptureLists.isoAutoLabels(hdr))
        assertEquals(IsoLimit.Max800, CaptureLists.isoLimit("100${dash}800", normal))
        assertEquals(IsoLimit.Max25600, CaptureLists.isoLimit("100${dash}25600", hdr))
        assertEquals(0x02, IsoLimit.Max200.rawValue)
        assertEquals(0x03, IsoLimit.Max400.rawValue)
        assertEquals(0x06, IsoLimit.Max3200.rawValue)
        assertEquals(0x08, IsoLimit.Max12800.rawValue)
    }

    @Test
    fun evLabelsThirdStopsFromMinus3ToPlus3() {
        val minus = EvComp.MINUS
        val labels = CaptureLists.evLabels
        assertEquals(19, labels.size)
        assertEquals("${minus}3.0", labels.first())
        assertEquals("+3.0", labels.last())
        assertTrue(labels.contains("0.0"))
        assertTrue(labels.contains("${minus}1.3"))
        assertTrue(labels.contains("+0.7"))
        assertTrue(labels.contains("+1.0"))
        assertEquals(0x07, EvComp.fromLabel("${minus}3.0")?.rawValue)
        assertEquals(0x10, EvComp.fromLabel("0.0")?.rawValue)
        assertEquals(0x19, EvComp.fromLabel("+3.0")?.rawValue)
        assertEquals(
            listOf(
                "${minus}3.0",
                "${minus}2.7",
                "${minus}2.3",
                "${minus}2.0",
                "${minus}1.7",
                "${minus}1.3",
                "${minus}1.0",
                "${minus}0.7",
                "${minus}0.3",
                "0.0",
                "+0.3",
                "+0.7",
                "+1.0",
                "+1.3",
                "+1.7",
                "+2.0",
                "+2.3",
                "+2.7",
                "+3.0",
            ),
            labels,
        )
    }

    @Test
    fun shutterAngleLadderIsCalculatedNotCaptured() {
        assertEquals("5.6°", ShutterAngle.labels.first())
        assertEquals("360°", ShutterAngle.labels.last())
        assertEquals(48, ShutterAngle.denom(180.0, 24))
        assertEquals(50, ShutterAngle.denom(180.0, 24, listOf(25, 50, 100)))
        assertEquals("180°", ShutterAngle.nearestLabel(48, 24))
    }

    @Test
    fun emptyCapListShowsOnlyCurrent() {
        val status = CameraStatus(shutterDenom = 80)
        assertEquals(listOf(80), CaptureLists.shutterDenoms(status))
        assertEquals(listOf("1/80"), CaptureLists.shutterLabels(status))
    }

    @Test
    fun headersAreUppercaseIosNames() {
        assertEquals("ISO", LiveSheet.ISO.headerLabel)
        assertEquals("SHUTTER", LiveSheet.SHUTTER.headerLabel)
        assertEquals("WB", LiveSheet.WB.headerLabel)
        assertEquals("FOCUS", LiveSheet.FOCUS.headerLabel)
        assertEquals("MODE", LiveSheet.EXPO.headerLabel)
        assertEquals("AUDIO", LiveSheet.AUDIO.headerLabel)
        assertEquals("COLOR", LiveSheet.COLOR.headerLabel)
        assertEquals("RESOLUTION", LiveSheet.FORMAT.headerLabel)
    }

    @Test
    fun kelvinDrumIs2000To10000ByHundreds() {
        assertEquals(2000, CaptureLists.kelvinValues.first())
        assertEquals(10000, CaptureLists.kelvinValues.last())
        assertEquals(81, CaptureLists.kelvinValues.size)
        assertEquals("5600K", CaptureLists.kelvinLabels[CaptureLists.kelvinValues.indexOf(5600)])
        assertEquals(3200, CaptureLists.kelvinFromLabel("3200K"))
    }

    @Test
    fun nativeIsoHopCopyDoesNotInventAPairing() {
        assertEquals("Auto Native ISO", CaptureLists.NATIVE_ISO_HOP_TITLE)
        assertTrue(CaptureLists.NATIVE_ISO_HOP_HELP.isNotEmpty())
        assertTrue(!CaptureLists.NATIVE_ISO_HOP_HELP.contains("400 ↔ 1600"))
        assertEquals("Face Priority", CaptureLists.FACE_PRIORITY_TITLE)
    }

    @Test
    fun nanoHasNoFocusMode() {
        assertTrue(!CaptureLists.supportsFocusMode("Osmo Nano"))
        assertTrue(!CaptureLists.supportsFocusMode("OsmoNano-ABCD"))
        assertTrue(CaptureLists.supportsFocusMode("Osmo Pocket 4 Pro"))
        assertTrue(CaptureLists.supportsFocusMode(null))
    }

    @Test
    fun fpsDrumAndColorWheelMatchIos() {
        assertEquals(listOf("24p", "25p", "30p", "48p", "50p", "60p"), CaptureLists.fpsDrumLabels)
        assertEquals(1, CaptureLists.fpsIndexFromDrum("24p"))
        assertEquals(6, CaptureLists.fpsIndexFromDrum("60p"))
        assertEquals(
            listOf("Normal", "HDR", "D-Log", "D-Log2"),
            CaptureLists.colorWheelLabels(CameraStatus()),
        )
        assertEquals(CameraCommands.COLOR_DLOG2, CaptureLists.colorModeFromLabel("D-Log2"))
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
