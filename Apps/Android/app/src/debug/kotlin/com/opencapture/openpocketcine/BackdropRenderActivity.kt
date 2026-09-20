package com.opencapture.openpocketcine

import android.graphics.Bitmap
import android.graphics.BitmapFactory
import android.os.Bundle
import androidx.activity.ComponentActivity
import androidx.activity.compose.setContent
import androidx.activity.enableEdgeToEdge
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.graphics.createBitmap
import androidx.core.graphics.scale
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import com.opencapture.monitorui.LocalMonitorBackdrops
import com.opencapture.monitorui.MonitorBackdropSource
import com.opencapture.monitorui.MonitorMaterial
import com.opencapture.monitorui.monitorBackdropSource
import com.opencapture.monitorui.monitorMaterial

/** Actual production material over a deterministic image; no model, camera, or decoder. */
class BackdropRenderActivity : ComponentActivity() {
    val source = MonitorBackdropSource()
    var material by mutableStateOf(MonitorMaterial.Expanded)
    var fixtureScale by mutableFloatStateOf(1f)
    var mirror by mutableStateOf(false)
    val secondSource = MonitorBackdropSource()
    var splitSources by mutableStateOf(false)
    var nested by mutableStateOf(false)
    private lateinit var pattern: Bitmap

    fun replaceSource(color: Int?) {
        source.image = color?.let { createBitmap(213, 120, Bitmap.Config.ARGB_8888).apply { eraseColor(it) } }
    }
    fun restorePattern() { source.image = pattern }

    override fun onCreate(savedInstanceState: Bundle?) {
        super.onCreate(savedInstanceState)
        enableEdgeToEdge()
        WindowCompat.getInsetsController(window, window.decorView).apply {
            hide(WindowInsetsCompat.Type.systemBars())
            systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_SHOW_TRANSIENT_BARS_BY_SWIPE
        }
        pattern = assets.open("monitor_backdrop_reference.png").use { BitmapFactory.decodeStream(it) }
        source.image = if (intent.getBooleanExtra("sampled", false)) pattern.scale(180, 120) else pattern
        material = when (intent.getStringExtra("material")) {
            "compact" -> MonitorMaterial.Compact
            "scope" -> MonitorMaterial.Scope
            "zoom" -> MonitorMaterial.Zoom
            "info" -> MonitorMaterial.Info
            "delivery" -> MonitorMaterial.Delivery
            "record" -> MonitorMaterial.Record
            else -> MonitorMaterial.Expanded
        }
        setContent {
            BoxWithConstraints(Modifier.fillMaxSize().background(Color(0xFF111213))) {
                val pixels = minOf(constraints.maxWidth / 900f, constraints.maxHeight / 600f) * fixtureScale
                CompositionLocalProvider(LocalDensity provides Density(pixels, 1f), LocalMonitorBackdrops provides if (splitSources) listOf(source, secondSource) else listOf(source)) {
                    Box(Modifier.size(900.dp, 600.dp)) {
                        Image(pattern.asImageBitmap(), null, Modifier.fillMaxSize(), contentScale = ContentScale.FillBounds)
                        if (splitSources) {
                            Box(Modifier.size(450.dp, 600.dp).monitorBackdropSource(source))
                            Box(Modifier.offset(450.dp).size(450.dp, 600.dp).monitorBackdropSource(secondSource))
                        } else Box(Modifier.fillMaxSize().monitorBackdropSource(source, mirrored = mirror))
                        Box(Modifier.offset(150.dp, 100.dp).size(600.dp, 400.dp)
                            .monitorMaterial(material, RoundedCornerShape(16.dp)), contentAlignment = Alignment.Center) {
                            Text("SHARP FOREGROUND", fontSize = 32.sp, fontWeight = FontWeight.Bold, letterSpacing = 2.sp, color = Color.White)
                            // A deterministic thin edge proves the foreground is not in the blur input.
                            Box(Modifier.align(Alignment.BottomCenter).offset(y = (-50).dp).size(120.dp, 4.dp).background(Color.White))
                            if (nested) Box(Modifier.size(150.dp, 70.dp).monitorMaterial(MonitorMaterial.Compact, RoundedCornerShape(10.dp)))
                        }
                    }
                }
            }
        }
    }
}
