package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorClipCard
import com.opencapture.monitorui.MonitorClipValue
import com.opencapture.monitorui.MonitorMediaHitTarget
import com.opencapture.monitorui.MonitorMediaSelectionHost
import com.opencapture.monitorui.MonitorPalette
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Native pointer and accessibility delivery into the production media selection host. */
@RunWith(AndroidJUnit4::class)
class MonitorMediaSelectionInputTest {
    @Test fun holdSweepSelectsRangeThenSelectedOriginDeselects() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = SelectionProbe()
            setCatalog(scenario, probe, count = 4)
            val first = center("Clip-0", probe)
            val last = center("Clip-3", probe)
            val down = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, down)
            SystemClock.sleep(400)
            settle()
            event(scenario, MotionEvent.ACTION_MOVE, last, down)
            settle()
            event(scenario, MotionEvent.ACTION_UP, last, down)
            settle()
            scenario.onActivity {
                assertTrue(probe.selecting)
                assertEquals(setOf("0", "1", "2", "3"), probe.selected)
                assertTrue(probe.opened.isEmpty())
            }

            val deselectDown = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, deselectDown)
            SystemClock.sleep(400)
            event(scenario, MotionEvent.ACTION_MOVE, last, deselectDown)
            settle()
            event(scenario, MotionEvent.ACTION_UP, last, deselectDown)
            settle()
            scenario.onActivity {
                assertTrue(probe.selecting)
                assertTrue(probe.selected.isEmpty())
            }
        }
    }

    @Test fun stationaryEdgeScrollStopsOnLift() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = SelectionProbe()
            setCatalog(scenario, probe, count = 16)
            val first = center("Clip-0", probe)
            val edge = Offset(probe.host.center.x, probe.host.bottom - 8f)
            val down = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, down)
            SystemClock.sleep(400)
            settle()
            event(scenario, MotionEvent.ACTION_MOVE, edge, down)
            SystemClock.sleep(1500)
            settle()
            var growing = 0
            scenario.onActivity { growing = probe.selected.size }
            assertTrue(growing > 1, "Edge autoscroll must add clips while held, size=$growing")
            event(scenario, MotionEvent.ACTION_UP, edge, down)
            settle()
            SystemClock.sleep(400)
            settle()
            scenario.onActivity {
                assertEquals(growing, probe.selected.size, "Lift must stop the edge pump")
            }
        }
    }

    @Test fun favoriteTapDoesNotOpenAndSemanticsOpenAndSelect() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = SelectionProbe()
            setCatalog(scenario, probe, count = 3)
            val favorite = Offset(probe.bounds.getValue("0").right - 22f, probe.bounds.getValue("0").center.y)
            val tap = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, favorite, tap)
            SystemClock.sleep(40)
            event(scenario, MotionEvent.ACTION_UP, favorite, tap)
            settle()
            scenario.onActivity {
                assertEquals(1, probe.favorites)
                assertTrue(probe.opened.isEmpty())
                assertFalse(probe.selecting)
            }

            assertTrue(performAccessibility("Clip-0", AccessibilityNodeInfo.ACTION_CLICK))
            settle()
            scenario.onActivity { assertEquals(listOf("0"), probe.opened) }

            assertTrue(performAccessibility("Clip-1", AccessibilityNodeInfo.ACTION_LONG_CLICK))
            settle()
            scenario.onActivity {
                assertTrue(probe.selecting)
                assertEquals(setOf("1"), probe.selected)
            }

            assertTrue(performAccessibility("Clip-1", AccessibilityNodeInfo.ACTION_CLICK))
            settle()
            scenario.onActivity { assertTrue(probe.selected.isEmpty()) }
        }
    }

    @Test fun selectingVerticalSwipeDoesNotChangeSelection() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = SelectionProbe()
            setCatalog(scenario, probe, count = 4)
            val first = center("Clip-0", probe)
            val last = center("Clip-3", probe)
            val down = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, down)
            SystemClock.sleep(40)
            event(scenario, MotionEvent.ACTION_MOVE, last, down)
            settle()
            event(scenario, MotionEvent.ACTION_UP, last, down)
            settle()
            scenario.onActivity {
                assertFalse(probe.selecting)
                assertTrue(probe.selected.isEmpty())
                assertTrue(probe.opened.isEmpty())
            }
        }
    }

    @Test fun selectingModeVerticalSwipePreservesSelectionAndSidewaysSweep() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = SelectionProbe()
            setCatalog(scenario, probe, count = 8)
            val first = center("Clip-0", probe)
            val last = center("Clip-3", probe)
            val hold = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, hold)
            SystemClock.sleep(400)
            settle()
            event(scenario, MotionEvent.ACTION_UP, first, hold)
            settle()
            scenario.onActivity {
                assertTrue(probe.selecting)
                assertEquals(setOf("0"), probe.selected)
                assertTrue(probe.opened.isEmpty())
            }

            val swipe = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, swipe)
            SystemClock.sleep(40)
            event(scenario, MotionEvent.ACTION_MOVE, last, swipe)
            settle()
            event(scenario, MotionEvent.ACTION_UP, last, swipe)
            settle()
            scenario.onActivity {
                assertTrue(probe.selecting)
                assertEquals(setOf("0"), probe.selected)
                assertTrue(probe.opened.isEmpty())
            }

            val sideways = Offset(first.x + 80f, first.y + 4f)
            val sweep = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, sweep)
            SystemClock.sleep(40)
            event(scenario, MotionEvent.ACTION_MOVE, sideways, sweep)
            settle()
            event(scenario, MotionEvent.ACTION_MOVE, last, sweep)
            settle()
            event(scenario, MotionEvent.ACTION_UP, last, sweep)
            settle()
            scenario.onActivity {
                assertTrue(probe.selecting)
                assertTrue(probe.selected.isEmpty())
                assertTrue(probe.opened.isEmpty())
            }
        }
    }

    @Test fun pauseCancelsAnActiveSweep() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = SelectionProbe()
            setCatalog(scenario, probe, count = 16)
            val first = center("Clip-0", probe)
            val edge = Offset(probe.host.center.x, probe.host.bottom - 8f)
            val down = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, first, down)
            SystemClock.sleep(400)
            event(scenario, MotionEvent.ACTION_MOVE, edge, down)
            SystemClock.sleep(400)
            settle()
            var before = 0
            scenario.onActivity { before = probe.selected.size }
            scenario.moveToState(Lifecycle.State.STARTED)
            settle()
            SystemClock.sleep(800)
            settle()
            scenario.onActivity {
                assertEquals(before, probe.selected.size, "Pause must stop the edge pump")
            }
            event(scenario, MotionEvent.ACTION_UP, edge, down)
        }
    }

    private fun setCatalog(scenario: ActivityScenario<BackdropRenderActivity>, probe: SelectionProbe, count: Int) {
        val ids = (0 until count).map { it.toString() }
        scenario.onActivity { activity ->
            activity.setContent {
                val listState = rememberLazyListState()
                var selecting by remember { mutableStateOf(false) }
                var selected by remember { mutableStateOf(setOf<String>()) }
                probe.selecting = selecting
                probe.selected = selected
                Box(Modifier.fillMaxSize().background(MonitorPalette.background).onGloballyPositioned {
                    probe.host = it.boundsInWindow()
                }) {
                    MonitorMediaSelectionHost(
                        ids = ids,
                        selecting = selecting,
                        selected = selected,
                        scroll = listState,
                        onOpen = { probe.opened = probe.opened + it },
                        onSelectionChange = { nextSelecting, nextIds ->
                            selecting = nextSelecting
                            selected = nextIds
                            probe.selecting = nextSelecting
                            probe.selected = nextIds
                        },
                        modifier = Modifier.fillMaxSize(),
                        sessionKey = "fixture/list/medium/newest",
                    ) { registry ->
                        LazyColumn(Modifier.fillMaxSize(), state = listState) {
                            items(ids, key = { it }) { id ->
                                MonitorMediaHitTarget(
                                    registry, id,
                                    Modifier.fillMaxWidth().onGloballyPositioned {
                                        probe.bounds[id] = it.boundsInWindow()
                                    },
                                ) {
                                    MonitorClipCard(
                                        MonitorClipValue(id, "Clip-$id", "4K", null, "CAM", id == "0"),
                                        list = true, selecting = selecting, selected = id in selected,
                                        onOpen = { probe.opened = probe.opened + id },
                                        onSelect = {
                                            if (selecting) {
                                                val next = if (id in selected) selected - id else selected + id
                                                selected = next
                                                probe.selected = next
                                            } else {
                                                selecting = true
                                                selected = setOf(id)
                                                probe.selecting = true
                                                probe.selected = setOf(id)
                                            }
                                        },
                                        onFavorite = { probe.favorites += 1 },
                                        clicks = false,
                                    ) {}
                                }
                            }
                        }
                    }
                }
            }
        }
        repeat(8) { settle() }
        scenario.onActivity {
            assertTrue(probe.host.width > 0f && probe.bounds.size >= minOf(3, count))
        }
    }

    private fun center(title: String, probe: SelectionProbe): Offset {
        val id = title.removePrefix("Clip-")
        val rect = probe.bounds.getValue(id)
        return rect.center
    }

    private fun event(scenario: ActivityScenario<BackdropRenderActivity>, action: Int, point: Offset, down: Long) {
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

    private fun performAccessibility(description: String, action: Int): Boolean {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        instrumentation.waitForIdleSync()
        fun search(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            val matches = node.contentDescription?.toString() == description
            val actionable = when (action) {
                AccessibilityNodeInfo.ACTION_LONG_CLICK -> node.isLongClickable
                else -> node.isClickable
            }
            if (matches && actionable) return node
            var fallback: AccessibilityNodeInfo? = null
            if (matches) fallback = node
            for (index in 0 until node.childCount) {
                search(node.getChild(index))?.let { return it }
            }
            return fallback
        }
        val found = search(instrumentation.uiAutomation.rootInActiveWindow) ?: return false
        return found.performAction(action)
    }

    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(32)
    }

    private class SelectionProbe {
        var selecting = false
        var selected = emptySet<String>()
        var opened = emptyList<String>()
        var favorites = 0
        var host = Rect.Zero
        val bounds = mutableMapOf<String, Rect>()
    }
}
