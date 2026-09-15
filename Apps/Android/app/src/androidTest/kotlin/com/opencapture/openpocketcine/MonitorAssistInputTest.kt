package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.monitorReadoutShadow
import com.opencapture.monitorui.MonitorAssistPalette
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Exercises the real separate popup window, including its offset parent and hit delivery. */
@RunWith(AndroidJUnit4::class)
class MonitorAssistInputTest {
    @Test fun readoutShadowPreservesStatusRowAlignment() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var left = 0f
            var right = 0f
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.size(300.dp, 44.dp).monitorReadoutShadow()) {
                        Text("STBY", Modifier.align(Alignment.CenterStart)
                            .onGloballyPositioned { left = it.positionOnScreen().x })
                        Text("REC SETUP", Modifier.align(Alignment.CenterEnd)
                            .onGloballyPositioned { right = it.positionOnScreen().x + it.size.width })
                    }
                }
            }
            SystemClock.sleep(350)
            instrumentation.waitForIdleSync()
            scenario.onActivity {
                assertEquals(300f * density, right - left, 2f,
                    "The shadow must preserve the fixed row width and opposite edge alignment")
            }
        }
    }

    @Test fun compactPopupKeepsItsOffsetAnchorAndReceivesATap() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            for (portrait in listOf(false, true)) {
                var anchor = Offset.Zero
                var target = Offset.Zero
                var density = 1f
                var toggles = 0
                scenario.onActivity { activity ->
                    density = activity.resources.displayMetrics.density
                    activity.setContent {
                        Box(Modifier.fillMaxSize()) {
                            Box(Modifier.offset(20.dp, 100.dp).size(94.dp, 119.dp)
                                .onGloballyPositioned { anchor = it.positionOnScreen() }) {
                                MonitorAssistPalette(
                                    tools = listOf("Peaking", "False Color"), portrait = portrait,
                                    locked = false, isOn = { false }, title = { it }, label = { it },
                                    hasOptions = { false }, onToggle = { toggles++ }, onOptions = {},
                                    glyph = { tool, _, modifier ->
                                        Text("+", modifier.onGloballyPositioned {
                                            if (tool == "Peaking") target = it.positionOnScreen() +
                                                Offset(it.size.width / 2f, it.size.height / 2f)
                                        })
                                    }, chevron = { _, _ -> Text(">") },
                                )
                            }
                        }
                    }
                }
                SystemClock.sleep(700)
                instrumentation.waitForIdleSync()
                var initial = Offset.Zero
                scenario.onActivity {
                    initial = target
                    assertEquals(anchor.x + 31f * density, target.x, 2f, "Popup must retain the slot leading edge")
                    assertTrue(target.y > anchor.y && target.y < anchor.y + 119 * density,
                        "Popup must follow the offset slot: anchor=$anchor target=$target")
                }
                SystemClock.sleep(250)
                scenario.onActivity { assertEquals(initial, target, "Popup anchor must remain stable") }
                val down = SystemClock.uptimeMillis()
                for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
                    val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                        initial.x, initial.y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
                    instrumentation.uiAutomation.injectInputEvent(event, true)
                    event.recycle()
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { assertEquals(1, toggles, "Native tap must reach the popup tool") }
            }
        }
    }
}
