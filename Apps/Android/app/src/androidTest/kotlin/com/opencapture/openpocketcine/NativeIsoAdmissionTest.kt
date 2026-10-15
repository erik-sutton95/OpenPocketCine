package com.opencapture.openpocketcine

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.dji.CameraNetworkPath
import com.opencapture.opencine.dji.DatalinkDriver
import com.opencapture.opencine.dji.DjiNative
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraCaptureProfile
import com.opencapture.opencine.vocabulary.CaptureNativeISOCapabilities
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.FoundCamera
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.multiview.MultiviewSession
import java.net.DatagramSocket
import java.net.Socket
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED actual native SET mailbox; the endpoint opens no camera socket. */
@RunWith(AndroidJUnit4::class)
class NativeIsoAdmissionTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Test fun anUndeclaredNativePairCannotSubmitAnAutomaticIsoWrite() = fixture { model ->
        model.session.setColorMode(CameraCommands.COLOR_DLOG2, true)
        assertNull(model.session.pendingCameraSetExtra(DjiNative.CMD_SET_ISO_INDEX),
            "The saved preference cannot declare a native ISO pair")
        assertEquals(1, model.session.pendingCameraSetCount, "Only the explicit color command is pending")
    }

    @Test fun anUndeclaredCeilingCannotSubmitANativeLimit() = fixture { model ->
        model.session.setIsoLimit(4)
        assertNull(model.session.pendingCameraSetExtra(DjiNative.CMD_SET_ISO_LIMIT))
        assertEquals(0, model.session.pendingCameraSetCount)
        assertEquals(-1, model.session.status.value.isoLimit)
    }

    @Test fun explicitlyDeclaredNativePairRetainsItsOperatorApprovedWrite() =
        fixture(CaptureNativeISOCapabilities(hop = true, ceiling = true)) { model ->
            model.session.setColorMode(CameraCommands.COLOR_DLOG2, true)
            assertEquals("7", model.session.pendingCameraSetExtra(DjiNative.CMD_SET_ISO_INDEX))
            assertEquals(2, model.session.pendingCameraSetCount)
        }

    @Test fun explicitlyDeclaredCeilingRetainsItsNativeLimitWrite() =
        fixture(CaptureNativeISOCapabilities(hop = true, ceiling = true)) { model ->
            model.session.setIsoLimit(4)
            assertEquals("4", model.session.pendingCameraSetExtra(DjiNative.CMD_SET_ISO_LIMIT))
            assertEquals(1, model.session.pendingCameraSetCount)
        }

    @Test fun knownUnsupportedServicesKeepTheirFalseDeclarations() =
        fixture(CaptureNativeISOCapabilities(hop = false, ceiling = false)) { model ->
            assertEquals(false, model.session.nativeISOCapabilities.hop)
            assertEquals(false, model.session.nativeISOCapabilities.ceiling)
            model.session.setIsoLimit(4)
            assertEquals(0, model.session.pendingCameraSetCount)
        }

    private fun fixture(nativeISO: CaptureNativeISOCapabilities = CaptureNativeISOCapabilities(),
        test: (AppModel) -> Unit) = instrumentation.runOnMainSync {
        assertTrue(SwiftCore.isAvailable)
        val tile = MultiviewSession.Tile(0, instrumentation.targetContext)
        try {
            tile.camera = FoundCamera("SIMULATED-native-iso", "unused", "SIMULATED",
                CameraModel("OsmoPocket4P-SIMULATED", family = "pocket",
                    captureProfile = CameraCaptureProfile(nativeISO = nativeISO)), null)
            tile.driver = DatalinkDriver(object : CameraNetworkPath {
                override fun bindSocket(socket: DatagramSocket) = error("No camera socket")
                override fun bindSocket(socket: Socket) = error("No camera socket")
                override fun isProcessBound() = false
                override fun cameraLocalIPv4(): String? = null
            }, 9004, false, "osmo")
            tile.latestSettings = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO,
                expoMode = CameraCommands.EXPO_MANUAL, colorMode = CameraCommands.COLOR_DLOG,
                isoIndex = assertNotNull(CameraCommands.isoIndexFromValue(400)), iso = 400,
                availableColorModes = listOf(CameraCommands.COLOR_DLOG, CameraCommands.COLOR_DLOG2))
            test(assertNotNull(tile.openControls { true }))
        } finally { tile.reset() }
    }
}
