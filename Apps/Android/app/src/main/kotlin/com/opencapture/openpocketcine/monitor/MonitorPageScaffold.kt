package com.opencapture.openpocketcine.monitor

import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import com.opencapture.monitorui.MonitorPageLayoutPolicy

/** Responsive shell shared by Settings, media and future monitor destinations. */
@Composable
fun MonitorPageScaffold(
    modifier: Modifier = Modifier,
    navigationWidth: Float = MonitorPageLayoutPolicy.LANDSCAPE_NAV_WIDTH,
    heading: (@Composable () -> Unit)? = null,
    navigation: @Composable (portrait: Boolean) -> Unit,
    content: @Composable () -> Unit,
) {
    com.opencapture.monitorui.MonitorPageScaffold(
        modifier = modifier, navigationWidth = navigationWidth,
        heading = heading, navigation = navigation, content = content,
    )
}

@Composable
fun MonitorPageHeading(title: String, kicker: String) {
    com.opencapture.monitorui.MonitorPageHeading(title, kicker)
}
