package com.opencapture.openpocketcine

import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource

/** Shared Lucide HUD catalog. Names match vendored SVG and opc_lucide drawables. */
enum class OpcIcon(
    val lucideName: String,
    val drawableRes: Int,
    val filledDrawableRes: Int? = null,
) {
    APERTURE("aperture", R.drawable.opc_lucide_aperture),
    AUDIO_LINES("audio-lines", R.drawable.opc_lucide_audio_lines),
    AUDIO_WAVEFORM("audio-waveform", R.drawable.opc_lucide_audio_waveform),
    BLEND("blend", R.drawable.opc_lucide_blend),
    CAMERA("camera", R.drawable.opc_lucide_camera),
    CHART_COLUMN("chart-column", R.drawable.opc_lucide_chart_column),
    CHECK("check", R.drawable.opc_lucide_check),
    CHEVRON_DOWN("chevron-down", R.drawable.opc_lucide_chevron_down),
    CHEVRON_LEFT("chevron-left", R.drawable.opc_lucide_chevron_left),
    CHEVRON_RIGHT("chevron-right", R.drawable.opc_lucide_chevron_right),
    CHEVRON_UP("chevron-up", R.drawable.opc_lucide_chevron_up),
    CHEVRONS_UP_DOWN("chevrons-up-down", R.drawable.opc_lucide_chevrons_up_down),
    CIRCLE("circle", R.drawable.opc_lucide_circle),
    CIRCLE_CHECK("circle-check", R.drawable.opc_lucide_circle_check),
    CIRCLE_PLAY("circle-play", R.drawable.opc_lucide_circle_play),
    CIRCLE_PLUS("circle-plus", R.drawable.opc_lucide_circle_plus),
    CONTRAST("contrast", R.drawable.opc_lucide_contrast),
    COPY("copy", R.drawable.opc_lucide_copy),
    CROSSHAIR("crosshair", R.drawable.opc_lucide_crosshair),
    DOWNLOAD("download", R.drawable.opc_lucide_download),
    ELLIPSIS("ellipsis", R.drawable.opc_lucide_ellipsis),
    EYE("eye", R.drawable.opc_lucide_eye),
    EYE_OFF("eye-off", R.drawable.opc_lucide_eye_off),
    FILM("film", R.drawable.opc_lucide_film),
    FLIP_HORIZONTAL_2("flip-horizontal-2", R.drawable.opc_lucide_flip_horizontal_2),
    FOLDER("folder", R.drawable.opc_lucide_folder),
    FOCUS("focus", R.drawable.opc_lucide_focus),
    FUNNEL("funnel", R.drawable.opc_lucide_funnel),
    GRID_3X3("grid-3x3", R.drawable.opc_lucide_grid_3x3),
    IMAGE("image", R.drawable.opc_lucide_image),
    INFO("info", R.drawable.opc_lucide_info),
    LAYERS("layers", R.drawable.opc_lucide_layers),
    LAYOUT_GRID("layout-grid", R.drawable.opc_lucide_layout_grid),
    LAYOUT_LIST("layout-list", R.drawable.opc_lucide_layout_list),
    LIST_FILTER("list-filter", R.drawable.opc_lucide_list_filter),
    LOCK("lock", R.drawable.opc_lucide_lock),
    MAXIMIZE("maximize", R.drawable.opc_lucide_maximize),
    MINIMIZE("minimize", R.drawable.opc_lucide_minimize),
    MONITOR("monitor", R.drawable.opc_lucide_monitor),
    MOUNTAIN("mountain", R.drawable.opc_lucide_mountain),
    PALETTE("palette", R.drawable.opc_lucide_palette),
    PAUSE("pause", R.drawable.opc_lucide_pause),
    PENCIL("pencil", R.drawable.opc_lucide_pencil),
    PLAY("play", R.drawable.opc_lucide_play),
    PLUS("plus", R.drawable.opc_lucide_plus),
    RADIO("radio", R.drawable.opc_lucide_radio),
    REFRESH_CW("refresh-cw", R.drawable.opc_lucide_refresh_cw),
    ROTATE_CW("rotate-cw", R.drawable.opc_lucide_rotate_cw),
    SCAN("scan", R.drawable.opc_lucide_scan),
    SETTINGS("settings", R.drawable.opc_lucide_settings),
    SHARE("share", R.drawable.opc_lucide_share),
    SIGNAL("signal", R.drawable.opc_lucide_signal),
    SKIP_BACK("skip-back", R.drawable.opc_lucide_skip_back),
    SKIP_FORWARD("skip-forward", R.drawable.opc_lucide_skip_forward),
    SLIDERS_HORIZONTAL("sliders-horizontal", R.drawable.opc_lucide_sliders_horizontal),
    SLIDERS_VERTICAL("sliders-vertical", R.drawable.opc_lucide_sliders_vertical),
    SMARTPHONE("smartphone", R.drawable.opc_lucide_smartphone),
    SQUARE("square", R.drawable.opc_lucide_square),
    SQUARE_DASHED("square-dashed", R.drawable.opc_lucide_square_dashed),
    STAR("star", R.drawable.opc_lucide_star, R.drawable.opc_lucide_star_fill),
    SUN("sun", R.drawable.opc_lucide_sun),
    THERMOMETER("thermometer", R.drawable.opc_lucide_thermometer),
    TIMER("timer", R.drawable.opc_lucide_timer),
    TRASH("trash", R.drawable.opc_lucide_trash),
    UNPLUG("unplug", R.drawable.opc_lucide_unplug),
    UPLOAD("upload", R.drawable.opc_lucide_upload),
    VIDEO("video", R.drawable.opc_lucide_video),
    VOLUME_2("volume-2", R.drawable.opc_lucide_volume_2),
    VOLUME_X("volume-x", R.drawable.opc_lucide_volume_x),
    WIFI("wifi", R.drawable.opc_lucide_wifi),
    WIFI_OFF("wifi-off", R.drawable.opc_lucide_wifi_off),
    X("x", R.drawable.opc_lucide_x),
    ZAP("zap", R.drawable.opc_lucide_zap),
    ZOOM_IN("zoom-in", R.drawable.opc_lucide_zoom_in),
}

@Composable
fun OpcIcon(
    icon: OpcIcon,
    contentDescription: String?,
    modifier: Modifier = Modifier,
    tint: Color = LocalContentColor.current,
    filled: Boolean = false,
) {
    val res = if (filled) icon.filledDrawableRes ?: icon.drawableRes else icon.drawableRes
    Icon(
        painter = painterResource(res),
        contentDescription = contentDescription,
        modifier = modifier,
        tint = tint,
    )
}
