package com.opencapture.openpocketcine

import android.view.SurfaceView
import android.view.TextureView
import android.view.View
import android.view.ViewGroup
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.AppShell
import com.opencapture.opencine.appkit.ShellActions
import com.opencapture.opencine.appkit.ShellBrand
import com.opencapture.opencine.appkit.ShellModel
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** SIMULATED native monitor: actual shared shell and native picture views, no datalink or approval. */
@RunWith(AndroidJUnit4::class)
class MonitorShellCompositionTest {
    @Test fun actualShellKeepsOneNativePictureHostThroughCoversAndLayoutChanges() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            lateinit var model: AppModel
            lateinit var host: BackdropRenderActivity
            var portrait by mutableStateOf(true)
            scenario.onActivity { activity ->
                host = activity
                model = AppModel(activity)
                presentSimulatedNativeMonitor(model)
                activity.setContent {
                    Box(Modifier.requiredSize(if (portrait) 400.dp else 800.dp,
                        if (portrait) 800.dp else 400.dp)) {
                        AppShell(model.shell, ShellBrand("SIMULATED Pocket"),
                            ShellActions(diagnostics = {}, reportProblem = {}),
                            monitor = { LiveViewScreen(model) },
                            page = { ShellCoverPage(model, it) },
                            coverPresentation = com.opencapture.opencine.appkit.ShellCoverPresentation.SHELL)
                    }
                }
            }
            fun frame() {
                val rendered = CountDownLatch(1)
                instrumentation.runOnMainSync {
                    host.window.decorView.viewTreeObserver.registerFrameCommitCallback { rendered.countDown() }
                    host.window.decorView.invalidate()
                }
                assertTrue(rendered.await(10, TimeUnit.SECONDS), "The actual native frame must commit")
            }
            try {
                frame()
                lateinit var picture: View
                lateinit var monitor: String
                // ActivityScenario.onActivity waits for a globally idle Looper. Live native
                // picture/HUD animations keep drawing, so synchronize a committed frame instead.
                instrumentation.runOnMainSync {
                    picture = assertNotNull(findPicture(host.window.decorView))
                    monitor = assertNotNull(model.shell.state.value.monitor).id
                    assertEquals(1, model.shell.hostsMounted)
                    assertEquals(0, model.shell.hostsUnmounted)
                    assertNull(model.control.recordEditor(), "Live presentation cannot create capture approval")
                }
                for ((cover, nextPortrait) in listOf(
                    ShellModel.Cover.SETTINGS to false,
                    ShellModel.Cover.MEDIA to true,
                )) {
                    instrumentation.runOnMainSync { model.shell.open(cover); portrait = nextPortrait }
                    frame()
                    instrumentation.runOnMainSync {
                        assertEquals(cover, model.shell.state.value.cover)
                        assertEquals(monitor, model.shell.state.value.monitor?.id)
                        assertSame(picture, findPicture(host.window.decorView), "Coverage and layout keep the native surface view")
                        assertEquals(1, model.shell.hostsMounted)
                        assertEquals(0, model.shell.hostsUnmounted)
                        model.shell.dismissCover()
                    }
                    frame()
                    instrumentation.runOnMainSync {
                        assertNull(model.shell.state.value.cover)
                        assertSame(picture, findPicture(host.window.decorView))
                    }
                }
                instrumentation.runOnMainSync { model.shell.close() }
                frame()
                instrumentation.runOnMainSync {
                    assertEquals(1, model.shell.hostsMounted)
                    assertEquals(1, model.shell.hostsUnmounted)
                    assertNull(model.shell.state.value.monitor)
                }
            } finally {
                instrumentation.runOnMainSync { model.close(); host.setContent {} }
            }
        }
    }

    private fun findPicture(view: View): View? {
        if (view is SurfaceView || view is TextureView) return view
        if (view is ViewGroup) for (index in 0 until view.childCount) {
            findPicture(view.getChildAt(index))?.let { return it }
        }
        return null
    }
}
