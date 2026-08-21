package com.opencapture.openpocketcine.lut

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
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material.icons.Icons
import androidx.compose.material.icons.filled.CheckCircle
import androidx.compose.material.icons.outlined.RadioButtonUnchecked
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.pairing.StartupColors
import java.io.File

private enum class LutTab(val label: String) {
    BUILT_IN("Built-in"),
    DJI("DJI"),
    CUSTOM("Custom"),
}

@Composable
fun LUTPicker(model: AppModel, onClose: () -> Unit) {
    val context = LocalContext.current
    val djiEntries =
        remember(context) {
            val names = context.assets.list(LutCatalog.ASSET_DIRECTORY)?.toList().orEmpty()
            LutCatalog.djiEntries(names)
        }
    var tab by remember {
        mutableStateOf(
            when (LutCatalog.categoryOf(model.lutSelection)) {
                LutCategory.DJI -> LutTab.DJI
                LutCategory.CUSTOM -> LutTab.CUSTOM
                LutCategory.BUILT_IN -> LutTab.BUILT_IN
            }
        )
    }
    var splitComparison by remember { mutableStateOf(false) }
    var splitVertical by remember { mutableStateOf(true) }
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
                    val current = model.lutSelection
                    if (current != LutCatalog.AUTO && current != LutCatalog.DJI_AUTO) {
                        model.updateLutSelection(entry.id)
                    }
                }
                .onFailure { error ->
                    importError = error.message ?: "The .cube file could not be read."
                }
        }

    BackHandler(onBack = onClose)
    Column(
        Modifier.fillMaxSize()
            .background(LiveDesign.background)
            .statusBarsPadding()
            .navigationBarsPadding()
            .padding(20.dp)
    ) {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Text("LUT", color = LiveDesign.text, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            Spacer(Modifier.weight(1f))
            Text(
                "Done",
                color = LiveDesign.accent,
                fontSize = 16.sp,
                fontWeight = FontWeight.SemiBold,
                modifier = Modifier.chromeClickable(onClick = onClose).padding(horizontal = 8.dp, vertical = 4.dp),
            )
        }
        Spacer(Modifier.height(12.dp))
        LutSegmentedButtons(
            items = LutTab.entries.map { it.label },
            selected = tab.label,
        ) { label ->
            val next = LutTab.entries.first { it.label == label }
            if (next == tab) return@LutSegmentedButtons
            tab = next
            when (next) {
                LutTab.BUILT_IN ->
                    if (LutCatalog.categoryOf(model.lutSelection) != LutCategory.BUILT_IN) {
                        model.updateLutSelection(LutCatalog.AUTO)
                    }
                LutTab.DJI ->
                    if (LutCatalog.categoryOf(model.lutSelection) != LutCategory.DJI) {
                        model.updateLutSelection(LutCatalog.DJI_AUTO)
                    }
                LutTab.CUSTOM -> Unit
            }
        }
        Spacer(Modifier.height(8.dp))
        Column(Modifier.weight(1f).fillMaxWidth()) {
            when (tab) {
                LutTab.BUILT_IN ->
                    CatalogTab(
                        caption = builtInCaption(model.lutSelection),
                        entries = LutCatalog.builtIn,
                        selection = model.lutSelection,
                        onSelect = model::updateLutSelection,
                    )
                LutTab.DJI ->
                    CatalogTab(
                        caption = djiCaption(model.lutSelection),
                        entries = djiEntries,
                        selection = model.lutSelection,
                        onSelect = model::updateLutSelection,
                    )
                LutTab.CUSTOM ->
                    CustomTab(
                        imported = customEntries,
                        selection = model.lutSelection,
                        onImport = { importer.launch(arrayOf("*/*")) },
                        onSelect = model::updateLutSelection,
                        onClear = { pendingDeletion = it },
                    )
            }
        }
        Spacer(Modifier.height(8.dp))
        LutSplitComparisonBar(
            splitComparison = splitComparison,
            splitVertical = splitVertical,
            onToggleSplit = { splitComparison = !splitComparison },
            onSplitVertical = { splitVertical = it },
        )
        if (importError != null) {
            Text(
                importError.orEmpty(),
                color = StartupColors.destructive,
                fontSize = 12.sp,
                modifier = Modifier.padding(top = 8.dp),
            )
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
                                if (model.lutSelection == LutCatalog.customId(pending)) {
                                    model.updateLutSelection(LutCatalog.AUTO)
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
private fun CatalogTab(
    caption: String,
    entries: List<LutEntry>,
    selection: String,
    onSelect: (String) -> Unit,
) {
    Column(Modifier.fillMaxSize()) {
        Text(
            caption,
            color = LiveDesign.muted,
            fontSize = 11.sp,
            fontWeight = FontWeight.Medium,
            modifier = Modifier.fillMaxWidth().padding(bottom = 4.dp),
        )
        Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
            entries.forEach { entry ->
                val selected = LutCatalog.matches(entry, selection)
                Text(
                    entry.title,
                    color = if (selected) LiveDesign.accent else LiveDesign.muted.copy(alpha = 0.7f),
                    fontSize = if (selected) 22.sp else 16.sp,
                    fontWeight = if (selected) FontWeight.SemiBold else FontWeight.Normal,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier =
                        Modifier.fillMaxWidth()
                            .clip(RoundedCornerShape(12.dp))
                            .background(if (selected) LiveDesign.accentDim else LiveDesign.glassBright)
                            .clickable { onSelect(entry.id) }
                            .padding(horizontal = 12.dp, vertical = 14.dp),
                )
                Spacer(Modifier.height(6.dp))
            }
        }
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
            Column(Modifier.weight(1f).fillMaxWidth().verticalScroll(rememberScrollState())) {
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

@Composable
private fun LutSplitComparisonBar(
    splitComparison: Boolean,
    splitVertical: Boolean,
    onToggleSplit: () -> Unit,
    onSplitVertical: (Boolean) -> Unit,
) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
        Row(
            Modifier.clip(RoundedCornerShape(50))
                .background(if (splitComparison) LiveDesign.accentDim else LiveDesign.glassBright)
                .clickable(onClick = onToggleSplit)
                .padding(horizontal = 12.dp, vertical = 8.dp),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(8.dp),
        ) {
            Icon(
                imageVector = if (splitComparison) Icons.Filled.CheckCircle else Icons.Outlined.RadioButtonUnchecked,
                contentDescription = null,
                tint = if (splitComparison) LiveDesign.accent else LiveDesign.muted,
                modifier = Modifier.size(18.dp),
            )
            Text("50/50", color = LiveDesign.text, fontSize = 14.sp, fontWeight = FontWeight.SemiBold)
        }
        if (splitComparison) {
            LutSegmentedButtons(
                items = listOf("Left / Right", "Top / Bottom"),
                selected = if (splitVertical) "Left / Right" else "Top / Bottom",
                modifier = Modifier.weight(1f),
            ) { label ->
                onSplitVertical(label == "Left / Right")
            }
        } else {
            Spacer(Modifier.weight(1f))
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
                    .background(if (on) LiveDesign.accentDim else LiveDesign.glassBright)
                    .clickable { onSelect(item) }
                    .padding(vertical = 10.dp),
                contentAlignment = Alignment.Center,
            ) {
                Text(
                    item,
                    color = if (on) LiveDesign.accent else LiveDesign.muted,
                    fontSize = 13.sp,
                    fontWeight = FontWeight.SemiBold,
                    maxLines = 1,
                )
            }
        }
    }
}

private fun builtInCaption(selection: String): String =
    when (selection) {
        LutCatalog.AUTO -> "App looks for this color / camera"
        LutCatalog.OFF -> "No matching look for this color / camera"
        else -> "App looks for this color / camera"
    }

private fun djiCaption(selection: String): String =
    when (selection) {
        LutCatalog.DJI_AUTO -> "Official DJI looks for this color / camera"
        else -> "Official DJI Rec.709 cube"
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
