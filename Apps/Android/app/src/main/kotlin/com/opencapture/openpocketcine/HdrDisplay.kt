package com.opencapture.openpocketcine

import android.app.Activity
import android.content.pm.ActivityInfo
import android.os.Build
import android.view.SurfaceView
import android.view.Window
import android.view.WindowManager

/**
 * Outdoor HDR panel boost for live view. Window-level: the camera picture stays
 * Rec.709 / log and WAVE / HISTO still measure decoded codes. Matches iOS
 * `LiveHDRDisplay.requestedHeadroom`.
 */
object HdrDisplay {
    const val REQUESTED_HEADROOM = 3f

    fun isEffective(preferred: Boolean, screenCaptured: Boolean): Boolean =
        preferred && !screenCaptured

    fun apply(window: Window, enabled: Boolean) {
        window.colorMode =
            if (enabled) ActivityInfo.COLOR_MODE_HDR else ActivityInfo.COLOR_MODE_DEFAULT
        if (Build.VERSION.SDK_INT >= 35) {
            window.setDesiredHdrHeadroom(if (enabled) REQUESTED_HEADROOM else 0f)
        }
        val params = window.attributes
        params.screenBrightness =
            if (enabled) {
                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_FULL
            } else {
                WindowManager.LayoutParams.BRIGHTNESS_OVERRIDE_NONE
            }
        window.attributes = params
    }

    fun apply(activity: Activity?, enabled: Boolean) {
        val window = activity?.window ?: return
        apply(window, enabled)
    }

    fun apply(surfaceView: SurfaceView, enabled: Boolean) {
        if (Build.VERSION.SDK_INT >= 35) {
            surfaceView.setDesiredHdrHeadroom(if (enabled) REQUESTED_HEADROOM else 0f)
        }
    }
}
