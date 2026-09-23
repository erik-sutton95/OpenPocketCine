package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.text.BasicText
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.assists.LiveAssistTool
import java.util.UUID
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/**
 * Reads the platform accessibility tree — what TalkBack itself consumes —
 * rather than Compose's own semantics, so a node that merges wrongly is caught
 * here instead of on a tester's phone. Same harness as the other input tests;
 * no Compose test dependency.
 */
@RunWith(AndroidJUnit4::class)
class LiveChromeSemanticsTest {

    @Test fun recChipSpeaksStateAndElapsedTimeAsOneNode() {
        val spoken = render { RecChip(recording = true, elapsedSeconds = 134) }
        assertEquals(
            listOf("Recording, 2 minutes 14 seconds"),
            spoken,
            "REC chip should speak one sentence, not \"REC\" and \"02:14\" as fragments",
        )
    }

    @Test fun recChipSpeaksStandbyWithoutAnIdleTimer() {
        assertEquals(listOf("Standby"), render { RecChip(recording = false, elapsedSeconds = 0) })
    }

    @Test fun cameraBatteryNamesItsSourceAndUnit() {
        assertEquals(listOf("Camera battery 87 percent"), render { CameraBatteryReadout(percent = 87) })
    }

    @Test fun cameraBatterySaysUnknownRatherThanReadingADash() {
        assertEquals(listOf("Camera battery level unknown"), render { CameraBatteryReadout(percent = -1) })
    }

    @Test fun timecodeIsNamedAndItsPlaceholderIsSpoken() {
        assertEquals(listOf("Timecode not available"), render { TimecodeReadout(timecode = null) })
        assertEquals(listOf("Timecode 01:23:45"), render { TimecodeReadout(timecode = "01:23:45:12") })
    }

    /** The shared readout shape, which the chips above all reuse. */
    @Test fun aReadoutPillAbsorbsItsChildText() {
        val spoken = render {
            ReadoutPill(value = "24 mm", accessibilityLabel = "Lens") { Spacer(Modifier.size(12.dp)) }
        }
        assertEquals(listOf("Lens 24 mm"), spoken)
    }

    /**
     * Every readout here shares one shape, so a leak in it is a leak in all of
     * them. This measures the shape itself rather than trusting it.
     */
    @Test fun fpsChipShapeDoesNotLeakItsChildText() {
        assertEquals(
            listOf("Live view 23.98 frames per second, 3 of 4 signal bars"),
            render { FpsChip(fps = "23.98", bars = 3) },
            "readout chips must merge; a stray \"FPS\" node means the convention leaks",
        )
    }

    /**
     * The rule the rest of this file depends on, pinned to the platform rather
     * than to belief: only clearing collapses a labelled row to one stop, and
     * it keeps the row activatable. `mergeDescendants` reads as merged in the
     * Compose tree but still publishes the child text, so it is not a fix.
     */
    @Test fun onlyClearingCollapsesALabelledRowAndItKeepsItsActions() {
        val plain = render { Row(Modifier.semantics { contentDescription = "PLAIN" }) { BasicText("kid") } }
        assertEquals(listOf("PLAIN", "kid"), plain, "plain semantics leaves the child text behind")

        val merged = render {
            Row(Modifier.semantics(mergeDescendants = true) { contentDescription = "MERGED" }) { BasicText("kid") }
        }
        assertEquals(listOf("MERGED", "kid"), merged, "mergeDescendants does not suppress the child either")

        val cleared = render {
            Row(Modifier.clearAndSetSemantics { contentDescription = "CLEARED" }) { BasicText("kid") }
        }
        assertEquals(listOf("CLEARED"), cleared, "clearing must collapse the row to a single stop")

        assertTrue(
            clickableDescriptions {
                Row(Modifier.clickable {}.clearAndSetSemantics { contentDescription = "TAPPABLE" }) {
                    BasicText("kid")
                }
            }.contains("TAPPABLE"),
            "clearing must not cost the row its click action",
        )
    }

    @Test fun assistToolSpeaksItsNameStateAndHoldGesture() {
        val spoken = render {
            com.opencapture.openpocketcine.assists.AssistToolCell(
                tool = LiveAssistTool.WAVE,
                isOn = true,
                enabled = true,
                onLongClick = {},
                onClick = {},
            )
        }
        assertEquals(listOf("Waveform, on. Hold for options"), spoken)
    }

    /**
     * The cell's own label promises a hold gesture, so the hold action has to
     * still be there after the clear — otherwise the sentence sends operators
     * after something the tree no longer offers.
     */
    @Test fun aClearedAssistToolStillOffersTapAndHold() {
        val actions = actionsOf("Waveform, on. Hold for options") {
            com.opencapture.openpocketcine.assists.AssistToolCell(
                tool = LiveAssistTool.WAVE,
                isOn = true,
                enabled = true,
                onLongClick = {},
                onClick = {},
            )
        }
        assertTrue(actions.contains(CLICK), "tap must survive clearAndSetSemantics, got $actions")
        assertTrue(actions.contains(LONG_CLICK), "hold must survive clearAndSetSemantics, got $actions")
    }

    @Test fun assistToolWithoutOptionsOmitsTheHoldHint() {
        val spoken = render {
            com.opencapture.openpocketcine.assists.AssistToolCell(
                tool = LiveAssistTool.GRID,
                isOn = false,
                enabled = true,
                onLongClick = null,
                onClick = {},
            )
        }
        assertEquals(listOf("Grid, off"), spoken)
    }

    @Test fun everyAssistToolIsNamedInWordsNotItsChipAbbreviation() {
        for (tool in LiveAssistTool.entries) {
            val spoken = render {
                com.opencapture.openpocketcine.assists.AssistToolCell(
                    tool = tool,
                    isOn = false,
                    enabled = true,
                    onLongClick = null,
                    onClick = {},
                )
            }
            assertEquals(listOf("${tool.title}, off"), spoken, "tool $tool")
            // LUT is an initialism the operator says aloud; the rest must not
            // fall back to the on-screen abbreviation.
            if (tool != LiveAssistTool.LUT) {
                assertTrue(tool.title != tool.chipLabel, "tool $tool still speaks its chip label")
            }
        }
    }

    /** Collects every description the platform publishes under the host. */
    private fun render(content: @Composable () -> Unit): List<String> {
        var spoken = emptyList<String>()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val fixture = mountFixture(scenario, content)
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val deadline = SystemClock.uptimeMillis() + 5_000
            var previous: List<String>? = null
            // Window layout settles before the accessibility service publishes
            // it, and it publishes in stages — so wait for two agreeing reads
            // rather than the first non-empty one.
            while (SystemClock.uptimeMillis() < deadline) {
                instrumentation.waitForIdleSync()
                val found = currentFixture(fixture)?.let(::descriptions).orEmpty()
                if (found.isNotEmpty() && found == previous) {
                    spoken = found
                    break
                }
                previous = found
                SystemClock.sleep(80)
            }
        }
        assertTrue(spoken.isNotEmpty(), "No accessibility node was published for the fixture")
        return spoken
    }

    /**
     * Actions offered by the node speaking [label] — named rather than taken
     * positionally, so the assertion cannot drift onto a neighbouring node.
     */
    private fun actionsOf(label: String, content: @Composable () -> Unit): List<Int> {
        var actions: List<Int>? = null
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val fixture = mountFixture(scenario, content)
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val deadline = SystemClock.uptimeMillis() + 5_000
            while (SystemClock.uptimeMillis() < deadline) {
                instrumentation.waitForIdleSync()
                val root = currentFixture(fixture)
                val found = root?.let { nodeSpeaking(it, label) }
                if (found != null) {
                    actions = found.actionList.map { it.id }
                    break
                }
                SystemClock.sleep(80)
            }
        }
        return actions ?: error("No node spoke \"$label\"")
    }

    private fun nodeSpeaking(node: AccessibilityNodeInfo, label: String): AccessibilityNodeInfo? {
        if (node.packageName?.toString() != TEST_PACKAGE) return null
        if (node.contentDescription?.toString() == label) return node
        for (index in 0 until node.childCount) {
            node.getChild(index)?.let { child -> nodeSpeaking(child, label)?.let { return it } }
        }
        return null
    }

    /** Descriptions carried by nodes TalkBack can actually activate. */
    private fun clickableDescriptions(content: @Composable () -> Unit): List<String> {
        var found = emptyList<String>()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            val fixture = mountFixture(scenario, content)
            val instrumentation = InstrumentationRegistry.getInstrumentation()
            val deadline = SystemClock.uptimeMillis() + 5_000
            while (SystemClock.uptimeMillis() < deadline) {
                instrumentation.waitForIdleSync()
                val root = currentFixture(fixture)
                val collected = root?.let(::clickableLabels).orEmpty()
                if (collected.isNotEmpty()) {
                    found = collected
                    break
                }
                SystemClock.sleep(80)
            }
        }
        return found
    }

    private fun mountFixture(
        scenario: ActivityScenario<BackdropRenderActivity>,
        content: @Composable () -> Unit,
    ): String {
        val identity = "semantics-fixture-${UUID.randomUUID()}"
        scenario.moveToState(Lifecycle.State.RESUMED)
        scenario.onActivity { activity ->
            activity.setContent {
                Box(Modifier.fillMaxSize().testTag(identity).semantics { testTagsAsResourceId = true }) {
                    Column { content() }
                }
            }
        }
        return identity
    }

    // Two stable reads can still be the activity's initial backdrop or an old
    // window. Scope every assertion to this mount without changing spoken labels.
    private fun currentFixture(identity: String): AccessibilityNodeInfo? {
        fun find(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.packageName?.toString() != TEST_PACKAGE) return null
            if (node.viewIdResourceName == identity) return node
            for (index in 0 until node.childCount) {
                node.getChild(index)?.let { child -> find(child)?.let { return it } }
            }
            return null
        }
        return InstrumentationRegistry.getInstrumentation().uiAutomation.rootInActiveWindow?.let(::find)
    }

    private fun clickableLabels(node: AccessibilityNodeInfo): List<String> {
        if (node.packageName?.toString() != TEST_PACKAGE) return emptyList()
        val own =
            node.contentDescription?.toString()
                ?.takeIf { it.isNotBlank() && node.actionList.any { action -> action.id == CLICK } }
        return listOfNotNull(own) +
            (0 until node.childCount).flatMap { index -> node.getChild(index)?.let(::clickableLabels).orEmpty() }
    }

    private fun descriptions(node: AccessibilityNodeInfo): List<String> {
        if (node.packageName?.toString() != TEST_PACKAGE) return emptyList()
        val own = node.contentDescription?.toString()?.takeIf { it.isNotBlank() }
        // Text that survives beside a description is text TalkBack would also
        // read, so it counts as spoken output and belongs in the assertion.
        val text = node.text?.toString()?.takeIf { it.isNotBlank() && own == null }
        val children = (0 until node.childCount).flatMap { index ->
            node.getChild(index)?.let(::descriptions).orEmpty()
        }
        return listOfNotNull(own, text) + children
    }

    private companion object {
        // The app under test, read rather than spelled out: the debug build
        // carries an `applicationIdSuffix`, so a literal would stop matching
        // every node and the tree helpers would walk away empty.
        val TEST_PACKAGE: String by lazy {
            InstrumentationRegistry.getInstrumentation().targetContext.packageName
        }
        val CLICK = AccessibilityNodeInfo.AccessibilityAction.ACTION_CLICK.id
        val LONG_CLICK = AccessibilityNodeInfo.AccessibilityAction.ACTION_LONG_CLICK.id
    }
}
