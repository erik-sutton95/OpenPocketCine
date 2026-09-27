package com.opencapture.openpocketcine

import android.app.UiAutomation
import android.content.res.Configuration
import android.graphics.Rect
import android.os.Bundle
import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.multiview.MultiviewNetworkStore
import com.opencapture.openpocketcine.pairing.StationNetworkSetup
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay
import kotlinx.coroutines.withContext
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.math.abs

/** Drive the real form with a radio boundary that holds cleanup through cancellation. */
@RunWith(AndroidJUnit4::class)
class StationNetworkSetupInputTest {
    @Test fun landscapeHeadersAndBottomActionsStayStableThroughScanAndKeyboard() {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.setRotation(UiAutomation.ROTATION_FREEZE_90)
        try {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                val scanComplete = CompletableDeferred<Unit>()
                var submitted: MultiviewNetworkStore.Network? = null
                var density = 1f
                scenario.onActivity { activity ->
                    assertEquals(Configuration.ORIENTATION_LANDSCAPE, activity.resources.configuration.orientation)
                    density = activity.resources.displayMetrics.density
                    activity.setContent {
                        OpenPocketCineTheme {
                            StationNetworkSetup(
                                savedNetworks = listOf(MultiviewNetworkStore.Network("Test network", "test-passphrase", false)),
                                currentSsid = { "Test network" }, hotspotActive = { false },
                                scan = { found ->
                                    repeat(24) { found("Nearby test network $it") }
                                    scanComplete.await()
                                },
                                connect = { selected -> submitted = selected; null },
                                cancel = {}, complete = {},
                            )
                        }
                    }
                }
                click("Local Wi-Fi")
                val beforeCurrent = bounds(awaitText("THIS PHONE IS ON"))
                val beforeNearby = bounds(awaitText("NEARBY"))
                assertTrue(abs(beforeCurrent.top - beforeNearby.top) <= 1)
                assertBottomAction("Other network…", density)
                scanComplete.complete(Unit)
                awaitText("Scan again")
                assertEquals(beforeCurrent, bounds(awaitText("THIS PHONE IS ON")))
                assertEquals(beforeNearby, bounds(awaitText("NEARBY")))
                // Twenty-four nearby results must not bury manual entry below the list.
                click("Other network…")
                awaitText("Network name")
                click("Cancel")
                click("Test network")
                assertTrue(abs(bounds(awaitText("NETWORK")).top - bounds(awaitText("PASSWORD")).top) <= 1)
                assertBottomAction("Connect over Wi-Fi", density)
                // The field's Password description may belong to a label node;
                // editing must target the native editable semantics node itself.
                var password = awaitPasswordInput()
                var focusTarget = password
                while (!focusTarget.isClickable) {
                    focusTarget = focusTarget.parent ?: error("Password has no focus action")
                }
                assertTrue(focusTarget.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                password = awaitPasswordInput()
                val input = Bundle().apply {
                    putCharSequence(AccessibilityNodeInfo.ACTION_ARGUMENT_SET_TEXT_CHARSEQUENCE, "edited-passphrase")
                }
                assertTrue(password.performAction(AccessibilityNodeInfo.ACTION_SET_TEXT, input))
                InstrumentationRegistry.getInstrumentation().waitForIdleSync()
                // The field stays mounted and the bottom action remains usable with the IME.
                click("Connect over Wi-Fi")
                scenario.onActivity { assertEquals("edited-passphrase", submitted?.password) }
            }
        } finally {
            automation.setRotation(UiAutomation.ROTATION_FREEZE_0)
            automation.setRotation(UiAutomation.ROTATION_UNFREEZE)
        }
    }

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

    private fun awaitPasswordInput(): AccessibilityNodeInfo {
        val deadline = SystemClock.uptimeMillis() + 10_000
        do {
            val root = InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow
            if (root != null) findPasswordInput(root)?.let { return it }
            SystemClock.sleep(100)
        } while (SystemClock.uptimeMillis() < deadline)
        error("Missing editable password field")
    }

    private fun findPasswordInput(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
        if (node.isEditable && node.isPassword && node.actionList.any {
                it.id == AccessibilityNodeInfo.ACTION_SET_TEXT
            }) return node
        for (index in 0 until node.childCount) {
            val child = node.getChild(index) ?: continue
            findPasswordInput(child)?.let { return it }
        }
        return null
    }

    private fun bounds(node: AccessibilityNodeInfo): Rect = Rect().also(node::getBoundsInScreen)

    private fun assertBottomAction(text: String, density: Float) {
        var action = awaitText(text)
        while (!action.isClickable) action = action.parent ?: error("No click action for $text")
        assertTrue(action.isVisibleToUser)
        val window = bounds(requireNotNull(InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow))
        val frame = bounds(action)
        assertTrue(frame.bottom <= window.bottom)
        assertTrue(window.bottom - frame.bottom < 96 * density, "Action should use the bottom of the safe viewport: $frame within $window")
        assertTrue(frame.height() >= 48 * density)
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
