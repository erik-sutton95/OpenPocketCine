package com.opencapture.monitorui

import android.graphics.Bitmap
import android.graphics.ColorMatrix
import android.graphics.ColorMatrixColorFilter
import android.graphics.Paint
import android.graphics.RectF
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Immutable
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.RectangleShape
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.LayoutCoordinates
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.unit.dp
import kotlin.math.ceil

/** Reference CSS values, in density-independent pixels. Tint is applied after blur/saturation. */
@Immutable
data class MonitorMaterial(val tint: Color, val blurDp: Float, val saturation: Float = 1.25f) {
    companion object {
        val Compact = MonitorMaterial(Color(20, 22, 24).copy(alpha = .52f), 18f)
        val Expanded = MonitorMaterial(Color(20, 22, 24).copy(alpha = .62f), 20f)
        val Zoom = MonitorMaterial(Color(18, 20, 22).copy(alpha = .72f), 24f)
        val Scope = MonitorMaterial(Color(6, 9, 8).copy(alpha = .70f), 8f, 1f)
        val Info = MonitorMaterial(Color(20, 22, 24).copy(alpha = .82f), 20f)
        val Delivery = MonitorMaterial(Color(20, 22, 24).copy(alpha = .86f), 20f)
        val Record = MonitorMaterial(Color.White.copy(alpha = .08f), 18f)
    }
}

/**
 * Passive image input. The shell owns sample admission, source identity and lifecycle.
 * Published Bitmaps must not be mutated or recycled while displayed. Screen coordinates
 * also align consumers in separate Popup windows. Multiple sources support a tiled stage.
 */
class MonitorBackdropSource {
    var image: Bitmap? by mutableStateOf(null)
    internal var bounds by mutableStateOf(Rect.Zero)
    internal var viewport by mutableStateOf(Rect.Zero)
    internal var mirrored by mutableStateOf(false)
}

val LocalMonitorBackdropSurround = compositionLocalOf { MonitorPalette.backgroundDeep }

val LocalMonitorBackdrops = compositionLocalOf<List<MonitorBackdropSource>> { emptyList() }

/** Geometry only: never records content, reads a Surface, or creates a decoder. */
@Composable
fun Modifier.monitorBackdropSource(source: MonitorBackdropSource, imageRect: Rect? = null,
    mirrored: Boolean = false): Modifier {
    val position = remember(source) { arrayOfNulls<LayoutCoordinates>(1) }
    fun update(coordinates: LayoutCoordinates) {
        if (!coordinates.isAttached) return
        val origin = coordinates.positionOnScreen()
        val viewport = Rect(origin, androidx.compose.ui.geometry.Size(
            coordinates.size.width.toFloat(), coordinates.size.height.toFloat()))
        source.viewport = viewport
        source.bounds = imageRect?.translate(origin) ?: viewport
        source.mirrored = mirrored
    }
    SideEffect { position[0]?.let(::update) }
    DisposableEffect(source) { onDispose { source.bounds = Rect.Zero; source.viewport = Rect.Zero } }
    return onGloballyPositioned { position[0] = it; update(it) }
}

/**
 * Controlled backdrop blur. ONLY image pixels are recorded into the RenderNode; foreground
 * and descendant nodes are never recorded. This structurally excludes backdrop recursion.
 * Each node is panel-sized plus a 3-sigma apron, with no CPU readback or full-window layer.
 * API 29/30, software Canvas, or an unavailable sample use a solid readable fallback.
 */
@Composable
fun Modifier.monitorMaterial(material: MonitorMaterial = MonitorMaterial.Compact,
    shape: Shape = RectangleShape): Modifier {
    val sources = LocalMonitorBackdrops.current
    val surround = LocalMonitorBackdropSurround.current
    var origin by remember { mutableStateOf(Offset.Zero) }
    val renderer = remember { if (Build.VERSION.SDK_INT >= 31) MonitorBackdropRenderer() else null }
    DisposableEffect(renderer) { onDispose { if (Build.VERSION.SDK_INT >= 31) renderer?.close() } }
    return onGloballyPositioned { origin = it.positionOnScreen() }.clip(shape).drawWithContent {
        val canvas = drawContext.canvas.nativeCanvas
        val hasImage = sources.any { it.image != null && !it.bounds.isEmpty && !it.viewport.isEmpty }
        val rendered = if (Build.VERSION.SDK_INT >= 31 && renderer != null && canvas.isHardwareAccelerated && hasImage) {
            renderer.draw(canvas, size.width, size.height, origin, sources, material.blurDp.dp.toPx(), material.saturation, surround.toArgb())
            true
        } else false
        drawRect(if (rendered) material.tint else if (material == MonitorMaterial.Record) Color(0xFF303234)
            else material.tint.copy(alpha = 1f))
        drawContent()
    }
}

@RequiresApi(31)
internal class MonitorBackdropRenderer : AutoCloseable {
    private val node = RenderNode("Monitor sampled backdrop")
    private val paint = Paint(Paint.FILTER_BITMAP_FLAG)
    private var lastBlur = Float.NaN
    private var lastSaturation = Float.NaN
    private data class Input(val image: Bitmap?, val bounds: Rect, val viewport: Rect, val mirrored: Boolean)
    private var inputs = emptyList<Input>()
    private var lastWidth = -1
    private var lastHeight = -1
    private var lastOrigin = Offset.Unspecified
    private var lastSurround = 0

    fun draw(canvas: android.graphics.Canvas, width: Float, height: Float, origin: Offset,
        sources: List<MonitorBackdropSource>, blurPx: Float, saturation: Float, surround: Int) {
        val apron = ceil(blurPx * 3f).toInt()
        val w = ceil(width).toInt() + apron * 2
        val h = ceil(height).toInt() + apron * 2
        if (w <= 0 || h <= 0) return
        node.setPosition(-apron, -apron, w - apron, h - apron)
        if (lastBlur != blurPx || lastSaturation != saturation) {
            // Android's public radius is converted to sigma by HWUI as
            // radius * 0.57735 + 0.5. CSS blur() specifies sigma directly.
            // Invert that mapping; actual rendered edge tests guard native parity.
            val radius = ((blurPx - .5f) / .57735f).coerceAtLeast(0f)
            val filter = ColorMatrixColorFilter(ColorMatrix().apply { setSaturation(saturation) })
            val effect = if (blurPx > 0f) RenderEffect.createColorFilterEffect(filter,
                RenderEffect.createBlurEffect(radius, radius, Shader.TileMode.CLAMP))
                else RenderEffect.createColorFilterEffect(filter)
            node.setRenderEffect(effect)
            lastBlur = blurPx; lastSaturation = saturation
        }
        val unchanged = node.hasDisplayList() && w == lastWidth && h == lastHeight && origin == lastOrigin &&
            surround == lastSurround && sources.size == inputs.size && sources.indices.all { index ->
                val source = sources[index]; val input = inputs[index]
                source.image === input.image && source.bounds == input.bounds && source.viewport == input.viewport &&
                    source.mirrored == input.mirrored
            }
        if (unchanged) { canvas.drawRenderNode(node); return }
        inputs = sources.map { Input(it.image, it.bounds, it.viewport, it.mirrored) }
        lastWidth = w; lastHeight = h; lastOrigin = origin; lastSurround = surround
        val recording = node.beginRecording(w, h)
        try {
            recording.drawColor(surround)
            recording.translate(apron - origin.x, apron - origin.y)
            for (source in sources) {
                val bitmap = source.image ?: continue
                val bounds = source.bounds
                val viewport = source.viewport
                recording.save()
                recording.clipRect(viewport.left, viewport.top, viewport.right, viewport.bottom)
                if (source.mirrored) recording.scale(-1f, 1f, bounds.center.x, bounds.center.y)
                recording.drawBitmap(bitmap, null, RectF(bounds.left, bounds.top, bounds.right, bounds.bottom), paint)
                recording.restore()
            }
        } finally { node.endRecording() }
        canvas.drawRenderNode(node)
    }

    override fun close() { node.discardDisplayList() }
}
