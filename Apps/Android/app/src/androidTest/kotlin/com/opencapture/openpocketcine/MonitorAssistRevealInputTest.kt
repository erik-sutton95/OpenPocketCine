package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Text
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.layout.positionInRoot
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorAssistPalette
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Native pointer delivery into the production assist Popup.
 * Uses the public [MonitorAssistPalette] fixture so the same testAPK can fail
 * against a pre-fix install (hold-still drift) and pass after install -r.
 */
@RunWith(AndroidJUnit4::class)
class MonitorAssistRevealInputTest {
    @Test fun portraitDragFollowsFingerThroughHoldAndReverse() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = AssistRevealProbe()
            composePalette(scenario, probe, portrait = true)
            settle()
            val start = requireChevron(probe)
            val down = SystemClock.uptimeMillis()
            inject(MotionEvent.ACTION_DOWN, start, down)
            SystemClock.sleep(40)
            var y = start.y - 40f
            inject(MotionEvent.ACTION_MOVE, Offset(start.x, y), down)
            settle()
            // Establish the measuring origin away from the collapsed clamp.
            // Android may resample/predict the first movement crossing slop.
            y -= 60f
            inject(MotionEvent.ACTION_MOVE, Offset(start.x, y), down)
            SystemClock.sleep(80)
            inject(MotionEvent.ACTION_MOVE, Offset(start.x, y), down)
            SystemClock.sleep(80)
            val armedEdge = requireChevron(probe).y
            val armedFinger = y
            val trace = mutableListOf<String>()
            var worstError = 0f
            var previousEdge = armedEdge
            var backwards = 0f
            repeat(24) {
                y -= 10f
                inject(MotionEvent.ACTION_MOVE, Offset(start.x, y), down)
                SystemClock.sleep(16)
                var edge = 0f
                scenario.onActivity { edge = probe.screenChevron().y }
                backwards = maxOf(backwards, edge - previousEdge)
                previousEdge = edge
                val expected = armedEdge + y - armedFinger
                val error = abs(edge - expected)
                worstError = maxOf(worstError, error)
                trace += "finger=$y edge=$edge expected=$expected"
            }
            settle()
            val afterUp = requireChevron(probe)
            // Native popup position publication may trail a few input samples.
            // It must never reverse direction, oscillate, or accumulate drift.
            assertTrue(backwards <= 1f, "Steady upward input must not move the edge down: $trace")
            assertTrue(worstError <= 30f, "Edge must follow within three input samples; worst=$worstError trace=$trace")
            assertTrue(
                abs(afterUp.y - (armedEdge - 240f)) < 6f,
                "Drag distance must match finger distance: edge=$armedEdge after=${afterUp.y}",
            )
            repeat(12) {
                inject(MotionEvent.ACTION_MOVE, Offset(start.x, y), down)
                settle()
            }
            val held = requireChevron(probe)
            assertTrue(
                abs(held.y - afterUp.y) < 6f,
                "Stationary finger must not fight the plate: afterUp=${afterUp.y} held=${held.y}",
            )
            repeat(6) {
                y += 10f
                inject(MotionEvent.ACTION_MOVE, Offset(start.x, y), down)
                settle()
            }
            val reversed = requireChevron(probe)
            assertTrue(
                reversed.y > held.y + 20f,
                "Reversing down must lower the expanding edge: held=${held.y} reversed=${reversed.y}",
            )
            inject(MotionEvent.ACTION_UP, Offset(start.x, y), down)
            settle()
        }
    }

    @Test fun chevronTapToggles() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = AssistRevealProbe()
            composePalette(scenario, probe, portrait = true)
            settle()
            val start = requireChevron(probe)
            val down = SystemClock.uptimeMillis()
            inject(MotionEvent.ACTION_DOWN, start, down)
            inject(MotionEvent.ACTION_UP, start, down)
            settle()
            SystemClock.sleep(450)
            instrumentation.waitForIdleSync()
            val opened = requireChevron(probe)
            assertTrue(
                opened.y < start.y - 24f,
                "Tap must expand the plate: start=${start.y} opened=${opened.y}",
            )
        }
    }

    @Test fun compactPlateLeavesTapsAboveTheCollapsedSlot() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = AssistRevealProbe()
            composePalette(scenario, probe, portrait = true)
            settle()
            val start = requireChevron(probe)
            val above = Offset(
                probe.above.x + probe.aboveSize.width / 2f,
                probe.above.y + probe.aboveSize.height / 2f,
            )
            assertTrue(probe.aboveSize.width > 0, "Above control must lay out")
            assertTrue(above.y < start.y - 24f, "Above control must sit clear of the compact plate")
            val tap = SystemClock.uptimeMillis()
            inject(MotionEvent.ACTION_DOWN, above, tap)
            inject(MotionEvent.ACTION_UP, above, tap)
            settle()
            scenario.onActivity {
                assertEquals(1, probe.aboveClicks, "Collapsed popup must not steal taps above the slot")
            }
        }
    }

    @Test fun landscapeDragStillOpensFromTheChevron() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = AssistRevealProbe()
            composePalette(scenario, probe, portrait = false)
            settle()
            val start = requireChevron(probe)
            val down = SystemClock.uptimeMillis()
            inject(MotionEvent.ACTION_DOWN, start, down)
            var x = start.x
            repeat(10) {
                x += 12f
                inject(MotionEvent.ACTION_MOVE, Offset(x, start.y), down)
                settle()
            }
            val opened = requireChevron(probe)
            assertTrue(
                opened.x > start.x + 24f,
                "Landscape drag must keep expanding along +X: start=${start.x} opened=${opened.x}",
            )
            inject(MotionEvent.ACTION_UP, Offset(x, start.y), down)
            settle()
        }
    }

    @Test fun cancelledTouchAndLockNeverToggleThePalette() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = AssistRevealProbe()
            composePalette(scenario, probe, portrait = true)
            settle()
            val start = requireChevron(probe)
            var down = SystemClock.uptimeMillis()
            inject(MotionEvent.ACTION_DOWN, start, down)
            inject(MotionEvent.ACTION_CANCEL, start, down)
            SystemClock.sleep(400)
            assertTrue(abs(requireChevron(probe).y - start.y) < 2f, "Cancelled touch is not a tap")
            down = SystemClock.uptimeMillis()
            inject(MotionEvent.ACTION_DOWN, start, down)
            inject(MotionEvent.ACTION_MOVE, start.copy(y = start.y - 40f), down)
            settle()
            inject(MotionEvent.ACTION_MOVE, start.copy(y = start.y - 200f), down)
            settle()
            scenario.onActivity { probe.locked = true }
            settle()
            inject(MotionEvent.ACTION_UP, start.copy(y = start.y - 200f), down)
            scenario.onActivity { probe.locked = false }
            SystemClock.sleep(400)
            assertTrue(abs(requireChevron(probe).y - start.y) < 2f, "Lock cancels the drag and stays collapsed")
        }
    }

    private class AssistRevealProbe {
        var locked by mutableStateOf(false)
        var chevronHost: View? = null
        var chevron = Offset.Zero
        fun screenChevron(): Offset {
            val origin = IntArray(2)
            checkNotNull(chevronHost).getLocationOnScreen(origin)
            return chevron + Offset(origin[0] + chevronSize.width / 2f, origin[1] + chevronSize.height / 2f)
        }
        var chevronSize = IntSize.Zero
        var above = Offset.Zero
        var aboveSize = IntSize.Zero
        var aboveClicks = 0
    }

    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    private fun composePalette(
        scenario: ActivityScenario<BackdropRenderActivity>,
        probe: AssistRevealProbe,
        portrait: Boolean,
    ) {
        scenario.onActivity { activity ->
            activity.setContent {
                Box(Modifier.fillMaxSize()) {
                    Box(
                        Modifier.align(Alignment.BottomStart).offset(16.dp, (-160).dp).size(54.dp, 48.dp)
                            .onGloballyPositioned {
                                probe.above = it.positionOnScreen()
                                probe.aboveSize = it.size
                            }
                            .clickable { probe.aboveClicks++ },
                    ) { Text("above") }
                    Box(Modifier.align(Alignment.BottomStart).offset(16.dp, (-24).dp)) {
                        MonitorAssistPalette(
                            tools = listOf(
                                "Peaking", "False Color", "Zebra", "Waveform",
                                "Parade", "Histogram", "Vectorscope", "Guides",
                            ),
                            portrait = portrait, locked = probe.locked, isOn = { false },
                            title = { it }, label = { it }, hasOptions = { false },
                            onToggle = {}, onOptions = {},
                            glyph = { tool, _, modifier -> Text(tool.take(1), modifier) },
                            chevron = { _, _ ->
                                probe.chevronHost = LocalView.current
                                Box(Modifier.size(14.dp).onGloballyPositioned {
                                    probe.chevron = it.positionInRoot()
                                    probe.chevronSize = it.size
                                }) { Text(">") }
                            },
                        )
                    }
                }
            }
        }
        SystemClock.sleep(500)
        instrumentation.waitForIdleSync()
    }

    private fun requireChevron(probe: AssistRevealProbe): Offset {
        instrumentation.waitForIdleSync()
        var point = Offset.Zero
        instrumentation.runOnMainSync { point = probe.screenChevron() }
        assertTrue(probe.chevronSize.width > 0 && probe.chevronSize.height > 0, "Chevron must lay out")
        return point
    }

    private fun inject(action: Int, point: Offset, down: Long) {
        val event = MotionEvent.obtain(
            down, SystemClock.uptimeMillis(), action, point.x, point.y, 0,
        ).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
        instrumentation.uiAutomation.injectInputEvent(event, true)
        event.recycle()
    }

    private fun settle() {
        instrumentation.waitForIdleSync()
        SystemClock.sleep(32)
    }
}
