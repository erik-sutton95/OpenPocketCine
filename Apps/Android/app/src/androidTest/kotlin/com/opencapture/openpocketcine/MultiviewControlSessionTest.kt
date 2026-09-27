package com.opencapture.openpocketcine

import android.os.SystemClock
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.multiview.MultiviewSession
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraNetworkPath
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.DatalinkDriver
import com.opencapture.openpocketcine.session.DumlFrame
import com.opencapture.openpocketcine.session.FoundCamera
import java.net.DatagramSocket
import java.net.Socket
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the real native SET mailbox and ACK handling; no socket or camera is opened. */
@RunWith(AndroidJUnit4::class)
class MultiviewControlSessionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private fun main(action: () -> Unit) = instrumentation.runOnMainSync(action)
    private fun tile(index: Int): MultiviewSession.Tile =
        MultiviewSession.Tile(index, instrumentation.targetContext).apply {
            camera = FoundCamera("camera-$index", "unused", "Camera $index", CameraModel("Osmo Pocket 4"), null)
            driver = endpoint()
            latestSettings = CameraStatus(isoIndex = 3)
        }
    private fun endpoint() = DatalinkDriver(object : CameraNetworkPath {
        override fun bindSocket(socket: DatagramSocket) = error("Test must not open a socket")
        override fun bindSocket(socket: Socket) = error("Test must not open a socket")
        override fun isProcessBound() = false
        override fun cameraLocalIPv4(): String? = null
    }, 9004, false, "osmo")

    private fun isoAck(): DumlFrame {
        val key = SwiftCore.waitKey(SwiftCore.CMD_SET_ISO_INDEX)
        return DumlFrame(0x08, 0x02, 1, 0x80, key shr 8, key and 0xff, byteArrayOf(0))
    }

    @Test fun cameraTabsRouteAcksSeparatelyAndRetirePendingWritesWithoutClosingFeeds() {
        val cleanup = mutableListOf<MultiviewSession.Tile>()
        lateinit var a: MultiviewSession.Tile
        lateinit var b: MultiviewSession.Tile
        lateinit var first: AppModel
        lateinit var second: AppModel
        val callback: () -> Unit = {}
        var sentAt = 0L
        try {
            main {
                assertTrue(SwiftCore.isAvailable)
                a = tile(0).also(cleanup::add)
                b = tile(1).also(cleanup::add)
                a.decoder.onParameterSetsChanged = callback
                first = assertNotNull(a.openControls { true })
                second = assertNotNull(b.openControls { true })
                assertTrue(first.session.isMultiviewControlOnly)
                assertSame(a.decoder, first.session.decoder)
                assertNull(a.liveModel)
                first.session.setIsoIndex(4)
                second.session.setIsoIndex(5)
                assertEquals(1, first.session.pendingCameraSetCount)
                assertEquals(1, second.session.pendingCameraSetCount)
                first.session.receiveMultiview(isoAck())
                assertEquals(0, first.session.pendingCameraSetCount)
                assertEquals(1, second.session.pendingCameraSetCount)
                first.session.setIsoIndex(6)
                first.session.setIsoIndex(7) // Latest-wins pending edit must retire with its tab.
                assertEquals(2, first.session.pendingCameraSetCount)
                sentAt = a.lastCommandAt
                a.closeControls()
                assertEquals(0, first.session.pendingCameraSetCount)
                assertFalse(assertNotNull(a.driver).isClosed)
                assertSame(callback, a.decoder.onParameterSetsChanged)
                first.session.receiveMultiview(isoAck())
                first.session.setIsoIndex(8)
                assertEquals(0, first.session.pendingCameraSetCount)
                assertEquals(1, second.session.pendingCameraSetCount)
                second.session.receiveMultiview(isoAck())
                assertEquals(0, second.session.pendingCameraSetCount)
            }
            SystemClock.sleep(380) // Cross the actual mailbox retransmission delay.
            main { assertEquals(sentAt, a.lastCommandAt, "Closed tab cannot retransmit on the retained endpoint") }
        } finally {
            main { cleanup.forEach { it.reset() } }
        }
    }

    @Test fun recordingReconnectAndRemovalInvalidateTheOldCommandBinding() {
        val cleanup = mutableListOf<MultiviewSession.Tile>()
        lateinit var tile: MultiviewSession.Tile
        lateinit var retired: AppModel
        var commandAt = 0L
        try {
            main {
                tile = tile(0).also(cleanup::add)
                retired = assertNotNull(tile.openControls { true })
                retired.session.setIsoIndex(4)
                commandAt = tile.lastCommandAt
                // Even before Compose disposes the old picker, its recording snapshot has expired.
                tile.latestSettings = tile.latestSettings.copy(isRecording = true)
                retired.session.setIsoIndex(5)
                assertEquals(1, retired.session.pendingCameraSetCount)
            }
            SystemClock.sleep(380)
            main {
                assertEquals(commandAt, tile.lastCommandAt)
                val previousDriver = assertNotNull(tile.driver)
                tile.driver = endpoint()
                assertNull(tile.controlsModel)
                assertEquals(0, retired.session.pendingCameraSetCount)
                assertFalse(previousDriver.isClosed, "Controls never close the tile transport")
                previousDriver.close()
                val next = assertNotNull(tile.openControls { true })
                tile.camera = null // Removal is rejected before composition observes it.
                next.session.setIsoIndex(6)
                assertEquals(0, next.session.pendingCameraSetCount)
            }
        } finally { main { cleanup.forEach { it.reset() } } }
    }

    @Test fun freshTilesEnableLutAndExplicitChoiceSurvivesControlRebinding() {
        main {
            val tile = tile(0)
            try {
                assertTrue(tile.lutEnabled)
                tile.toggleLUT()
                assertFalse(tile.lutEnabled)
                tile.openControls { true }
                tile.closeControls()
                assertFalse(tile.lutEnabled)
                tile.reset()
                assertTrue(tile.lutEnabled)
            } finally { tile.reset() }
        }
    }

    @Test fun audioControlsKeepNativePinsUntilTheCameraConfirmsTheEdit() {
        main {
            val tile = tile(0)
            try {
                tile.latestSettings = CameraStatus(audioChannel = CameraCommands.AUDIO_STEREO)
                val controls = assertNotNull(tile.openControls { true })
                fun report(value: Int) = DumlFrame(0x08, 0x02, 1, 0x80, 0x02, CameraCommands.CMD_PARAM,
                    byteArrayOf(0, 0, 0, CameraCommands.PID_AUDIO_CHANNEL.toByte(), 0, 1, value.toByte()))
                controls.session.setAudioChannel(CameraCommands.AUDIO_SPATIAL)
                assertEquals(CameraCommands.AUDIO_SPATIAL, controls.session.status.value.audioChannel)
                controls.session.receiveMultiview(report(CameraCommands.AUDIO_STEREO))
                assertEquals(CameraCommands.AUDIO_SPATIAL, controls.session.status.value.audioChannel,
                    "A stale report must not undo an in-flight native audio edit")
                controls.session.receiveMultiview(report(CameraCommands.AUDIO_SPATIAL))
                controls.session.receiveMultiview(report(CameraCommands.AUDIO_STEREO))
                assertEquals(CameraCommands.AUDIO_STEREO, controls.session.status.value.audioChannel,
                    "Once confirmed, later camera-side changes must be visible")
            } finally { tile.reset() }
        }
    }

    @Test fun backgroundRetiresPendingSettingsWhileKeepingTheFourFeedOwners() {
        lateinit var stage: MultiviewSession
        lateinit var controls: AppModel
        var commandAt = 0L
        main {
            stage = MultiviewSession(instrumentation.targetContext, saveStage = { true })
            // Enter the already-connected stage state without discovery, provisioning, or sockets.
            MultiviewSession::class.java.getDeclaredField("running").apply { isAccessible = true }.setBoolean(stage, true)
            val tile = stage.tiles[0]
            tile.camera = FoundCamera("first", "unused", "First", CameraModel("Osmo Pocket 4"), null)
            tile.driver = endpoint()
            tile.controlHost = "unused"
            controls = assertNotNull(tile.openControls { stage.controlsAvailable(tile) })
            controls.session.setIsoIndex(4)
            controls.session.setIsoIndex(5)
            assertEquals(2, controls.session.pendingCameraSetCount)
            commandAt = tile.lastCommandAt
            val decoder = tile.decoder
            val driver = tile.driver
            stage.setApplicationActive(false)
            assertNull(tile.controlsModel)
            assertEquals(0, controls.session.pendingCameraSetCount)
            assertFalse(stage.controlsAvailable(tile))
            assertSame(decoder, tile.decoder)
            assertSame(driver, tile.driver)
            assertFalse(assertNotNull(driver).isClosed)
            assertEquals(4, stage.tiles.size)
        }
        try {
            SystemClock.sleep(380)
            main {
                assertEquals(commandAt, stage.tiles[0].lastCommandAt)
                stage.setApplicationActive(true)
                assertTrue(stage.controlsAvailable(stage.tiles[0]))
                assertNull(stage.tiles[0].controlsModel)
                controls.session.setIsoIndex(6)
                assertEquals(0, controls.session.pendingCameraSetCount)
            }
        } finally { main { stage.dispose() } }
    }
}
