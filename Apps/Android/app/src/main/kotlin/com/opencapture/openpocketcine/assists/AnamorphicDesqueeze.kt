package com.opencapture.openpocketcine.assists

/** Presentation only: the source pixels, scope samples and delivered files stay unchanged. */
typealias DesqueezePreset = com.opencapture.opencine.media.MonitorDesqueezePreset

typealias DesqueezeDirection = com.opencapture.opencine.media.MonitorDesqueezeDirection

object AnamorphicDesqueeze {
    const val HELP = "Corrects the displayed shape of an anamorphic image in live view and playback. " +
        "Horizontal widens the image; Vertical makes it taller. The full image stays fitted. " +
        "Recordings, photos, exports and scope measurements are unchanged."
}
