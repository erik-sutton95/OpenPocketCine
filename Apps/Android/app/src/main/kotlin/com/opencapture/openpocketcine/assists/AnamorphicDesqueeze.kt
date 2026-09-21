package com.opencapture.openpocketcine.assists

import java.util.Locale
import kotlin.math.roundToInt

/** Presentation only: the source pixels, scope samples and delivered files stay unchanged. */
enum class DesqueezePreset(val label: String, val factor: Double) {
    X110("1.1×", 1.1), X120("1.2×", 1.2), X133("1.33×", 1.33),
    X150("1.5×", 1.5), X160("1.6×", 1.6), X180("1.8×", 1.8), X200("2.0×", 2.0),
}

enum class DesqueezeDirection(val label: String) {
    HORIZONTAL("Horizontal"), VERTICAL("Vertical"),
}

object AnamorphicDesqueeze {
    const val HELP = "Corrects the displayed shape of an anamorphic image in live view and playback. " +
        "Horizontal widens the image; Vertical makes it taller. The full image stays fitted. " +
        "Recordings, photos, exports and scope measurements are unchanged."

    fun snap(value: Double): Double =
        ((if (value.isFinite()) value else 1.33).coerceIn(1.0, 2.0) * 100 + 1e-7).roundToInt() / 100.0

    fun label(value: Double): String = String.format(Locale.ROOT, "%.2f×", snap(value))

    fun aspect(sourceAspect: Float, enabled: Boolean, factor: Double, direction: DesqueezeDirection): Float {
        val source = sourceAspect.takeIf { it.isFinite() && it > 0f } ?: (16f / 9f)
        if (!enabled) return source
        val squeeze = snap(factor).toFloat()
        return if (direction == DesqueezeDirection.HORIZONTAL) source * squeeze else source / squeeze
    }
}
