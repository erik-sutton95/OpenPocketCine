package com.opencapture.openpocketcine.lut

import android.content.Context
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.cameracontrols.LUTPicker
import com.opencapture.opencine.cameracontrols.LutPickerCopy
import com.opencapture.opencine.cameracontrols.MonitorLutCategory
import com.opencapture.opencine.cameracontrols.MonitorLutLibrary
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.LutCatalog
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.bridge.SwiftCore

/** What this app's LUT picker says: the official cubes sit on the DJI tab with its own Auto. */
internal val AppLutPickerCopy = LutPickerCopy(
    cameraTab = "DJI",
    autoId = LutCatalog.OFFICIAL_AUTO,
    customHint = "Imported looks land here. Auto stays on Built-in or DJI.",
    noLookCaption = "No matching look for this color / camera",
    officialCubeCaption = "Official DJI Rec.709 cube",
    cameraLooksCaption = "Official DJI looks for this color / camera",
)

private var processLutLibrary: MonitorLutLibrary? = null

/**
 * The process's one custom LUT library. The Swift facade's `packImportedLut` runs the shared
 * `CubeLUT.validatedImport` gate, so a cube it refuses is never stored.
 */
@Synchronized
internal fun appLutLibrary(context: Context): MonitorLutLibrary = processLutLibrary ?: MonitorLutLibrary(
    mapOf(MonitorLutCategory.CUSTOM to LutCatalog.customDirectory(context.applicationContext.filesDir)),
    pack = { bytes -> if (SwiftCore.isAvailable) SwiftCore.packImportedLut(bytes, 0.0, CameraCommands.COLOR_NORMAL) else null },
).also { processLutLibrary = it }

/** Settings sheet. Same body as the assist-tray form; 50/50 stays inline. */
@Composable
fun LUTPicker(model: AppModel, onClose: () -> Unit) {
    val assist = model.assist
    val status by model.session.chromeStatus.collectAsState()
    LUTPicker(
        copy = AppLutPickerCopy,
        selection = model.lutSelection,
        onSelect = model::updateLutSelection,
        library = appLutLibrary(LocalContext.current),
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
