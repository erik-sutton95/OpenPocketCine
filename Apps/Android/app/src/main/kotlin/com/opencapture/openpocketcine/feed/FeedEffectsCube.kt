package com.opencapture.openpocketcine.feed

/** One packed-2D RGBA8 cube (`width = size²`, `height = size`) from the Swift core. */
internal class FeedEffectsCube(
    val size: Int,
    val rgba: ByteArray,
) {
    init {
        require(size in 2..64) { "unsupported feed-effects cube size $size" }
        require(rgba.size == size * size * size * 4) {
            "bad feed-effects cube payload for size $size"
        }
    }

    companion object {
        fun fromPacked(rgba: ByteArray): FeedEffectsCube? {
            if (rgba.size % 4 != 0) return null
            val cells = rgba.size / 4
            var size = 2
            while (size <= 64 && size * size * size < cells) size += 1
            if (size > 64 || size * size * size != cells) return null
            return runCatching { FeedEffectsCube(size, rgba) }.getOrNull()
        }
    }
}
