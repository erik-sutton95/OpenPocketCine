package com.opencapture.openpocketcine.assists

import com.opencapture.opencine.media.MonitorAnamorphicDesqueeze

/** Presentation only: the source pixels, scope samples and delivered files stay unchanged. */
typealias DesqueezePreset = com.opencapture.opencine.media.MonitorDesqueezePreset

typealias DesqueezeDirection = com.opencapture.opencine.media.MonitorDesqueezeDirection

object AnamorphicDesqueeze {
    const val HELP = "Corrects the displayed shape of an anamorphic image in live view and playback. " +
        "Horizontal widens the image; Vertical makes it taller. The full image stays fitted. " +
        "Recordings, photos, exports and scope measurements are unchanged."

    fun snap(value: Double): Double = MonitorAnamorphicDesqueeze.snap(value)
    fun label(value: Double): String = MonitorAnamorphicDesqueeze.label(value)
    fun aspect(sourceAspect: Float, enabled: Boolean, factor: Double, direction: DesqueezeDirection): Float {
        val source = sourceAspect.takeIf { it.isFinite() && it > 0f } ?: (16f / 9f)
        return requireNotNull(MonitorAnamorphicDesqueeze.aspect(source, enabled, factor, direction))
    }
}
