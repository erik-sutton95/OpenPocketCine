package com.opencapture.openpocketcine

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.core.ConnectedCamera
import com.opencapture.opencine.core.SavedCamera
import com.opencapture.opencine.core.SessionCloseReason
import com.opencapture.opencine.dji.DjiCameraSession
import com.opencapture.opencine.dji.DjiCameraSessionAdapter
import com.opencapture.opencine.vocabulary.ConnectionPhase
import kotlinx.coroutines.flow.MutableStateFlow
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotEquals
import kotlin.test.assertNull

/** SIMULATED native sessions: no driver is opened and no approval or camera report is invented. */
private fun simulatedNativeCamera(model: AppModel): ConnectedCamera {
    val field = DjiCameraSession::class.java.getDeclaredField("_phase").apply { isAccessible = true }
    @Suppress("UNCHECKED_CAST")
    (field.get(model.session) as MutableStateFlow<ConnectionPhase>).value = ConnectionPhase.LIVE
    return ConnectedCamera(SavedCamera(id = "simulated-dji", integration = DjiCameraSessionAdapter.INTEGRATION,
        advertisedName = "SIMULATED DJI", model = "SIMULATED"), model.session.control)
}

internal fun presentSimulatedNativeMonitor(model: AppModel) { model.shell.present(simulatedNativeCamera(model)) }

@RunWith(AndroidJUnit4::class)
class MonitorShellLifetimeTest {
    @Test fun coverAndCompatibilityPanelsKeepOneNativeSessionThenOwnedCloseRetiresIt() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val model = AppModel(instrumentation.targetContext)
            try {
                presentSimulatedNativeMonitor(model)
                val common = model.session.control
                val monitor = model.shell.state.value.monitor?.id
                model.shell.open(ShellModel.Cover.SETTINGS)
                assertEquals(ShellModel.Cover.SETTINGS, model.shell.state.value.cover)
                assertNull(model.homePanel)
                model.shell.open(ShellModel.Cover.MEDIA)
                assertEquals(ShellModel.Cover.MEDIA, model.shellState.cover)
                assertEquals(monitor, model.shell.state.value.monitor?.id)
                assertEquals(common.id, model.session.control.id)
                assertNull(model.control.recordEditor(), "Unknown mode and recording cannot approve capture")
                model.shell.dismissCover()
                assertNull(model.shell.state.value.cover)
                model.shell.close()
                model.shell.close()
                assertNull(model.shell.state.value.monitor)
                assertEquals(ConnectionPhase.IDLE, model.session.phase)
                assertEquals(com.opencapture.opencine.core.ConnectionState.Disconnected(SessionCloseReason.REQUESTED),
                    common.current.connection)
                assertNotEquals(common.id, model.session.control.id)
            } finally { model.close() }
        }
    }

    @Test fun borrowedReturnAndSceneSignalsAreIdempotent() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.runOnMainSync {
            val model = AppModel(instrumentation.targetContext)
            try {
                val camera = simulatedNativeCamera(model)
                var releases = 0
                model.shell.borrow(camera, release = { releases++ })
                val signals = mutableListOf<Boolean>()
                model.shell.onSceneActivity = { signals += it }
                model.shell.setSceneActive(false)
                model.shell.setSceneActive(false)
                model.shell.setSceneActive(true)
                model.shell.setSceneActive(true)
                assertEquals(listOf(false, true), signals)
                model.shell.open(ShellModel.Cover.SETTINGS)
                model.shell.dismissCover()
                assertEquals(0, releases)
                model.shell.close()
                model.shell.close()
                assertEquals(1, releases)
                assertFalse(model.session.control.current.connection is com.opencapture.opencine.core.ConnectionState.Disconnected,
                    "Returning a borrowed display must leave the native transport owner alone")
            } finally { model.close() }
        }
    }
}
