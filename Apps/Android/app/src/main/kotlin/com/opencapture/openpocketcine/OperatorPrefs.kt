package com.opencapture.openpocketcine

import android.content.Context
import androidx.core.content.edit
import com.opencapture.opencine.cameracontrols.OperatorPreferenceStore
import com.opencapture.openpocketcine.feed.FeedUpscaler

typealias PocketDispMode = com.opencapture.opencine.appkit.MonitorDisplayMode
typealias PocketDispSection = com.opencapture.opencine.appkit.MonitorDisplaySection
typealias PocketDispChrome = com.opencapture.opencine.appkit.MonitorDisplayChrome

typealias OperatorSettingsTab = com.opencapture.monitorui.settings.MonitorSettingsTab

enum class LiveOperatorPanel {
    SETTINGS,
    MEDIA,
}

/** The operator's choices in this app's existing preferences file and keys. */
object OperatorPrefs : OperatorPreferenceStore(file = "openpocketcine.operator", keyPrefix = "OpenPocketCine.") {
    private val FEED_UPSCALER = key("feedUpscaler")

    fun feedUpscaler(context: Context): FeedUpscaler =
        FeedUpscaler.fromStored(prefs(context).getString(FEED_UPSCALER, null))

    fun setFeedUpscaler(context: Context, value: FeedUpscaler) {
        prefs(context).edit { putString(FEED_UPSCALER, value.label) }
    }
}
