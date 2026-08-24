package com.opencapture.openpocketcine.lut

import com.opencapture.openpocketcine.session.CameraCommands

/**
 * iOS `PlaybackLUTColor`. `nclx` is Rec.709 even for D-Log2; the shot profile
 * is `com.dji.camera.ColorGammaSxS` on the **original** take. LRF / XRF
 * proxies are Rec.709 even for log — pass `clip` only from the original.
 * That clip value wins. Live `@2` is the body's current SET — used only when
 * the original has no Keys atom.
 */
internal object PlaybackLutColor {
    fun bindsAutoLut(code: Int): Boolean =
        when (code) {
            CameraCommands.COLOR_DLOG, CameraCommands.COLOR_DLOG2, CameraCommands.COLOR_DLOG_M ->
                true
            else -> false
        }

    fun resolve(live: Int, last: Int): Int = resolve(clip = -1, live = live, last = last)

    fun resolve(clip: Int, live: Int, last: Int): Int {
        if (clip >= 0) return clip
        val liveMode = live.takeIf { it >= 0 }
        val lastMode = last.takeIf { it >= 0 }
        if (lastMode != null && bindsAutoLut(lastMode)) {
            if (liveMode == null || !bindsAutoLut(liveMode)) return lastMode
        }
        return liveMode ?: lastMode ?: -1
    }
}
