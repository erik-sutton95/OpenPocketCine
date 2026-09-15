package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.MotionEvent
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.settings.GlassPillSlider
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercise real settings input inside a scroll page without changing camera preferences. */
@RunWith(AndroidJUnit4::class)
class SettingsSliderInputTest {
    @Test fun horizontalInputUsesCurrentCallbackAndVerticalInputScrollsThePage() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var value by mutableIntStateOf(50)
            var handler by mutableIntStateOf(0)
            val calls = intArrayOf(0, 0)
            var bounds = Rect.Zero
            var scrollPosition = { 0 }
            scenario.onActivity { activity ->
                activity.setContent {
                    val scroll = rememberScrollState()
                    scrollPosition = { scroll.value }
                    val currentHandler = handler
                    Column(Modifier.fillMaxSize().verticalScroll(scroll).padding(horizontal = 24.dp)) {
                        Spacer(Modifier.height(100.dp))
                        GlassPillSlider(value, 0..100, onChange = {
                            calls[currentHandler]++
                            value = it
                        }, modifier = Modifier.onGloballyPositioned { bounds = it.boundsInWindow() })
                        Spacer(Modifier.height(1600.dp))
                    }
                }
            }
            settle()
            scenario.onActivity { handler = 1 }
            settle()
            assertTrue(bounds.width > 0f)
            drag(scenario, bounds.left + bounds.width * .2f, bounds.center.y,
                bounds.left + bounds.width * .8f, bounds.center.y)
            scenario.onActivity {
                assertEquals(0, calls[0], "Recomposition must retire the old callback")
                assertTrue(calls[1] > 0 && value > 70, "Horizontal drag adjusts the setting")
            }
            val priorCalls = calls[1]
            val priorValue = value
            drag(scenario, bounds.center.x, bounds.center.y,
                bounds.center.x, bounds.center.y - bounds.height * 2f)
            scenario.onActivity {
                assertTrue(scrollPosition() > 0, "Vertical drag must reach the parent scroller")
                assertEquals(priorCalls, calls[1], "Scrolling must not adjust the slider")
                assertEquals(priorValue, value)
            }
        }
    }

    private fun drag(scenario: ActivityScenario<BackdropRenderActivity>, x0: Float, y0: Float, x1: Float, y1: Float) {
        val down = SystemClock.uptimeMillis()
        for (step in 0..12) {
            val fraction = step / 12f
            val action = when (step) { 0 -> MotionEvent.ACTION_DOWN; 12 -> MotionEvent.ACTION_UP; else -> MotionEvent.ACTION_MOVE }
            scenario.onActivity { activity ->
                val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                    x0 + (x1 - x0) * fraction, y0 + (y1 - y0) * fraction, 0)
                activity.window.decorView.dispatchTouchEvent(event)
                event.recycle()
            }
            Thread.sleep(18)
        }
        settle()
    }

    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Thread.sleep(160)
    }
}
