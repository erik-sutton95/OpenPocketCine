package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.session.GimbalProgram
import com.opencapture.openpocketcine.session.GimbalWaypoint
import com.opencapture.openpocketcine.session.PocketCameraSession
import kotlinx.coroutines.flow.MutableStateFlow
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Production editor lifecycle and accessibility actions, without sending camera commands. */
@RunWith(AndroidJUnit4::class)
class MotionProgramSessionTest {
    private val program = GimbalProgram(
        a = GimbalWaypoint(0.0, 0.0, 1.0, 175.0),
        b = GimbalWaypoint(30.0, 0.0, 1.0, 175.0),
        c = GimbalWaypoint(30.0, 20.0, 1.0, 155.0),
        durationAB = 3.5, durationBC = 6.5, smoothness = 0.7, loop = true,
    )

    @OptIn(ExperimentalComposeUiApi::class)
    @Test fun closeReopenRetainsFullProgramUntilClearAndActiveCloseKeepsStop() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var model: AppModel? = null
            try {
                scenario.onActivity { activity ->
                    val app = AppModel(activity)
                    model = app
                    seed(app.session, "_gimbalProgram", program)
                    app.liveGimbalPanel = LiveGimbalPanel.EDITOR
                    activity.setContent {
                        BoxWithConstraints(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                            val layout = LiveMonitorLayout.fit(maxWidth.value, maxHeight.value,
                                0f, 0f, 0f, 0f, showsBottomBars = true)
                            LiveGimbalOverlay(app, layout, layout.feed, uiLocked = false)
                        }
                    }
                }
                assertTrue(node("motion.loop").isChecked)
                click("motion.close")
                scenario.onActivity {
                    assertEquals(LiveGimbalPanel.NONE, model!!.liveGimbalPanel)
                    assertEquals(program, model!!.session.gimbalProgram.value)
                    model!!.liveGimbalPanel = LiveGimbalPanel.EDITOR
                }
                assertTrue(node("motion.loop").isChecked)
                click("motion.loop")
                scenario.onActivity { assertEquals(program.copy(loop = false), model!!.session.gimbalProgram.value) }
                click("motion.loop")

                for (state in listOf("countdown", "running", "paused")) {
                    scenario.onActivity {
                        seed(model!!.session, "_gimbalMoveRunning", true)
                        seed(model!!.session, "_gimbalMoveCountdown", if (state == "countdown") 2 else null)
                        seed(model!!.session, "_gimbalMovePaused", state == "paused")
                    }
                    assertFalse(node("motion.loop") { !it.isEnabled }.isEnabled, "Loop is fixed during $state")
                    click("motion.close")
                    scenario.onActivity {
                        assertEquals(LiveGimbalPanel.RUN_PILL, model!!.liveGimbalPanel)
                        assertEquals(program, model!!.session.gimbalProgram.value)
                    }
                    assertTrue(node("motion.startStop").isEnabled)
                    click("motion.expand")
                    assertTrue(node("motion.loop").isChecked)
                }

                click("motion.startStop")
                scenario.onActivity {
                    assertFalse(model!!.session.gimbalMoveRunning.value)
                    assertEquals(program, model!!.session.gimbalProgram.value)
                }
                click("motion.clear")
                scenario.onActivity {
                    assertEquals(GimbalProgram(durationAB = 3.5, durationBC = 6.5),
                        model!!.session.gimbalProgram.value)
                }
                assertFalse(node("motion.loop") { !it.isChecked }.isChecked)
            } finally {
                scenario.onActivity { model?.close() }
            }
        }
    }

    /** Seed camera-owned state in the fixture; no production bypass for stable-pose capture. */
    @Suppress("UNCHECKED_CAST")
    private fun <T> seed(session: PocketCameraSession, name: String, value: T) {
        val field = PocketCameraSession::class.java.getDeclaredField(name).apply { isAccessible = true }
        (field.get(session) as MutableStateFlow<T>).value = value
    }

    private fun click(id: String) {
        assertTrue(node(id).performAction(AccessibilityNodeInfo.ACTION_CLICK), "$id must be actionable")
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun node(id: String, ready: (AccessibilityNodeInfo) -> Boolean = { true }): AccessibilityNodeInfo {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            instrumentation.waitForIdleSync()
            instrumentation.uiAutomation.rootInActiveWindow?.let { find(it, id) }?.let {
                if (ready(it)) return it
            }
            SystemClock.sleep(80)
        }
        error("No accessibility node for $id")
    }

    private fun find(node: AccessibilityNodeInfo, id: String): AccessibilityNodeInfo? {
        if (node.viewIdResourceName == id) return node
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { find(it, id) }?.let { return it }
        }
        return null
    }
}
