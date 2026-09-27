package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.foundation.layout.size
import androidx.compose.material3.DropdownMenu
import androidx.compose.material3.Text
import androidx.compose.material3.MaterialTheme
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.testTagsAsResourceId
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.multiview.MultiviewCameraAction
import com.opencapture.openpocketcine.multiview.MultiviewAssistPalette
import com.opencapture.openpocketcine.multiview.MultiviewCameraSettings
import com.opencapture.openpocketcine.multiview.MultiviewSession
import com.opencapture.openpocketcine.multiview.MultiviewCameraMenu
import com.opencapture.openpocketcine.multiview.MultiviewTileChrome
import com.opencapture.openpocketcine.multiview.MultiviewTileOverlay
import com.opencapture.openpocketcine.multiview.multiviewTileReadouts
import com.opencapture.openpocketcine.session.CameraStatus
import com.opencapture.openpocketcine.session.CameraCommands
import com.opencapture.openpocketcine.session.CameraModel
import com.opencapture.openpocketcine.session.CameraNetworkPath
import com.opencapture.openpocketcine.session.DatalinkDriver
import com.opencapture.openpocketcine.session.FoundCamera
import com.opencapture.monitorui.MonitorDrawerTabs
import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import com.opencapture.monitorui.MonitorInspectorPolicy
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.monitorui.MultiviewArrangement
import com.opencapture.monitorui.MultiviewPresentationLayout
import java.net.DatagramSocket
import java.net.Socket
import java.util.Collections
import kotlin.math.abs
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Real Compose semantics/menu dispatch at the compact portrait-feed size; no camera I/O. */
@RunWith(AndroidJUnit4::class)
class MultiviewTileChromeTest {
    @Test fun horizontalTabsShareEdgesAndPreserveFullTargetsAndSelection() = joinedTabsFixture(false)

    @Test fun verticalTabsShareEdgesAndPreserveFullTargetsAndSelection() = joinedTabsFixture(true)

    private fun joinedTabsFixture(vertical: Boolean) {
        var selected = 0
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    MaterialTheme {
                        var choice by remember { mutableStateOf(0) }
                        val labels = listOf("Camera", "REC", "Settings")
                        val select: (Int) -> Unit = { selected = it; choice = it }
                        if (vertical) {
                            Column(Modifier.monitorTabStrip()) {
                                labels.forEachIndexed { index, label ->
                                    MonitorTab(choice == index, { select(index) }, Modifier.size(120.dp, 44.dp),
                                        vertical = true, separator = index > 0, accessibilityLabel = label) { Text(label) }
                                }
                            }
                        } else MonitorDrawerTabs(labels, choice, select)
                    }
                }
            }
            val density = InstrumentationRegistry.getInstrumentation().targetContext.resources.displayMetrics.density
            val hits = listOf("Camera", "REC", "Settings").map { label ->
                android.graphics.Rect().also { bounds ->
                    awaitNode(label) { node ->
                        node.getBoundsInScreen(bounds)
                        node.contentDescription?.toString() == label && bounds.width() + 1 >= 44 * density &&
                            bounds.height() + 1 >= 44 * density
                    }.getBoundsInScreen(bounds)
                }
            }
            hits.forEach { assertTrue(it.width() + 1 >= 44 * density && it.height() + 1 >= 44 * density, "Tab hit $it at density $density; all hits $hits") }
            hits.zipWithNext().forEach { (first, next) ->
                assertEquals(if (vertical) first.bottom else first.right, if (vertical) next.top else next.left)
            }
            awaitTabSelection("Camera", true)
            click(awaitNode("REC"))
            awaitCondition { selected == 1 }
            awaitTabSelection("REC", true)
            awaitTabSelection("Camera", false)
        }
    }

    @Test fun rightToolbarScrollKeepsAllFourActionsReachableOnSmallLandscape() =
        toolbarFixture(667f, 375f, MultiviewSafeArea())

    @Test fun rightIslandMovesToolbarToNativeLeftColumnWithFullTouchTargets() =
        toolbarFixture(852f, 393f, MultiviewSafeArea(trailing = 59f, bottom = 21f))

    @Test fun rightNotchMovesToolbarToNativeLeftColumnWithFullTouchTargets() =
        toolbarFixture(844f, 390f, MultiviewSafeArea(trailing = 44f, bottom = 21f))

    @Test fun leftIslandKeepsToolbarAlignedWithNativeWifiAndDisplay() =
        toolbarFixture(852f, 393f, MultiviewSafeArea(leading = 59f, bottom = 21f))

    @Test fun centerStagePaletteBelowLeftIslandKeepsAllActionsReachable() =
        toolbarFixture(852f, 393f, MultiviewSafeArea(leading = 59f, bottom = 21f), MultiviewArrangement.CENTER_STAGE)

    @Test fun centerStagePaletteBelowWifiKeepsAllActionsReachableWithRightNotch() =
        toolbarFixture(844f, 390f, MultiviewSafeArea(trailing = 44f, bottom = 21f), MultiviewArrangement.CENTER_STAGE)

    private fun toolbarFixture(width: Float, height: Float, safe: MultiviewSafeArea,
        arrangement: MultiviewArrangement = MultiviewArrangement.GRID) {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        automation.serviceInfo = automation.serviceInfo.apply {
            flags = flags or android.accessibilityservice.AccessibilityServiceInfo.FLAG_RETRIEVE_INTERACTIVE_WINDOWS
        }
        val layout = MultiviewPresentationLayout.compute(width, height, safe,
            arrangement = arrangement, selected = 0)
        val toolbarOnLeft = arrangement == MultiviewArrangement.CENTER_STAGE || safe.trailing > safe.leading
        val column = if (toolbarOnLeft) layout.sessionControls.midX else layout.display.midX
        lateinit var stage: MultiviewSession
        var settingsOpened = false
        var scale = 1f
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    stage = MultiviewSession(activity, saveStage = { true })
                    stage.layout = if (arrangement == MultiviewArrangement.GRID) {
                        com.opencapture.openpocketcine.multiview.MultiviewLayout.GRID
                    } else com.opencapture.openpocketcine.multiview.MultiviewLayout.CENTER_STAGE
                    stage.tiles[0].camera = FoundCamera("first", "unused", "First", CameraModel("Osmo Pocket 4"), null)
                    activity.setContent {
                        MaterialTheme {
                            BoxWithConstraints(Modifier.fillMaxSize()) {
                                scale = constraints.maxWidth / width
                                CompositionLocalProvider(LocalDensity provides Density(scale, 1f)) {
                                    Box(Modifier.size(width.dp, height.dp)) {
                                        MultiviewAssistPalette(stage, layout.controlCellSize,
                                            Modifier.offset(layout.assists.x.dp, layout.assists.y.dp)
                                                .requiredSize(layout.assists.width.dp, layout.assists.height.dp),
                                            maxExpandedHeight = layout.assists.height) {
                                            settingsOpened = true
                                        }
                                    }
                                }
                            }
                        }
                    }
                }
                awaitNode(if (arrangement == MultiviewArrangement.GRID) "Show Focused stage" else "Show Grid")
                click(awaitNode("Show Multiview tools"))
                awaitNode("Toggle Auto LUT for all cameras")
                    .performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
                val lut = awaitNode("Toggle Auto LUT for all cameras") { node ->
                    val bounds = android.graphics.Rect().also(node::getBoundsInScreen)
                    node.contentDescription?.toString() == "Toggle Auto LUT for all cameras" &&
                        bounds.height() + 1 >= layout.controlCellSize * scale
                }
                val lutHit = android.graphics.Rect().also(lut::getBoundsInScreen)
                assertTrue(abs(lutHit.exactCenterX() - column * scale) <= 1.5f,
                    "LUT must align with the native system column: $lutHit")
                assertEquals(toolbarOnLeft, lutHit.exactCenterX() < width / 2 * scale)
                click(lut)
                scenario.onActivity { assertTrue(!stage.tiles[0].lutEnabled) }
                val rail = awaitNode("scrollable toolbar") { it.isScrollable }
                assertTrue(rail.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD))
                SystemClock.sleep(250)
                awaitNode("scrollable toolbar") { it.isScrollable }.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                awaitNode("Camera settings").performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SHOW_ON_SCREEN.id)
                val settings = awaitNode("Camera settings after toolbar scroll settles") { node ->
                    val bounds = android.graphics.Rect().also(node::getBoundsInScreen)
                    node.contentDescription?.toString() == "Camera settings" && bounds.height() + 1 >= layout.controlCellSize * scale
                }
                val hit = android.graphics.Rect().also(settings::getBoundsInScreen)
                assertTrue(hit.height() + 1 >= layout.controlCellSize * scale, "Scrolling must expose a full camera settings target: $hit")
                assertTrue(abs(hit.exactCenterX() - column * scale) <= 1.5f,
                    "Camera settings must align with the native system column: $hit")
                assertEquals(toolbarOnLeft, hit.exactCenterX() < width / 2 * scale)
                click(settings)
                scenario.onActivity {
                    assertTrue(settingsOpened)
                    assertEquals(4, stage.tiles.size)
                }
            } finally { scenario.onActivity { stage.dispose() } }
        }
    }

    @Test fun floatingSettingsCameraTabsRetireEditsWithoutChangingStageFocus() = settingsFixture(false)

    @Test fun floatingSettingsStayReachableInSmallLandscapeViewport() = settingsFixture(true)

    @OptIn(ExperimentalComposeUiApi::class)
    private fun settingsFixture(smallLandscape: Boolean) {
        lateinit var stage: MultiviewSession
        lateinit var first: AppModel
        val expectedPanel = android.graphics.Rect()
        val expectedViewport = android.graphics.Rect()
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            try {
                scenario.onActivity { activity ->
                    stage = MultiviewSession(activity, saveStage = { true })
                    MultiviewSession::class.java.getDeclaredField("running").apply { isAccessible = true }
                        .setBoolean(stage, true)
                    repeat(2) { index ->
                        val tile = stage.tiles[index]
                        tile.camera = FoundCamera("camera-$index", "unused", "Camera $index", CameraModel("Osmo Pocket 4"), null)
                        tile.driver = DatalinkDriver(object : CameraNetworkPath {
                            override fun bindSocket(socket: DatagramSocket) = error("No sockets in UI fixture")
                            override fun bindSocket(socket: Socket) = error("No sockets in UI fixture")
                            override fun isProcessBound() = false
                            override fun cameraLocalIPv4(): String? = null
                        }, 9004, false, "osmo")
                        tile.controlHost = "unused"
                        tile.latestSettings = CameraStatus(shootingMode = CameraCommands.SHOOT_VIDEO,
                            isoIndex = 3, isoLimit = 6, expoMode = CameraCommands.EXPO_MANUAL, availableIsoIndices = listOf(3, 4, 5))
                    }
                    activity.setContent {
                        MaterialTheme {
                            BoxWithConstraints(Modifier.fillMaxSize().semantics { testTagsAsResourceId = true }) {
                                val nativeDensity = LocalDensity.current
                                val density = if (smallLandscape) Density(constraints.maxWidth / 667f, 1f) else nativeDensity
                                val width = if (smallLandscape) 667f else maxWidth.value
                                val height = if (smallLandscape) 375f else maxHeight.value
                                CompositionLocalProvider(LocalDensity provides density) {
                                    Box(Modifier.size(width.dp, height.dp).onGloballyPositioned { coordinates ->
                                        val origin = coordinates.boundsInWindow()
                                        android.graphics.RectF(origin.left, origin.top, origin.right, origin.bottom).roundOut(expectedViewport)
                                        // Camera settings reuse Live View's trailing gimbal inspector frame.
                                        val panel = MonitorInspectorPolicy.frame(width, height, trailing = true)
                                        val panelY = if (panel.portrait) (height - panel.height) / 2 else 0f
                                        android.graphics.RectF(origin.left + (width - panel.width) * density.density,
                                            origin.top + panelY * density.density, origin.left + width * density.density,
                                            origin.top + (panelY + panel.height) * density.density).roundOut(expectedPanel)
                                    }.testTag("multiview.settingsViewport")) {
                                        MultiviewCameraSettings(stage, 0, width, height,
                                            MultiviewSafeArea(top = 24f, bottom = 20f)) {}
                                    }
                                }
                            }
                        }
                    }
                }
                awaitNode("Camera settings")
                awaitCondition { stage.tiles[0].controlsModel != null }
                SystemClock.sleep(350) // Measure after the native reveal transition settles.
                val panel = android.graphics.Rect(expectedPanel)
                val screen = android.graphics.Rect(expectedViewport)
                assertTrue(panel.left > screen.left && panel.right == screen.right, "Side panel must attach to the trailing edge")
                assertTrue(panel.top >= screen.top && panel.bottom <= screen.bottom)
                for (label in listOf("Close camera settings", "A · Camera 0", "B · Camera 1", "ISO")) {
                    val action = android.graphics.Rect().also { awaitNode(label).getBoundsInScreen(it) }
                    assertTrue(panel.contains(action), "$label $action must stay inside the side panel $panel")
                }
                val viewportScale = screen.width() / if (smallLandscape) 667f else
                    InstrumentationRegistry.getInstrumentation().targetContext.resources.configuration.screenWidthDp.toFloat()
                var drum = awaitNode("adjustable ISO control") { it.rangeInfo != null }
                var drumBounds = android.graphics.Rect().also(drum::getBoundsInScreen)
                // The live preview leads the scrolled controls; short panels scroll the drum into view.
                repeat(3) {
                    if (panel.contains(drumBounds) && drumBounds.height() >= 44 * viewportScale) return@repeat
                    generateSequence(drum.parent) { it.parent }.filter { it.isScrollable }.forEach {
                        it.performAction(AccessibilityNodeInfo.ACTION_SCROLL_FORWARD)
                    }
                    SystemClock.sleep(300)
                    drum = awaitNode("adjustable ISO control") { it.rangeInfo != null }
                    drumBounds = android.graphics.Rect().also(drum::getBoundsInScreen)
                }
                assertTrue(panel.contains(drumBounds) && drumBounds.height() >= 44 * viewportScale,
                    "Native picker must remain reachable: $drumBounds in $panel")
                val progress = assertNotNull(drum.rangeInfo)
                assertTrue(drum.performAction(AccessibilityNodeInfo.AccessibilityAction.ACTION_SET_PROGRESS.id, android.os.Bundle().apply {
                    putFloat(AccessibilityNodeInfo.ACTION_ARGUMENT_PROGRESS_VALUE, (progress.current + 1).coerceAtMost(progress.max))
                }))
                awaitCondition { (stage.tiles[0].controlsModel?.session?.pendingCameraSetCount ?: 0) > 0 }
                scenario.onActivity {
                    first = assertNotNull(stage.tiles[0].controlsModel)
                    first.session.setIsoIndex(4)
                    first.session.setIsoIndex(5)
                    assertEquals(2, first.session.pendingCameraSetCount)
                }
                click(awaitNode("B · Camera 1"))
                awaitCondition { stage.tiles[1].controlsModel != null }
                scenario.onActivity {
                    assertNull(stage.tiles[0].controlsModel)
                    assertEquals(0, first.session.pendingCameraSetCount)
                    assertEquals(0, stage.focusedIndex)
                    assertEquals(4, stage.tiles.size)
                    stage.tiles[1].reset()
                }
                awaitCondition { stage.tiles[0].controlsModel != null }
                awaitNode("A · Camera 0")
                scenario.onActivity { assertEquals(0, stage.focusedIndex) }
            } finally { scenario.onActivity { stage.dispose() } }
        }
    }

    @Test fun focusedMainMetadataReservesTheOverlayReadoutBand() {
        var bottom = 0f
        var density = 1f
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                density = activity.resources.displayMetrics.density
                activity.setContent {
                    MaterialTheme {
                        Box(Modifier.size(390.dp, 260.dp).onGloballyPositioned { bottom = it.boundsInWindow().bottom }) {
                            MultiviewTileOverlay(
                                multiviewTileReadouts(0, "Main camera", "Osmo Pocket 4", CameraStatus(
                                    batteryPercent = 73, sdTotalMb = 65536, sdFreeMb = 8192,
                                    recordElapsedSec = 84), "01:02:03:04", true, true, false, false, true, null),
                                focused = true, compact = false, clean = false, enabled = true,
                                onOptions = {}, readoutsOverlay = true,
                            )
                        }
                    }
                }
            }
            for (label in listOf("Storage 8 GB", "REC 1:24", "Camera battery 73 percent")) {
                val hit = android.graphics.Rect().also { awaitNode(label).getBoundsInScreen(it) }
                assertTrue(hit.bottom <= bottom - 45 * density + 1, "$label must stay above exposure values: $hit")
            }
            awaitNode("Timecode 01:02:03")
            awaitNode("Camera A options")
        }
    }

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
            for (label in listOf("Side angle", "Osmo Pocket 4", "Timecode 01:02:03", "Camera battery 73 percent", "Storage 8 GB", "REC 1:24")) {
                awaitNode(label)
            }
            val labels = listOf("Open Live View", "Stop recording", "Disable Auto LUT", "Reconnect", "Try experimental shared Wi-Fi", "Remove camera")
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

    private fun awaitTabSelection(label: String, selected: Boolean) {
        // Compose exposes the label separately; selection lives on its tab ancestor.
        // Wait for the AX update itself, which follows the synchronous selection callback.
        awaitNode("$label selected=$selected") { node ->
            node.contentDescription?.toString() == label &&
                generateSequence(node) { it.parent }.any { it.isSelected } == selected
        }
    }

    private fun actionNode(node: AccessibilityNodeInfo): AccessibilityNodeInfo {
        var target: AccessibilityNodeInfo? = node
        while (target != null && !target.isClickable && !target.isSelected) target = target.parent
        return assertNotNull(target, "Action must expose a clickable or selected accessibility node")
    }

    private fun click(node: AccessibilityNodeInfo) {
        assertTrue(actionNode(node).performAction(AccessibilityNodeInfo.ACTION_CLICK))
        InstrumentationRegistry.getInstrumentation().waitForIdleSync()
    }

    private fun awaitNode(label: String, matches: (AccessibilityNodeInfo) -> Boolean = {
        it.text?.toString() == label || it.contentDescription?.toString() == label || it.viewIdResourceName == label
    }): AccessibilityNodeInfo {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline = SystemClock.uptimeMillis() + 5_000
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (matches(node)) return node
            for (index in 0 until node.childCount) find(node.getChild(index))?.let { return it }
            return null
        }
        while (SystemClock.uptimeMillis() < deadline) {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            find(automation.rootInActiveWindow)?.let { return it }
            for (window in automation.windows.orEmpty()) find(window.root)?.let { return it }
            SystemClock.sleep(32)
        }
        fun labels(node: AccessibilityNodeInfo?): List<String> {
            if (node == null) return emptyList()
            return listOf("${node.text}/${node.contentDescription}") + (0 until node.childCount).flatMap { labels(node.getChild(it)) }
        }
        error("Missing compact feed readout/action: $label; windows=${automation.windows.size}; " +
            (labels(automation.rootInActiveWindow) + automation.windows.flatMap { labels(it.root) }))
    }

    private fun awaitCondition(condition: () -> Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            var ready = false
            instrumentation.runOnMainSync { ready = condition() }
            if (ready) return
            SystemClock.sleep(32)
        }
        error("Camera settings binding did not update")
    }
}
