package com.opencapture.openpocketcine.media

import kotlin.math.min

/** Letterbox the video raster in a container — OpenZCine `aspectFitRect`. */
object PlaybackVideoLayout {
    data class Size(val width: Float, val height: Float)

    data class Rect(val x: Float, val y: Float, val width: Float, val height: Float) {
        val minX: Float
            get() = x
        val minY: Float
            get() = y
        val maxX: Float
            get() = x + width
        val maxY: Float
            get() = y + height
        val midX: Float
            get() = x + width / 2f
        val midY: Float
            get() = y + height / 2f
    }

    fun aspectFitRect(videoSize: Size, container: Rect): Rect {
        if (videoSize.width <= 0f || videoSize.height <= 0f || container.width <= 0f || container.height <= 0f) {
            return container
        }
        val scale = min(container.width / videoSize.width, container.height / videoSize.height)
        val width = videoSize.width * scale
        val height = videoSize.height * scale
        return Rect(
            x = container.midX - width / 2f,
            y = container.midY - height / 2f,
            width = width,
            height = height,
        )
    }

    fun sizeFromResolution(listed: String?): Size? {
        if (listed.isNullOrBlank()) return null
        val parts = listed.split('x', 'X', '×', '*')
        if (parts.size != 2) return null
        val width = parts[0].toFloatOrNull() ?: return null
        val height = parts[1].toFloatOrNull() ?: return null
        if (width <= 1f || height <= 1f) return null
        return Size(width, height)
    }
}
