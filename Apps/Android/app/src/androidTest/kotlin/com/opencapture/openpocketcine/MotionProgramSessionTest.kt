package com.opencapture.openpocketcine

import android.os.SystemClock
import android.graphics.Rect
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.core.view.accessibility.AccessibilityNodeInfoCompat
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
import kotlin.math.min
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
    @Test fun closeReopenAndPausedRestartRetainFullProgramUntilClear() {
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
                scrollToEnd()
                assertTrue(node("motion.loop").isChecked)
                click("motion.close")
                scenario.onActivity {
                    assertEquals(LiveGimbalPanel.NONE, model!!.liveGimbalPanel)
                    assertEquals(program, model!!.session.gimbalProgram.value)
                    model!!.liveGimbalPanel = LiveGimbalPanel.EDITOR
                }
                scrollToEnd()
                assertTrue(node("motion.loop").isChecked)
                click("motion.loop")
                scenario.onActivity { assertEquals(program.copy(loop = false), model!!.session.gimbalProgram.value) }
                click("motion.loop")

                for (state in listOf("countdown", "running", "paused")) {
                    scenario.onActivity {
                        seed(model!!.session, "_gimbalMoveRunning", true)
                        seed(model!!.session, "_gimbalMoveCountdown", if (state == "countdown") 2 else null)
                        seed(model!!.session, "_gimbalMovePaused", state == "paused")
                        if (state != "paused") {
                            model!!.session.restartProgrammedMove()
                            assertTrue(model!!.session.gimbalMoveRunning.value, "Restart requires a paused move")
                            assertEquals(if (state == "countdown") 2 else null,
                                model!!.session.gimbalMoveCountdown.value)
                        }
                    }
                    assertFalse(node("motion.loop") { !it.isEnabled }.isEnabled, "Loop is fixed during $state")
                    click("motion.close")
                    scenario.onActivity {
                        assertEquals(LiveGimbalPanel.RUN_PILL, model!!.liveGimbalPanel)
                        assertEquals(program, model!!.session.gimbalProgram.value)
                    }
                    assertTrue(node("motion.startStop").isEnabled)
                    click("motion.expand")
                    scrollToEnd()
                    assertTrue(node("motion.loop").isChecked)
                }

                val token = PocketCameraSession::class.java.getDeclaredField("moveToken").apply { isAccessible = true }
                scenario.onActivity { token.set(model!!.session, 42L) }
                click("motion.restart")
                scenario.onActivity {
                    // No connected camera: the existing Start guards prevent a new countdown,
                    // after Restart has retired the paused continuation without clearing its program.
                    assertFalse(model!!.session.gimbalMoveRunning.value)
                    assertFalse(model!!.session.gimbalMovePaused.value)
                    assertEquals(null, model!!.session.gimbalMoveCountdown.value)
                    assertEquals(null, token.get(model!!.session))
                    assertEquals(program, model!!.session.gimbalProgram.value)
                    model!!.session.restartProgrammedMove()
                    assertFalse(model!!.session.gimbalMoveRunning.value, "Restart is ignored while idle")
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

    @OptIn(ExperimentalComposeUiApi::class)
    @Test fun compactEditorKeepsActionsFixedWhileSettingsScrollAndFadeClearsAtTheEnd() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var model: AppModel? = null
            var heightLimit by mutableFloatStateOf(420f)
            var maximumHeightPx = 0f
            try {
                scenario.onActivity { activity ->
                    val app = AppModel(activity)
                    model = app
                    seed(app.session, "_gimbalProgram", program)
                    app.liveGimbalPanel = LiveGimbalPanel.EDITOR
                    activity.setContent {
                        BoxWithConstraints(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                            val height = min(maxHeight.value, heightLimit)
                            maximumHeightPx = (height - 16f) * LocalDensity.current.density
                            key(heightLimit) {
                                val layout = LiveMonitorLayout.fit(maxWidth.value, height,
                                    0f, 0f, 0f, 0f, showsBottomBars = true)
                                LiveGimbalOverlay(app, layout, layout.feed, uiLocked = false)
                            }
                        }
                    }
                }
                for (height in listOf(420f, 280f)) {
                    scenario.onActivity {
                        heightLimit = height
                        seed(model!!.session, "_gimbalMoveRunning", true)
                        seed(model!!.session, "_gimbalMovePaused", true)
                    }
                    val settings = node("motion.settings") { state(it) == "More settings below" }
                    val header = bounds(node("motion.close"))
                    val stop = bounds(node("motion.startStop"))
                    val resume = bounds(node("motion.pauseResume"))
                    val restart = bounds(node("motion.restart"))
                    assertTrue(restart.right <= resume.left && resume.right <= stop.left,
                        "Paused actions stay ordered Restart, Resume, Stop")
                    assertTrue(stop.bottom - header.top <= maximumHeightPx + 1,
                        "Editor must fit the available height")
                    assertTrue(bounds(settings).bottom <= stop.top, "Fade belongs above the actions")
                    swipeSettings(scenario, bounds(settings))
                    scrollToEnd()
                    assertEquals(null, state(node("motion.settings")),
                        "The fade and its accessibility hint disappear at the end")
                    assertEquals(header, bounds(node("motion.close")))
                    assertEquals(stop, bounds(node("motion.startStop")))
                    assertEquals(resume, bounds(node("motion.pauseResume")))
                    assertEquals(restart, bounds(node("motion.restart")))
                    assertTrue(node("motion.loop").isVisibleToUser)
                    scenario.onActivity {
                        assertEquals(null, model!!.gimbalFloatCenter, "Settings scroll must not drag the window")
                        assertEquals(program, model!!.session.gimbalProgram.value)
                    }
                    click("motion.startStop")
                    scenario.onActivity { assertFalse(model!!.session.gimbalMoveRunning.value) }
                }
            } finally {
                scenario.onActivity { model?.close() }
            }
        }
    }

    private fun scrollToEnd() {
        repeat(20) {
            val settings = node("motion.settings")
            if (state(settings) != "More settings below") return
            assertTrue(settings.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            SystemClock.sleep(80)
        }
        error("Motion settings did not reach the end")
    }

    private fun bounds(node: AccessibilityNodeInfo) = Rect().also(node::getBoundsInScreen)
    private fun state(node: AccessibilityNodeInfo) = AccessibilityNodeInfoCompat.wrap(node).stateDescription?.toString()

    /** Begin within the visible fade to prove it cannot intercept the settings gesture. */
    private fun swipeSettings(scenario: ActivityScenario<BackdropRenderActivity>, rect: Rect) {
        val downAt = SystemClock.uptimeMillis()
        val x = rect.left + rect.width() * 0.15f
        val startY = rect.bottom - 8f
        val endY = rect.top + 16f
        for (step in 0..9) {
            val action = when (step) {
                0 -> MotionEvent.ACTION_DOWN
                9 -> MotionEvent.ACTION_UP
                else -> MotionEvent.ACTION_MOVE
            }
            val y = startY + (endY - startY) * step / 9
            scenario.onActivity { activity ->
                val decor = activity.window.decorView
                val location = IntArray(2)
                decor.getLocationOnScreen(location)
                val event = MotionEvent.obtain(downAt, SystemClock.uptimeMillis(), action,
                    x - location[0], y - location[1], 0)
                event.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
                try { decor.dispatchTouchEvent(event) } finally { event.recycle() }
            }
            SystemClock.sleep(16)
        }
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(80)
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
