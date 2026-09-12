package com.opencapture.monitorui

import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource

/** Exact paths extracted from the approved Field Monitor HTML, never approximations. */
enum class MonitorAssistIcon(val drawable: Int) {
    LUT(R.drawable.monitor_assist_lut), PEAKING(R.drawable.monitor_assist_peaking),
    FALSE_COLOR(R.drawable.monitor_assist_false_color), ZEBRA(R.drawable.monitor_assist_zebra),
    WAVEFORM(R.drawable.monitor_assist_waveform), RGB_PARADE(R.drawable.monitor_assist_rgb_parade),
    HISTOGRAM(R.drawable.monitor_assist_histogram), VECTORSCOPE(R.drawable.monitor_assist_vectorscope),
    TRAFFIC_LIGHTS(R.drawable.monitor_assist_traffic_lights), FRAME_GUIDE(R.drawable.monitor_assist_frame_guide),
    GRID(R.drawable.monitor_assist_grid), CROSSHAIR(R.drawable.monitor_assist_crosshair),
    MIRROR(R.drawable.monitor_assist_mirror), AUDIO_METERS(R.drawable.monitor_assist_audio_meters),
}

@Composable
fun MonitorAssistIcon(icon: MonitorAssistIcon, tint: Color, modifier: Modifier = Modifier,
    contentDescription: String? = null) {
    Icon(painterResource(icon.drawable), contentDescription, modifier, tint)
}
