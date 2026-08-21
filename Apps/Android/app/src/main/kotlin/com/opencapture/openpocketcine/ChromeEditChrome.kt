package com.opencapture.openpocketcine

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.graphics.PathEffect
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.min

private const val BADGE = 26f
private const val BADGE_GAP = 4f
private const val EDGE_INSET = 16f
private const val OVERHANG = 4f

@Composable
fun ChromeEditBanner(
    mode: PocketDispMode,
    modifier: Modifier = Modifier,
    onDone: () -> Unit,
) {
    Row(
        modifier
            .clip(RoundedCornerShape(50))
            .background(LiveDesign.glassOpaque)
            .padding(start = 12.dp, end = 6.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Column(verticalArrangement = Arrangement.spacedBy(1.dp)) {
            Text("Editing ${mode.title}", color = LiveDesign.text, style = LiveType.ui(11.5f, FontWeight.SemiBold))
            Text("Tap an eye to show or hide it", color = LiveDesign.muted, style = LiveType.ui(10f))
        }
        Box(
            Modifier
                .clip(RoundedCornerShape(50))
                .background(LiveDesign.accent)
                .chromeClickable(onClick = onDone)
                .padding(horizontal = 12.dp, vertical = 6.dp),
        ) {
            Text("Done", color = LiveDesign.background, style = LiveType.ui(11.5f, FontWeight.Bold))
        }
    }
}

@Composable
fun ChromeEditBadgeLayer(
    mode: PocketDispMode,
    boxes: List<Pair<PocketDispSection, ChromeRect>>,
    viewportWidth: Float,
    viewportHeight: Float,
    visible: (PocketDispSection) -> Boolean,
    onToggle: (PocketDispSection) -> Unit,
) {
    val frames = badgeFrames(boxes, viewportWidth, viewportHeight)
    frames.forEach { (section, frame) ->
        val on = visible(section)
        Box(
            Modifier
                .offset(frame.x.dp, frame.y.dp)
                .size(BADGE.dp)
                .clip(CircleShape)
                .background(if (on) LiveDesign.accent else androidx.compose.ui.graphics.Color.Black.copy(alpha = 0.9f))
                .border(1.dp, LiveDesign.text.copy(alpha = 0.55f), CircleShape)
                .chromeClickable(onClick = { onToggle(section) }),
            contentAlignment = Alignment.Center,
        ) {
            Text(
                if (on) "👁" else "🚫",
                color = if (on) LiveDesign.background else LiveDesign.text,
                style = LiveType.ui(11f, FontWeight.Bold),
            )
        }
    }
}

fun Modifier.chromeEditStroke(editing: Boolean, visible: Boolean): Modifier {
    if (!editing) return this
    val color = if (visible) LiveDesign.accent.copy(alpha = 0.75f) else LiveDesign.muted.copy(alpha = 0.75f)
    return drawWithContent {
        drawContent()
        drawRoundRect(
            color = color,
            cornerRadius = CornerRadius(8.dp.toPx()),
            style = Stroke(width = 1.dp.toPx(), pathEffect = PathEffect.dashPathEffect(floatArrayOf(6f, 6f))),
        )
    }
}

internal fun chromeEditBoxes(
    layout: LiveMonitorLayout,
    model: AppModel,
    uiLocked: Boolean,
    zoom: ChromeRect,
    stick: ChromeRect,
): List<Pair<PocketDispSection, ChromeRect>> {
    val out = mutableListOf<Pair<PocketDispSection, ChromeRect>>()
    fun add(section: PocketDispSection, rect: ChromeRect) {
        if (!rect.isEmpty) out += section to rect
    }
    if (model.chromeSectionMounts(PocketDispSection.STATUS_BAR)) add(PocketDispSection.STATUS_BAR, layout.topDeck)
    if (model.chromeSectionMounts(PocketDispSection.LOCK_BUTTON) || uiLocked) add(PocketDispSection.LOCK_BUTTON, layout.lock)
    if (model.chromeSectionMounts(PocketDispSection.BATTERIES)) add(PocketDispSection.BATTERIES, layout.battery)
    if (model.chromeSectionMounts(PocketDispSection.RAIL_SETTINGS)) add(PocketDispSection.RAIL_SETTINGS, layout.settings)
    if (model.chromeSectionMounts(PocketDispSection.RAIL_MEDIA)) add(PocketDispSection.RAIL_MEDIA, layout.media)
    if (model.chromeSectionMounts(PocketDispSection.RAIL_RECORD)) add(PocketDispSection.RAIL_RECORD, layout.record)
    if (model.chromeSectionMounts(PocketDispSection.TOOL_BAR)) add(PocketDispSection.TOOL_BAR, layout.assist)
    if (model.chromeSectionMounts(PocketDispSection.CAMERA_VALUES)) add(PocketDispSection.CAMERA_VALUES, layout.capture)
    if (model.chromeSectionMounts(PocketDispSection.ZOOM_CHIP)) add(PocketDispSection.ZOOM_CHIP, zoom)
    if (model.chromeSectionMounts(PocketDispSection.GIMBAL_STICK)) add(PocketDispSection.GIMBAL_STICK, stick)
    return out
}

private fun badgeFrames(
    boxes: List<Pair<PocketDispSection, ChromeRect>>,
    vw: Float,
    vh: Float,
): List<Pair<PocketDispSection, ChromeRect>> {
    val playable =
        ChromeRect(
            min(EDGE_INSET, max(0f, vw - BADGE)),
            min(EDGE_INSET, max(0f, vh - BADGE)),
            max(BADGE, vw - 2f * EDGE_INSET),
            max(BADGE, vh - 2f * EDGE_INSET),
        )
    val placed = mutableListOf<ChromeRect>()
    val result = mutableListOf<Pair<PocketDispSection, ChromeRect>>()
    for ((section, box) in boxes) {
        if (box.isEmpty) continue
        val preferTrailing = box.midX < vw / 2f
        val preferBottom = box.midY < vh / 2f
        val candidates =
            listOf(
                ChromeRect(box.maxX - (BADGE - OVERHANG), box.minY - OVERHANG, BADGE, BADGE),
                ChromeRect(box.minX - OVERHANG, box.minY - OVERHANG, BADGE, BADGE),
                ChromeRect(box.maxX - (BADGE - OVERHANG), box.maxY - (BADGE - OVERHANG), BADGE, BADGE),
                ChromeRect(box.minX - OVERHANG, box.maxY - (BADGE - OVERHANG), BADGE, BADGE),
                ChromeRect(box.midX - BADGE / 2f, box.minY - OVERHANG, BADGE, BADGE),
                ChromeRect(box.midX - BADGE / 2f, box.maxY - (BADGE - OVERHANG), BADGE, BADGE),
            ).map { clampBadge(it, playable) }
                .sortedBy { rank(it, box, preferTrailing, preferBottom) }
        val choice =
            candidates.firstOrNull { candidate ->
                placed.none { overlaps(it, candidate) }
            } ?: candidates.first()
        placed += choice
        result += section to choice
    }
    return result
}

private fun clampBadge(frame: ChromeRect, playable: ChromeRect): ChromeRect {
    val x = min(max(frame.minX, playable.minX), playable.maxX - frame.width)
    val y = min(max(frame.minY, playable.minY), playable.maxY - frame.height)
    return ChromeRect(x, y, frame.width, frame.height)
}

private fun overlaps(a: ChromeRect, b: ChromeRect): Boolean =
    a.minX < b.maxX + BADGE_GAP &&
        b.minX < a.maxX + BADGE_GAP &&
        a.minY < b.maxY + BADGE_GAP &&
        b.minY < a.maxY + BADGE_GAP

private fun rank(badge: ChromeRect, box: ChromeRect, preferTrailing: Boolean, preferBottom: Boolean): Int {
    val trailing = badge.midX >= box.midX
    val bottom = badge.midY >= box.midY
    val h = if (trailing == preferTrailing) 0 else 2
    val v = if (bottom == preferBottom) 0 else 2
    return h + v
}
