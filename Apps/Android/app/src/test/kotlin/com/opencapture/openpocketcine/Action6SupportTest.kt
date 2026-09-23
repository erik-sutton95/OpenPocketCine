package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.session.ApertureStrategy
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.DatalinkDriver
import com.opencapture.openpocketcine.session.StatusExtras
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

/** Osmo Action 6 parity with the core (handbook `devices/action-6/`). */
class Action6SupportTest {
    private val action6 = "Osmo Action 6"

    private fun bytes(vararg v: Int) = ByteArray(v.size) { v[it].toByte() }

    @Test fun modelJsonDefaultsFollowTheBody() {
        val a6 = CameraModel.fromJson("""{"name":"$action6","family":"other"}""")
        assertFalse(a6.sendsLiveViewPrepare)
        assertTrue(a6.supportsAperture)
        val pocket = CameraModel.fromJson("""{"name":"Osmo Pocket 4"}""")
        assertTrue(pocket.sendsLiveViewPrepare)
        assertFalse(pocket.supportsAperture)
        val nano = CameraModel.fromJson("""{"name":"Osmo Nano","family":"nano","usesNanoLiveViewGate":true}""")
        assertFalse(nano.sendsLiveViewPrepare)
        // Facade keys win over the name fallback.
        val wire = CameraModel.fromJson(
            """{"name":"$action6","liveViewEnableReceiver":65,"sendsLiveViewPrepare":false,"supportsAperture":true,"supportsFocusMode":false,"supportsTapFocus":false}""",
        )
        assertEquals(0x41, wire.liveViewEnableReceiver)
        assertFalse(wire.supportsFocusMode)
        assertFalse(CaptureLists.supportsFocusModeOrDefault(wire))
    }

    @Test fun colorUsesTheNanoWireBytesWithoutEightBit() {
        assertEquals(
            listOf(CameraCommands.COLOR_NORMAL10, CameraCommands.COLOR_DLOG_M),
            CameraModel.colorModesFor(action6, "other"),
        )
        assertEquals(0x3F, CameraCommands.wireColorMode(CameraCommands.COLOR_NORMAL10, action6, "other"))
        assertEquals(0x3D, CameraCommands.wireColorMode(CameraCommands.COLOR_DLOG_M, action6, "other"))
        assertEquals(CameraCommands.COLOR_NORMAL10, CameraCommands.parseColorMode(0x3F, action6, "other"))
        assertEquals(CameraCommands.COLOR_DLOG_M, CameraCommands.parseColorMode(0x3D, action6, "other"))
        assertEquals(listOf("Normal 10-bit", "D-Log M"), CaptureLists.colorWheelLabels(CameraStatus(), "other", action6))
    }

    @Test fun captureBytes() {
        assertEquals(CameraCommands.SHOOT_PHOTO, CameraCommands.photoModeRaw(action6))
        assertEquals(
            CaptureShutterPolicy.CaptureKind.SHUTTER_TRIGGER,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_TIMELAPSE, action6),
        )
        assertEquals(
            CaptureShutterPolicy.CaptureKind.VIDEO_RECORD,
            CaptureShutterPolicy.captureKind(CameraCommands.SHOOT_TIMELAPSE, "Osmo Pocket 4"),
        )
    }

    @Test fun favoriteIsTheFifteenByteAction6Body() {
        val on = CameraCommands.setMediaFavorite(0x12345678, true, counter = 9, cameraName = action6)
        assertTrue(bytes(1, 1, 0x78, 0x56, 0x34, 0x12, 1, 0, 0, 0, 0, 1, 0, 0, 0).contentEquals(on))
        val off = CameraCommands.setMediaFavorite(0x12345678, false, counter = 9, cameraName = action6)
        assertEquals(0, off[1].toInt())
        assertEquals(15, off.size)
        assertEquals(15, CameraCommands.setMediaFavorite(1, true, 9).size) // Pocket keeps its layout
    }

    @Test fun subscriptionsAppendApertureKeysOnlyForAction6() {
        val base = DatalinkDriver.subscriptionKeys(CameraModel(name = "Osmo Pocket 4"))
        val a6 = DatalinkDriver.subscriptionKeys(CameraModel(name = action6))
        assertEquals(base, a6.take(base.size))
        assertEquals(listOf(ApertureStrategy.STATE_KEY, ApertureStrategy.CAPABILITY_KEY), a6.drop(base.size))
    }

    @Test fun apertureParsing() {
        assertEquals(listOf(4, 2, 3), ApertureStrategy.parseCapability(bytes(1, 4, 0, 3, 4, 2, 3)))
        assertEquals(listOf(1, 2, 3), ApertureStrategy.parseCapability(bytes(1, 6, 0, 3, 1, 2, 3, 3, 4)))
        assertEquals(emptyList(), ApertureStrategy.parseCapability(bytes(1, 9, 0, 3, 1, 2, 3)))
        assertEquals(ApertureStrategy.STARBURST, ApertureStrategy.parseState(bytes(1, 0, 0, 3)))
        assertNull(ApertureStrategy.parseState(bytes(1, 0, 0, 9)))
        val expo = ByteArray(23).also { it[7] = 0x04; it[13] = 0x22; it[14] = 0x01 }
        assertEquals(290, ApertureStrategy.irisHundredths(expo))
        assertNull(ApertureStrategy.irisHundredths(ByteArray(23)))
        assertEquals("f/2.9", ApertureStrategy.fNumberLabel(290))

        var status = StatusExtras.applySubscribe(StatusExtras.packSubscribe("cam_expo_param", expo), CameraStatus(), action6)
        assertEquals(290, status.irisHundredths)
        assertEquals(-1, StatusExtras.applySubscribe(
            StatusExtras.packSubscribe("cam_expo_param", expo), CameraStatus(), "Osmo Pocket 4").irisHundredths)
        status = StatusExtras.applySubscribe(
            StatusExtras.packSubscribe(ApertureStrategy.STATE_KEY, bytes(1, 0, 0, 4)), status, action6)
        status = StatusExtras.applySubscribe(
            StatusExtras.packSubscribe(ApertureStrategy.CAPABILITY_KEY, bytes(1, 4, 0, 3, 4, 2, 3)), status, action6)
        assertEquals(ApertureStrategy.AUTO, status.apertureStrategy)
        assertEquals(listOf(4, 2, 3), status.availableApertureStrategies)
        assertEquals("f/2.9", ApertureStrategy.tileValue(status))
        assertEquals("Auto", ApertureStrategy.tileValue(status.copy(irisHundredths = -1)))
        assertEquals("—", ApertureStrategy.tileValue(CameraStatus()))
        // The JNI status JSON drops these fields; the session carries them over.
        assertEquals(status.availableApertureStrategies, CameraStatus().carryingAperture(status).availableApertureStrategies)
    }

    @Test fun apertureChoicesFallBackByModeUntilTheCapabilityLands() {
        val superNight = CameraStatus(shootingMode = CameraCommands.SHOOT_SUPER_NIGHT)
        assertEquals(listOf(0, 2, 3), ApertureStrategy.choices(superNight))
        assertEquals(listOf(1, 2, 3), ApertureStrategy.choices(CameraStatus(expoMode = CameraCommands.EXPO_MANUAL)))
        assertEquals(listOf(4, 2, 3), ApertureStrategy.choices(CameraStatus(expoMode = CameraCommands.EXPO_AUTO)))
        assertEquals(listOf(1), ApertureStrategy.choices(superNight.copy(availableApertureStrategies = listOf(1))))
        assertEquals(listOf("Auto", "f/2.8", "Starburst f/4"), CaptureLists.apertureLabels(CameraStatus()))
        assertEquals(ApertureStrategy.STARBURST, CaptureLists.apertureFromLabel("Starburst f/4"))
        assertEquals("APERTURE", LiveSheet.APERTURE.headerLabel)
        assertEquals("Aperture strategy", LiveSheet.APERTURE.subtitle)
    }
}
