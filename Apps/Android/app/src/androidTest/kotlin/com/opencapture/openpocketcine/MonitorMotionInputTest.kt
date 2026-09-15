package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.MotionEvent
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.detectDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorMotionDismissBackdrop
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real pointer delivery through the production backdrop and floating-window gesture. */
@RunWith(AndroidJUnit4::class)
class MonitorMotionInputTest {
    @Test fun editorDragStaysLocalAndOriginalStickRemainsUsableWhileExpanded() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var model: AppModel? = null
            var panel = Rect.Zero
            var stick = Rect.Zero
            var editorCompositions = 0
            var childClicks = 0
            var stickMoves = 0
            var stickReleases = 0
            var dismissals = 0
            try {
                scenario.onActivity { activity ->
                    val app = AppModel(activity)
                    model = app
                    activity.setContent {
                        Box(Modifier.fillMaxSize()) {
                            Box(Modifier.offset(200.dp, 350.dp).size(100.dp)
                                .background(Color.Blue)
                                .onGloballyPositioned { stick = it.boundsInWindow() }
                                .pointerInput(Unit) {
                                    detectDragGestures(onDragEnd = { stickReleases++ }) { change, _ ->
                                        change.consume(); stickMoves++
                                    }
                                })
                            MonitorMotionDismissBackdrop(
                                Rect(0f, 0f, 320f, 600f), Rect(200f, 350f, 300f, 450f),
                                onDismiss = { dismissals++ },
                            )
                            GimbalFloatMove(app, 160f, 80f, ChromeRect(0f, 0f, 320f, 600f),
                                defaultTopCenter = Offset(110f, 50f)) {
                                editorCompositions++
                                Box(Modifier.size(160.dp, 80.dp).background(Color.Red)
                                    .onGloballyPositioned { panel = it.boundsInWindow() }
                                    .clickable { childClicks++ }) { Text("Motion editor") }
                            }
                        }
                    }
                }
                settle()
                scenario.onActivity { assertTrue(panel.width > 0 && stick.width > 0) }
                val originalPanel = panel
                val down = SystemClock.uptimeMillis()
                event(scenario, MotionEvent.ACTION_DOWN, panel.center, down)
                SystemClock.sleep(20)
                event(scenario, MotionEvent.ACTION_MOVE, originalPanel.center + Offset(0f, 40f), down)
                settle()
                scenario.onActivity {
                    assertTrue(panel.top > originalPanel.top + 20f, "Editor must move before any hold")
                }
                val before = editorCompositions
                repeat(20) { index ->
                    event(scenario, MotionEvent.ACTION_MOVE,
                        originalPanel.center + Offset(0f, 40f + (index + 1) * 3f), down)
                    settle()
                    scenario.onActivity { assertNull(model?.gimbalFloatCenter) }
                }
                scenario.onActivity {
                    assertTrue(panel.top > originalPanel.top + 40f, "Window must visibly follow the pointer")
                    assertEquals(before, editorCompositions, "Moving must not recompose editor content")
                }
                event(scenario, MotionEvent.ACTION_UP, originalPanel.center + Offset(0f, 100f), down)
                settle()
                scenario.onActivity {
                    assertTrue(model?.gimbalFloatCenter != null)
                    assertEquals(0, childClicks, "Dragging must not activate an editor control")
                }

                val stickDown = SystemClock.uptimeMillis()
                event(scenario, MotionEvent.ACTION_DOWN, stick.center, stickDown)
                repeat(5) { index ->
                    event(scenario, MotionEvent.ACTION_MOVE, stick.center + Offset((index + 1) * 8f, 0f), stickDown)
                }
                event(scenario, MotionEvent.ACTION_UP, stick.center + Offset(40f, 0f), stickDown)
                settle()
                scenario.onActivity {
                    assertTrue(stickMoves > 0, "Original stick receives movement through the backdrop")
                    assertEquals(1, stickReleases)
                    assertEquals(0, dismissals, "Stick use must keep the editor expanded")
                }
            } finally { scenario.onActivity { model?.close() } }
        }
    }

    private fun event(scenario: ActivityScenario<BackdropRenderActivity>, action: Int,
        point: Offset, down: Long) {
        scenario.onActivity { activity ->
            val decor = activity.window.decorView
            val location = IntArray(2)
            decor.getLocationInWindow(location)
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                point.x - location[0], point.y - location[1], 0)
            event.source = android.view.InputDevice.SOURCE_TOUCHSCREEN
            try { decor.dispatchTouchEvent(event) } finally { event.recycle() }
        }
    }

    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(32)
    }
}
