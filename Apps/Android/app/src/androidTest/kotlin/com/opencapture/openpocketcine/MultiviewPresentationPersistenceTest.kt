package com.opencapture.openpocketcine

import android.content.Context
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.MultiviewStagePreferencesStore
import com.opencapture.openpocketcine.multiview.MultiviewLayout
import com.opencapture.openpocketcine.multiview.MultiviewSession
import com.opencapture.opencine.appkit.MultiviewStageJournal
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/** SIMULATED presentation restore through the actual session; no network or camera is opened. */
@RunWith(AndroidJUnit4::class)
class MultiviewPresentationPersistenceTest {
    @Test fun commonPresentationSurvivesRelaunchWithoutRestoringNetworkOrCameraSlots() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val context = instrumentation.targetContext
        val domain = "SIMULATED-multiview-${System.nanoTime()}"
        val storage = context.getSharedPreferences(domain, Context.MODE_PRIVATE)
        try {
            instrumentation.runOnMainSync {
                val store = MultiviewStagePreferencesStore(storage, "presentation")
                val legacy = MultiviewStageJournal.Stage(
                    ssid = "Previous network", hotspot = true, layout = MultiviewLayout.GRID.raw,
                    focusedIndex = 2, cameras = emptyList(), pendingReset = emptyList(), returnedToCameraWiFi = true, fill = true,
                )
                val first = MultiviewSession(context, saveStage = { true })
                val restored = MultiviewSession(context, saveStage = { true })
                try {
                    first.presentation.attachPersistence(store::load, store::save)
                    first.restoreStage(legacy)
                    first.presentation.clean = true
                    first.presentation.toolsExpanded = true
                    first.layout = MultiviewLayout.CENTER_STAGE
                    restored.presentation.attachPersistence(store::load, store::save)
                    restored.restoreStage(legacy)
                    assertEquals(first.presentation.preferences, restored.presentation.preferences)
                    assertEquals(MultiviewLayout.CENTER_STAGE, restored.layout)
                    assertEquals(2, restored.focusedIndex)
                    assertTrue(restored.fill)
                    assertFalse(restored.networkConfigured)
                    assertTrue(restored.tiles.all { it.camera == null })
                    assertEquals("", restored.password)
                } finally { first.dispose(); restored.dispose() }
            }
        } finally { context.deleteSharedPreferences(domain) }
    }
}
