package com.opencapture.openpocketcine.monitor

import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalConfiguration
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import com.opencapture.monitorui.MonitorPageLayoutPolicy
import com.opencapture.openpocketcine.AuxCircleButton
import com.opencapture.openpocketcine.OpcIcon

/** Responsive shell shared by Settings, media and future monitor destinations. */
@Composable
fun MonitorPageScaffold(
    modifier: Modifier = Modifier,
    navigationWidth: Float = MonitorPageLayoutPolicy.LANDSCAPE_NAV_WIDTH,
    back: (@Composable () -> Unit)? = null,
    heading: (@Composable () -> Unit)? = null,
    navigation: @Composable (portrait: Boolean) -> Unit,
    content: @Composable () -> Unit,
) {
    com.opencapture.monitorui.MonitorPageScaffold(
        modifier = modifier, navigationWidth = navigationWidth,
        back = back, heading = heading, navigation = navigation, content = content,
    )
}

@Composable
fun MonitorPageBackButton(label: String = "Back", onClick: () -> Unit) {
    val configuration = LocalConfiguration.current
    val tablet = minOf(configuration.screenWidthDp, configuration.screenHeightDp) >= 600
    val side = com.opencapture.monitorui.MonitorLayoutPolicy.systemButtonSize(tablet)
    AuxCircleButton(
        Modifier.size(side.dp).semantics { contentDescription = label },
        onClick = onClick,
    ) { tint ->
        OpcIcon(OpcIcon.CHEVRON_LEFT, null, Modifier.fillMaxSize(), tint)
    }
}

@Composable
fun MonitorPageHeading(title: String, kicker: String) {
    com.opencapture.monitorui.MonitorPageHeading(title, kicker)
}
