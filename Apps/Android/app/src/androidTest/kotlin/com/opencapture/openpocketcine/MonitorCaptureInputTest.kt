package com.opencapture.openpocketcine

import android.content.res.Configuration
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.View
import android.view.ViewGroup
import android.view.accessibility.AccessibilityNodeInfo
import androidx.lifecycle.Lifecycle
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.LocalMonitorReadoutRegions
import com.opencapture.monitorui.MonitorQuickControl
import com.opencapture.monitorui.MonitorQuickGestureOwner
import com.opencapture.monitorui.MonitorQuickPreview
import com.opencapture.monitorui.MonitorReadoutDismissBackdrop
import com.opencapture.monitorui.MonitorReadoutRegions
import com.opencapture.monitorui.monitorReadoutGesture
import com.opencapture.openpocketcine.session.CameraStatus
import kotlin.test.assertEquals
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Reuses the existing native activity/instrumentation harness; no Compose test dependency. */
@RunWith(AndroidJUnit4::class)
class MonitorCaptureInputTest {
    @Test fun recordHasOnlyShutterActionAndRespectsLock() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var shutters = 0
            var enabled by mutableStateOf(true)
            scenario.onActivity { activity ->
                activity.setContent {
                    Box(Modifier.fillMaxSize(), contentAlignment = androidx.compose.ui.Alignment.Center) {
                        RecordButton(recording = false, enabled = enabled, confirm = false, onClick = { shutters++ })
                    }
                }
            }
            settle()
            val target = nativeControlRect(scenario, "Start recording")
            fun hold() {
                val down = SystemClock.uptimeMillis()
                event(scenario, MotionEvent.ACTION_DOWN, target.center.x, target.center.y, down)
                SystemClock.sleep(750)
                event(scenario, MotionEvent.ACTION_UP, target.center.x, target.center.y, down)
                settle()
            }
            hold()
            scenario.onActivity {
                assertEquals(1, shutters, "Release uses only the shutter action; no mode shortcut")
            }
            settle()
            tap(scenario, target)
            scenario.onActivity {
                assertEquals(2, shutters, "Tap still operates shutter")
                enabled = false
            }
            settle()
            hold()
            scenario.onActivity {
                assertEquals(2, shutters, "Locked or busy control cannot operate shutter")
            }
        }
    }

    @Test fun portraitSettingsAndMediaReceiveFirstNativeTapThroughRetainedPicker() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var model: AppModel? = null
            try {
                scenario.onActivity { model = AppModel(it) }
                for (tablet in listOf(false, true)) {
                    val probe = NavigationProbe()
                    val layoutProbe = InputProbe()
                    scenario.onActivity { activity ->
                        activity.setContent { NavigationFixture(checkNotNull(model), probe, layoutProbe, tablet) }
                    }
                    awaitReady(scenario, layoutProbe)
                    for ((label, destination) in listOf("Settings" to LiveOperatorPanel.SETTINGS,
                        "Media" to LiveOperatorPanel.MEDIA)) {
                        val target = nativeControlRect(scenario, label)
                        val down = SystemClock.uptimeMillis()
                        event(scenario, MotionEvent.ACTION_DOWN, target.center.x, target.center.y, down)
                        SystemClock.sleep(60)
                        event(scenario, MotionEvent.ACTION_UP, target.center.x, target.center.y, down)
                        settle()
                        scenario.onActivity {
                            assertEquals(destination, model?.liveOperatorPanel,
                                "First $label tap, tablet=$tablet, sheet=${probe.sheet}, target=$target")
                            assertEquals(LiveSheet.ISO, probe.sheet, "Navigation must retain the picker")
                            // Simulate the destination's close callback without replacing the monitor host.
                            model?.liveOperatorPanel = null
                        }
                        settle()
                        // Disabling a mounted control retires its hole without requiring relayout.
                        scenario.onActivity { probe.navigationEnabled = false }
                        settle()
                        tap(scenario, target)
                        scenario.onActivity {
                            assertNull(model?.liveOperatorPanel, "Disabled navigation cannot bypass the backdrop")
                            assertNull(probe.sheet, "The disabled target becomes an outside-dismiss region")
                            probe.navigationEnabled = true
                            probe.sheet = LiveSheet.ISO
                        }
                        settle()
                    }
                    val oldSettings = nativeControlRect(scenario, "Settings")
                    scenario.onActivity { probe.showsNavigation = false }
                    settle()
                    tap(scenario, oldSettings)
                    scenario.onActivity {
                        assertNull(model?.liveOperatorPanel, "Unmounting navigation must remove its hole")
                        assertNull(probe.sheet)
                        probe.showsNavigation = true
                        probe.sheet = LiveSheet.ISO
                    }
                    settle()
                    tap(scenario, layoutProbe.blank)
                    scenario.onActivity { assertNull(probe.sheet, "Ordinary outside tap still dismisses") }
                }
            } finally { scenario.onActivity { model?.close() } }
        }
    }

    @Test fun backdropPreservesOriginalTapHoldAndReleaseAcrossPickerReplacement() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = InputProbe()
            scenario.onActivity { activity -> activity.setContent { InputFixture(probe) } }
            awaitReady(scenario, probe)
            tap(scenario, probe.top)
            scenario.onActivity { assertEquals("FORMAT", probe.sheet, "opens=${probe.opens}") }
            tap(scenario, probe.lower)
            scenario.onActivity { assertEquals("ISO", probe.sheet, "One tap replaces the top picker") }
            tap(scenario, probe.top)
            scenario.onActivity { assertEquals("FORMAT", probe.sheet, "Reverse replacement uses the same recognizer") }

            // A real DOWN reaches the lower node through the backdrop hole.
            val down = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, probe.lower.center.x, probe.lower.center.y, down)
            Thread.sleep(350)
            settle()
            scenario.onActivity {
                assertNull(probe.sheet, "Preview admission retires the full drawer")
                assertEquals(1, probe.previews)
                assertEquals(0, probe.commits)
            }
            event(scenario, MotionEvent.ACTION_UP, probe.lower.center.x, probe.lower.center.y, down)
            settle()
            scenario.onActivity { assertEquals(0, probe.commits, "Stationary hold never sends") }

            tap(scenario, probe.top)
            val dragDown = SystemClock.uptimeMillis()
            event(scenario, MotionEvent.ACTION_DOWN, probe.lower.center.x, probe.lower.center.y, dragDown)
            Thread.sleep(350)
            val endX = probe.lower.center.x - 56f * probe.density
            event(scenario, MotionEvent.ACTION_MOVE, endX, probe.lower.center.y, dragDown)
            scenario.onActivity { assertEquals(0, probe.commits, "Moving updates preview only") }
            event(scenario, MotionEvent.ACTION_UP, endX, probe.lower.center.y, dragDown)
            settle()
            scenario.onActivity { assertEquals(1, probe.commits, "Only original release commits") }

            tap(scenario, probe.top)
            tap(scenario, probe.blank)
            scenario.onActivity { assertNull(probe.sheet, "Ordinary picture tap still dismisses") }
            // Disabling a mounted readout removes its hole even with no layout change.
            scenario.onActivity { probe.sheet = "FORMAT"; probe.lowerEnabled = false }
            settle()
            tap(scenario, probe.lower)
            scenario.onActivity { assertNull(probe.sheet) }
        }
    }

    @Test fun actualCompactCameraPanelsMeasure128InBothOrientations() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var model: AppModel? = null
            try {
                scenario.onActivity { model = AppModel(it) }
                for (portrait in listOf(false, true)) {
                    for (sheet in listOf(LiveSheet.FORMAT, LiveSheet.COLOR, LiveSheet.MODE, LiveSheet.ISO)) {
                        var height = 0f
                        scenario.onActivity { activity ->
                            val config = Configuration(activity.resources.configuration).apply {
                                screenWidthDp = if (portrait) 400 else 800
                                screenHeightDp = if (portrait) 800 else 400
                            }
                            activity.setContent {
                                CompositionLocalProvider(LocalConfiguration provides config) {
                                    val density = LocalDensity.current.density
                                    Box(Modifier.fillMaxSize()) {
                                        Box(Modifier.width(320.dp).onGloballyPositioned { height = it.size.height / density }) {
                                            LiveControlSheet(sheet, checkNotNull(model), CameraStatus(), locked = false,
                                                onDismiss = {}, preview = MonitorQuickPreview(
                                                    MonitorQuickControl(listOf("24", "25", "30"), "25"), 1f))
                                        }
                                    }
                                }
                            }
                        }
                        settle()
                        scenario.onActivity { assertEquals(128f, height, .6f, "$sheet portrait=$portrait") }
                    }
                }
            } finally { scenario.onActivity { model?.close() } }
        }
    }

    private fun nativeControlRect(scenario: ActivityScenario<BackdropRenderActivity>, label: String): Rect {
        fun find(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.contentDescription?.toString() == label) return node
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let { find(it)?.let { found -> return found } }
            }
            return null
        }
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline = SystemClock.uptimeMillis() + 3_000
        var control: AccessibilityNodeInfo? = null
        // Window layout can settle before the accessibility service publishes it.
        while (control == null && SystemClock.uptimeMillis() < deadline) {
            control = automation.rootInActiveWindow?.let(::find)
            if (control == null) SystemClock.sleep(50)
        }
        val node = checkNotNull(control) { "Native control $label missing after window publication" }
        val bounds = android.graphics.Rect()
        node.getBoundsInScreen(bounds)
        var result = Rect.Zero
        scenario.onActivity { activity ->
            val host = composeHost(activity)
            val screen = IntArray(2)
            val window = IntArray(2)
            host.getLocationOnScreen(screen)
            host.getLocationInWindow(window)
            val dx = (window[0] - screen[0]).toFloat()
            val dy = (window[1] - screen[1]).toFloat()
            result = Rect(bounds.left + dx, bounds.top + dy, bounds.right + dx, bounds.bottom + dy)
        }
        return result
    }

    private fun tap(scenario: ActivityScenario<BackdropRenderActivity>, rect: Rect) {
        assertTrue(rect.width > 0f && rect.height > 0f, "Fixture must have laid out")
        val down = SystemClock.uptimeMillis()
        // One main-thread pass: 60ms eventTime, no composition/inset restart between down and up.
        scenario.onActivity { activity ->
            dispatchOnHost(activity, MotionEvent.ACTION_DOWN, rect.center.x, rect.center.y, down, down)
            dispatchOnHost(activity, MotionEvent.ACTION_UP, rect.center.x, rect.center.y, down, down + 60)
        }
        settle()
    }

    private fun event(scenario: ActivityScenario<BackdropRenderActivity>, action: Int,
        x: Float, y: Float, down: Long) {
        scenario.onActivity { activity ->
            dispatchOnHost(activity, action, x, y, down, SystemClock.uptimeMillis())
        }
    }

    private fun dispatchOnHost(activity: BackdropRenderActivity, action: Int, x: Float, y: Float,
        down: Long, eventTime: Long) {
        assertTrue(activity.hasWindowFocus(), "Window must have focus")
        val host = composeHost(activity)
        val windowOrigin = IntArray(2)
        val screenOrigin = IntArray(2)
        host.getLocationInWindow(windowOrigin)
        host.getLocationOnScreen(screenOrigin)
        val localX = x - windowOrigin[0]
        val localY = y - windowOrigin[1]
        assertTrue(localX in 0f..host.width.toFloat() && localY in 0f..host.height.toFloat(),
            "Pointer $localX,$localY outside host ${host.width}x${host.height}")
        val event = obtainTouch(down, eventTime, action, screenOrigin[0] + localX, screenOrigin[1] + localY)
        event.offsetLocation(-screenOrigin[0].toFloat(), -screenOrigin[1].toFloat())
        try {
            assertTrue(host.dispatchTouchEvent(event),
                "Compose host must accept $action at $localX,$localY")
        } finally { event.recycle() }
    }

    private fun composeHost(activity: BackdropRenderActivity): View {
        fun find(view: View): View? {
            if (view.javaClass.name == "androidx.compose.ui.platform.AndroidComposeView") return view
            if (view is ViewGroup) {
                for (i in 0 until view.childCount) find(view.getChildAt(i))?.let { return it }
            }
            return null
        }
        return checkNotNull(find(activity.window.decorView)) { "AndroidComposeView missing" }
    }

    private fun obtainTouch(down: Long, eventTime: Long, action: Int, x: Float, y: Float): MotionEvent {
        val properties = arrayOf(MotionEvent.PointerProperties().apply {
            id = 0
            toolType = MotionEvent.TOOL_TYPE_FINGER
        })
        val coords = arrayOf(MotionEvent.PointerCoords().apply {
            this.x = x
            this.y = y
            pressure = 1f
            size = 1f
        })
        return MotionEvent.obtain(down, eventTime, action, 1, properties, coords,
            0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
    }

    private fun awaitReady(scenario: ActivityScenario<BackdropRenderActivity>, probe: InputProbe) {
        scenario.moveToState(Lifecycle.State.RESUMED)
        val deadline = SystemClock.uptimeMillis() + 5_000
        var focused = false
        var laidOut = false
        var lastTop = Rect.Zero
        var stableFrames = 0
        while (SystemClock.uptimeMillis() < deadline) {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            scenario.onActivity { activity ->
                val host = runCatching { composeHost(activity) }.getOrNull()
                host?.requestFocus()
                if (!activity.hasWindowFocus()) activity.window.decorView.requestFocus()
                focused = activity.hasWindowFocus() && host != null && host.isAttachedToWindow
                laidOut = probe.top.width > 0f && probe.lower.width > 0f && probe.blank.width > 0f
                if (focused && laidOut && probe.top == lastTop) stableFrames++
                else { stableFrames = 0; lastTop = probe.top }
            }
            if (focused && laidOut && stableFrames >= 3) return
            Thread.sleep(32)
        }
        assertTrue(focused, "Window must have focus before injecting pointer events")
        assertTrue(laidOut, "Fixture must have laid out")
        assertTrue(stableFrames >= 3, "Fixture layout must settle before injecting pointer events")
    }

    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Thread.sleep(180)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }
}

private class InputProbe {
    var sheet by mutableStateOf<String?>(null)
    var lowerEnabled by mutableStateOf(true)
    var opens = 0
    var previews = 0
    var commits = 0
    var density = 1f
    var top = Rect.Zero
    var lower = Rect.Zero
    var blank = Rect.Zero
}

private class NavigationProbe {
    var sheet by mutableStateOf<LiveSheet?>(LiveSheet.ISO)
    var navigationEnabled by mutableStateOf(true)
    var showsNavigation by mutableStateOf(true)
}

@Composable
private fun NavigationFixture(model: AppModel, probe: NavigationProbe, layoutProbe: InputProbe, tablet: Boolean) {
    val regions = remember { MonitorReadoutRegions() }
    val currentConfig = LocalConfiguration.current
    val config = remember(currentConfig, tablet) {
        Configuration(currentConfig).apply {
            screenWidthDp = if (tablet) 800 else 400
            screenHeightDp = if (tablet) 1200 else 800
        }
    }
    CompositionLocalProvider(LocalMonitorReadoutRegions provides regions, LocalConfiguration provides config) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val width = maxWidth.value
            val height = maxHeight.value
            val floor = height - 100f
            // Production portrait controls and production picker host in their original sibling order.
            Box(Modifier.fillMaxSize()) {
                Box(Modifier.offset(y = floor.dp).size(width.dp, 100.dp).onGloballyPositioned {
                    layoutProbe.top = it.boundsInWindow()
                    layoutProbe.lower = it.boundsInWindow()
                }) {
                    LivePortraitSystemBar(model, model.assist, CameraStatus(), uiLocked = false,
                        onLock = {}, chromeInteractive = probe.navigationEnabled, showsLock = true,
                        showsRecord = true, showsMedia = probe.showsNavigation,
                        showsSettings = probe.showsNavigation, controlBusy = false)
                }
            }
            Box(Modifier.offset(2.dp, maxHeight - 6.dp).size(4.dp)
                .onGloballyPositioned { layoutProbe.blank = it.boundsInWindow() })
            probe.sheet?.let {
                LivePickerHost(it, width, height, 0f, 0f, 0f, 0f, floor,
                    model, CameraStatus(), false, { probe.sheet = it })
            }
        }
    }
}

@Composable
private fun InputFixture(probe: InputProbe) {
    val regions = remember { MonitorReadoutRegions() }
    val owner = remember { MonitorQuickGestureOwner() }
    probe.density = LocalDensity.current.density
    CompositionLocalProvider(LocalMonitorReadoutRegions provides regions) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            @Composable fun readout(id: String, modifier: Modifier, enabled: Boolean) {
                Text(id, modifier.monitorReadoutGesture(
                    MonitorQuickControl(listOf("24", "25", "30"), "24"), enabled,
                    onOpen = { probe.opens++; probe.sheet = if (probe.sheet == id) null else id },
                    onCommit = { _, _ -> probe.commits++ }, bottomClearanceDp = 0f,
                    owner = owner, ownerId = id,
                    previewContent = { _, _ -> Box(Modifier.size(120.dp, 128.dp).background(Color.Black)) },
                    onPreviewBegin = { probe.previews++; probe.sheet = null }))
            }
            readout("FORMAT", Modifier.offset(20.dp, 30.dp).size(120.dp, 44.dp)
                .onGloballyPositioned { probe.top = it.boundsInWindow() }, true)
            readout("ISO", Modifier.offset(20.dp, maxHeight - 70.dp).size(120.dp, 44.dp)
                .onGloballyPositioned { probe.lower = it.boundsInWindow() }, probe.lowerEnabled)
            Box(Modifier.offset(maxWidth - 70.dp, 100.dp).size(30.dp)
                .onGloballyPositioned { probe.blank = it.boundsInWindow() })
            if (probe.sheet != null) MonitorReadoutDismissBackdrop(onDismiss = { probe.sheet = null })
        }
    }
}
