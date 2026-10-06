package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.monitorChromeEditStroke
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import com.opencapture.monitorui.MonitorSystemControls
import com.opencapture.monitorui.MonitorSystemControlsVisibility
import com.opencapture.monitorui.monitorPickerPassthrough
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.cameracontrols.LockButton
import com.opencapture.monitorui.MonitorIcon

/** App display customization and the native photo adapter over the shared system composition. */
@Composable
internal fun LiveSystemChrome(model: AppModel, layout: LiveMonitorLayout,
    uiLocked: Boolean, onLock: () -> Unit, capturePresented: Boolean,
    navigationHidden: Boolean, interactive: Boolean, controlBusy: Boolean, onDisplay: () -> Unit, onMode: () -> Unit) {
    val field = checkNotNull(layout.field)
    val control by model.control.state.collectAsState()
    val editing = model.chromeEditorMode
    val visibility = MonitorSystemControlsVisibility(
        lock = model.multiviewExit != null || model.chromeSectionMounts(PocketDispSection.LOCK_BUTTON),
        settings = model.chromeSectionMounts(PocketDispSection.RAIL_SETTINGS),
        media = model.chromeSectionMounts(PocketDispSection.RAIL_MEDIA),
        record = model.chromeSectionMounts(PocketDispSection.RAIL_RECORD),
    ).resolved(uiLocked, model.control.isRecording, model.session.isMultiviewBorrowed)
    // Keep collection in this bounded observation scope, away from native picture geometry.
    control
    fun decoration() = Modifier.monitorChromeEditStroke(editing != null, true)
    MonitorSystemControls(field, visibility, capturePresented = capturePresented,
        navigationHidden = navigationHidden, interactive = interactive,
        lock = { enabled ->
            val exit = model.multiviewExit
            if (exit != null) MultiviewReturnButton(onClick = exit)
            else LockButton(uiLocked, decoration(), enabled = enabled, onClick = onLock)
        },
        settings = { enabled ->
            AuxCircleButton(decoration().monitorPickerPassthrough(enabled && !uiLocked), enabled = enabled && !uiLocked,
                onClick = { model.shell.open(ShellModel.Cover.SETTINGS) }) {
                MonitorIcon(MonitorIcon.SETTINGS, "Settings", Modifier.fillMaxSize(), it)
            }
        },
        media = { enabled ->
            AuxCircleButton(decoration().monitorPickerPassthrough(enabled && !uiLocked), enabled = enabled && !uiLocked,
                onClick = { model.shell.open(ShellModel.Cover.MEDIA) }) {
                MonitorIcon(MonitorIcon.FILM, "Media", Modifier.fillMaxSize(), it)
            }
        },
        record = { enabled -> LiveCaptureButton(model, enabled && !controlBusy && !uiLocked,
            field.record.width, decoration(), openMode = onMode) },
        display = { enabled ->
            com.opencapture.monitorui.MonitorDisplayButton(model.assistClean,
                field.display.width, field.display.height, enabled = enabled && !uiLocked,
                onClick = onDisplay)
        })
}
