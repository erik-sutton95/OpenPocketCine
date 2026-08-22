package com.opencapture.openpocketcine

import android.os.Build
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

    companion object {
        val None: OperatorHaptics =
            object : OperatorHaptics {
                override fun selection() = Unit

                override fun tick() = Unit

                override fun confirm() = Unit

                override fun longPress() = Unit
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
