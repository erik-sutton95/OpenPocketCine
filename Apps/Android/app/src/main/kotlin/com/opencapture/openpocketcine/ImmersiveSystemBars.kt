package com.opencapture.openpocketcine

import android.view.Window
import androidx.activity.compose.LocalActivity
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.PointerEventPass
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.unit.dp
import androidx.core.graphics.Insets
import androidx.core.view.WindowCompat
import androidx.core.view.WindowInsetsCompat
import androidx.core.view.WindowInsetsControllerCompat
import kotlinx.coroutines.delay

/**
 * Transient system-bar lanes while the swipe-reveal cycle has the bars up.
 * Compose [androidx.compose.foundation.layout.WindowInsets] do not update after
 * a programmatic `show()` on the devices we measured (OpenZCine SM-A127F), so
 * chrome reads these instead.
 */
val LocalImmersiveBarInsets = compositionLocalOf { Insets.NONE }

/** Hides the system bars. A swipe-from-edge cycle in [ImmersiveSystemBarCycle] shows them. */
fun applyImmersiveSystemBars(window: Window) {
    WindowCompat.getInsetsController(window, window.decorView).apply {
        systemBarsBehavior = WindowInsetsControllerCompat.BEHAVIOR_DEFAULT
        hide(WindowInsetsCompat.Type.systemBars())
    }
}

/**
 * OpenZCine sticky-immersive cycle: observe an inward swipe from a screen
 * edge, `show()` the bars so real insets land, hold, then `hide()`.
 * Pointer events are not consumed — chrome and pairing still get the tap.
 */
@Composable
fun ImmersiveSystemBarCycle(content: @Composable () -> Unit) {
    var barsShown by remember { mutableStateOf(false) }
    var barInsets by remember { mutableStateOf(Insets.NONE) }
    val view = LocalView.current
    val activity = LocalActivity.current
    LaunchedEffect(barsShown) {
        if (!barsShown) return@LaunchedEffect
        val window = activity?.window ?: return@LaunchedEffect
        val controller = WindowCompat.getInsetsController(window, view)
        controller.show(WindowInsetsCompat.Type.systemBars())
        var attempts = 0
        while (attempts < 20) {
            delay(50)
            attempts++
            val applied =
                view.rootWindowInsets?.let {
                    WindowInsetsCompat.toWindowInsetsCompat(it, view)
                        .getInsets(WindowInsetsCompat.Type.systemBars())
                } ?: Insets.NONE
            if (applied != Insets.NONE) {
                barInsets = applied
                break
            }
        }
        delay(3_000)
        controller.hide(WindowInsetsCompat.Type.systemBars())
        barInsets = Insets.NONE
        barsShown = false
    }
    CompositionLocalProvider(LocalImmersiveBarInsets provides barInsets) {
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown(pass = PointerEventPass.Initial)
                        val edge = 24.dp.toPx()
                        val nearTop = down.position.y < edge
                        val nearRight = down.position.x > size.width - edge
                        val nearBottom = down.position.y > size.height - edge
                        val nearLeft = down.position.x < edge
                        if (!nearTop && !nearRight && !nearBottom && !nearLeft) {
                            return@awaitEachGesture
                        }
                        var travelX = 0f
                        var travelY = 0f
                        while (true) {
                            val event = awaitPointerEvent(PointerEventPass.Initial)
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            val delta = change.positionChange()
                            travelX += delta.x
                            travelY += delta.y
                            val inward =
                                when {
                                    nearTop -> travelY
                                    nearBottom -> -travelY
                                    nearRight -> -travelX
                                    else -> travelX
                                }
                            if (inward > 40.dp.toPx()) {
                                barsShown = true
                                break
                            }
                        }
                    }
                },
        ) {
            content()
        }
    }
}
