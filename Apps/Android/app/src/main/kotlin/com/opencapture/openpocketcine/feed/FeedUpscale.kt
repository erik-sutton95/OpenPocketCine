package com.opencapture.openpocketcine.feed

/**
 * Bake→drawable upscaler. Labels match iOS `FeedUpscaler` raw values.
 *
 * Present of the 720p bake (iOS `bakeSize` then fit). Off is bilinear of
 * Rec.709; Fast is Catmull-Rom of that bake (portable Lanczos analogue).
 * Quality / AI have no GLES equivalent, so they are omitted the same way
 * iOS hides unsupported options. Do not reconstruct log RGB and then cube.
 */
enum class FeedUpscaler(val label: String) {
    OFF("Off"),
    FAST("Fast"),
    ;

    companion object {
        val supported: List<FeedUpscaler> = entries

        fun fromStored(raw: String?): FeedUpscaler {
            if (raw.isNullOrBlank()) return FAST
            entries.firstOrNull { it.label.equals(raw, ignoreCase = true) }?.let { return it }
            return when (raw) {
                "Lanczos" -> FAST
                "MetalFX", "Quality", "Super Res", "AI" -> FAST
                else -> FAST
            }
        }

        /**
         * Catmull-Rom is for magnification only. A 720p panel (or portrait
         * 1080×608 well) minifies — cubic aliases there and GL_LINEAR is right.
         */
        fun shouldReconstructToDisplay(
            sourceWidth: Float,
            sourceHeight: Float,
            displayWidth: Float,
            displayHeight: Float,
        ): Boolean {
            if (sourceWidth < 1f || sourceHeight < 1f) return false
            val scale =
                maxOf(displayWidth / sourceWidth, displayHeight / sourceHeight)
            return scale > 1.01f
        }
    }
}

/** GLES reads this off the UI thread. Operator Setup writes it with the prefs. */
object FeedUpscaleSwitch {
    @Volatile
    var rendererReads: FeedUpscaler = FeedUpscaler.FAST
}
