package com.opencapture.openpocketcine

import android.graphics.Bitmap
import android.graphics.Color
import android.os.Handler
import android.os.Looper
import android.view.Choreographer
import android.view.PixelCopy
import android.view.ViewTreeObserver
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorAspectGuideFrames
import com.opencapture.monitorui.MonitorGuideAspect
import com.opencapture.monitorui.MonitorGuideMaskPolicy
import com.opencapture.monitorui.MonitorScopeRect
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Reads real shared Compose/HWUI pixels. Uses existing debug fixture Activity and dependencies. */
@RunWith(AndroidJUnit4::class)
class MonitorGuideMaskRenderingTest {
    private val crossed = setOf(MonitorGuideAspect.ACADEMY, MonitorGuideAspect.CINEMA)

    @Test fun crossedGuideMaskPreservesUnionAndEnvelopeCornerPolicies() {
        val union = render(crossed, true, MonitorGuideMaskPolicy.UNION)
        val envelope = render(crossed, true, MonitorGuideMaskPolicy.ENVELOPE)
        for ((x, y) in listOf(10 to 5, 150 to 5, 10 to 85, 150 to 85)) {
            assertTrue(abs(Color.red(union.pixel(x, y)) - 102) <= 3)
            assertTrue(abs(Color.green(union.pixel(x, y)) - 102) <= 3)
            assertTrue(abs(Color.blue(union.pixel(x, y)) - 102) <= 3)
            assertEquals(Color.WHITE, envelope.pixel(x, y))
        }
        assertEquals(Color.WHITE, union.pixel(80, 45))
        assertEquals(Color.WHITE, envelope.pixel(80, 45))
        save(union.image, "guide-mask-crossed-union")
        save(envelope.image, "guide-mask-crossed-envelope")
    }

    @Test fun defaultMaskIsActualUnionRendering() {
        assertEquals(render(crossed, true, null).pixels().toList(),
            render(crossed, true, MonitorGuideMaskPolicy.UNION).pixels().toList())
    }

    @Test fun disabledEmptyAndSingleGuidePoliciesRenderIdentically() {
        for ((ratios, enabled) in listOf(crossed to false, emptySet<MonitorGuideAspect>() to true,
                setOf(MonitorGuideAspect.ACADEMY) to true)) {
            assertEquals(render(ratios, enabled, MonitorGuideMaskPolicy.UNION).pixels().toList(),
                render(ratios, enabled, MonitorGuideMaskPolicy.ENVELOPE).pixels().toList())
        }
    }

    private fun render(ratios: Set<MonitorGuideAspect>, enabled: Boolean,
        policy: MonitorGuideMaskPolicy?): Pixels {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val laidOut = CountDownLatch(1)
            var bounds = Rect.Zero
            scenario.onActivity { activity ->
                activity.setContent {
                    val frame = remember { mutableStateOf(MonitorScopeRect(0f, 0f, 0f, 0f)) }
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.White),
                        contentAlignment = Alignment.Center) {
                        Box(Modifier.size(160.dp, 90.dp).onGloballyPositioned {
                            bounds = it.boundsInWindow()
                            frame.value = MonitorScopeRect(0f, 0f, bounds.width, bounds.height)
                            laidOut.countDown()
                        }) {
                            if (policy == null) MonitorAspectGuideFrames(ratios, frame.value, enabled)
                            else MonitorAspectGuideFrames(ratios, frame.value, enabled, policy)
                        }
                    }
                }
            }
            assertTrue(laidOut.await(5, TimeUnit.SECONDS), "guide fixture layout timed out")
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            val drawScheduled = CountDownLatch(1)
            scenario.onActivity { activity ->
                val view = activity.window.decorView
                val listener = object : ViewTreeObserver.OnDrawListener {
                    override fun onDraw() {
                        view.post { view.viewTreeObserver.removeOnDrawListener(this) }
                        Choreographer.getInstance().postFrameCallback { drawScheduled.countDown() }
                    }
                }
                view.viewTreeObserver.addOnDrawListener(listener)
                view.invalidate()
            }
            assertTrue(drawScheduled.await(5, TimeUnit.SECONDS), "guide fixture draw timed out")
            val copied = CountDownLatch(1)
            var image: Bitmap? = null
            var status = -1
            scenario.onActivity { activity ->
                val bitmap = Bitmap.createBitmap(activity.window.decorView.width,
                    activity.window.decorView.height, Bitmap.Config.ARGB_8888)
                image = bitmap
                PixelCopy.request(activity.window, bitmap, { result ->
                    status = result; copied.countDown()
                }, Handler(Looper.getMainLooper()))
            }
            assertTrue(copied.await(5, TimeUnit.SECONDS), "guide window readback timed out")
            assertEquals(PixelCopy.SUCCESS, status)
            val bitmap = checkNotNull(image)
            return Pixels(Bitmap.createBitmap(bitmap, bounds.left.roundToInt(), bounds.top.roundToInt(),
                bounds.width.roundToInt(), bounds.height.roundToInt()))
        }
    }

    private data class Pixels(val image: Bitmap) {
        fun pixel(x: Int, y: Int): Int = image.getPixel(
            (x * image.width / 160f).roundToInt(), (y * image.height / 90f).roundToInt())
        fun pixels(): IntArray = IntArray(image.width * image.height).also {
            image.getPixels(it, 0, image.width, 0, 0, image.width, image.height)
        }
    }
    private fun save(image: Bitmap, name: String) {
        val context = InstrumentationRegistry.getInstrumentation().targetContext
        File(context.getExternalFilesDir(null), "$name.png").outputStream().use {
            image.compress(Bitmap.CompressFormat.PNG, 100, it)
        }
    }
}
