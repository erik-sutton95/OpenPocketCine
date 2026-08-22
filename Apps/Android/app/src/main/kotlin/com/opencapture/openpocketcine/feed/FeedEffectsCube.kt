package com.opencapture.openpocketcine.feed

/** One packed-2D RGBA8 cube (`width = size²`, `height = size`) from the Swift core. */
class FeedEffectsCube(
    val size: Int,
    val rgba: ByteArray,
) {
    init {
        require(size in 2..64) { "unsupported feed-effects cube size $size" }
        require(rgba.size == size * size * size * 4) {
            "bad feed-effects cube payload for size $size"
        }
    }

    /** Trilinear sample. Lattice is `dst = (g·n² + b·n + r)·4` (LUTLibraryWire packedRGBA). */
    fun map(red: Float, green: Float, blue: Float): Triple<Float, Float, Float> {
        val n = size
        val scale = (n - 1).toFloat()
        val fr = red.coerceIn(0f, 1f) * scale
        val fg = green.coerceIn(0f, 1f) * scale
        val fb = blue.coerceIn(0f, 1f) * scale
        val r0 = fr.toInt()
        val g0 = fg.toInt()
        val b0 = fb.toInt()
        val r1 = minOf(r0 + 1, n - 1)
        val g1 = minOf(g0 + 1, n - 1)
        val b1 = minOf(b0 + 1, n - 1)
        val tr = fr - r0
        val tg = fg - g0
        val tb = fb - b0
        fun lattice(r: Int, g: Int, b: Int, channel: Int): Float {
            val dst = (g * n * n + b * n + r) * 4 + channel
            return (rgba[dst].toInt() and 0xFF) / 255f
        }
        fun sample(channel: Int): Float {
            val c00 = lattice(r0, g0, b0, channel) * (1 - tr) + lattice(r1, g0, b0, channel) * tr
            val c10 = lattice(r0, g1, b0, channel) * (1 - tr) + lattice(r1, g1, b0, channel) * tr
            val c01 = lattice(r0, g0, b1, channel) * (1 - tr) + lattice(r1, g0, b1, channel) * tr
            val c11 = lattice(r0, g1, b1, channel) * (1 - tr) + lattice(r1, g1, b1, channel) * tr
            val c0 = c00 * (1 - tg) + c10 * tg
            val c1 = c01 * (1 - tg) + c11 * tg
            return c0 * (1 - tb) + c1 * tb
        }
        return Triple(sample(0), sample(1), sample(2))
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
