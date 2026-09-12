package com.opencapture.openpocketcine.assists

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.chromeClickable
import com.opencapture.openpocketcine.pickerPanelGlass
import kotlin.math.max
import kotlin.math.min

/** Leading inspector: shell layout only, using the existing assist state/actions. */
@Composable
fun MonitorAssistInspector(
    tool: LiveAssistTool, state: LiveAssistState, model: AppModel?, colorMode: Int,
    viewportWidth: Float, viewportHeight: Float, safeLeading: Float,
    safeTop: Float, safeBottom: Float, controlsFloor: Float,
    onDismiss: () -> Unit,
    playback: Boolean = false,
) {
    val portrait = viewportHeight > viewportWidth
    val width = min(424f, viewportWidth * .86f)
    val height = if (portrait) min(viewportHeight, controlsFloor) else viewportHeight
    val leading = max(14f, safeLeading + 10f)
    val top = max(16f, safeTop + 10f)
    var shown by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { shown = true }
    val reveal by animateFloatAsState(if (shown) 1f else 0f, tween(150), label = "assist-drawer")
    Box(Modifier.fillMaxSize().chromeClickable(onClick = onDismiss)) {
        Box(Modifier.width(width.dp).height(height.dp)
            .graphicsLayer { translationX = -(1f - reveal) * size.width; alpha = reveal }
            .clip(RoundedCornerShape(topEnd = 16.dp, bottomEnd = 16.dp))
            .pickerPanelGlass(RoundedCornerShape(topEnd = 16.dp, bottomEnd = 16.dp))
            .chromeClickable { }) {
            if (portrait) {
                Column(Modifier.fillMaxSize().padding(top = top.dp, bottom = max(8f, safeBottom).dp)) {
                    Row(Modifier.fillMaxWidth().horizontalScroll(rememberScrollState())
                        .padding(start = leading.dp, end = 10.dp, bottom = 10.dp),
                        horizontalArrangement = Arrangement.spacedBy(3.dp)) {
                        LiveAssistTool.settingsCases.forEach { InspectorTab(it, tool, state, portrait = true) }
                    }
                    Box(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        AssistOptionsPopup(tool, state, onDismiss, model = model,
                            maxHeightDp = (height - top - 72f).coerceAtLeast(100f),
                            colorMode = colorMode, embedded = true, playback = playback)
                    }
                }
            } else {
                Row(Modifier.fillMaxSize().padding(top = top.dp, bottom = max(12f, safeBottom).dp)) {
                    Column(Modifier.width((108f + max(0f, safeLeading - 4f)).dp).fillMaxHeight()
                        .verticalScroll(rememberScrollState()).padding(start = leading.dp, end = 8.dp),
                        verticalArrangement = Arrangement.spacedBy(3.dp)) {
                        LiveAssistTool.settingsCases.forEach { InspectorTab(it, tool, state, portrait = false) }
                    }
                    Box(Modifier.weight(1f).padding(horizontal = 12.dp)) {
                        AssistOptionsPopup(tool, state, onDismiss, model = model,
                            maxHeightDp = (height - top - max(12f, safeBottom)).coerceAtLeast(100f),
                            colorMode = colorMode, embedded = true, playback = playback)
                    }
                }
            }
        }
    }
}

@Composable
private fun InspectorTab(tool: LiveAssistTool, selected: LiveAssistTool, state: LiveAssistState, portrait: Boolean) {
    val active = tool == selected
    val tint = if (active) LiveDesign.accent else LiveDesign.muted
    Row(Modifier.then(if (portrait) Modifier.width(94.dp) else Modifier.fillMaxWidth()).height(44.dp)
        .clip(RoundedCornerShape(10.dp)).background(if (active) LiveDesign.accentDim else androidx.compose.ui.graphics.Color.Transparent)
        .chromeClickable { state.configureTool = tool }.padding(horizontal = 9.dp),
        verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
        AssistToolGlyph(tool, tint, Modifier.size(15.dp))
        Text(tool.chipLabel, color = tint, style = LiveType.ui(9f, FontWeight.SemiBold), maxLines = 1)
    }
}
