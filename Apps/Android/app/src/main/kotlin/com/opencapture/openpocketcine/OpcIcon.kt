package com.opencapture.openpocketcine

import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource

/** Shared Lucide HUD catalog. Names match vendored SVG and opc_lucide drawables. */
enum class OpcIcon(val lucideName: String, val drawableRes: Int) {
    CAMERA("camera", R.drawable.opc_lucide_camera),
    CHEVRON_LEFT("chevron-left", R.drawable.opc_lucide_chevron_left),
    CHEVRON_RIGHT("chevron-right", R.drawable.opc_lucide_chevron_right),
    CONTRAST("contrast", R.drawable.opc_lucide_contrast),
    CROSSHAIR("crosshair", R.drawable.opc_lucide_crosshair),
    GRID_3X3("grid-3x3", R.drawable.opc_lucide_grid_3x3),
    LAYERS("layers", R.drawable.opc_lucide_layers),
    LOCK("lock", R.drawable.opc_lucide_lock),
    PAUSE("pause", R.drawable.opc_lucide_pause),
    PLAY("play", R.drawable.opc_lucide_play),
    SETTINGS("settings", R.drawable.opc_lucide_settings),
    SHARE("share", R.drawable.opc_lucide_share),
    STAR("star", R.drawable.opc_lucide_star),
    TRASH("trash", R.drawable.opc_lucide_trash),
    VIDEO("video", R.drawable.opc_lucide_video),
    X("x", R.drawable.opc_lucide_x),
    ZAP("zap", R.drawable.opc_lucide_zap),
}

@Composable
fun OpcIcon(
    icon: OpcIcon,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current,
) {
    Icon(
        painter = painterResource(icon.drawableRes),
        contentDescription = contentDescription,
        modifier = modifier,
        tint = tint,
    )
}
