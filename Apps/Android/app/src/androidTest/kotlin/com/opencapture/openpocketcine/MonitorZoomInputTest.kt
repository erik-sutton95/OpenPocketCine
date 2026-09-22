package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import android.view.accessibility.AccessibilityWindowInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.material3.Text
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.platform.LocalViewConfiguration
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorMotion
import com.opencapture.monitorui.MonitorZoomDisc
import com.opencapture.monitorui.MonitorZoomGeometry
import java.util.Collections
import java.util.Locale
import java.util.concurrent.atomic.AtomicInteger
import kotlin.math.abs
import kotlin.math.hypot
import kotlin.math.ln
import kotlin.math.max
import kotlin.math.round
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Native pointer delivery into the production zoom popup window.
 * Activity decor dispatch cannot reach a focusable Popup; UiAutomation must inject.
 */
@RunWith(AndroidJUnit4::class)
class MonitorZoomInputTest {
    @Test fun extensionStartStaysUnarmedAndDiscStartPausesWithoutJumpWhilePopupOwnsPointer() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val probe = ZoomNativeProbe()
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.onActivity { activity ->
                activity.setContent {
                    val configuration = LocalConfiguration.current
                    val density = LocalDensity.current
                    val view = LocalView.current
                    val slop = LocalViewConfiguration.current.touchSlop
                    probe.density = density.density
                    probe.fontScale = density.fontScale
                    probe.screenWidthDp = configuration.screenWidthDp
                    probe.screenHeightDp = configuration.screenHeightDp
                    probe.touchSlop = slop
                    probe.layout = MonitorZoomGeometry.layout(
                        configuration.screenWidthDp.toFloat(),
                        configuration.screenHeightDp.toFloat(),
                        probe.trailingInsetDp,
                    )
                    val screen = IntArray(2)
                    view.getLocationOnScreen(screen)
                    probe.viewScreen = Offset(screen[0].toFloat(), screen[1].toFloat())
                    activity.window.decorView.getLocationOnScreen(screen)
                    probe.windowScreen = Offset(screen[0].toFloat(), screen[1].toFloat())
                    probe.composed = true
                    Box(Modifier.fillMaxSize().pointerInput(Unit) {
                        awaitPointerEventScope {
                            while (true) {
                                val event = awaitPointerEvent(PointerEventPass.Initial)
                                probe.underEvents.addAndGet(event.changes.size)
                                if (event.changes.any { it.pressed && !it.previousPressed }) {
                                    probe.underDowns.incrementAndGet()
                                }
                            }
                        }
                    }.clickable { probe.underClicks.incrementAndGet() }) {
                        Text("underlying zoom control")
                        MonitorZoomDisc(
                            initial = 2.0,
                            maximum = 12.0,
                            label = { value -> String.format(Locale.US, "%.2f", value) },
                            onChange = { probe.changes.add(it) },
                            onDismiss = { probe.dismissals++ },
                            trailingInset = probe.trailingInsetDp,
                        )
                    }
                }
            }
            awaitPopup(scenario, probe)
            val pixel = MonitorZoomGeometry(
                probe.layout.radius * probe.density,
                probe.layout.edgeExtension * probe.density,
            )
            assertTrue(pixel.radius > 0f && pixel.edgeExtension >= probe.trailingInsetDp * probe.density - 1f,
                "Forced 48dp extrusion must be measurable: $pixel density=${probe.density} layout=${probe.layout} viewport=${probe.screenWidthDp}x${probe.screenHeightDp}")
            val discBounds = discScreenBounds(probe, pixel)
            fun screen(local: Offset) = Offset(discBounds.left + local.x, discBounds.top + local.y)

            val extensionStart = Offset(pixel.radius + pixel.edgeExtension * 0.5f, pixel.radius)
            val discThroughMidpoint = Offset(pixel.radius * 0.40f, pixel.radius)
            assertFalse(pixel.canStartZoom(extensionStart.x, extensionStart.y), "extension midpoint must not arm")
            assertTrue(pixel.contains(extensionStart.x, extensionStart.y))
            assertTrue(pixel.canStartZoom(discThroughMidpoint.x, discThroughMidpoint.y))

            play(listOf(screen(extensionStart), screen(discThroughMidpoint)), probe.touchSlop, lift = true)
            settle()
            scenario.onActivity {
                assertTrue(probe.changes.isEmpty(),
                    "Extension-start crossing the midpoint into the disc must not change zoom: ${probe.changes}")
                assertEquals(0, probe.underDowns.get(), "Popup must own the extension-start pointer")
                assertEquals(0, probe.underEvents.get(), "Underlying control received ${probe.underEvents} during unarmed drag")
                assertEquals(0, probe.underClicks.get())
                assertEquals(0, probe.dismissals)
            }

            val discStart = Offset(pixel.radius * 0.40f, pixel.radius * 0.55f)
            val discDrag = Offset(pixel.radius * 0.40f, pixel.radius * 1.20f)
            val inExtension = Offset(pixel.radius + pixel.edgeExtension * 0.55f, pixel.radius * 1.20f)
            val extensionTravel = Offset(pixel.radius + pixel.edgeExtension * 0.55f, pixel.radius * 1.45f)
            val reentry = Offset(pixel.radius * 0.40f, pixel.radius * 1.45f)
            val reentryStep = Offset(pixel.radius * 0.40f, pixel.radius * 1.48f)
            assertTrue(pixel.canStartZoom(discStart.x, discStart.y))
            assertTrue(pixel.canStartZoom(discDrag.x, discDrag.y))
            assertFalse(pixel.canStartZoom(inExtension.x, inExtension.y))
            assertTrue(pixel.contains(inExtension.x, inExtension.y))

            val down = play(listOf(screen(discStart), screen(discDrag)), probe.touchSlop, lift = false)
            settle()
            val afterDisc = snapshot(probe)
            assertTrue(afterDisc.values.isNotEmpty() && abs(afterDisc.values.last() - 2.0) > 0.08,
                "Disc-start drag must change zoom from 2.00, got ${afterDisc.values}")
            assertTrue(afterDisc.values.any { abs(it - round(it * 100.0) / 100.0) > 1e-6 },
                "Touch zoom must retain sub-hundredth values instead of snapping to the displayed label")
            assertEquals(0, afterDisc.downs, "Popup must own the disc-start pointer")
            assertEquals(0, afterDisc.events)
            assertEquals(0, afterDisc.clicks)

            play(listOf(screen(discDrag), screen(inExtension)), probe.touchSlop, lift = false, downTime = down)
            settle()
            val entered = snapshot(probe)
            play(listOf(screen(inExtension), screen(extensionTravel)), probe.touchSlop, lift = false, downTime = down)
            settle()
            val paused = snapshot(probe)
            assertEquals(entered.values.last(), paused.values.last(), 1e-6,
                "Travel inside the extension must pause zoom at ${entered.values.last()}, got ${paused.values}")
            assertEquals(entered.values.size, paused.values.size,
                "Extension travel must not emit zoom: ${paused.values}")
            assertEquals(0, paused.downs)
            assertEquals(0, paused.events)

            move(screen(reentry), down)
            settle()
            val reentered = snapshot(probe)
            assertEquals(paused.values.last(), reentered.values.last(), 1e-6,
                "First reentry sample must rebase without applying the missing arc: paused=${paused.values.last()} got ${reentered.values}")
            assertEquals(paused.values.size, reentered.values.size)

            move(screen(reentryStep), down)
            lift(screen(reentryStep), down)
            settle()
            val finished = snapshot(probe)
            assertTrue(finished.values.size > reentered.values.size,
                "A small disc sample after rebase must change zoom smoothly, got ${finished.values}")
            val posJump = abs(ln(finished.values.last()) - ln(paused.values.last())) / ln(12.0)
            assertTrue(posJump > 0.0 && posJump < 0.02,
                "Post-reentry step must be a local dial step, not the missing arc: paused=${paused.values.last()} got ${finished.values.last()} posJump=$posJump")
            scenario.onActivity {
                assertEquals(0, probe.underDowns.get(), "Underlying control must receive no touch")
                assertEquals(0, probe.underEvents.get(), "Underlying control events=${probe.underEvents}")
                assertEquals(0, probe.underClicks.get())
                assertEquals(0, probe.dismissals, "Popup must stay up through both gestures")
            }
        }
    }

    private fun awaitPopup(scenario: ActivityScenario<BackdropRenderActivity>, probe: ZoomNativeProbe) {
        val deadline = SystemClock.uptimeMillis() + 8_000
        var stable = 0
        var last = android.graphics.Rect()
        while (SystemClock.uptimeMillis() < deadline) {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            val laidOut = probe.composed && probe.layout.radius > 0f && probe.density > 0f
            val bounds = findZoomBounds()
            if (laidOut && bounds != null && bounds.width() > 0 && bounds.height() > 0) {
                if (bounds == last) stable++ else { stable = 0; last = android.graphics.Rect(bounds) }
                if (stable >= 3) {
                    SystemClock.sleep(MonitorMotion.ZOOM_IN_MS.toLong() + 40L)
                    InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                    return
                }
            }
            scenario.onActivity { activity ->
                if (!activity.hasWindowFocus()) activity.window.decorView.requestFocus()
            }
            SystemClock.sleep(32)
        }
        assertTrue(probe.composed, "Fixture must compose")
        assertTrue(probe.layout.radius > 0f, "Composition geometry missing")
        assertTrue(findZoomBounds() != null, "Zoom popup semantics never published")
        assertTrue(stable >= 3, "Zoom popup bounds must settle")
    }

    private fun discScreenBounds(probe: ZoomNativeProbe, pixel: MonitorZoomGeometry): android.graphics.Rect {
        val expected = android.graphics.Rect().apply {
            val popupW = probe.screenWidthDp * probe.density
            val popupH = probe.screenHeightDp * probe.density
            val left = probe.windowScreen.x + popupW - pixel.width
            val top = probe.windowScreen.y + (popupH - pixel.height) / 2f
            set(left.toInt(), top.toInt(), (left + pixel.width).toInt(), (top + pixel.height).toInt())
        }
        val published = findZoomBounds()
        val bounds = published ?: expected
        assertTrue(bounds.width() > 0 && bounds.height() > 0, "Disc screen bounds empty")
        assertTrue(abs(bounds.height() - pixel.height) < max(12f, pixel.height * 0.04f),
            "A11y height ${bounds.height()} must match composition pixel height ${pixel.height} (expected=$expected published=$published density=${probe.density} window=${probe.windowScreen})")
        assertTrue(abs(bounds.width() - pixel.width) < max(12f, pixel.width * 0.08f),
            "A11y width ${bounds.width()} must match composition pixel width ${pixel.width} (48dp extrusion)")
        return bounds
    }

    private fun findZoomBounds(): android.graphics.Rect? {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun search(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            val description = node.contentDescription?.toString().orEmpty()
            if (description.startsWith("Zoom")) return node
            for (index in 0 until node.childCount) {
                search(node.getChild(index))?.let { return it }
            }
            return null
        }
        val roots = mutableListOf<AccessibilityNodeInfo>()
        automation.rootInActiveWindow?.let(roots::add)
        automation.windows.orEmpty().mapNotNull(AccessibilityWindowInfo::getRoot).forEach(roots::add)
        for (root in roots) {
            val found = search(root) ?: continue
            val bounds = android.graphics.Rect()
            found.getBoundsInScreen(bounds)
            if (bounds.width() > 0 && bounds.height() > 0) return bounds
        }
        return null
    }

    private var lastEventTime = 0L

    private fun nextEventTime(): Long {
        val now = SystemClock.uptimeMillis()
        val time = if (now > lastEventTime) now else lastEventTime + 1L
        lastEventTime = time
        return time
    }

    private fun play(points: List<Offset>, touchSlop: Float, lift: Boolean, downTime: Long? = null): Long {
        val path = interpolate(points, max(8f, touchSlop / 2f))
        val down = downTime ?: nextEventTime()
        var index = 0
        if (downTime == null) {
            inject(MotionEvent.ACTION_DOWN, path.first(), down, down)
            index = 1
        }
        for (sample in index until path.size) {
            inject(MotionEvent.ACTION_MOVE, path[sample], down, nextEventTime())
        }
        if (lift) lift(path.last(), down)
        return down
    }

    private fun move(point: Offset, down: Long) {
        inject(MotionEvent.ACTION_MOVE, point, down, nextEventTime())
    }

    private fun lift(point: Offset, down: Long) {
        inject(MotionEvent.ACTION_UP, point, down, nextEventTime())
    }

    private fun interpolate(points: List<Offset>, step: Float): List<Offset> {
        require(points.size >= 2)
        val out = mutableListOf(points.first())
        for (index in 1 until points.size) {
            val from = out.last()
            val to = points[index]
            val distance = hypot((to.x - from.x).toDouble(), (to.y - from.y).toDouble()).toFloat()
            val count = max(1, (distance / step).toInt())
            for (sample in 1..count) {
                val t = sample / count.toFloat()
                out += Offset(from.x + (to.x - from.x) * t, from.y + (to.y - from.y) * t)
            }
        }
        return out
    }

    private fun inject(action: Int, point: Offset, down: Long, eventTime: Long) {
        val properties = arrayOf(MotionEvent.PointerProperties().apply {
            id = 0
            toolType = MotionEvent.TOOL_TYPE_FINGER
        })
        val coords = arrayOf(MotionEvent.PointerCoords().apply {
            x = point.x
            y = point.y
            pressure = 1f
            size = 1f
        })
        val event = MotionEvent.obtain(down, eventTime, action, 1, properties, coords,
            0, 0, 1f, 1f, 0, 0, InputDevice.SOURCE_TOUCHSCREEN, 0)
        try {
            assertTrue(
                InstrumentationRegistry.getInstrumentation().uiAutomation.injectInputEvent(event, true),
                "injectInputEvent $action at ${point.x},${point.y}",
            )
        } finally { event.recycle() }
    }

    private fun snapshot(probe: ZoomNativeProbe) = ZoomSnapshot(
        values = probe.changes.toList(),
        downs = probe.underDowns.get(),
        events = probe.underEvents.get(),
        clicks = probe.underClicks.get(),
    )

    private fun settle() {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        SystemClock.sleep(48)
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }
}

private class ZoomNativeProbe {
    val trailingInsetDp = 48f
    var density = 0f
    var fontScale = 0f
    var screenWidthDp = 0
    var screenHeightDp = 0
    var touchSlop = 18f
    var layout = MonitorZoomGeometry(0f, 0f)
    var windowScreen = Offset.Zero
    var viewScreen = Offset.Zero
    val changes = Collections.synchronizedList(mutableListOf<Double>())
    val underEvents = AtomicInteger()
    val underDowns = AtomicInteger()
    val underClicks = AtomicInteger()
    var dismissals = 0
    var composed = false
}

private data class ZoomSnapshot(
    val values: List<Double>,
    val downs: Int,
    val events: Int,
    val clicks: Int,
)
