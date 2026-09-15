package com.opencapture.openpocketcine

import android.view.Window
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat

/** Live view hides both bars; pages retain navigation while hiding the status bar. */
fun applyMonitorSystemBars(window: Window, hideNavigation: Boolean = false) {
    WindowCompat.getInsetsController(window, window.decorView).apply {
        systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        if (hideNavigation) hide(WindowInsetsCompat.Type.navigationBars())
        else show(WindowInsetsCompat.Type.navigationBars())
        hide(WindowInsetsCompat.Type.statusBars())
    }
}
