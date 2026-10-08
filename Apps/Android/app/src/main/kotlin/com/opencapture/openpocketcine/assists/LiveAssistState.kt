package com.opencapture.openpocketcine.assists

import android.content.Context
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.opencine.appkit.MonitorInspectorScopeDemand
import com.opencapture.opencine.appkit.MonitorAssistState


fun createLiveAssistState(context: Context): MonitorAssistState {
    val app = context.applicationContext
    return MonitorAssistState(
        encoded = OperatorPrefs.assistEncoded(app),
        pinnedNames = OperatorPrefs.cleanViewPinnedTools(app),
        onPersist = { OperatorPrefs.setAssistEncoded(app, it) },
        onPersistPins = { OperatorPrefs.setCleanViewPinnedTools(app, it) },
        playbackNames = OperatorPrefs.playbackVisibleAssistTools(app),
        onPersistPlayback = { OperatorPrefs.setPlaybackVisibleAssistTools(app, it) },
    )
}

/** Before the first tap, use the source's existing calibration table, not a measurement. */
internal val MonitorAssistState.scopeDisplayCeiling: com.opencapture.opencine.media.ScopeClipSource
    get() = if (scopeBundle.isEmpty) com.opencapture.opencine.dji.DjiScopeExposureCeiling.UNOBSERVED
        else scopeCeiling
