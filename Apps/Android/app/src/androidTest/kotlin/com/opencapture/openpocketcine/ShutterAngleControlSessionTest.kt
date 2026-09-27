package com.opencapture.openpocketcine

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.multiview.MultiviewSession
import com.opencapture.openpocketcine.session.*
import java.net.DatagramSocket
import java.net.Socket
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real native FORMAT/SET mailbox and telemetry, with an endpoint that opens no camera socket. */
@RunWith(AndroidJUnit4::class)
class ShutterAngleControlSessionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun frameRateChangesKeep180AndDeferOneCorrectShutterUntilFormatConfirmation() = fixture { session ->
        session.setVideoFormat(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60))
        assertEquals(1, session.pendingCameraSetCount)
        assertNull(session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
        assertEquals(120, session.status.value.shutterDenom)
        session.receiveMultiview(exposure(48))
        assertEquals(120, session.status.value.shutterDenom)
        session.receiveMultiview(format(VideoFrameRate.FPS60))
        assertEquals("120", session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
        assertEquals(180.0, OperatorPrefs.shutterAngleDegrees(instrumentation.targetContext))
    }

    @Test fun earlyExposureEchoCannotReleasePendingAngle() = fixture { session ->
        session.setVideoFormat(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60))
        session.receiveMultiview(exposure(120))
        session.receiveMultiview(exposure(48))
        assertEquals(120, session.status.value.shutterDenom)
        assertNull(session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
    }

    @Test fun staleAutoReportRespectsTheNewerManualChoice() = fixture { session ->
        session.receiveMultiview(exposure(48, CameraCommands.EXPO_AUTO))
        session.setExpoMode(CameraCommands.EXPO_MANUAL)
        session.setVideoFormat(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60))
        session.receiveMultiview(exposure(48, CameraCommands.EXPO_AUTO))
        assertEquals(CameraCommands.EXPO_MANUAL, session.status.value.expoMode)
        assertEquals(120, session.status.value.shutterDenom)
        session.receiveMultiview(format(VideoFrameRate.FPS60))
        assertEquals("120", session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
    }

    @Test fun delayedFormatConfirmationKeepsTheLatestAngleBeyondOptimisticWindow() = fixture { session ->
        session.setVideoFormat(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60))
        // The main looper remains blocked so only the actual telemetry below,
        // rather than an unrelated timeout callback, resolves this request.
        Thread.sleep(2_150)
        session.setShutterAngle(90.0)
        assertNull(session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
        session.receiveMultiview(format(VideoFrameRate.FPS60))
        assertEquals("240", session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
    }

    @Test fun newestAngleWinsWhileFormatIsPending() = fixture { session ->
        session.setVideoFormat(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60))
        session.setShutterAngle(90.0)
        assertNull(session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
        session.receiveMultiview(format(VideoFrameRate.FPS60))
        assertEquals("240", session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
        assertEquals(90.0, OperatorPrefs.shutterAngleDegrees(instrumentation.targetContext))
    }

    @Test fun autoAndRetiredEditorsCannotReleaseAQueuedManualShutter() {
        for (retire in listOf(false, true)) fixture { session ->
            session.setVideoFormat(VideoFormat(VideoResolution.P4K, VideoFrameRate.FPS60))
            if (retire) session.releaseMultiview() else session.setExpoMode(CameraCommands.EXPO_AUTO)
            session.receiveMultiview(format(VideoFrameRate.FPS60))
            assertNull(session.pendingCameraSetExtra(SwiftCore.CMD_SET_SHUTTER))
        }
    }

    private fun fixture(test: (PocketCameraSession) -> Unit) {
        instrumentation.runOnMainSync {
            assertTrue(SwiftCore.isAvailable)
            val context = instrumentation.targetContext
            val usesAngle = OperatorPrefs.shutterUsesAngle(context)
            val degrees = OperatorPrefs.shutterAngleDegrees(context)
            val tile = MultiviewSession.Tile(0, context)
            try {
                OperatorPrefs.setShutterUsesAngle(context, true)
                OperatorPrefs.setShutterAngleDegrees(context, 180.0)
                tile.camera = FoundCamera("angle-camera", "unused", "OsmoPocket3-Test", CameraModel("Osmo Pocket 3"), null)
                tile.driver = DatalinkDriver(object : CameraNetworkPath {
                    override fun bindSocket(socket: DatagramSocket) = error("No camera socket")
                    override fun bindSocket(socket: Socket) = error("No camera socket")
                    override fun isProcessBound() = false
                    override fun cameraLocalIPv4(): String? = null
                }, 9004, false, "osmo")
                tile.latestSettings = CameraStatus(
                    shootingMode = CameraCommands.SHOOT_VIDEO, resolutionCode = VideoResolution.P4K.rawValue,
                    fpsIndex = VideoFrameRate.FPS24.rawValue, fps = 24,
                    expoMode = CameraCommands.EXPO_MANUAL, shutterDenom = 48,
                    availableShutterDenoms = listOf(24, 48, 50, 60, 120, 240),
                )
                test(assertNotNull(tile.openControls { true }).session)
            } finally {
                tile.reset()
                OperatorPrefs.setShutterUsesAngle(context, usesAngle)
                OperatorPrefs.setShutterAngleDegrees(context, degrees)
            }
        }
    }

    private fun format(rate: VideoFrameRate) = subscribe("cam_video_param_v2", byteArrayOf(0x10, rate.rawValue.toByte()))
    private fun exposure(denom: Int, mode: Int = CameraCommands.EXPO_MANUAL): DumlFrame {
        val value = ByteArray(23)
        value[2] = (denom and 0xff).toByte()
        value[3] = ((denom shr 8) or 0x80).toByte()
        value[5] = 3
        value[6] = 0x10
        value[7] = mode.toByte()
        return subscribe("cam_expo_param", value)
    }
    private fun subscribe(name: String, value: ByteArray) =
        DumlFrame(0, 0, 1, 0, 0, 0x99, StatusExtras.packSubscribe(name, value))
}
