package com.opencapture.openpocketcine.feed

/** Packed GPU slot / glass-plate layout. Policy only — no I/O. */
object GpuLiveLayout {
    const val SLOT_STRIDE = 8
    const val PLATE_STRIDE = 9

    fun packSlot(
        out: FloatArray,
        index: Int,
        visible: Boolean,
        x: Float,
        y: Float,
        w: Float,
        h: Float,
        mode: Int,
        intensity: Float,
        gain: Float = 1f,
    ) {
        val o = index * SLOT_STRIDE
        out[o] = if (visible) 1f else 0f
        out[o + 1] = x
        out[o + 2] = y
        out[o + 3] = w
        out[o + 4] = h
        out[o + 5] = mode.toFloat()
        out[o + 6] = intensity
        out[o + 7] = gain
    }

    /** Same RGBA as [com.opencapture.openpocketcine.LiveDesign.scopePlate]. */
    const val PANEL_FILL_R = 20f / 255f
    const val PANEL_FILL_G = 20f / 255f
    const val PANEL_FILL_B = 20f / 255f
    const val PANEL_FILL_A = 0.72f
    const val PANEL_CORNER_RADIUS_DP = 16f
}
