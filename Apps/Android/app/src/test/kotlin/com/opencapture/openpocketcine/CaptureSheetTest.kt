package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.FocusOption
import com.opencapture.openpocketcine.session.FocusTrackMode
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
    fun focusTrackChipsMatchIosCopy() {
        assertEquals(
            listOf(
                "Default",
                "Product Showcase",
                "Subject Lock Tracking",
                "Registered Subject Priority",
            ),
            FocusTrackMode.entries.map { it.label },
        )
        assertEquals(0x00, FocusTrackMode.DEFAULT.raw)
        assertEquals(0x01, FocusTrackMode.PRODUCT_SHOWCASE.raw)
        assertEquals(0x02, FocusTrackMode.SUBJECT_LOCK.raw)
        assertEquals(0x03, FocusTrackMode.REGISTERED_PRIORITY.raw)
        assertEquals("AF-S", FocusOption.resolve(CameraCommands.FOCUS_SINGLE, 2)?.chip)
        assertEquals("AF-C", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, -1)?.chip)
        assertEquals("Showcase", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 1)?.chip)
        assertEquals("Lock", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 2)?.chip)
        assertEquals("Priority", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 3)?.chip)
        assertEquals(
            "Showcase",
            CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = 1).focusLabel,
        )
        assertEquals("AF-S", CameraStatus(focusMode = CameraCommands.FOCUS_SINGLE, focusTrack = 2).focusLabel)
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

    @Test
    fun nanoColorWheelUsesCamcapFamily() {
        assertEquals(
            listOf("Normal 8-bit", "Normal 10-bit", "D-Log M 10-bit"),
            CaptureLists.colorWheelLabels(CameraStatus(), family = "nano"),
        )
        assertEquals(CameraCommands.COLOR_NORMAL, CaptureLists.colorModeFromLabel("Normal 8-bit", "nano"))
        assertEquals(CameraCommands.COLOR_NORMAL10, CaptureLists.colorModeFromLabel("Normal 10-bit", "nano"))
        assertEquals(CameraCommands.COLOR_DLOG_M, CaptureLists.colorModeFromLabel("D-Log M 10-bit", "nano"))
        assertEquals("Normal 8-bit", CameraCommands.colorLabel(CameraCommands.COLOR_NORMAL, "nano"))
        assertEquals("Normal", CameraCommands.colorLabel(CameraCommands.COLOR_NORMAL, "pocket"))
    }

    @Test
    fun expoModeSheetIsAutoManualOnly() {
        assertEquals("MODE", LiveSheet.EXPO.headerLabel)
        assertEquals("Exposure", LiveSheet.EXPO.subtitle)
        assertEquals("Auto", CameraStatus(expoMode = CameraCommands.EXPO_AUTO).expoLabel)
        assertEquals("Manual", CameraStatus(expoMode = CameraCommands.EXPO_MANUAL).expoLabel)
    }

    @Test
    fun isoAutoChipAndLimitGetMatchIos() {
        assertEquals("Auto", CaptureLists.isoChipValue(CameraStatus(isoIndex = 0, iso = 400)))
        assertEquals("1600", CaptureLists.isoChipValue(CameraStatus(isoIndex = 0x07, iso = 1600)))
        assertTrue(CaptureLists.shouldGetIsoLimit(CameraStatus(colorMode = CameraCommands.COLOR_NORMAL)))
        assertTrue(CaptureLists.shouldGetIsoLimit(CameraStatus(colorMode = CameraCommands.COLOR_DLOG)))
        assertTrue(CaptureLists.shouldGetIsoLimit(CameraStatus(colorMode = -1)))
        assertTrue(!CaptureLists.shouldGetIsoLimit(CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)))
    }

    @Test
    fun nativeIsoHopOnlyWhenStillOnBase() {
        assertEquals(
            0x05,
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG2,
                to = CameraCommands.COLOR_DLOG,
                currentIndex = 0x07,
                hopEnabled = true,
            ),
        )
        assertEquals(
            0x07,
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG,
                to = CameraCommands.COLOR_DLOG2,
                currentIndex = 0x05,
                hopEnabled = true,
            ),
        )
        assertEquals(
            null,
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG2,
                to = CameraCommands.COLOR_DLOG,
                currentIndex = 0x06,
                hopEnabled = true,
            ),
        )
        assertEquals(
            null,
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG,
                to = CameraCommands.COLOR_DLOG2,
                currentIndex = 0,
                hopEnabled = true,
            ),
        )
        assertEquals(
            null,
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG2,
                to = CameraCommands.COLOR_DLOG,
                currentIndex = 0x07,
                hopEnabled = false,
            ),
        )
    }

    @Test
    fun recFormatChipMatchesIosChipLabel() {
        assertEquals(
            "4K · 25p",
            CaptureLists.recFormatChipLabel(
                CameraStatus(resolutionCode = CameraCommands.RES_4K, fps = 25),
            ),
        )
        assertEquals(
            "1080p · 24p",
            CaptureLists.recFormatChipLabel(
                CameraStatus(resolutionCode = CameraCommands.RES_1080, fps = 24),
            ),
        )
        assertEquals("— · —", CaptureLists.recFormatChipLabel(CameraStatus()))
    }

    @Test
    fun storagePrefersStorageThenSdLikeIos() {
        val mixed =
            CameraStatus(
                storageFreeMb = 2048,
                storageTotalMb = 4096,
                sdFreeMb = 512,
                sdTotalMb = 1024,
            )
        assertEquals("2 GB · 50%", CaptureLists.storageLabel(mixed, showDuration = false))
        val sdOnly = CameraStatus(sdFreeMb = 1024, sdTotalMb = 2048)
        assertEquals("1 GB · 50%", CaptureLists.storageLabel(sdOnly, showDuration = false))
        val duration = CameraStatus(recordRemainingSec = 180)
        assertEquals("3 Min", CaptureLists.storageLabel(duration, showDuration = true))
        assertEquals("— Min", CaptureLists.storageLabel(CameraStatus(), showDuration = true))
    }

    @Test
    fun wbChipShowsCustomKelvinAndAuto() {
        assertEquals("Auto", CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_AUTO)))
        assertEquals(
            "5600K",
            CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 5600)),
        )
        assertEquals("Custom", CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_CUSTOM)))
        assertTrue(CaptureLists.wbIsAuto(CameraStatus(wbMode = CameraCommands.WB_AUTO)))
        assertTrue(!CaptureLists.wbIsAuto(CameraStatus(wbMode = CameraCommands.WB_CUSTOM)))
    }

    @Test
    fun holdFpsIgnoresHundredthTick() {
        assertEquals("25.00", LiveChromeReadout.holdFPS("25.13", "25.00"))
        assertEquals("25.00", LiveChromeReadout.holdFPS("24.70", "25.00"))
        assertEquals("25.50", LiveChromeReadout.holdFPS("25.50", "25.00"))
        assertEquals("RECOV", LiveChromeReadout.holdFPS("RECOV", "25.00"))
        assertEquals("25.00", LiveChromeReadout.holdFPS("25.00", "LINK"))
        assertEquals("—", LiveChromeReadout.holdFPS("—", "25.00"))
    }

    @Test
    fun fpsChipLabelIsLiveViewHealthNotRecordFps() {
        assertEquals(
            "—",
            LiveViewLink.fpsChipLabel(
                connection = com.opencapture.openpocketcine.core.ConnectionPhase.IDLE,
                recovering = false,
                formattedFPS = "25.00",
                measuredFPS = 0.0,
            ),
        )
        assertEquals(
            "LINK",
            LiveViewLink.fpsChipLabel(
                connection = com.opencapture.openpocketcine.core.ConnectionPhase.LIVE,
                recovering = false,
                formattedFPS = "25.00",
                measuredFPS = 0.0,
            ),
        )
        assertEquals(
            "RECOV",
            LiveViewLink.fpsChipLabel(
                connection = com.opencapture.openpocketcine.core.ConnectionPhase.LIVE,
                recovering = true,
                formattedFPS = "25.00",
                measuredFPS = 12.0,
            ),
        )
        assertEquals(
            "FAIL",
            LiveViewLink.fpsChipLabel(
                connection = com.opencapture.openpocketcine.core.ConnectionPhase.FAILED,
                recovering = false,
                formattedFPS = "25.00",
                measuredFPS = 25.0,
            ),
        )
        assertEquals(
            "25.00",
            LiveViewLink.fpsChipLabel(
                connection = com.opencapture.openpocketcine.core.ConnectionPhase.LIVE,
                recovering = false,
                formattedFPS = "25.00",
                measuredFPS = 25.0,
            ),
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
