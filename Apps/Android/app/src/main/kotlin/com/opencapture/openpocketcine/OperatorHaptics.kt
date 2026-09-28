package com.opencapture.openpocketcine

import android.os.Build
import android.os.VibrationEffect
import android.os.Vibrator
import android.view.HapticFeedbackConstants
import android.view.View
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.platform.LocalView

/**
 * Operator-facing haptics. Ported from OpenZCine: iOS uses
 * `UIImpactFeedbackGenerator` gated by `hapticsEnabled`. Android mirrors that
 * with [View.performHapticFeedback], ignoring the global Sound setting so the
 * in-app toggle wins.
 */
interface OperatorHaptics {
    fun selection()

    fun tick()

    fun confirm()

    fun longPress()

    fun limit()

    /** AE lock: stronger than [longPress], two full-strength clicks. */
    fun lock()

    companion object {
        val None: OperatorHaptics =
            object : OperatorHaptics {
                override fun selection() = Unit

                override fun tick() = Unit

                override fun confirm() = Unit

                override fun longPress() = Unit

                override fun limit() = Unit

                override fun lock() = Unit
            }
    }
}

val LocalOperatorHaptics = staticCompositionLocalOf { OperatorHaptics.None }

private class ViewOperatorHaptics(
    private val view: View,
    private val enabled: () -> Boolean,
) : OperatorHaptics {
    override fun selection() {
        perform(
            preferred = HapticFeedbackConstants.CONTEXT_CLICK,
            fallback = HapticFeedbackConstants.KEYBOARD_TAP,
        )
    }

    override fun tick() {
        perform(
            preferred = HapticFeedbackConstants.CLOCK_TICK,
            fallback = HapticFeedbackConstants.KEYBOARD_TAP,
        )
    }

    override fun confirm() {
        val preferred =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.CONFIRM
            } else {
                HapticFeedbackConstants.LONG_PRESS
            }
        perform(preferred = preferred, fallback = HapticFeedbackConstants.LONG_PRESS)
    }

    override fun longPress() {
        perform(
            preferred = HapticFeedbackConstants.LONG_PRESS,
            fallback = HapticFeedbackConstants.KEYBOARD_TAP,
        )
    }

    override fun limit() {
        val preferred =
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.R) {
                HapticFeedbackConstants.REJECT
            } else {
                HapticFeedbackConstants.LONG_PRESS
            }
        perform(preferred = preferred, fallback = HapticFeedbackConstants.LONG_PRESS)
    }

    override fun lock() {
        if (!enabled()) return
        val vibrator = view.context.getSystemService(Vibrator::class.java)
        if (vibrator == null || !vibrator.hasVibrator()) return longPress()
        val double = Build.VERSION.SDK_INT >= Build.VERSION_CODES.R &&
            vibrator.areAllPrimitivesSupported(VibrationEffect.Composition.PRIMITIVE_CLICK)
        // ponytail: fixed pattern; raise the gap or swap the primitive here if it still reads soft.
        val effect = if (double) {
            VibrationEffect.startComposition()
                .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f)
                .addPrimitive(VibrationEffect.Composition.PRIMITIVE_CLICK, 1f, 70)
                .compose()
        } else {
            VibrationEffect.createPredefined(VibrationEffect.EFFECT_HEAVY_CLICK)
        }
        vibrator.vibrate(effect)
    }

    private fun perform(preferred: Int, fallback: Int) {
        if (!enabled()) return
        view.isHapticFeedbackEnabled = true
        @Suppress("DEPRECATION")
        val flags = HapticFeedbackConstants.FLAG_IGNORE_GLOBAL_SETTING
        if (!view.performHapticFeedback(preferred, flags)) {
            view.performHapticFeedback(fallback, flags)
        }
    }
}

@Composable
fun rememberOperatorHaptics(enabled: () -> Boolean): OperatorHaptics {
    val view = LocalView.current
    val enabledState = rememberUpdatedState(enabled)
    return remember(view) { ViewOperatorHaptics(view) { enabledState.value() } }
}
