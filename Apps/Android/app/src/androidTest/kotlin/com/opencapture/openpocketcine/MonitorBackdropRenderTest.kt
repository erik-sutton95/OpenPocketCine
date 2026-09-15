package com.opencapture.openpocketcine

import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.monitorReadoutShadow
import android.content.Intent
import android.graphics.Bitmap
import android.graphics.Color
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.view.PixelCopy
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.core.app.ApplicationProvider
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorMaterial
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Pixel evidence from the real HWUI/RenderEffect modifier, not an emulated blur model. */
@RunWith(AndroidJUnit4::class)
class MonitorBackdropRenderTest {
    @Test fun readoutBloomExtendsOutsideContentWithoutChangingLayoutOrForeground() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var bounds = Rect.Zero
            var density = 1f
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    Box(Modifier.fillMaxSize().background(androidx.compose.ui.graphics.Color.White),
                        contentAlignment = Alignment.Center) {
                        Box(Modifier.size(20.dp).onGloballyPositioned { bounds = it.boundsInWindow() }
                            .monitorReadoutShadow().background(androidx.compose.ui.graphics.Color.Cyan))
                    }
                }
            }
            val image = capture(scenario)
            assertEquals(20f * density, bounds.width, 1f, "Bloom must not enlarge the hit target")
            val halo = image.getPixel((bounds.left - 2f * density).roundToInt(), bounds.center.y.roundToInt())
            assertTrue(Color.red(halo) < 230, "Shadow must extend outside the content bounds")
            val foreground = image.getPixel(bounds.center.x.roundToInt(), bounds.center.y.roundToInt())
            assertTrue(Color.red(foreground) < 5 && Color.green(foreground) > 250 && Color.blue(foreground) > 250,
                "Foreground stays sharp and keeps its original color")
        }
    }

    @Test fun referenceMaterialsBlurBackdropAndKeepForegroundSharp() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val treatments = listOf("compact" to MonitorMaterial.Compact, "expanded" to MonitorMaterial.Expanded,
                "zoom" to MonitorMaterial.Zoom, "scope" to MonitorMaterial.Scope, "info" to MonitorMaterial.Info,
                "delivery" to MonitorMaterial.Delivery, "record" to MonitorMaterial.Record)
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            val colors = org.json.JSONObject(context.assets.open("monitor_backdrop_color_samples.json")
                .bufferedReader().use { it.readText() })
            for ((name, material) in treatments) {
                scenario.onActivity { it.material = material }
                val image = capture(scenario, name)
                val scale = minOf(image.width / 900f, image.height / 600f)
                fun pixel(x: Float, y: Float) = image.getPixel((x * scale).roundToInt(), (y * scale).roundToInt())
                val left = Color.red(pixel(300f, 200f)); val right = Color.red(pixel(600f, 200f))
                val low = left + (right - left) * .1f; val high = left + (right - left) * .9f
                fun crossing(level: Float): Int = (350..550).first { Color.red(pixel(it.toFloat(), 200f)) >= level }
                val spread = crossing(high) - crossing(low)
                // Browser reference 10–90 sigma spread: compact46, expanded52, zoom60, scope20.
                val oracle = colors.getJSONObject(when (name) { "info" -> "information"; "record" -> "recording"; else -> name })
                for (x in listOf(225, 375, 525, 675)) {
                    val rgb = oracle.getJSONArray(x.toString())
                    val color = pixel(x.toFloat(), 410f)
                    listOf(Color.red(color), Color.green(color), Color.blue(color)).forEachIndexed { channel, actual ->
                        assertTrue(abs(actual - rgb.getInt(channel)) <= 2, "$name color x$x channel$channel=$actual")
                    }
                }
                val expected = material.blurDp * 2.56f
                assertTrue(abs(spread - expected) <= maxOf(5f, expected * .15f), "$name spread=$spread expected=$expected")
                val expectedLeft = material.tint.red * 255 * material.tint.alpha
                val expectedRight = 255 * (1 - material.tint.alpha) + expectedLeft
                assertTrue(abs(left - expectedLeft) < 3f, "$name left=$left")
                assertTrue(abs(right - expectedRight) < 3f, "$name right=$right")
                assertTrue(Color.red(pixel(447f, 60f)) < 4 && Color.red(pixel(453f, 60f)) > 250, "outside plate stays sharp")
                assertTrue(Color.red(pixel(420f, 448f)) > 250, "foreground remains opaque white")
                assertTrue(Color.red(pixel(420f, 443f)) < 240, "no blurred foreground halo")
            }
        }
    }

    @Test fun sampledImageReplacementResizeMirrorAndNestedPanelsStayIndependent() {
        assumeTrue(Build.VERSION.SDK_INT >= 31)
        val intent = Intent(ApplicationProvider.getApplicationContext(), BackdropRenderActivity::class.java)
            .putExtra("sampled", true)
        ActivityScenario.launch<BackdropRenderActivity>(intent).use { scenario ->
            capture(scenario, "sampled")
            scenario.onActivity { it.mirror = true; it.nested = true }
            var image = capture(scenario, "mirrored-nested")
            var scale = minOf(image.width / 900f, image.height / 600f)
            assertTrue(Color.red(image.getPixel((300 * scale).toInt(), (200 * scale).toInt())) > 100)
            repeat(8) { scenario.onActivity { it.fixtureScale = if (it.fixtureScale == 1f) .8f else 1f }; capture(scenario) }
            scenario.onActivity { it.replaceSource(Color.GREEN) }
            image = capture(scenario, "replacement")
            scale = minOf(image.width / 900f, image.height / 600f)
            val green = image.getPixel((300 * scale).toInt(), (200 * scale).toInt())
            assertTrue(Color.green(green) > 100 && Color.red(green) < 20, "new source replaces old pixels")
            scenario.onActivity { it.replaceSource(null) }
            image = capture(scenario, "unavailable")
            val cleared = image.getPixel((300 * scale).toInt(), (200 * scale).toInt())
            assertTrue(
                abs(Color.red(cleared) - 8) <= 1 &&
                    abs(Color.green(cleared) - 9) <= 1 &&
                    abs(Color.blue(cleared) - 10) <= 1,
                "missing source is canvas 0x08090A",
            )
            scenario.onActivity {
                it.replaceSource(Color.GREEN)
                it.secondSource.image = Bitmap.createBitmap(100, 80, Bitmap.Config.ARGB_8888).apply { eraseColor(Color.BLUE) }
                it.splitSources = true
            }
            image = capture(scenario, "multiple-sources")
            val leftTile = image.getPixel((300 * scale).toInt(), (200 * scale).toInt())
            val rightTile = image.getPixel((600 * scale).toInt(), (200 * scale).toInt())
            assertTrue(Color.green(leftTile) > 100 && Color.blue(leftTile) < 20)
            assertTrue(Color.blue(rightTile) > 100 && Color.green(rightTile) < 20)
            scenario.moveToState(Lifecycle.State.CREATED)
            scenario.moveToState(Lifecycle.State.RESUMED)
            scenario.recreate()
            capture(scenario, "recreated")
        }
    }

    private fun capture(scenario: ActivityScenario<BackdropRenderActivity>, name: String? = null): Bitmap {
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
        Thread.sleep(160) // wait for actual display presentation, not just Compose apply
        val latch = CountDownLatch(1)
        var image: Bitmap? = null
        var status = -1
        scenario.onActivity { activity ->
            val bitmap = Bitmap.createBitmap(activity.window.decorView.width, activity.window.decorView.height, Bitmap.Config.ARGB_8888)
            image = bitmap
            // Test-only window readback verifies actual HWUI output. Production never PixelCopies chrome.
            PixelCopy.request(activity.window, bitmap, { result -> status = result; latch.countDown() }, Handler(Looper.getMainLooper()))
        }
        assertTrue(latch.await(5, TimeUnit.SECONDS), "window capture timed out")
        assertEquals(PixelCopy.SUCCESS, status)
        val bitmap = checkNotNull(image)
        if (name != null) {
            val context = InstrumentationRegistry.getInstrumentation().targetContext
            File(context.getExternalFilesDir(null), "backdrop-$name.png").outputStream().use { bitmap.compress(Bitmap.CompressFormat.PNG, 100, it) }
        }
        return bitmap
    }
}
