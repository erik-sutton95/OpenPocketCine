package com.opencapture.openpocketcine.bridge

import com.opencapture.opencine.dji.DjiNative

/**
 * JNI binding to `libOpenPocketCineAndroid.so` for this app's own natives: core version, LUT
 * packing and feed-effect cubes. The DJI wire natives in the same library
 * belong to OpenCine's [DjiNative]. Staged by `:app:stageSwiftCore` / `just android-core`.
 */
object SwiftCore {
    /** Loads the library once for both facades (this one and [DjiNative]). */
    val isAvailable: Boolean by lazy { DjiNative.load("OpenPocketCineAndroid") }

    external fun coreVersion(): String

    /** Packed-2D RGBA8 cube (`n³ × 4`) for GLES upload. Input-referred LUT exposure. */
    external fun packImportedLut(utf8: ByteArray, exposureStops: Double, colorMode: Int): ByteArray?

    /** Generated Creative look (Mono / Contrast / Warm / Cool). */
    external fun packCreativeLut(title: String, exposureStops: Double, colorMode: Int): ByteArray?

    /** Overlay paint cube for FALSE (`0` Video / `1` IRE / `2` Limits / `3` CineStop). */
    external fun packFalseColorPaint(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /** Overlay weight cube paired with [packFalseColorPaint]. */
    external fun packFalseColorWeight(scaleOrdinal: Int, colorMode: Int, iso: Int): ByteArray?

    /**
     * `[highlightNative, midtoneNative, midtoneHalfNative, peakingGateScale]`
     * on encoded camera codes (iOS `ScopeDisplayScale.signalNative`).
     */
    external fun feedAssistScalars(
        colorMode: Int,
        iso: Int,
        highlightIRE: Float,
        midtoneIRE: Float,
    ): FloatArray?
}
