package com.opencapture.openpocketcine.lut

import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import com.opencapture.opencine.cameracontrols.LUTPicker
import com.opencapture.opencine.cameracontrols.LutPickerCopy
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.openpocketcine.AppModel

/** What this app's LUT picker says: the official cubes sit on the DJI tab with its own Auto. */
internal val AppLutPickerCopy = LutPickerCopy(
    cameraTab = "DJI",
    autoId = LutCatalog.OFFICIAL_AUTO,
    customHint = "Imported looks land here. Auto stays on Built-in or DJI.",
    noLookCaption = "No matching look for this color / camera",
    officialCubeCaption = "Official DJI Rec.709 cube",
    cameraLooksCaption = "Official DJI looks for this color / camera",
)

/** Settings sheet. Same body as the assist-tray form; 50/50 stays inline. */
@Composable
fun LUTPicker(model: AppModel, onClose: () -> Unit) {
    val assist = model.assist
    val status by model.session.chromeStatus.collectAsState()
    LUTPicker(
        copy = AppLutPickerCopy,
        selection = model.lutSelection,
        onSelect = model::updateLutSelection,
        onClose = onClose,
        embedded = false,
        splitComparison = assist.splitComparison,
        splitVertical = assist.splitVertical,
        lutExposureStops = assist.lutExposureStops,
        onToggleSplit = { assist.setSplitComparison(!assist.splitComparison) },
        onSplitVertical = { assist.setSplitComparison(assist.splitComparison, it) },
        onExposure = { assist.updateLutExposure(it) },
        onArmLut = { assist.armLut() },
        colorMode = status.monitorColorMode,
        profile = model.session.connectedCamera?.model?.captureProfile?.looks ?: com.opencapture.opencine.dji.DjiCameraLUTProfile.make("pocket", null),
        isPhoto = status.isPhoto,
    )
}
