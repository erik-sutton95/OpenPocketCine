package com.opencapture.openpocketcine.assists

import com.opencapture.monitorui.MonitorGuideMaskPolicy
import com.opencapture.monitorui.settings.MonitorSettingsColorDot
import com.opencapture.opencine.cameracontrols.AssistHost
import com.opencapture.openpocketcine.settings.SettingsPalette

/** This app's assist values: its settings palettes, the envelope guide mask, and the calibration table before the first tap. */
internal val AppAssistHost = AssistHost(
    peakingColors = SettingsPalette.peaking.map { MonitorSettingsColorDot(it.name, it.color) },
    highlightColors = SettingsPalette.highlight.map { MonitorSettingsColorDot(it.name, it.color) },
    midtoneColors = SettingsPalette.midtone.map { MonitorSettingsColorDot(it.name, it.color) },
    guideMaskPolicy = MonitorGuideMaskPolicy.ENVELOPE,
    scopeCeiling = { it.scopeDisplayCeiling },
    rec709LookCurve = { com.opencapture.opencine.dji.DjiMonitorColorProfile.value.rec709LookCurves[it] },
)
