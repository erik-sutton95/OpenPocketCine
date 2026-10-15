package com.opencapture.openpocketcine
import androidx.compose.ui.unit.IntOffset

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
                var anchorSize = androidx.compose.ui.unit.IntSize.Zero
                var target = Offset.Zero
                var cell = androidx.compose.ui.geometry.Rect.Zero
                var density = 1f
                val canvasOffset = androidx.compose.runtime.mutableStateOf(Offset(20f, 100f))
                var toggles = 0
                scenario.onActivity { activity ->
                    density = activity.resources.displayMetrics.density
                    activity.setContent {
                        Box(Modifier.fillMaxSize()) {
                            Box(Modifier.offset {
                                IntOffset(canvasOffset.value.x.dp.roundToPx(), canvasOffset.value.y.dp.roundToPx())
                            }
                                .size(94.dp, 119.dp).onGloballyPositioned {
                                    anchor = it.positionOnScreen(); anchorSize = it.size
                                }) {
                                MonitorAssistPalette(
                                    tools = listOf("Peaking", "False Color"), portrait = portrait,
                                    locked = false, isOn = { false }, title = { it }, label = { it },
                                    hasOptions = { false }, onToggle = { toggles++ }, onOptions = {},
                                    glyph = { tool, _, modifier ->
                                        Text("+", modifier.onGloballyPositioned {
                                            if (tool == "Peaking") target = it.positionOnScreen() +
                                                Offset(it.size.width / 2f, it.size.height / 2f)
                                            if (tool == "Peaking") {
                                                val input = checkNotNull(it.parentLayoutCoordinates)
                                                val location = input.positionOnScreen()
                                                cell = androidx.compose.ui.geometry.Rect(location,
                                                    androidx.compose.ui.geometry.Size(input.size.width.toFloat(), input.size.height.toFloat()))
                                            }
                                        })
                                    }, chevron = { _, _ -> Text(">") },
                                )
                            }
                        }
                    }
                }
                SystemClock.sleep(700)
                instrumentation.waitForIdleSync()
                val firstCell = cell
                var initialAnchor = Offset.Zero
                scenario.onActivity {
                    initialAnchor = anchor
                    assertTrue(firstCell.width >= 44 * density && firstCell.height >= 44 * density,
                        "Measured parent must be the native input cell, not the smaller glyph")
                    assertTrue(firstCell.left >= anchor.x - 2 && firstCell.right <= anchor.x + anchorSize.width + 2,
                        "Native cell must remain within the offset popup slot: cell=$firstCell anchor=$anchor")
                    assertEquals(anchor.x + 4f * density, firstCell.left, 2f,
                        "Native input cell must retain the slot leading inset")
                    assertEquals(firstCell.center.x, target.x, 2f, "Glyph must stay centered in its actual native input cell")
                    assertTrue(firstCell.contains(target), "Glyph must belong to the native clicked cell")
                    assertTrue(target.y > anchor.y && target.y < anchor.y + anchorSize.height,
                        "Popup must follow the offset slot: anchor=$anchor target=$target")
                    canvasOffset.value = Offset(60f, 140f)
                }
                val movedDeadline = SystemClock.uptimeMillis() + 3_000
                var moved = false
                while (SystemClock.uptimeMillis() < movedDeadline && !moved) {
                    instrumentation.waitForIdleSync()
                    scenario.onActivity {
                        val dx = anchor.x - initialAnchor.x
                        val dy = anchor.y - initialAnchor.y
                        moved = kotlin.math.abs(dx - 40f * density) <= 2f
                            && kotlin.math.abs(dy - 40f * density) <= 2f
                            && kotlin.math.abs(cell.left - firstCell.left - dx) <= 2f
                            && kotlin.math.abs(cell.top - firstCell.top - dy) <= 2f
                    }
                    if (!moved) SystemClock.sleep(16)
                }
                assertTrue(moved, "Actual moved canvas and native popup cell must settle within 3 seconds")
                val movedCell = cell
                scenario.onActivity {
                    assertEquals(anchor.x - initialAnchor.x, (movedCell.left - firstCell.left).toFloat(), 2f,
                        "Separate popup window must follow the consumer canvas horizontal offset")
                    assertEquals(anchor.y - initialAnchor.y, (movedCell.top - firstCell.top).toFloat(), 2f,
                        "Separate popup window must follow the consumer canvas vertical offset")
                    assertEquals(movedCell.center.x, target.x, 2f)
                }
                SystemClock.sleep(250)
                assertEquals(movedCell, cell, "Popup anchor must remain stable")
                val down = SystemClock.uptimeMillis()
                for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
                    val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action,
                        target.x, target.y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
                    instrumentation.uiAutomation.injectInputEvent(event, true)
                    event.recycle()
                }
                instrumentation.waitForIdleSync()
                scenario.onActivity { assertEquals(1, toggles, "Native tap must reach the popup tool") }
            }
        }
    }
}
