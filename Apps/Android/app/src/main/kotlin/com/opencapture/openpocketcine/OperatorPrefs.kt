package com.opencapture.openpocketcine

import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import android.content.Context
import androidx.core.content.edit
import com.opencapture.opencine.cameracontrols.OperatorPreferenceStore
import com.opencapture.opencine.runtime.MonitorGlesUpscaler
import com.opencapture.monitorui.settings.MonitorSettingsTab
import com.opencapture.opencine.appkit.MonitorDisplaySection
import com.opencapture.opencine.appkit.MonitorDisplayChrome
import com.opencapture.opencine.appkit.MonitorDisplayMode



/** The operator's choices in this app's existing preferences file and keys. */
object OperatorPrefs : OperatorPreferenceStore(file = "openpocketcine.operator", keyPrefix = "OpenPocketCine.") {
    private val FEED_UPSCALER = key("feedUpscaler")

    fun feedUpscaler(context: Context): MonitorGlesUpscaler =
        MonitorGlesUpscaler.fromStored(prefs(context).getString(FEED_UPSCALER, null))

    fun setFeedUpscaler(context: Context, value: MonitorGlesUpscaler) {
        prefs(context).edit { putString(FEED_UPSCALER, value.label) }
        AppDiagnostics.reporting.noteFeedUpscaler(value.label)
    }
}
