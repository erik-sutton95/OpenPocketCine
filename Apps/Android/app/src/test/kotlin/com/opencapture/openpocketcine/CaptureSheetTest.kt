package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.FocusOption
import com.opencapture.openpocketcine.session.FocusTrackMode
import com.opencapture.openpocketcine.session.VideoFormat
import com.opencapture.openpocketcine.session.VideoFrameRate
import com.opencapture.openpocketcine.session.VideoResolution
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull
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
    fun isoStarFollowsStatusTransferNotTeleHopGuess() {
        var status = CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)
        assertEquals(setOf("1600"), CaptureLists.isoMarkedLabels(status))
        status = status.copy(colorMode = CameraCommands.COLOR_DLOG)
        assertEquals(
            setOf("400"),
            CaptureLists.isoMarkedLabels(status),
            "star follows status.colorMode after the body reports D-Log",
        )
        assertEquals(
            CameraCommands.COLOR_DLOG,
            CameraCommands.colorModeForZoom(3.0, CameraCommands.COLOR_DLOG2),
        )
        status = status.copy(colorMode = CameraCommands.COLOR_DLOG2)
        assertEquals(
            setOf("1600"),
            CaptureLists.isoMarkedLabels(status),
            "zoom tele hop guess must not flip the star while status is still D-Log2",
        )
        assertEquals(
            setOf("400"),
            CaptureLists.isoMarkedLabels(CameraStatus(colorMode = CameraCommands.COLOR_DLOG_M)),
        )
        assertTrue(CaptureLists.isoMarkedLabels(CameraStatus()).isEmpty())
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
        assertTrue(ShutterAngle.labels.contains("180°"))
        assertTrue(ShutterAngle.labels.contains("86.4°"))
        assertTrue(ShutterAngle.labels.contains("172°"))
        assertEquals(180.0, ShutterAngle.parse("180°"))
        assertEquals(5.6, ShutterAngle.parse("5.6°"))
        assertEquals("180°", ShutterAngle.label(180.0))
        assertEquals("5.6°", ShutterAngle.label(5.6))
        assertEquals("11.2°", ShutterAngle.label(11.2))
        assertEquals(48, ShutterAngle.denom(180.0, 24))
        assertEquals(50, ShutterAngle.denom(180.0, 25))
        assertEquals(60, ShutterAngle.denom(180.0, 30))
        assertEquals(120, ShutterAngle.denom(180.0, 60))
        assertEquals(24, ShutterAngle.denom(360.0, 24))
        assertEquals(1_543, ShutterAngle.denom(5.6, 24))
        assertEquals(50, ShutterAngle.denom(180.0, 24, listOf(25, 50, 100)))
        assertEquals(48, ShutterAngle.denom(180.0, 24, emptyList()))
        assertEquals(24, ShutterAngle.effectiveFps(0))
        assertEquals(60, ShutterAngle.effectiveFps(60))
        assertEquals("180°", ShutterAngle.nearestLabel(48, 24))
        assertEquals("172°", ShutterAngle.nearestLabel(50, 24))
        assertEquals("360°", ShutterAngle.nearestLabel(24, 24))
        assertEquals("180°", ShutterAngle.nearestLabel(50, 25))
    }

    @Test
    fun emptyCapListShowsOnlyCurrent() {
        val status = CameraStatus(shutterDenom = 80)
        assertEquals(listOf(80), CaptureLists.shutterDenoms(status))
        assertEquals(listOf("1/80"), CaptureLists.shutterLabels(status))
    }

    @Test
    fun autoExpoWheelIsEvLabelsAndAngleLadder() {
        val auto = CameraStatus(expoMode = CameraCommands.EXPO_AUTO, evComp = 0x10)
        val manual = CameraStatus(expoMode = CameraCommands.EXPO_MANUAL, shutterDenom = 50)
        assertTrue(CaptureLists.isEvSheet(LiveSheet.SHUTTER, auto.expoMode))
        assertTrue(!CaptureLists.isEvSheet(LiveSheet.SHUTTER, manual.expoMode))
        assertEquals("EV", CaptureLists.shutterHeaderTitle(true))
        assertEquals("SHUTTER", CaptureLists.shutterHeaderTitle(false))
        assertEquals("Compensation", CaptureLists.shutterHeaderSubtitle(true, false, false))
        assertEquals("Face priority", CaptureLists.shutterHeaderSubtitle(true, false, true))
        assertEquals("Speed", CaptureLists.shutterHeaderSubtitle(false, false, false))
        assertEquals("Angle", CaptureLists.shutterHeaderSubtitle(false, true, false))
        assertEquals(emptyList(), CaptureLists.shutterModeTabs(true))
        assertEquals(listOf("Speed", "Angle"), CaptureLists.shutterModeTabs(false))
        assertEquals(CaptureLists.evLabels, CaptureLists.shutterWheelOptions(auto, true, false))
        assertEquals(ShutterAngle.labels, CaptureLists.shutterWheelOptions(manual, false, true))
        assertEquals(
            CaptureLists.shutterLabels(manual),
            CaptureLists.shutterWheelOptions(manual, false, false),
        )
        assertEquals(null, CaptureLists.shutterTabAfterExpoChange(CameraCommands.EXPO_AUTO, true))
        assertEquals(1, CaptureLists.shutterTabAfterExpoChange(CameraCommands.EXPO_MANUAL, true))
        assertEquals(0, CaptureLists.shutterTabAfterExpoChange(CameraCommands.EXPO_MANUAL, false))
    }

    @Test
    fun reseatIgnoresLiveShutterDenomTicks() {
        assertTrue(
            !CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.SHUTTER_DENOM, false),
        )
        assertTrue(
            !CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.SHUTTER_DENOM, true),
        )
        assertTrue(
            CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.AVAILABLE_DENOMS, false),
        )
        assertTrue(!CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.AVAILABLE_DENOMS, true))
        assertTrue(CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.FPS, false))
        assertTrue(!CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.FPS, true))
        assertTrue(CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.EXPO_MODE, true))
        assertTrue(CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.EV_COMP, true))
        assertTrue(!CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.EV_COMP, false))
        assertTrue(CaptureLists.shouldReseatShutter(CaptureLists.ShutterReseatKey.FACE_PRIORITY, true))
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

    @Test
    fun applyDrumAngleMapsToNearestLegalDenomAtLiveFps() {
        val status =
            CameraStatus(
                fps = 24,
                shutterDenom = 50,
                expoMode = CameraCommands.EXPO_MANUAL,
                availableShutterDenoms = listOf(25, 50, 100),
            )
        assertEquals(
            CaptureLists.ShutterDrumCommand.SetAngle(180.0, 50),
            CaptureLists.applyShutterDrum("180°", false, true, false, status),
        )
        val empty = status.copy(availableShutterDenoms = emptyList(), shutterDenom = 48)
        assertEquals(
            CaptureLists.ShutterDrumCommand.SetAngle(180.0, 48),
            CaptureLists.applyShutterDrum("180°", false, true, false, empty),
        )
    }

    @Test
    fun applyDrumEvThirdsAndFacePriorityGreysWrites() {
        val auto = CameraStatus(expoMode = CameraCommands.EXPO_AUTO, evComp = 0x10)
        assertEquals(
            CaptureLists.ShutterDrumCommand.SetEv(3),
            CaptureLists.applyShutterDrum("+1.0", true, false, false, auto),
        )
        assertEquals(
            CaptureLists.ShutterDrumCommand.SetEv(-9),
            CaptureLists.applyShutterDrum("${EvComp.MINUS}3.0", true, false, false, auto),
        )
        assertEquals(
            CaptureLists.ShutterDrumCommand.Ignored,
            CaptureLists.applyShutterDrum("+1.0", true, false, true, auto),
        )
        assertEquals("0.0", CaptureLists.reseatEv(auto).selection)
        assertEquals("+0.3", CaptureLists.reseatEv(auto.copy(evComp = 0x11)).selection)
        assertEquals("0.0", CaptureLists.reseatEv(CameraStatus()).selection)
    }

    @Test
    fun reseatAngleKeepsPreferredWhenMappedToLive() {
        val status =
            CameraStatus(
                fps = 24,
                shutterDenom = 50,
                availableShutterDenoms = listOf(25, 50, 100),
            )
        val seat = CaptureLists.reseatShutterAngle(status, 180.0)
        assertEquals("180°", seat.selection)
        assertEquals(180.0, seat.preferredAngle)
        assertTrue(!seat.persistAngle)
    }

    @Test
    fun reseatAngleSnapsWhenLiveDiffersAndPersists() {
        val status =
            CameraStatus(
                fps = 24,
                shutterDenom = 24,
                availableShutterDenoms = listOf(24, 48, 50),
            )
        val seat = CaptureLists.reseatShutterAngle(status, 180.0)
        assertEquals("360°", seat.selection)
        assertEquals(360.0, seat.preferredAngle)
        assertTrue(seat.persistAngle)
        val speed = CaptureLists.reseatShutterSpeed(CameraStatus(shutterDenom = 80))
        assertEquals("1/80", speed.selection)
    }

    @Test
    fun rematchShutterDenomAfterFpsKeepsAngle() {
        assertEquals(
            60,
            CaptureLists.rematchShutterDenomAfterFps(
                usesAngle = true,
                degrees = 180.0,
                previousFps = 24,
                nextFps = 30,
                expoMode = CameraCommands.EXPO_MANUAL,
                currentDenom = 48,
                available = emptyList(),
            ),
        )
        assertEquals(
            null,
            CaptureLists.rematchShutterDenomAfterFps(
                usesAngle = true,
                degrees = 180.0,
                previousFps = 24,
                nextFps = 24,
                expoMode = CameraCommands.EXPO_MANUAL,
                currentDenom = 48,
                available = emptyList(),
            ),
        )
        assertEquals(
            null,
            CaptureLists.rematchShutterDenomAfterFps(
                usesAngle = true,
                degrees = 180.0,
                previousFps = 24,
                nextFps = 30,
                expoMode = CameraCommands.EXPO_AUTO,
                currentDenom = 48,
                available = emptyList(),
            ),
        )
        assertEquals(
            50,
            CaptureLists.rematchShutterDenomAfterFps(
                usesAngle = true,
                degrees = 180.0,
                previousFps = 24,
                nextFps = 25,
                expoMode = CameraCommands.EXPO_MANUAL,
                currentDenom = 48,
                available = listOf(25, 50, 100),
            ),
        )
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
        assertEquals(100, CaptureLists.kelvinValues[1] - CaptureLists.kelvinValues[0])
        assertEquals("2000K", CaptureLists.kelvinLabels.first())
        assertEquals("10000K", CaptureLists.kelvinLabels.last())
        assertEquals("5600K", CaptureLists.kelvinLabels[CaptureLists.kelvinValues.indexOf(5600)])
        assertEquals(3200, CaptureLists.kelvinFromLabel("3200K"))
        assertEquals(10000, CaptureLists.kelvinFromLabel("10000K"))
    }

    @Test
    fun wbSheetTabsModeKelvinTint() {
        assertEquals(listOf("Mode", "Kelvin", "Tint"), CaptureLists.wbTabs)
        assertEquals("Kelvin / auto / tint", LiveSheet.WB.subtitle)
        assertEquals(listOf("Auto", "Custom"), CaptureLists.wbModeRows)
        assertEquals(
            CaptureLists.WB_TAB_MODE,
            CaptureLists.wbInitialTab(CameraStatus(wbMode = CameraCommands.WB_AUTO)),
        )
        assertEquals(
            CaptureLists.WB_TAB_MODE,
            CaptureLists.wbInitialTab(CameraStatus()),
        )
        assertEquals(
            CaptureLists.WB_TAB_KELVIN,
            CaptureLists.wbInitialTab(
                CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 3200),
            ),
        )
        assertEquals("Auto", CaptureLists.wbModeRowSelected(CameraStatus()))
        assertEquals(
            "Custom",
            CaptureLists.wbModeRowSelected(CameraStatus(wbMode = CameraCommands.WB_CUSTOM)),
        )
        assertTrue(CaptureLists.wbSendsAuto("Auto"))
        assertTrue(!CaptureLists.wbSendsAuto("Custom"))
        assertEquals(
            listOf("Mode", "Kelvin", "Tint"),
            CaptureLists.modeTabs(LiveSheet.WB, CameraCommands.EXPO_MANUAL, false),
        )
    }

    @Test
    fun wbCustomRowSendsCurrentKelvinAndTint() {
        val custom =
            CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 3200, wbTint = -20)
        assertEquals(3200 to -20, CaptureLists.wbCustomFromStatus(custom))
        val autoCleared =
            CameraStatus(wbMode = CameraCommands.WB_AUTO, wbKelvin = -1, wbTint = 0)
        assertEquals(5600 to 0, CaptureLists.wbCustomFromStatus(autoCleared))
        val unknownKelvin = CameraStatus(wbMode = CameraCommands.WB_AUTO, wbKelvin = 0, wbTint = 7)
        assertEquals(5600, CaptureLists.currentKelvin(unknownKelvin))
        assertEquals(7, CaptureLists.currentTint(unknownKelvin))
        assertEquals("5600K", CaptureLists.wbDrumSelection(autoCleared))
        assertEquals("3200K", CaptureLists.wbDrumSelection(custom))
        val autoKeepsLast =
            CameraStatus(wbMode = CameraCommands.WB_AUTO, wbKelvin = 4200, wbTint = 20)
        assertEquals(4200 to 20, CaptureLists.wbCustomFromStatus(autoKeepsLast))
        assertEquals("4200K", CaptureLists.wbDrumSelection(autoKeepsLast))
    }

    @Test
    fun wbKelvinDrumAppliesOnlyOnKelvinTab() {
        val status = CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 5600, wbTint = 12)
        assertEquals(null, CaptureLists.wbKelvinDrumApply(CaptureLists.WB_TAB_MODE, "3200K", status))
        assertEquals(null, CaptureLists.wbKelvinDrumApply(CaptureLists.WB_TAB_TINT, "3200K", status))
        assertEquals(3200 to 12, CaptureLists.wbKelvinDrumApply(CaptureLists.WB_TAB_KELVIN, "3200K", status))
        assertEquals(10000 to 12, CaptureLists.wbKelvinDrumApply(CaptureLists.WB_TAB_KELVIN, "10000K", status))
        assertEquals(null, CaptureLists.wbKelvinDrumApply(CaptureLists.WB_TAB_KELVIN, "nope", status))
    }

    @Test
    fun wbTintPadIsMinus100To100WithNudgesAndNeutral() {
        assertEquals("Neutral", CaptureLists.tintLabel(0))
        assertEquals("+10", CaptureLists.tintLabel(10))
        assertEquals("-5", CaptureLists.tintLabel(-5))
        assertEquals("Apply tint 0", CaptureLists.tintApplyLabel(0))
        assertEquals("Apply tint 25", CaptureLists.tintApplyLabel(25))
        assertEquals(-100f, CaptureLists.nudgeTint(-95f, -10))
        assertEquals(100f, CaptureLists.nudgeTint(95f, 10))
        assertEquals(5f, CaptureLists.nudgeTint(-5f, 10))
        assertEquals(-100, CaptureLists.roundedTint(-100.4f))
        assertEquals(100, CaptureLists.roundedTint(100.6f))
        val status = CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 5600, wbTint = 0)
        assertEquals(5600 to -10, CaptureLists.wbCustomFromTint(-10f, status))
        assertEquals(5600 to 100, CaptureLists.wbCustomFromTint(140f, status))
        assertTrue(
            !CaptureLists.wbTintStaysAuto(
                CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 5600),
            ),
        )
        assertTrue(CaptureLists.wbTintStaysAuto(CameraStatus(wbMode = CameraCommands.WB_AUTO)))
        assertTrue(CaptureLists.wbTintStaysAuto(CameraStatus()))
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
        assertEquals(CaptureLists.FOCUS_TAB_SINGLE, "AF-S")
        assertEquals(CaptureLists.FOCUS_TAB_CONTINUOUS, "AF-C")
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
        assertEquals("AF-C", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 0)?.chip)
        assertEquals("Showcase", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 1)?.chip)
        assertEquals("Lock", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 2)?.chip)
        assertEquals("Priority", FocusOption.resolve(CameraCommands.FOCUS_CONTINUOUS, 3)?.chip)
        assertEquals(
            "Showcase",
            CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = 1).focusLabel,
        )
        assertEquals("AF-S", CameraStatus(focusMode = CameraCommands.FOCUS_SINGLE, focusTrack = 2).focusLabel)
        assertEquals("AF-C", CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = -1).focusLabel)
        assertEquals("—", CameraStatus().focusLabel)

        val afs = CameraStatus(focusMode = CameraCommands.FOCUS_SINGLE, focusTrack = -1)
        val afc = CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = -1)
        val lock = CameraStatus(focusMode = CameraCommands.FOCUS_CONTINUOUS, focusTrack = 2)
        assertTrue(!CaptureLists.focusIsContinuous(afs))
        assertTrue(!CaptureLists.focusShowsTrackChips(afs))
        assertTrue(CaptureLists.focusIsContinuous(afc))
        assertTrue(CaptureLists.focusShowsTrackChips(afc))
        assertEquals(FocusTrackMode.DEFAULT.raw, CaptureLists.selectedFocusTrack(afc))
        assertEquals(FocusTrackMode.SUBJECT_LOCK.raw, CaptureLists.selectedFocusTrack(lock))
        assertTrue(CaptureLists.shouldRefreshFocusTrack(afc, supportsFocus = true))
        assertTrue(!CaptureLists.shouldRefreshFocusTrack(lock, supportsFocus = true))
        assertTrue(!CaptureLists.shouldRefreshFocusTrack(afc, supportsFocus = false))
    }

    @Test
    fun nanoHasNoFocusMode() {
        assertTrue(!CaptureLists.supportsFocusMode("Osmo Nano"))
        assertTrue(!CaptureLists.supportsFocusMode("OsmoNano-ABCD"))
        assertTrue(CaptureLists.supportsFocusMode("Osmo Pocket 4 Pro"))
        assertTrue(CaptureLists.supportsFocusMode(null))
        assertTrue(
            !CaptureLists.supportsFocusMode(
                CameraModel(name = "Osmo Nano", family = "nano", supportsFocusMode = false),
            ),
        )
        assertTrue(
            !CaptureLists.supportsFocusMode(
                CameraModel(name = "Osmo", family = "nano", supportsFocusMode = true),
            ),
        )
        assertTrue(
            !CaptureLists.supportsFocusMode(
                CameraModel(name = "Osmo Nano", family = "pocket", supportsFocusMode = true),
            ),
        )
        assertTrue(
            CaptureLists.supportsFocusMode(
                CameraModel(name = "Osmo Pocket 4 Pro", family = "pocket", supportsFocusMode = true),
            ),
        )
        assertTrue(CaptureLists.supportsFocusModeOrDefault(null))
        assertTrue(
            !CaptureLists.supportsFocusModeOrDefault(
                CameraModel(name = "Osmo Nano", family = "nano", supportsFocusMode = false),
            ),
        )
        assertTrue(
            !CaptureLists.shouldRefreshFocusTrack(
                CameraStatus(focusTrack = -1),
                supportsFocus = CaptureLists.supportsFocusMode("Osmo Nano"),
            ),
        )
    }

    @Test
    fun fpsDrumAndColorWheelMatchIos() {
        assertEquals(listOf("24p", "25p", "30p", "48p", "50p", "60p"), CaptureLists.fpsDrumLabels)
        assertEquals(listOf("1080", "4K"), CaptureLists.resolutionTabTitles)
        assertEquals(listOf("1080p", "4K"), VideoResolution.entries.map { it.label })
        assertEquals(listOf(24, 25, 30, 48, 50, 60), VideoFrameRate.entries.map { it.fps })
        assertEquals(1, CaptureLists.fpsIndexFromDrum("24p"))
        assertEquals(6, CaptureLists.fpsIndexFromDrum("60p"))
        assertEquals(VideoFrameRate.FPS48, VideoFrameRate.fromDrumLabel("48p"))
        assertNull(VideoFrameRate.fromDrumLabel("120p"))
        assertNull(CaptureLists.fpsIndexFromDrum("120p"))
        assertTrue(!CaptureLists.resolutionTabTitles.contains("2.7K"))
        assertTrue(!CaptureLists.fpsDrumLabels.contains("120p"))
        assertEquals(
            listOf("Normal", "HDR", "D-Log"),
            CaptureLists.colorWheelLabels(CameraStatus()),
        )
        assertEquals(
            listOf("Normal", "HDR", "D-Log", "D-Log2"),
            CaptureLists.colorWheelLabels(
                CameraStatus(),
                family = "pocket",
                name = "Osmo Pocket 4 Pro",
            ),
        )
        assertEquals(
            listOf("Normal", "HDR", "D-Log M"),
            CaptureLists.colorWheelLabels(
                CameraStatus(),
                family = "pocket",
                name = "Osmo Pocket 3",
            ),
        )
        assertEquals(
            listOf("Normal", "HDR", "D-Log"),
            CaptureLists.colorWheelLabels(
                CameraStatus(),
                family = "pocket",
                name = "Osmo Pocket 4",
            ),
        )
        assertEquals(CameraCommands.COLOR_DLOG2, CaptureLists.colorModeFromLabel("D-Log2"))
        assertEquals(CameraCommands.COLOR_DLOG_M, CaptureLists.colorModeFromLabel("D-Log M"))
        assertEquals(
            listOf("Normal", "HDR", "D-Log", "D-Log2"),
            CaptureLists.colorWheel(
                "pocket",
                listOf(
                    CameraCommands.COLOR_DLOG2,
                    CameraCommands.COLOR_DLOG,
                    CameraCommands.COLOR_HDR,
                    CameraCommands.COLOR_NORMAL,
                ),
                "Osmo Pocket 4 Pro",
            ).map { it.second },
        )
        assertTrue(
            CaptureLists.colorWheel(
                "pocket",
                listOf(
                    CameraCommands.COLOR_DLOG2,
                    CameraCommands.COLOR_DLOG,
                    CameraCommands.COLOR_HDR,
                    CameraCommands.COLOR_NORMAL,
                ),
                "Osmo Pocket 3",
            ).none { it.first == CameraCommands.COLOR_DLOG2 },
        )
        assertTrue(
            CaptureLists.colorWheel(
                "pocket",
                listOf(
                    CameraCommands.COLOR_DLOG2,
                    CameraCommands.COLOR_DLOG,
                    CameraCommands.COLOR_HDR,
                    CameraCommands.COLOR_NORMAL,
                ),
                "Osmo Pocket 4",
            ).none { it.first == CameraCommands.COLOR_DLOG2 },
        )
        assertNull(CaptureLists.colorModeFromLabel("N-Log"))
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
        assertEquals(
            listOf("Normal 8-bit", "Normal 10-bit", "D-Log M 10-bit"),
            CaptureLists.colorWheel(
                "nano",
                listOf(
                    CameraCommands.COLOR_DLOG_M,
                    CameraCommands.COLOR_NORMAL,
                    CameraCommands.COLOR_NORMAL10,
                ),
            ).map { it.second },
        )
        assertEquals(
            listOf("Normal 8-bit", "Normal 10-bit", "D-Log M 10-bit"),
            CaptureLists.colorWheelLabels(
                CameraStatus(
                    availableColorModes =
                        listOf(
                            CameraCommands.COLOR_DLOG_M,
                            CameraCommands.COLOR_NORMAL,
                            CameraCommands.COLOR_NORMAL10,
                        ),
                ),
                family = "nano",
            ),
        )
        assertTrue(
            CaptureLists.colorWheel("pocket", listOf(CameraCommands.COLOR_NORMAL, 0x99))
                .none { it.first == 0x99 },
        )
    }

    @Test
    fun expoModeSheetIsAutoManualOnly() {
        assertEquals("MODE", LiveSheet.EXPO.headerLabel)
        assertEquals("Exposure", LiveSheet.EXPO.subtitle)
        assertEquals(listOf("Auto", "Manual"), CaptureLists.expoLabels)
        assertEquals("Auto", CameraStatus(expoMode = CameraCommands.EXPO_AUTO).expoLabel)
        assertEquals("Manual", CameraStatus(expoMode = CameraCommands.EXPO_MANUAL).expoLabel)
        assertEquals("Auto", CaptureLists.expoSelectedLabel(CameraCommands.EXPO_AUTO))
        assertEquals("Manual", CaptureLists.expoSelectedLabel(CameraCommands.EXPO_MANUAL))
        assertEquals(null, CaptureLists.expoSelectedLabel(-1))
        assertEquals(CameraCommands.EXPO_AUTO, CaptureLists.expoModeFromLabel("Auto"))
        assertEquals(CameraCommands.EXPO_MANUAL, CaptureLists.expoModeFromLabel("Manual"))
        assertEquals(null, CaptureLists.expoModeFromLabel("Video"))
        assertEquals(null, CaptureLists.expoModeFromLabel("Photo"))
        assertTrue(LiveSheet.entries.none { it.subtitle == "Shooting mode" })
        assertEquals(
            setOf("ISO", "SHUTTER", "WB", "FOCUS", "EXPO", "AUDIO", "COLOR", "FORMAT"),
            LiveSheet.entries.map { it.name }.toSet(),
        )
    }

    @Test
    fun audioSheetMatchesIosChannelWindDirVocal() {
        assertEquals("AUDIO", LiveSheet.AUDIO.headerLabel)
        assertEquals("Channel · wind · direction · vocal", LiveSheet.AUDIO.subtitle)
        assertEquals(listOf("Channel", "Wind", "Dir", "Vocal"), CaptureLists.audioTabs)
        assertEquals(
            CaptureLists.audioTabs,
            CaptureLists.modeTabs(LiveSheet.AUDIO, CameraCommands.EXPO_MANUAL, false),
        )
        assertEquals(0, CaptureLists.audioInitialTab())
        assertTrue(CaptureLists.shouldRefreshAudio(LiveSheet.AUDIO))
        assertTrue(!CaptureLists.shouldRefreshAudio(LiveSheet.EXPO))

        assertEquals(listOf("Stereo", "Mono", "Spatial"), CaptureLists.audioChannelLabels)
        assertEquals("Stereo", CaptureLists.audioChannelLabel(CameraCommands.AUDIO_STEREO))
        assertEquals("Mono", CaptureLists.audioChannelLabel(CameraCommands.AUDIO_MONO))
        assertEquals("Spatial", CaptureLists.audioChannelLabel(CameraCommands.AUDIO_SPATIAL))
        assertEquals(null, CaptureLists.audioChannelLabel(-1))
        assertEquals(CameraCommands.AUDIO_STEREO, CaptureLists.audioChannelValue("Stereo"))
        assertEquals(CameraCommands.AUDIO_MONO, CaptureLists.audioChannelValue("Mono"))
        assertEquals(CameraCommands.AUDIO_SPATIAL, CaptureLists.audioChannelValue("Spatial"))
        assertEquals(null, CaptureLists.audioChannelValue("Surround"))

        assertEquals(listOf("Off", "On"), CaptureLists.audioWindLabels)
        assertEquals("Off", CaptureLists.audioWindLabel(0))
        assertEquals("On", CaptureLists.audioWindLabel(1))
        assertEquals(null, CaptureLists.audioWindLabel(-1))

        assertEquals(listOf("All", "Front", "Front+back"), CaptureLists.audioDirLabels)
        assertEquals("All", CaptureLists.audioDirLabel(0))
        assertEquals("Front", CaptureLists.audioDirLabel(1))
        assertEquals("Front+back", CaptureLists.audioDirLabel(2))
        assertEquals(0, CaptureLists.audioDirValue("All"))
        assertEquals(1, CaptureLists.audioDirValue("Front"))
        assertEquals(2, CaptureLists.audioDirValue("Front+back"))
        assertEquals(null, CaptureLists.audioDirValue("Rear"))

        assertEquals(listOf("Off", "On"), CaptureLists.audioVocalLabels)
        assertEquals("Off", CaptureLists.audioVocalLabel(0))
        assertEquals("On", CaptureLists.audioVocalLabel(1))
        assertEquals(null, CaptureLists.audioVocalLabel(-1))

        assertEquals("Spatial", CameraStatus(audioChannel = CameraCommands.AUDIO_SPATIAL).audioLabel)
        assertEquals("Stereo", CameraStatus(audioChannel = CameraCommands.AUDIO_STEREO).audioLabel)
        assertEquals("Mono", CameraStatus(audioChannel = CameraCommands.AUDIO_MONO).audioLabel)
        assertEquals("—", CameraStatus().audioLabel)
    }

    @Test
    fun autoExpoTurnsShutterSheetIntoEv() {
        assertTrue(CaptureLists.isEvSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO))
        assertTrue(!CaptureLists.isEvSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL))
        assertTrue(!CaptureLists.isEvSheet(LiveSheet.SHUTTER, -1))
        assertTrue(!CaptureLists.isEvSheet(LiveSheet.EXPO, CameraCommands.EXPO_AUTO))
        assertEquals("EV", CaptureLists.headerTitle(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO))
        assertEquals("Compensation", CaptureLists.headerSubtitle(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO, 0, false))
        assertEquals(
            "Face priority",
            CaptureLists.headerSubtitle(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO, 0, true),
        )
        assertEquals(emptyList(), CaptureLists.modeTabs(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO, true))
        assertEquals(null, CaptureLists.shutterTabAfterExpoChange(CameraCommands.EXPO_AUTO, true))
        assertEquals("MODE", CaptureLists.headerTitle(LiveSheet.EXPO, CameraCommands.EXPO_AUTO))
        assertEquals("Exposure", CaptureLists.headerSubtitle(LiveSheet.EXPO, CameraCommands.EXPO_AUTO, 0, false))
        assertEquals(emptyList(), CaptureLists.modeTabs(LiveSheet.EXPO, CameraCommands.EXPO_AUTO, true))
    }

    @Test
    fun manualExpoRestoresShutterSpeedOrAngle() {
        assertEquals("SHUTTER", CaptureLists.headerTitle(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL))
        assertEquals("Speed", CaptureLists.headerSubtitle(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, 0, false))
        assertEquals("Angle", CaptureLists.headerSubtitle(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, 1, false))
        assertEquals(
            listOf("Speed", "Angle"),
            CaptureLists.modeTabs(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, true),
        )
        assertEquals(0, CaptureLists.shutterTabAfterExpoChange(CameraCommands.EXPO_MANUAL, false))
        assertEquals(1, CaptureLists.shutterTabAfterExpoChange(CameraCommands.EXPO_MANUAL, true))
        assertTrue(!CaptureLists.isAngleSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_AUTO, 1))
        assertTrue(CaptureLists.isAngleSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, 1))
        assertTrue(!CaptureLists.isAngleSheet(LiveSheet.SHUTTER, CameraCommands.EXPO_MANUAL, 0))
    }

    @Test
    fun expoModeCommandsMatchIosBytes() {
        assertTrue(CameraCommands.expoMode(CameraCommands.EXPO_AUTO).contentEquals(byteArrayOf(0x01, 0x00)))
        assertTrue(CameraCommands.expoMode(CameraCommands.EXPO_MANUAL).contentEquals(byteArrayOf(0x04, 0x00)))
        assertTrue(CameraCommands.expoMode(manual = false).contentEquals(byteArrayOf(0x01, 0x00)))
        assertTrue(CameraCommands.expoMode(manual = true).contentEquals(byteArrayOf(0x04, 0x00)))
        assertEquals("auto", CameraCommands.expoWireExtra(CameraCommands.EXPO_AUTO))
        assertEquals("manual", CameraCommands.expoWireExtra(CameraCommands.EXPO_MANUAL))
        assertEquals(null, CameraCommands.expoWireExtra(-1))
        assertTrue(CameraCommands.expoMode(-1).isEmpty())
        assertEquals(0x021E, SwiftCore.waitKey(SwiftCore.CMD_SET_EXPO_MODE))
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
        assertNull(
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG2,
                to = CameraCommands.COLOR_NORMAL,
                currentIndex = 0x07,
                hopEnabled = true,
            ),
        )
        assertNull(
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_NORMAL,
                to = CameraCommands.COLOR_DLOG2,
                currentIndex = 0x03,
                hopEnabled = true,
            ),
        )
        assertNull(
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG2,
                to = CameraCommands.COLOR_DLOG2,
                currentIndex = 0x07,
                hopEnabled = true,
            ),
        )
        assertNull(
            CaptureLists.nativeIsoHop(
                from = -1,
                to = CameraCommands.COLOR_DLOG,
                currentIndex = 0x07,
                hopEnabled = true,
            ),
        )
        assertEquals(
            0x05,
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG2,
                to = CameraCommands.COLOR_DLOG,
                currentIndex = 0x07,
                hopEnabled = true,
            ),
        )
        assertNull(
            CaptureLists.nativeIsoHop(
                from = CameraCommands.COLOR_DLOG_M,
                to = CameraCommands.COLOR_DLOG2,
                currentIndex = 0x05,
                hopEnabled = true,
            ),
        )
    }

    @Test
    fun colorDrumHopsNativeIsoAfterColorSetAndRejectsOffFamily() {
        val pro = "Osmo Pocket 4 Pro"
        val dlog2Native =
            CameraStatus(colorMode = CameraCommands.COLOR_DLOG2, isoIndex = 0x07)
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG, 0x05),
            CaptureLists.applyColorDrum("D-Log", "pocket", dlog2Native, hopEnabled = true, name = pro),
        )
        val dlogNative = CameraStatus(colorMode = CameraCommands.COLOR_DLOG, isoIndex = 0x05)
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG2, 0x07),
            CaptureLists.applyColorDrum("D-Log2", "pocket", dlogNative, hopEnabled = true, name = pro),
        )
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG, null),
            CaptureLists.applyColorDrum(
                "D-Log",
                "pocket",
                CameraStatus(colorMode = CameraCommands.COLOR_DLOG2, isoIndex = 0x06),
                hopEnabled = true,
                name = pro,
            ),
        )
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG2, null),
            CaptureLists.applyColorDrum(
                "D-Log2", "pocket", dlogNative, hopEnabled = false, name = pro,
            ),
        )
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG, null),
            CaptureLists.applyColorDrum(
                "D-Log",
                "pocket",
                CameraStatus(colorMode = CameraCommands.COLOR_DLOG2, isoIndex = 0),
                hopEnabled = true,
                name = pro,
            ),
        )
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_NORMAL, null),
            CaptureLists.applyColorDrum(
                "Normal", "pocket", dlog2Native, hopEnabled = true, name = pro,
            ),
        )
        assertNull(CaptureLists.applyColorDrum("D-Log2", "nano", CameraStatus(), hopEnabled = true))
        assertNull(CaptureLists.applyColorDrum("D-Log2", "pocket", CameraStatus(), hopEnabled = true))
        assertNull(
            CaptureLists.applyColorDrum(
                "D-Log2", "pocket", CameraStatus(), hopEnabled = true, name = "Osmo Pocket 4",
            ),
        )
        assertNull(
            CaptureLists.applyColorDrum(
                "D-Log2", "pocket", CameraStatus(), hopEnabled = true, name = "Osmo Pocket 3",
            ),
        )
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG_M, null),
            CaptureLists.applyColorDrum(
                "D-Log M", "pocket", CameraStatus(), hopEnabled = true, name = "Osmo Pocket 3",
            ),
        )
        assertNull(CaptureLists.applyColorDrum("N-Log", "pocket", CameraStatus(), hopEnabled = true))
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_NORMAL, null),
            CaptureLists.applyColorDrum("Normal 8-bit", "nano", CameraStatus(), hopEnabled = true),
        )
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_DLOG_M, null),
            CaptureLists.applyColorDrum("D-Log M 10-bit", "nano", CameraStatus(), hopEnabled = true),
        )
        val pocketCap =
            CameraStatus(
                availableColorModes = listOf(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_HDR),
            )
        assertNull(CaptureLists.applyColorDrum("D-Log2", "pocket", pocketCap, hopEnabled = true))
        assertEquals(
            ColorDrumCommand(CameraCommands.COLOR_HDR, null),
            CaptureLists.applyColorDrum("HDR", "pocket", pocketCap, hopEnabled = true),
        )
        val nanoWithDLog =
            CameraStatus(
                availableColorModes =
                    listOf(CameraCommands.COLOR_NORMAL, CameraCommands.COLOR_DLOG),
            )
        assertNull(CaptureLists.applyColorDrum("D-Log", "nano", nanoWithDLog, hopEnabled = true))
    }

    @Test
    fun isoDrumFallsBackToColorTableAndKeepsAutoOnlyCap() {
        val dlog2 = CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)
        assertEquals(
            listOf("100", "200", "400", "800", "1600", "3200"),
            CaptureLists.isoDrumLabels(dlog2),
        )
        assertTrue(!CaptureLists.isoDrumLabels(dlog2).contains("Auto"))
        val dlog = CameraStatus(colorMode = CameraCommands.COLOR_DLOG)
        assertEquals(listOf("400", "800", "1600", "3200", "6400"), CaptureLists.isoDrumLabels(dlog))
        assertTrue(CaptureLists.isoFallback(CameraCommands.COLOR_DLOG).contains(0))
        val autoOnly =
            CameraStatus(colorMode = CameraCommands.COLOR_DLOG, availableIsoIndices = listOf(0))
        assertEquals(listOf(0), CaptureLists.isoIndices(autoOnly))
        assertTrue(CaptureLists.isoDrumLabels(autoOnly).isEmpty())
        assertEquals(
            0,
            CaptureLists.isoIndexFromLabel("Auto"),
        )
        assertEquals(0x07, CaptureLists.isoIndexFromLabel("1600"))
        assertEquals(1600, CameraCommands.isoValue(0x07))
        assertEquals(null, CameraCommands.isoValue(0))
    }

    @Test
    fun isoSheetSendsIndexNotNumberAndAutoIsZero() {
        val dash = "\u2013"
        val dlog =
            CameraStatus(
                colorMode = CameraCommands.COLOR_DLOG,
                isoIndex = 0x05,
                iso = 400,
                availableIsoIndices = listOf(0, 0x05, 0x06, 0x07, 0x08, 0x09),
            )
        assertEquals(
            IsoSheetLogic.Command.SetIndex(0x07),
            IsoSheetLogic.applyDrum("1600", dlog, selectedMode = 1),
        )
        assertEquals(null, IsoSheetLogic.applyDrum("Auto", dlog, selectedMode = 1))
        val auto =
            CameraStatus(
                colorMode = CameraCommands.COLOR_DLOG,
                isoIndex = 0,
                isoLimit = 0x05,
            )
        assertEquals(
            IsoSheetLogic.Command.SetLimit(0x05),
            IsoSheetLogic.applyDrum("400${dash}1600", auto, selectedMode = 0),
        )
        val (autoTab, autoCmd) = IsoSheetLogic.handleModeChange(0, dlog)
        assertEquals(0, autoTab.selectedMode)
        assertEquals(IsoSheetLogic.Command.SetIndex(0), autoCmd)
        val (manualTab, manualCmd) = IsoSheetLogic.handleModeChange(1, auto.copy(iso = 400))
        assertEquals(1, manualTab.selectedMode)
        assertEquals(IsoSheetLogic.Command.SetIndex(0x05), manualCmd)
        val dlog2 = CameraStatus(colorMode = CameraCommands.COLOR_DLOG2, isoIndex = 0x07, iso = 1600)
        assertEquals(0, IsoSheetLogic.reseat(dlog2).selectedMode)
        assertEquals("1600", IsoSheetLogic.reseat(dlog2).drumSelection)
        assertTrue(!CaptureLists.offersIsoAuto(dlog2))
    }

    @Test
    fun isoSheetReseatsOnlyOnCamcapAndColorNotLiveIndex() {
        val base =
            CameraStatus(
                colorMode = CameraCommands.COLOR_DLOG,
                isoIndex = 0x05,
                availableIsoIndices = listOf(0, 0x05, 0x06, 0x07),
            )
        assertTrue(
            !IsoSheetLogic.shouldReseat(base, base.copy(isoIndex = 0, iso = 800)),
            "live isoIndex ticks must not reseat the drum",
        )
        assertTrue(!IsoSheetLogic.shouldReseat(base, base.copy(iso = 1600, isoLimit = 0x07)))
        assertTrue(IsoSheetLogic.shouldReseat(base, base.copy(colorMode = CameraCommands.COLOR_DLOG2)))
        assertTrue(
            IsoSheetLogic.shouldReseat(
                base,
                base.copy(availableIsoIndices = listOf(0x03, 0x04, 0x05, 0x06, 0x07, 0x08)),
            ),
        )
        val autoSeat = IsoSheetLogic.reseat(base.copy(isoIndex = 0, isoLimit = 0x05))
        assertEquals(0, autoSeat.selectedMode)
        val dash = "\u2013"
        assertEquals("400${dash}1600", autoSeat.drumSelection)
        assertTrue(CaptureLists.shouldGetIsoLimit(CameraStatus(colorMode = -1)))
        assertTrue(!CaptureLists.shouldGetIsoLimit(CameraStatus(colorMode = CameraCommands.COLOR_DLOG2)))
        assertTrue(CameraCommands.shouldGetIsoLimit(-1))
        assertTrue(!CameraCommands.shouldGetIsoLimit(CameraCommands.COLOR_DLOG2))
        assertTrue(!CameraCommands.isoIndex(0).contentEquals(byteArrayOf(0x07)))
        assertEquals(0x00, CameraCommands.isoIndex(0)[0].toInt() and 0xFF)
        assertEquals(1, CameraCommands.isoIndex(0).size)
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
            "4K · 25p",
            CaptureLists.recFormatChipLabel(
                CameraStatus(resolutionCode = CameraCommands.RES_4K, fpsIndex = 2),
            ),
        )
        assertEquals(
            "1080p · 24p",
            CaptureLists.recFormatChipLabel(
                CameraStatus(resolutionCode = CameraCommands.RES_1080, fps = 24),
            ),
        )
        assertEquals(
            "4K · 25p",
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25).chipLabel,
        )
        assertEquals(
            "1080p · 24p",
            VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS24).chipLabel,
        )
        assertEquals("— · —", CaptureLists.recFormatChipLabel(CameraStatus()))
        assertEquals(
            "4K · 120p",
            CaptureLists.recFormatChipLabel(
                CameraStatus(resolutionCode = CameraCommands.RES_4K, fps = 120, fpsIndex = 7),
            ),
        )
        assertEquals(
            "24p",
            CaptureLists.fpsDrumLabel(
                CameraStatus(resolutionCode = CameraCommands.RES_4K, fps = 120, fpsIndex = 7),
            ),
        )
    }

    @Test
    fun formatPickerTabsAndDrumMatchIos() {
        val live =
            CameraStatus(
                fps = 24,
                resolutionCode = CameraCommands.RES_1080,
                fpsIndex = 1,
            )
        assertEquals(VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS24), VideoFormat.current(live))
        assertEquals(
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS24),
            VideoFormat.nextForTab(live, tab = 1, drum = "24p"),
        )
        assertNull(VideoFormat.nextForTab(live, tab = 0, drum = "24p"))
        assertEquals(
            VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS60),
            VideoFormat.nextForDrum(live, tab = 0, drum = "60p"),
        )
        assertNull(VideoFormat.nextForDrum(live, tab = 0, drum = "120p"))
        val boot = VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25)
        assertEquals(
            VideoFormat(VideoResolution.P1080, VideoFrameRate.FPS25),
            VideoFormat.firstPictureEncoderKick(boot),
        )
        assertEquals(
            boot,
            VideoFormat.firstPictureOriginal(
                CameraStatus(
                    fps = 25,
                    resolutionCode = CameraCommands.RES_4K,
                    fpsIndex = 2,
                ),
            ),
        )
        assertEquals(
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS30),
            VideoFormat.firstPictureOriginal(CameraStatus()),
            "unknown falls back to 4K 30, not 1080 24",
        )
        assertEquals(VideoResolution.P4K, VideoResolution.fromTabIndex(1))
        assertEquals(VideoResolution.P1080, VideoResolution.fromTabIndex(0))
        assertEquals(
            listOf("1080", "4K"),
            CaptureLists.modeTabs(LiveSheet.FORMAT, expoMode = -1, offersIsoAuto = false),
        )
        val fourKOnly =
            live.copy(
                resolutionCode = CameraCommands.RES_4K,
                fpsIndex = 1,
                fps = 24,
                availableVideoFormats =
                    listOf(
                        VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS24),
                        VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25),
                    ),
            )
        assertEquals(
            listOf("4K"),
            CaptureLists.modeTabs(LiveSheet.FORMAT, fourKOnly, offersIsoAuto = false),
        )
        assertEquals(
            listOf("24p", "25p"),
            CaptureLists.fpsDrumLabels(fourKOnly, tab = 0),
        )
        assertEquals(
            VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS25),
            CaptureLists.nextVideoFormat(fourKOnly, tab = 0, drum = "25p", fromDrum = true),
        )
        assertNull(
            CaptureLists.nextVideoFormat(fourKOnly, tab = 0, drum = "60p", fromDrum = true),
        )
    }

    @Test
    fun formatChangeRewritesShutterAngleLikeIos() {
        assertEquals(
            50,
            CaptureLists.shutterDenomAfterFormatChange(
                previousFps = 24,
                nextFps = 25,
                expoMode = CameraCommands.EXPO_MANUAL,
                shutterUsesAngle = true,
                angleDegrees = 180.0,
                currentDenom = 48,
                available = listOf(25, 50, 100),
            ),
        )
        assertNull(
            CaptureLists.shutterDenomAfterFormatChange(
                previousFps = 24,
                nextFps = 25,
                expoMode = CameraCommands.EXPO_MANUAL,
                shutterUsesAngle = false,
                angleDegrees = 180.0,
                currentDenom = 48,
                available = listOf(25, 50, 100),
            ),
        )
        assertNull(
            CaptureLists.shutterDenomAfterFormatChange(
                previousFps = 24,
                nextFps = 25,
                expoMode = CameraCommands.EXPO_AUTO,
                shutterUsesAngle = true,
                angleDegrees = 180.0,
                currentDenom = 48,
                available = listOf(25, 50, 100),
            ),
        )
        assertNull(
            CaptureLists.shutterDenomAfterFormatChange(
                previousFps = 24,
                nextFps = 24,
                expoMode = CameraCommands.EXPO_MANUAL,
                shutterUsesAngle = true,
                angleDegrees = 180.0,
                currentDenom = 48,
                available = listOf(25, 50, 100),
            ),
        )
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
        assertEquals("10000K", CaptureLists.wbChipWidest())
        assertEquals("Auto", CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_AUTO)))
        assertEquals(
            "5600K",
            CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 5600)),
        )
        assertEquals(
            "10000K",
            CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_CUSTOM, wbKelvin = 10_000)),
        )
        assertEquals("Custom", CaptureLists.wbChipValue(CameraStatus(wbMode = CameraCommands.WB_CUSTOM)))
        assertEquals("—", CaptureLists.wbChipValue(CameraStatus()))
        assertTrue(CaptureLists.wbIsAuto(CameraStatus(wbMode = CameraCommands.WB_AUTO)))
        assertTrue(CaptureLists.wbIsAuto(CameraStatus()))
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
