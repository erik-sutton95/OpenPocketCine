package com.opencapture.openpocketcine.feed

import android.view.Surface
import android.hardware.HardwareBuffer
import android.util.Log

/**
 * JNI to `libopc_vulkan.so`. One renderer owns the swapchain, the imported
 * decoder AHB, compute histogram, point-list WAVE/PARADE, vectorscope scatter,
 * dual-kawase grab, and SDF glass plates.
 */
internal object OpcVulkan {
    private const val TAG = "OpcVulkan"

    val isAvailable: Boolean by lazy {
        try {
            System.loadLibrary("opc_vulkan")
            nativeProbe()
        } catch (error: Throwable) {
            Log.w(TAG, "vulkan library missing", error)
            false
        }
    }

    @JvmStatic external fun nativeProbe(): Boolean

    @JvmStatic external fun nativeCreate(): Long

    @JvmStatic external fun nativeDestroy(handle: Long)

    @JvmStatic external fun nativeAttachWindow(handle: Long, surface: Surface, w: Int, h: Int): Boolean

    @JvmStatic external fun nativeResize(handle: Long, w: Int, h: Int)

    @JvmStatic external fun nativeSubmit(handle: Long, buffer: HardwareBuffer): Boolean

    /** Re-present last imported frame with current slots (drag/resize, no new HEVC). */
    @JvmStatic external fun nativeRedraw(handle: Long): Boolean

    @JvmStatic external fun nativeSetFeedRect(handle: Long, x: Float, y: Float, w: Float, h: Float)

    @JvmStatic external fun nativeSetUiScale(handle: Long, scale: Float)

    @JvmStatic external fun nativeSetSlots(handle: Long, slots: FloatArray)

    /** Back-to-front GPU slot indices (WAVE=0, PARADE=1, VECTOR=3). */
    @JvmStatic external fun nativeSetStack(handle: Long, order: IntArray)

    @JvmStatic external fun nativeSetPlates(handle: Long, plates: FloatArray)

    @JvmStatic external fun nativeSetIre(
        handle: Long,
        ire: FloatArray,
        lumaR: Float,
        lumaG: Float,
        lumaB: Float,
        stride: Int,
    )

    @JvmStatic
    external fun nativeSetCube(
        handle: Long,
        slot: Int,
        rgba: ByteArray?,
        width: Int,
        height: Int,
        cubeSize: Float,
    )

    @JvmStatic external fun nativeSetFeedFlags(
        handle: Long,
        lutSize: Float,
        limitsOn: Float,
        splitOn: Float,
        splitVertical: Float,
        zebraHiOn: Float,
        zebraHi: Float,
        zebraMidOn: Float,
        zebraMid: Float,
        zebraMidHalf: Float,
        upscale: Float,
        mirror: Float,
    )

    @JvmStatic external fun nativeCopyHisto(handle: Long, out: IntArray)

    @JvmStatic external fun nativeSetNeedTap(handle: Long, on: Boolean)

    /** 213×120 RGBA8 tap (PocketScopeSampler.tapSize 1280×720). */
    @JvmStatic external fun nativeCopyTap(handle: Long, out: ByteArray): Boolean
}
