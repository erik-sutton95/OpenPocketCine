package com.opencapture.openpocketcine.feed

/**
 * Bake→drawable upscaler. Labels match iOS `FeedUpscaler` raw values.
 *
 * GLES2 offers a plain bilinear sample ([OFF]) and the existing Catmull-Rom
 * reconstruction ([FAST], the portable Lanczos analogue). Quality / AI have
 * no GLES equivalent, so they are omitted the same way iOS hides unsupported
 * options.
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
    }
}

/** GLES reads this off the UI thread. Operator Setup writes it with the prefs. */
object FeedUpscaleSwitch {
    @Volatile
    var rendererReads: FeedUpscaler = FeedUpscaler.FAST
}
