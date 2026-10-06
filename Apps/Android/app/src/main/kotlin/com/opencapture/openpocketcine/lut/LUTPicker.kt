package com.opencapture.openpocketcine.lut

import com.opencapture.opencine.appkit.LocalOperatorHaptics
import com.opencapture.monitorui.MonitorLabelWheel
import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import com.opencapture.monitorui.monitorScrollFade
import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.OpenableColumns
import androidx.activity.compose.BackHandler
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.opencine.cameracontrols.chromeClickable
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.OpcIcon
import com.opencapture.openpocketcine.feed.LutLookResolver
import com.opencapture.openpocketcine.pairing.StartupColors
import java.io.File

private enum class LutTab(val label: String) {
    DJI("DJI"),
    CREATIVE("Creative"),
    CUSTOM("Custom"),
}

/** iOS `LUTPicker` landscape metrics — caption + drum, not a stretched well.
 * Catalog is ~15% taller than iOS 146 so the fade well can show neighbours. */
internal object LutPickerMetrics {
    const val CONTENT_DP = 168f
    const val CAPTION_DP = 28f
    const val ROW_DP = 52f
    const val WHEEL_GAP_DP = 4f
    const val SPLIT_TYPE_PT = 11f
    const val SPLIT_ICON_DP = 13f
    const val SPLIT_PAD_H_DP = 10f
    const val SPLIT_PAD_V_DP = 6f
    const val CLOSE_DP = 27f
}

private val LutContentHeight = LutPickerMetrics.CONTENT_DP.dp
private val LutCaptionHeight = LutPickerMetrics.CAPTION_DP.dp
private val LutDrumRowHeight = LutPickerMetrics.ROW_DP.dp


/** Settings sheet. Same body as the assist-tray form; 50/50 stays inline. */
@Composable
fun LUTPicker(model: AppModel, onClose: () -> Unit) {
    val assist = model.assist
    val status by model.session.chromeStatus.collectAsState()
    LUTPicker(
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
        family = model.session.connectedCamera?.model?.family ?: "pocket",
        cameraName = model.session.connectedCamera?.name,
        isPhoto = status.isPhoto,
    )
}

/**
 * Built-in / DJI / Custom catalog with an AccentDrumWheel (iOS `LUTPicker`).
 * `embedded` is the assist-tray form; the sheet wraps the same body.
 */
@Composable
internal fun LUTPicker(
    selection: String,
    onSelect: (String) -> Unit,
    embedded: Boolean,
    splitComparison: Boolean,
    splitVertical: Boolean,
    lutExposureStops: Double = 0.0,
    onToggleSplit: () -> Unit,
    onSplitVertical: (Boolean) -> Unit,
    onExposure: (Double) -> Unit = {},
    onArmLut: () -> Unit = {},
    onClose: (() -> Unit)? = null,
    colorMode: Int = CameraCommands.COLOR_NORMAL,
    family: String = "pocket",
    cameraName: String? = null,
    isPhoto: Boolean = false,
    modifier: Modifier = Modifier,
) {
    val context = LocalContext.current
    val djiEntries =
        remember(context, isPhoto) {
            val names = context.assets.list(LutCatalog.ASSET_DIRECTORY)?.toList().orEmpty()
            LutCatalog.djiEntries(names, isPhotoLive = isPhoto)
        }
    val creativeEntries = remember { LutCatalog.creative }
    var tab by remember {
        mutableStateOf(
            when (LutCatalog.categoryOf(selection)) {
                LutCategory.CREATIVE -> LutTab.CREATIVE
                LutCategory.CUSTOM -> LutTab.CUSTOM
                LutCategory.DJI -> LutTab.DJI
            }
        )
    }
    var customRevision by remember { mutableIntStateOf(0) }
    var pendingDeletion by remember { mutableStateOf<String?>(null) }
    var deletionError by remember { mutableStateOf<String?>(null) }
    var importError by remember { mutableStateOf<String?>(null) }
    val customDir = remember(context) { LutCatalog.customDirectory(context.filesDir) }
    val customEntries = remember(customRevision, customDir) { LutCatalog.listCustom(customDir) }
    val importer =
        rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
            if (uri == null) return@rememberLauncherForActivityResult
            runCatching { importCube(context, uri, customDir) }
                .onSuccess { entry ->
                    importError = null
                    customRevision += 1
                    val current = selection
                    if (current != LutCatalog.AUTO && current != LutCatalog.DJI_AUTO) {
                        onSelect(entry.id)
                    }
                    onArmLut()
                }
                .onFailure { error ->
                    importError = error.message ?: "The .cube file could not be read."
                }
        }

    val onTab: (LutTab) -> Unit = { next ->
        if (next != tab) {
            tab = next
            when (next) {
                LutTab.DJI ->
                    if (LutCatalog.categoryOf(selection) != LutCategory.DJI) {
                        onSelect(LutCatalog.DJI_AUTO)
                        onArmLut()
                    }
                LutTab.CREATIVE ->
                    if (LutCatalog.categoryOf(selection) != LutCategory.CREATIVE) {
                        onSelect("creativeMono")
                        onArmLut()
                    }
                LutTab.CUSTOM -> Unit
            }
        }
    }
    val onPick: (String) -> Unit = { id ->
        onSelect(id)
        onArmLut()
    }
    val body =
        @Composable {
            LUTPickerBody(
                modifier = modifier,
                tab = tab,
                onTab = onTab,
                selection = selection,
                onSelect = onPick,
                creativeEntries = creativeEntries,
                djiEntries = djiEntries,
                customEntries = customEntries,
                onImport = { importer.launch(arrayOf("*/*")) },
                onClear = { pendingDeletion = it },
                importError = importError,
                embedded = embedded,
                splitComparison = splitComparison,
                splitVertical = splitVertical,
                lutExposureStops = lutExposureStops,
                onToggleSplit = onToggleSplit,
                onSplitVertical = onSplitVertical,
                onExposure = onExposure,
                colorMode = colorMode,
                family = family,
                cameraName = cameraName,
                isPhoto = isPhoto,
            )
        }

    if (embedded) {
        body()
    } else {
        BackHandler(enabled = onClose != null, onBack = { onClose?.invoke() })
        Column(
            Modifier.fillMaxSize()
                .background(LiveDesign.background)
                .statusBarsPadding()
                .navigationBarsPadding()
                .padding(20.dp),
        ) {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                Text("LUT", color = LiveDesign.text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
                Spacer(Modifier.weight(1f))
                if (onClose != null) {
                    Text(
                        "Done",
                        color = LiveDesign.accent,
                        fontSize = 16.sp,
                        fontWeight = FontWeight.SemiBold,
                        modifier =
                            Modifier.chromeClickable(onClick = onClose)
                                .padding(horizontal = 8.dp, vertical = 4.dp),
                    )
                }
            }
            Spacer(Modifier.height(12.dp))
            body()
        }
    }

    val pending = pendingDeletion
    if (pending != null) {
        AlertDialog(
            onDismissRequest = { pendingDeletion = null },
            title = { Text("Clear ${LutCatalog.displayName(pending)}?") },
            text = { Text("This removes the stored LUT from this device. This action cannot be undone.") },
            confirmButton = {
                TextButton(
                    onClick = {
                        pendingDeletion = null
                        runCatching { LutCatalog.deleteCustom(pending, customDir) }
                            .onSuccess {
                                customRevision += 1
                                if (selection == LutCatalog.customId(pending)) {
                                    onSelect(LutCatalog.AUTO)
                                    onArmLut()
                                }
                            }
                            .onFailure { error ->
                                deletionError = error.message ?: "The LUT could not be deleted."
                            }
                    }
                ) { Text("Clear LUT", color = StartupColors.destructive) }
            },
            dismissButton = { TextButton(onClick = { pendingDeletion = null }) { Text("Cancel") } },
        )
    }
    if (deletionError != null) {
        AlertDialog(
            onDismissRequest = { deletionError = null },
            title = { Text("Couldn’t Delete LUT") },
            text = { Text(deletionError ?: "The LUT could not be deleted.") },
            confirmButton = { TextButton(onClick = { deletionError = null }) { Text("OK") } },
        )
    }
}

@Composable
private fun LUTPickerBody(
    modifier: Modifier = Modifier,
    tab: LutTab,
    onTab: (LutTab) -> Unit,
    selection: String,
    onSelect: (String) -> Unit,
    creativeEntries: List<LutEntry>,
    djiEntries: List<LutEntry>,
    customEntries: List<LutEntry>,
    onImport: () -> Unit,
    onClear: (String) -> Unit,
    importError: String?,
    embedded: Boolean,
    splitComparison: Boolean,
    splitVertical: Boolean,
    lutExposureStops: Double,
    onToggleSplit: () -> Unit,
    onSplitVertical: (Boolean) -> Unit,
    onExposure: (Double) -> Unit,
    colorMode: Int,
    family: String,
    cameraName: String?,
    isPhoto: Boolean,
) {
    BoxWithConstraints(
        modifier
            .fillMaxWidth()
            .then(if (embedded) Modifier.fillMaxHeight() else Modifier),
    ) {
        val tabBlock = 44.dp
        val tabGap = 8.dp
        val contentH =
            if (constraints.hasBoundedHeight) {
                (maxHeight - tabBlock - tabGap).coerceAtLeast(LutDrumRowHeight)
            } else {
                LutContentHeight
            }
        Column(
            Modifier.fillMaxWidth().wrapContentHeight(),
            verticalArrangement = Arrangement.spacedBy(tabGap),
        ) {
        val haptics = LocalOperatorHaptics.current
        Row(Modifier.fillMaxWidth().monitorTabStrip()) {
            LutTab.entries.forEachIndexed { index, item ->
                MonitorTab(item == tab, { haptics.selection(); onTab(item) }, Modifier.weight(1f),
                    separator = index > 0, accessibilityLabel = item.label) {
                    Text(item.label, style = LiveType.ui(13f, FontWeight.SemiBold),
                        color = if (item == tab) LiveDesign.accent else LiveDesign.muted, maxLines = 1)
                }
            }
        }
        Box(Modifier.fillMaxWidth().height(contentH)) {
            when (tab) {
                LutTab.DJI ->
                    CatalogTab(
                        caption = djiCaption(selection, colorMode, family, cameraName, isPhoto),
                        entries = djiEntries,
                        selection = selection,
                        fallbackId = LutCatalog.DJI_AUTO,
                        onSelect = onSelect,
                        contentHeight = contentH,
                    )
                LutTab.CREATIVE ->
                    CatalogTab(
                        caption = creativeCaption(selection, colorMode, family, cameraName, isPhoto),
                        entries = creativeEntries,
                        selection = selection,
                        fallbackId = "creativeMono",
                        onSelect = onSelect,
                        contentHeight = contentH,
                    )
                LutTab.CUSTOM ->
                    CustomTab(
                        imported = customEntries,
                        selection = selection,
                        onImport = onImport,
                        onSelect = onSelect,
                        onClear = onClear,
                    )
            }
        }
        if (!embedded) {
            LUTSplitComparisonBar(
                splitComparison = splitComparison,
                splitVertical = splitVertical,
                lutExposureStops = lutExposureStops,
                onToggleSplit = onToggleSplit,
                onSplitVertical = onSplitVertical,
                onExposure = onExposure,
            )
        }
        if (importError != null) {
            Text(
                importError,
                color = StartupColors.destructive,
                fontSize = 12.sp,
            )
        }
        }
    }
}

@Composable
private fun CatalogTab(
    caption: String,
    entries: List<LutEntry>,
    selection: String,
    fallbackId: String,
    onSelect: (String) -> Unit,
    contentHeight: Dp = LutContentHeight,
) {
    val inCatalog = entries.any { LutCatalog.matches(it, selection) }
    val wheelSelection = if (inCatalog) selection else fallbackId
    val gap = LutPickerMetrics.WHEEL_GAP_DP.dp
    val captionH = if (contentHeight >= LutContentHeight) LutCaptionHeight else 18.dp
    val minCaptioned = captionH + LutDrumRowHeight
    val showCaption = contentHeight >= minCaptioned
    val captionGap = if (showCaption && contentHeight >= minCaptioned + gap) gap else 0.dp
    val drumH =
        if (showCaption) {
            (contentHeight - captionH - captionGap).coerceAtLeast(LutDrumRowHeight)
        } else {
            contentHeight.coerceAtLeast(LutDrumRowHeight)
        }
    Column(
        Modifier.fillMaxWidth().height(contentHeight),
        verticalArrangement = Arrangement.spacedBy(captionGap),
    ) {
        if (showCaption) {
            Box(
                Modifier.fillMaxWidth().height(captionH),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    caption,
                    style = LiveType.ui(11f, FontWeight.Medium),
                    color = LiveDesign.muted,
                    textAlign = TextAlign.Center,
                    modifier = Modifier.fillMaxWidth(),
                )
            }
        }
        val haptics = LocalOperatorHaptics.current
        MonitorLabelWheel(
            entries = entries,
            selection = wheelSelection,
            matches = LutCatalog::matches,
            key = { it.id },
            label = { it.title },
            onSelect = { onSelect(it.id) },
            rowHeight = LutDrumRowHeight,
            wheelHeight = drumH,
            onClickFeedback = { haptics.selection() },
        )
    }
}

@Composable
private fun CustomTab(
    imported: List<LutEntry>,
    selection: String,
    onImport: () -> Unit,
    onSelect: (String) -> Unit,
    onClear: (String) -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Box(
            Modifier.fillMaxWidth()
                .clip(RoundedCornerShape(50))
                .background(LiveDesign.glassBright)
                .clickable(onClick = onImport)
                .padding(vertical = 8.dp),
            contentAlignment = Alignment.Center,
        ) {
            Text("Import .cube", color = LiveDesign.text, fontSize = 13.sp, fontWeight = FontWeight.SemiBold)
        }
        Spacer(Modifier.height(6.dp))
        if (imported.isEmpty()) {
            Box(Modifier.weight(1f).fillMaxWidth(), contentAlignment = Alignment.Center) {
                Text(
                    "Imported looks land here. Auto stays on Built-in or DJI.",
                    color = LiveDesign.muted,
                    fontSize = 11.sp,
                    fontWeight = FontWeight.Medium,
                )
            }
        } else {
            val importedScroll = rememberScrollState()
            Column(Modifier.weight(1f).fillMaxWidth().monitorScrollFade(importedScroll).verticalScroll(importedScroll)) {
                imported.forEach { entry ->
                    val selected = LutCatalog.matches(entry, selection)
                    val fileName = entry.fileName ?: return@forEach
                    Row(
                        Modifier.fillMaxWidth()
                            .clip(RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp))
                            .background(if (selected) LiveDesign.accentDim else LiveDesign.glassBright)
                            .padding(horizontal = 10.dp, vertical = 6.dp),
                        verticalAlignment = Alignment.CenterVertically,
                        horizontalArrangement = Arrangement.spacedBy(6.dp),
                    ) {
                        Text(
                            entry.title,
                            color = if (selected) LiveDesign.accent else LiveDesign.text,
                            fontSize = 13.sp,
                            fontWeight = FontWeight.SemiBold,
                            maxLines = 1,
                            overflow = TextOverflow.Ellipsis,
                            modifier =
                                Modifier.weight(1f)
                                    .clickable { onSelect(entry.id) }
                                    .padding(vertical = 6.dp),
                        )
                        Box(
                            Modifier.clip(RoundedCornerShape(50))
                                .background(LiveDesign.glassBright)
                                .clickable { onClear(fileName) }
                                .padding(horizontal = 8.dp, vertical = 6.dp),
                        ) {
                            Text("Clear", color = StartupColors.destructive, fontSize = 12.sp, fontWeight = FontWeight.SemiBold)
                        }
                    }
                    Spacer(Modifier.height(6.dp))
                }
            }
        }
    }
}

/** Absolute half-stop slider over the existing input-referred LUT compensation. */
@Composable
internal fun LUTExposureCompensationBar(stops: Double, onChange: (Double) -> Unit,
    modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth()) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("Exposure", style = LiveType.ui(11f, FontWeight.Medium), color = LiveDesign.text)
            Spacer(Modifier.weight(1f))
            Text(LutExposureCompensation.label(stops) + " EV", style = LiveType.ui(11f, FontWeight.Medium),
                color = LiveDesign.muted)
        }
        com.opencapture.monitorui.MonitorSlider(stops.toFloat(), -3f..3f,
            Modifier.semantics { contentDescription = "Exposure compensation in stops" }) {
            val next = LutExposureCompensation.snap(it.toDouble())
            if (next != stops) onChange(next)
        }
    }
}

/** OpenZCine 50/50: off-by-default; orientation chips only while armed. */
@Composable
internal fun LUTSplitComparisonBar(
    splitComparison: Boolean,
    splitVertical: Boolean,
    lutExposureStops: Double = 0.0,
    onToggleSplit: () -> Unit,
    onSplitVertical: (Boolean) -> Unit,
    onExposure: (Double) -> Unit = {},
    modifier: Modifier = Modifier,
) {
    Column(modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(8.dp)) {
        LUTExposureCompensationBar(stops = lutExposureStops, onChange = onExposure)
        Row(
            Modifier.fillMaxWidth(),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("Split comparison", style = LiveType.ui(11f, FontWeight.Medium), color = LiveDesign.text)
            Spacer(Modifier.weight(1f))
            Row(
                Modifier.clip(RoundedCornerShape(50))
                    .background(if (splitComparison) LiveDesign.accentDim else LiveDesign.glassBright)
                    .chromeClickable(onClick = onToggleSplit)
                    .padding(
                        horizontal = LutPickerMetrics.SPLIT_PAD_H_DP.dp,
                        vertical = LutPickerMetrics.SPLIT_PAD_V_DP.dp,
                    ),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(6.dp),
            ) {
                OpcIcon(
                    icon = if (splitComparison) OpcIcon.CIRCLE_CHECK else OpcIcon.CIRCLE,
                    contentDescription = null,
                    tint = if (splitComparison) LiveDesign.accent else LiveDesign.muted,
                    modifier = Modifier.size(LutPickerMetrics.SPLIT_ICON_DP.dp),
                )
                Text(
                    "50/50",
                    style = LiveType.ui(LutPickerMetrics.SPLIT_TYPE_PT, FontWeight.SemiBold),
                    color = LiveDesign.text,
                )
            }
        }
        if (splitComparison) {
            LutSegmentedButtons(
                items = listOf("Left / Right", "Top / Bottom"),
                selected = if (splitVertical) "Left / Right" else "Top / Bottom",
            ) { label ->
                onSplitVertical(label == "Left / Right")
            }
        }
    }
}

@Composable
private fun LutSegmentedButtons(
    items: List<String>,
    selected: String,
    modifier: Modifier = Modifier,
    onSelect: (String) -> Unit,
) {
    Row(modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        items.forEach { item ->
            val on = item == selected
            Box(
                Modifier.weight(1f)
                    .clip(RoundedCornerShape(50))
                    .background(if (on) LiveDesign.accent else LiveDesign.glassBright)
                    .chromeClickable { onSelect(item) }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    item,
                    style = LiveType.ui(13f, FontWeight.SemiBold),
                    color = if (on) Color(0xFF08191F) else LiveDesign.muted,
                    maxLines = 1,
                )
            }
        }
    }
}

/**
 * iOS `AccentDrumWheel`: snapping wheel — the settled row renders large in
 * accent between two hairlines; neighbours sit in the 0.22 / 0.78 fade.
 */
private fun creativeCaption(
    selection: String,
    colorMode: Int,
    family: String,
    cameraName: String?,
    isPhoto: Boolean,
): String =
    if (LutCatalog.categoryOf(selection) == LutCategory.CREATIVE) {
        LutLookResolver.autoCaption(
            LutLookResolver.resolve(selection, true, colorMode, family, cameraName, isPhoto),
        )
    } else {
        "Looks for the displayed picture"
    }

private fun djiCaption(
    selection: String,
    colorMode: Int,
    family: String,
    cameraName: String?,
    isPhoto: Boolean,
): String =
    if (isPhoto) {
        LutCatalog.PHOTO_REC709_CAPTION
    } else when (selection) {
        LutCatalog.AUTO, LutCatalog.DJI_AUTO ->
            LutLookResolver.autoCaption(
                LutLookResolver.resolve(selection, true, colorMode, family, cameraName, isPhoto),
            )
        else ->
            if (LutCatalog.categoryOf(selection) == LutCategory.DJI) {
                "Official DJI Rec.709 cube"
            } else {
                "Official DJI looks for this color / camera"
            }
    }

private fun importCube(context: Context, uri: Uri, directory: File): LutEntry {
    runCatching {
        context.contentResolver.takePersistableUriPermission(uri, Intent.FLAG_GRANT_READ_URI_PERMISSION)
    }
    val rawName = queryDisplayName(context, uri) ?: uri.lastPathSegment ?: "Imported.cube"
    val bytes =
        context.contentResolver.openInputStream(uri)?.use { it.readBytes() }
            ?: throw IllegalStateException("The .cube file could not be read.")
    return LutCatalog.importCube(rawName, bytes, directory)
}

private fun queryDisplayName(context: Context, uri: Uri): String? {
    val cursor = context.contentResolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)
    cursor?.use {
        if (it.moveToFirst()) {
            val index = it.getColumnIndex(OpenableColumns.DISPLAY_NAME)
            if (index >= 0) return it.getString(index)
        }
    }
    return null
}
