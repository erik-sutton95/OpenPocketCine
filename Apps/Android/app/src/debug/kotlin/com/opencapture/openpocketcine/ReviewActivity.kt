package com.opencapture.openpocketcine

import android.content.Context
import android.os.Bundle
import androidx.compose.runtime.Composable
import androidx.lifecycle.lifecycleScope
import kotlinx.coroutines.launch

/**
 * Debug only, SIMULATED: the real app root over [ReviewCameras]' scripted pipeline, so the cameras
 * and pair pages show each connection state on an emulator. `adb shell am start -n
 * <pkg>/.ReviewActivity --es opv_review_state <state>`. Release builds have neither class.
 */
class ReviewActivity : MainActivity() {
    private val state: String? get() = intent?.getStringExtra("opv_review_state")

    override fun onCreate(savedInstanceState: Bundle?) {
        if (savedInstanceState == null) {
            ReviewCameras.seed(state, getSharedPreferences(AppModel.LEGACY_CAMERAS, Context.MODE_PRIVATE))
        }
        super.onCreate(savedInstanceState)
        val review = state ?: return
        if (savedInstanceState != null) return
        if (review == "multiview") model.openMultiview()
        if (review.startsWith("pair-")) model.pairing = true
        lifecycleScope.launch { ReviewCameras.start(review, model) }
    }

    override fun createModel(): AppModel =
        state?.let { review -> AppModel(applicationContext, discovers = true, connectPort = { ReviewCameras.port(review, it) }) }
            ?: super.createModel()

    @Composable
    override fun Overlay(model: AppModel) = ReviewCameras.AddSetup(state, model)
}
