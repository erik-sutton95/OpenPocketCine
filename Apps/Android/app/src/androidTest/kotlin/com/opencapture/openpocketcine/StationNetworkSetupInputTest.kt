package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.multiview.MultiviewNetworkStore
import com.opencapture.openpocketcine.pairing.StationNetworkSetup
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertTrue

/** Drive the real form with a radio boundary that holds cleanup through cancellation. */
@RunWith(AndroidJUnit4::class)
class StationNetworkSetupInputTest {
    @Test fun selectingDuringScanWaitsForCleanupAndFailedJoinCanRetry() {
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            var cleaned = false
            var calls = 0
            var completed = false
            scenario.onActivity { activity ->
                activity.setContent {
                    OpenPocketCineTheme {
                        StationNetworkSetup(
                            savedNetworks = listOf(MultiviewNetworkStore.Network("Test network", "test-passphrase", false)),
                            currentSsid = { "Test network" }, hotspotActive = { false },
                            scan = { found ->
                                found("Nearby test network")
                                try { awaitCancellation() } finally {
                                    withContext(NonCancellable) { delay(250); cleaned = true }
                                }
                            },
                            connect = { selected ->
                                assertTrue(cleaned, "The scan must release the camera before connecting")
                                assertEquals("Test network", selected.ssid)
                                assertEquals("test-passphrase", selected.password)
                                calls++
                                if (calls == 1) "Test join failed. Try again." else null
                            }, cancel = {}, complete = { completed = true },
                        )
                    }
                }
            }
            click("Local Wi-Fi")
            awaitText("Nearby test network")
            click("Test network")
            click("Connect over Wi-Fi")
            awaitText("Test join failed. Try again.")
            scenario.onActivity { assertEquals(1, calls); assertTrue(cleaned) }
            click("Connect over Wi-Fi")
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            scenario.onActivity { assertEquals(2, calls); assertTrue(completed) }
        }
    }

    private fun awaitText(text: String): AccessibilityNodeInfo {
        val deadline = SystemClock.uptimeMillis() + 10_000
        do {
            val root = InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow
            if (root != null) find(root, text)?.let { return it }
            SystemClock.sleep(100)
        } while (SystemClock.uptimeMillis() < deadline)
        error("Missing setup text: $text")
    }

    private fun click(text: String) {
        var node = awaitText(text)
        while (!node.isClickable) node = node.parent ?: error("No click action for $text")
        assertTrue(node.performAction(AccessibilityNodeInfo.ACTION_CLICK))
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun find(node: AccessibilityNodeInfo, text: String): AccessibilityNodeInfo? {
        if (node.text?.toString() == text || node.contentDescription?.toString() == text) return node
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            find(child, text)?.let { return it }
        }
        return null
    }
}
