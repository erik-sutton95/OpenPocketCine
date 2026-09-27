package com.opencapture.openpocketcine

import android.graphics.SurfaceTexture
import android.os.SystemClock
import android.view.InputDevice
import android.view.MotionEvent
import android.view.Surface
import android.view.TextureView
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.viewinterop.AndroidView
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MultiviewArrangement
import com.opencapture.monitorui.MultiviewPresentationLayout
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.openpocketcine.multiview.MultiviewSession
import com.opencapture.openpocketcine.multiview.MultiviewTileCanvas
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.math.abs
import kotlin.math.roundToInt
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/** Real TextureView buffers at the production retained-canvas seam; no camera I/O. */
@RunWith(AndroidJUnit4::class)
class MultiviewTileIdentityTest {
    @OptIn(ExperimentalComposeUiApi::class)
    @Test fun nativePicturesSurviveLayoutPromotionRotationAndSecondaryScrolling() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val views = mutableMapOf<Int, TextureView>()
        val textures = mutableMapOf<Int, SurfaceTexture>()
        val presented = mutableSetOf<Int>()
        var expectedSizes = emptyMap<Int, Pair<Int, Int>>()
        val colors = listOf(0xffca3434.toInt(), 0xff42bf62.toInt(), 0xff427bd4.toInt(), 0xffc49c32.toInt())
        val background = 0xffed24b4.toInt()
        var shownLayout: MultiviewPresentationLayout? = null
        var shownScale = 1f
        var created = 0
        var destroyed = 0
        var generation by mutableStateOf(0)
        var shownGeneration = -1
        var arrangement by mutableStateOf(MultiviewArrangement.GRID)
        var selected by mutableStateOf(0)
        var viewport by mutableStateOf(852f to 393f)
        var safe by mutableStateOf(MultiviewSafeArea(trailing = 59f, bottom = 21f))
        lateinit var stage: MultiviewSession
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    stage = MultiviewSession(activity, saveStage = { true })
                    activity.setContent {
                        BoxWithConstraints(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                            val (width, height) = viewport
                            val scale = constraints.maxWidth / width
                            val layout = MultiviewPresentationLayout.compute(width, height, safe, arrangement, selected)
                            CompositionLocalProvider(LocalDensity provides Density(scale, 1f)) {
                                Box(Modifier.requiredSize(width.dp, height.dp).background(Color(background))) {
                                    MultiviewTileCanvas(stage.tiles.map { it.id }, layout) { index, _ ->
                                        Box(Modifier.fillMaxSize().semantics {
                                            contentDescription = "Fixture camera ${'A' + index}"
                                            onClick { selected = index; generation++; true }
                                        }) {
                                            AndroidView(factory = { context ->
                                                created++
                                                TextureView(context).apply {
                                                    views[index] = this
                                                    surfaceTextureListener = object : TextureView.SurfaceTextureListener {
                                                        override fun onSurfaceTextureAvailable(texture: SurfaceTexture, width: Int, height: Int) {
                                                            textures[index] = texture
                                                            val surface = Surface(texture)
                                                            val canvas = surface.lockCanvas(null)
                                                            canvas.drawColor(colors[index])
                                                            surface.unlockCanvasAndPost(canvas)
                                                            surface.release()
                                                        }
                                                        override fun onSurfaceTextureSizeChanged(texture: SurfaceTexture, width: Int, height: Int) = Unit
                                                        override fun onSurfaceTextureUpdated(texture: SurfaceTexture) { presented.add(index) }
                                                        override fun onSurfaceTextureDestroyed(texture: SurfaceTexture): Boolean {
                                                            destroyed++
                                                            return true
                                                        }
                                                    }
                                                }
                                            }, modifier = Modifier.fillMaxSize())
                                        }
                                    }
                                }
                            }
                            SideEffect {
                                shownGeneration = generation
                                shownLayout = layout
                                shownScale = scale
                                expectedSizes = layout.tiles.mapIndexed { index, frame ->
                                    index to ((frame.width * scale).roundToInt() to (frame.height * scale).roundToInt())
                                }.toMap()
                            }
                        }
                    }
                }
                await { views.size == 4 && views.values.all { it.isAvailable } && textures.size == 4 && presented.size == 4 }
                val originalViews = views.toMap()
                val originalTextures = textures.toMap()
                val owners = stage.tiles.map { it.decoder }
                fun verifyPictures() {
                    await { shownGeneration == generation && views.all { (index, view) ->
                        val (width, height) = expectedSizes.getValue(index)
                        abs(view.width - width) <= 1 && abs(view.height - height) <= 1
                    } }
                    instrumentation.waitForIdleSync()
                    scenario.onActivity {
                        assertEquals(4, created, "A layout or scroll must not recreate a native feed host")
                        assertEquals(0, destroyed, "A layout or scroll must keep each output surface attached")
                        stage.tiles.forEachIndexed { index, tile ->
                            assertSame(owners[index], tile.decoder)
                            assertSame(originalViews[index], views[index])
                            assertSame(originalTextures[index], views[index]?.surfaceTexture)
                            val picture = assertNotNull(views[index]?.bitmap)
                            assertEquals(colors[index], picture.getPixel(picture.width / 2, picture.height / 2),
                                "Camera $index must retain its native picture")
                            picture.recycle()
                        }
                    }
                }
                fun verifyFades(topFaded: Boolean, bottomFaded: Boolean) {
                    instrumentation.waitForIdleSync()
                    SystemClock.sleep(350)
                    val layout = assertNotNull(shownLayout)
                    val strip = assertNotNull(layout.secondaryViewport)
                    val samples = mutableListOf<Triple<Int, Int, Int>>()
                    scenario.onActivity {
                        val main = IntArray(2).also(views.getValue(0)::getLocationOnScreen)
                        val originX = main[0] - layout.tiles[0].x * shownScale
                        val originY = main[1] - layout.tiles[0].y * shownScale
                        val x = (originX + strip.midX * shownScale).roundToInt()
                        listOf(strip.y + 8, strip.maxY - 8).forEach { y ->
                            val screenY = (originY + y * shownScale).roundToInt()
                            val owner = layout.secondaryIndices.first { index ->
                                val location = IntArray(2).also(views.getValue(index)::getLocationOnScreen)
                                screenY >= location[1] && screenY < location[1] + views.getValue(index).height
                            }
                            samples += Triple(x, screenY, colors[owner])
                        }
                    }
                    val screenshot = assertNotNull(instrumentation.uiAutomation.takeScreenshot())
                    fun distance(left: Int, right: Int) = listOf(16, 8, 0).sumOf { shift ->
                        abs((left shr shift and 255) - (right shr shift and 255))
                    }
                    samples.zip(listOf(topFaded, bottomFaded)).forEach { (sample, faded) ->
                        val (x, y, source) = sample
                        val rendered = screenshot.getPixel(x, y)
                        if (faded) assertTrue(distance(rendered, background) < distance(source, background) * .6,
                            "Offscreen content must fade to the actual canvas through alpha, not a painted color")
                        else assertTrue(distance(rendered, source) <= 6,
                            "The fade must disappear at the scroll endpoint: top=$topFaded bottom=$bottomFaded pixel=$rendered source=$source sample=$sample")
                    }
                    screenshot.recycle()
                }
                verifyPictures()
                scenario.onActivity { arrangement = MultiviewArrangement.CENTER_STAGE; generation++ }
                verifyPictures()
                verifyFades(topFaded = false, bottomFaded = true)
                val strip = awaitNode { it.isScrollable && it.viewIdResourceName == "multiview.secondaryStrip" }
                assertTrue(strip.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))
                awaitNode { it.contentDescription?.toString() == "Fixture camera D" && it.isVisibleToUser }
                verifyPictures()
                verifyFades(topFaded = true, bottomFaded = false)
                assertTrue(awaitNode { it.isScrollable && it.viewIdResourceName == "multiview.secondaryStrip" }
                    .performAction(AccessibilityNodeInfo.ACTION_SCROLL_BACKWARD))
                verifyFades(topFaded = false, bottomFaded = true)
                val stripBounds = android.graphics.Rect().also {
                    val frame = assertNotNull(shownLayout?.secondaryViewport)
                    val main = IntArray(2)
                    scenario.onActivity { views.getValue(0).getLocationOnScreen(main) }
                    val originX = main[0] - assertNotNull(shownLayout).tiles[0].x * shownScale
                    val originY = main[1] - assertNotNull(shownLayout).tiles[0].y * shownScale
                    it.set((originX + frame.x * shownScale).roundToInt(), (originY + frame.y * shownScale).roundToInt(),
                        (originX + frame.maxX * shownScale).roundToInt(), (originY + frame.maxY * shownScale).roundToInt())
                }
                val downAt = SystemClock.uptimeMillis()
                fun touch(action: Int, y: Float) {
                    val event = MotionEvent.obtain(downAt, SystemClock.uptimeMillis(), action,
                        stripBounds.exactCenterX(), y, 0).apply { source = InputDevice.SOURCE_TOUCHSCREEN }
                    assertTrue(instrumentation.uiAutomation.injectInputEvent(event, true))
                    event.recycle()
                }
                val startY = stripBounds.bottom - 20 * shownScale
                val endY = stripBounds.top + 20 * shownScale
                touch(MotionEvent.ACTION_DOWN, startY)
                repeat(10) { step ->
                    SystemClock.sleep(25)
                    touch(MotionEvent.ACTION_MOVE, startY + (endY - startY) * (step + 1) / 10)
                }
                touch(MotionEvent.ACTION_UP, endY)
                verifyPictures()
                verifyFades(topFaded = true, bottomFaded = false)
                assertTrue(awaitNode { it.contentDescription?.toString() == "Fixture camera D" }
                    .performAction(AccessibilityNodeInfo.ACTION_CLICK))
                await { selected == 3 }
                verifyPictures()
                scenario.onActivity { arrangement = MultiviewArrangement.GRID; generation++ }
                verifyPictures()
                scenario.onActivity {
                    viewport = 393f to 852f
                    safe = MultiviewSafeArea(top = 59f, bottom = 34f)
                    generation++
                }
                verifyPictures()
                scenario.onActivity { arrangement = MultiviewArrangement.CENTER_STAGE; selected = 2; generation++ }
                verifyPictures()
                scenario.onActivity {
                    viewport = 852f to 393f
                    safe = MultiviewSafeArea(leading = 59f, bottom = 21f)
                    generation++
                }
                verifyPictures()
            } finally { scenario.onActivity { stage.dispose() } }
        }
    }

    private fun await(condition: () -> Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            var ready = false
            instrumentation.runOnMainSync { ready = condition() }
            if (ready) return
            SystemClock.sleep(32)
        }
        error("Retained tile host did not settle")
    }

    private fun awaitNode(matches: (AccessibilityNodeInfo) -> Boolean): AccessibilityNodeInfo {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (matches(node)) return node
            for (index in 0 until node.childCount) find(node.getChild(index))?.let { return it }
            return null
        }
        while (SystemClock.uptimeMillis() < deadline) {
            find(automation.rootInActiveWindow)?.let { return it }
            SystemClock.sleep(32)
        }
        error("Missing secondary feed control")
    }
}
