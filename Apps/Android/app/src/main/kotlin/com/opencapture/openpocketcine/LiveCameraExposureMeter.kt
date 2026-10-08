package com.opencapture.openpocketcine

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.monitorui.monitorReadoutShadow
import com.opencapture.opencine.vocabulary.EvComp
import kotlin.math.cos
import kotlin.math.sin
import com.opencapture.opencine.appkit.MonitorDisplayMode
import com.opencapture.monitorui.MonitorRect

internal typealias CameraExposureMeter = com.opencapture.opencine.cameracontrols.MonitorOperatorExposureReading

@Composable
internal fun LiveCameraExposureMeter(raw: Int, available: Boolean, feed: MonitorRect, mode: MonitorDisplayMode,
    modifier: Modifier = Modifier, avoid: MonitorRect? = null) {
    com.opencapture.opencine.cameracontrols.MonitorOperatorExposureMeter(raw, available, feed, mode, modifier, avoid)
}
