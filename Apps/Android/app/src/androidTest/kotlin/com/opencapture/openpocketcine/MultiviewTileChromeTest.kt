package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.multiview.MultiviewCameraAction
import com.opencapture.openpocketcine.multiview.MultiviewCameraMenu
import com.opencapture.openpocketcine.multiview.MultiviewTileChrome
import com.opencapture.openpocketcine.multiview.MultiviewTileOverlay
import com.opencapture.openpocketcine.multiview.multiviewTileReadouts
import com.opencapture.openpocketcine.session.CameraStatus
import java.util.Collections
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real Compose semantics/menu dispatch at the compact portrait-feed size; no camera I/O. */
@RunWith(AndroidJUnit4::class)
class MultiviewTileChromeTest {
    @Test fun compactPortraitFeedShowsTelemetryAndEveryCameraAction() {
        val actions = Collections.synchronizedList(mutableListOf<MultiviewCameraAction>())
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    MaterialTheme {
                        var menu by remember { mutableStateOf(false) }
                        Box(Modifier.size(298.dp, 112.dp)) {
                            MultiviewTileChrome(
                                readouts = multiviewTileReadouts(
                                    1, "Side angle", "Osmo Pocket 4", CameraStatus(
                                        batteryPercent = 73, sdTotalMb = 65536, sdFreeMb = 8192,
                                        recordElapsedSec = 84,
                                    ), "01:02:03:04", true, true, false, false, true, null,
                                ),
                                focused = true, compact = true, enabled = true, onOptions = { menu = true },
                            )
                            DropdownMenu(expanded = menu, onDismissRequest = { menu = false }) {
                                MultiviewCameraMenu(
                                    "Side angle", recording = true, lutEnabled = true,
                                    canOpen = true, canRecord = true, canReconnect = true, canRemove = true,
                                    experimentalRetryEnabled = true,
                                ) { action -> actions.add(action); menu = false }
                            }
                        }
                    }
                }
            }
            for (label in listOf("Side angle", "Osmo Pocket 4", "Timecode 01:02:03:04", "Battery 73%", "Storage 8 GB", "REC 1:24")) {
                awaitNode(label)
            }
            val labels = listOf("Open Live View", "Stop recording", "Disable Auto LUT", "Reconnect", "Try experimental shared Wi-Fi", "Remove Side angle")
            for (label in labels) {
                click(awaitNode("Camera B options"))
                click(awaitNode(label))
            }
            assertEquals(MultiviewCameraAction.entries, actions.toList())
        }
    }

    @Test fun cleanDisplayKeepsRecoveryStatusAndOptionsReachableOnCompactFeeds() {
        var optionsOpened = false
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    MaterialTheme {
                        Box(Modifier.size(120.dp, 64.dp)) {
                            MultiviewTileOverlay(
                                readouts = multiviewTileReadouts(
                                    1, "Side angle", "Osmo Pocket 4", CameraStatus(), null,
                                    false, false, false, true, true, null,
                                ), focused = true, compact = true, clean = true, enabled = true,
                                onOptions = { optionsOpened = true },
                            )
                        }
                    }
                }
            }
            click(awaitNode("Restoring picture… Camera B options"))
            scenario.onActivity { assertTrue(optionsOpened) }
        }
    }

    private fun click(node: AccessibilityNodeInfo) {
        var target: AccessibilityNodeInfo? = node
        while (target != null && !target.isClickable) target = target.parent
        assertNotNull(target, "Action must expose a clickable accessibility node")
        assertTrue(target.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun awaitNode(label: String): AccessibilityNodeInfo {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (node.text?.toString() == label || node.contentDescription?.toString() == label) return node
            for (index in 0 until node.childCount) find(node.getChild(index))?.let { return it }
            return null
        }
        while (SystemClock.uptimeMillis() < deadline) {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            find(automation.rootInActiveWindow)?.let { return it }
            for (window in automation.windows.orEmpty()) find(window.root)?.let { return it }
            SystemClock.sleep(32)
        }
        error("Missing compact feed readout/action: $label")
    }
}
