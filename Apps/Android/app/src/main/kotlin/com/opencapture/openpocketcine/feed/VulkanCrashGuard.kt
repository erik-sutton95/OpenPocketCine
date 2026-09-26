package com.opencapture.openpocketcine.feed

import android.content.Context
import android.util.Log
import androidx.core.content.edit
import com.opencapture.openpocketcine.BuildConfig

/**
 * Breaks a native crash loop in vendor AHB import. MediaTek Mali drivers can
 * SIGSEGV inside vkAllocateMemory (gralloc_extra_query, Sentry
 * OPENPOCKETCINE-ANDROID-E), which kills the process before [LiveVulkanSession]
 * can report failure. Each new decoder ImageReader arms the guard; the first
 * frames clear it. A window that never cleared means the process died while
 * importing. [STRIKES_TO_DISABLE] such launches in a row turn Vulkan off for
 * this app version, and Live View uses the decoder surface path instead.
 */
internal object VulkanCrashGuard {
    private const val TAG = "VulkanCrashGuard"
    private const val PREFS = "openpocketcine.vulkan_guard"
    private const val KEY_VERSION = "version"
    private const val KEY_ARMED = "armed"
    private const val KEY_STRIKES = "strikes"
    const val STRIKES_TO_DISABLE = 2
    /** More than the ImageReader pool (5), so every pooled buffer has been imported. */
    const val FRAMES_TO_CLEAR = 15

    data class State(val version: Int, val armed: Boolean, val strikes: Int)

    /** Launch-time transition: an armed window left over from the last process is a strike. */
    fun atLaunch(stored: State, version: Int): State =
        when {
            stored.version != version -> State(version, armed = false, strikes = 0)
            stored.armed -> State(version, armed = false, strikes = stored.strikes + 1)
            else -> stored
        }

    fun isTripped(state: State): Boolean = state.strikes >= STRIKES_TO_DISABLE

    @Volatile private var launchState: State? = null

    @Synchronized
    fun isTripped(context: Context): Boolean = isTripped(launch(context))

    /**
     * Call before the first frame of a new ImageReader. Commits synchronously:
     * the flag must be on disk before a driver fault can kill the process.
     */
    @Synchronized
    fun arm(context: Context) {
        launch(context)
        prefs(context).edit(commit = true) { putBoolean(KEY_ARMED, true) }
    }

    @Synchronized
    fun clear(context: Context) {
        launch(context)
        prefs(context).edit { putBoolean(KEY_ARMED, false).putInt(KEY_STRIKES, 0) }
    }

    private fun launch(context: Context): State {
        launchState?.let { return it }
        val p = prefs(context)
        val stored = State(p.getInt(KEY_VERSION, -1), p.getBoolean(KEY_ARMED, false), p.getInt(KEY_STRIKES, 0))
        val next = atLaunch(stored, BuildConfig.VERSION_CODE)
        if (next != stored) {
            p.edit(commit = true) {
                putInt(KEY_VERSION, next.version)
                putBoolean(KEY_ARMED, next.armed)
                putInt(KEY_STRIKES, next.strikes)
            }
        }
        if (isTripped(next)) Log.w(TAG, "Vulkan disabled after ${next.strikes} crashed import windows")
        launchState = next
        return next
    }

    private fun prefs(context: Context) =
        context.applicationContext.getSharedPreferences(PREFS, Context.MODE_PRIVATE)
}
