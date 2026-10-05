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
import androidx.compose.ui.layout.positionOnScreen
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.dp
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraModel
import com.opencapture.opencine.vocabulary.CameraStatus
import com.opencapture.opencine.vocabulary.FoundCamera
import com.opencapture.openpocketcine.multiview.MultiviewCameraSettings
import com.opencapture.openpocketcine.multiview.MultiviewSession
import com.opencapture.openpocketcine.multiview.MultiviewStageContent
import com.opencapture.opencine.appkit.MultiviewCameraAction as MultiviewStageAction
import com.opencapture.opencine.appkit.MultiviewReadout
import com.opencapture.opencine.appkit.MultiviewRecordContext
import com.opencapture.opencine.appkit.MultiviewStage
import com.opencapture.opencine.appkit.MultiviewStageActions
import com.opencapture.opencine.appkit.MultiviewTile
import com.opencapture.opencine.appkit.MultiviewTileStatus
import com.opencapture.opencine.appkit.MultiviewTool
import com.opencapture.opencine.multicam.MulticamGroup
import com.opencapture.opencine.multicam.MulticamSnapshot
import com.opencapture.opencine.multicam.RecordDirection
import com.opencapture.opencine.multicam.RecordPlan
import com.opencapture.opencine.multicam.TargetPolicy
import com.opencapture.opencine.dji.CameraNetworkPath
import com.opencapture.opencine.dji.DatalinkDriver
import com.opencapture.monitorui.MonitorDrawerTabs
import com.opencapture.monitorui.MonitorTab
import com.opencapture.monitorui.monitorTabStrip
import com.opencapture.monitorui.MonitorInspectorPolicy
import com.opencapture.monitorui.MonitorLayoutPolicy
import com.opencapture.monitorui.MultiviewSafeArea
import com.opencapture.monitorui.MultiviewArrangement
import com.opencapture.monitorui.MultiviewPresentationLayout
import java.net.DatagramSocket
import java.net.Socket
import java.util.Collections
import kotlin.math.abs
import kotlin.math.roundToInt
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

    // Landscape stages mount Live View's horizontal View Assist palette at its bottom-leading slot,
    // whichever edge holds a cutout and whichever arrangement shows (Pocket main's MultiviewScreen).
    @Test fun smallLandscapePaletteShowsAllFourActionsWithoutScrolling() =
        toolbarFixture(667f, 375f, MultiviewSafeArea())

    @Test fun rightIslandKeepsPaletteInLiveViewSlotWithFullTouchTargets() =
        toolbarFixture(852f, 393f, MultiviewSafeArea(trailing = 59f, bottom = 21f))

    @Test fun rightNotchKeepsPaletteInLiveViewSlotWithFullTouchTargets() =
        toolbarFixture(844f, 390f, MultiviewSafeArea(trailing = 44f, bottom = 21f))

    @Test fun leftIslandKeepsPaletteInLiveViewSlotLeftOfDisplay() =
        toolbarFixture(852f, 393f, MultiviewSafeArea(leading = 59f, bottom = 21f))

    @Test fun centerStagePaletteKeepsAllActionsReachableWithLeftIsland() =
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
        val live = MonitorLayoutPolicy.fieldMonitor(width, height, safe.top, safe.leading, safe.bottom, safe.trailing)
        assertTrue(layout.assistsHorizontal)
        assertEquals(live.assists, layout.assists, "Multiview reuses Live View's landscape palette slot")
        lateinit var stage: MultiviewSession
        var settingsOpened = false
        var scale = 1f
        val origin = android.graphics.PointF()
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
                                    Box(Modifier.size(width.dp, height.dp).onGloballyPositioned {
                                        val screen = it.positionOnScreen()
                                        origin.set(screen.x, screen.y)
                                    }) {
                                        MultiviewStageContent(stage, layout, confirmsRecord = false, interactive = true,
                                            onAdd = {}, onOpenLive = {}, onSettings = { settingsOpened = true },
                                            onNetwork = {}, onExit = {}) {}
                                    }
                                }
                            }
                        }
                    }
                }
                val layoutTitle = if (arrangement == MultiviewArrangement.GRID) "Show Focused stage" else "Show Grid"
                awaitNode(layoutTitle)
                click(awaitNode("Show Multiview tools"))
                awaitNode("Collapse Multiview tools")
                // Expanded, the four tools fill two columns of two, ranked FOCUS/GRID, LUT, FIT, CAM.
                val titles = listOf(layoutTitle, "Toggle Auto LUT for all cameras", "Fill frame with feed", "Camera settings")
                val hits = titles.map { title -> android.graphics.Rect().also { awaitNode(title).getBoundsInScreen(it) } }
                val lane = android.graphics.Rect().also { awaitNode("Collapse Multiview tools").getBoundsInScreen(it) }
                fun x(dp: Float) = origin.x + dp * scale
                fun y(dp: Float) = origin.y + dp * scale
                val cell = layout.controlCellSize
                val step = cell + MonitorLayoutPolicy.ASSIST_SPACING
                // The plate grows up and trailing from the slot's bottom-leading corner, inset 4.
                val plate = PALETTE_PLATE_EXTRA + 2 * cell
                val top = layout.assists.maxY - plate + 4
                val expected = listOf(0 to 0, 0 to 1, 1 to 0, 1 to 1).map { (column, row) ->
                    android.graphics.RectF(x(layout.assists.x + 4 + column * step), y(top + row * step),
                        x(layout.assists.x + 4 + column * step + cell), y(minOf(top + row * step + cell, layout.assists.maxY - 4)))
                }
                titles.indices.forEach { index ->
                    val hit = hits[index]
                    val want = expected[index]
                    assertTrue(abs(hit.left - want.left) <= 1.5f && abs(hit.top - want.top) <= 1.5f &&
                        abs(hit.right - want.right) <= 1.5f && abs(hit.bottom - want.bottom) <= 1.5f,
                        "${titles[index]} $hit must fill its palette cell $want (scale $scale)")
                }
                assertTrue(hits.all { it.width() + 1 >= cell * scale }, "Every tool keeps a full-width target: $hits")
                assertTrue(hits.all { it.height() + 1 >= 44 * scale }, "Every tool keeps a 44dp target: $hits")
                assertTrue(maxOf(lane.right, hits.maxOf { it.right }) < x(layout.display.x),
                    "The open palette stays short of DISP: $hits $lane")
                assertTrue(hits.minOf { it.top } > y(layout.network.maxY), "The palette sits below Wi-Fi: $hits")
                click(awaitNode(titles[1]))
                scenario.onActivity { assertTrue(!stage.tiles[0].lutEnabled) }
                click(awaitNode(titles[3]))
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
                                        // Camera settings reuse Live View's trailing gimbal inspector frame,
                                        // in whole pixels as Compose lays it out (dp sizes round to px).
                                        val panel = MonitorInspectorPolicy.frame(width, height, trailing = true)
                                        val viewport = coordinates.size
                                        val panelWidth = with(density) { panel.width.dp.roundToPx() }.coerceAtMost(viewport.width)
                                        val panelHeight = with(density) { panel.height.dp.roundToPx() }.coerceAtMost(viewport.height)
                                        val panelY = if (panel.portrait) ((viewport.height - panelHeight) / 2f).roundToInt() else 0
                                        android.graphics.RectF(origin.left + viewport.width - panelWidth, origin.top + panelY,
                                            origin.left + viewport.width, origin.top + panelY + panelHeight).roundOut(expectedPanel)
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

    /** One camera's values as Pocket maps them (73 %, 8 GB free, a 1:24 take, TC 01:02:03). */
    private fun tile(name: String, status: MultiviewTileStatus? = null) = MultiviewTile(
        name = name, model = "Osmo Pocket 4", format = "4K · 30p · Normal", battery = 73, storage = "8 GB",
        timecode = "01:02:03", tally = "REC 1:24", recording = true, status = status,
        actions = listOf(
            MultiviewStageAction(MultiviewStageAction.LIVE_VIEW, "Open Live View"),
            MultiviewStageAction("record", "Stop recording", MultiviewStageAction.Kind.RECORD),
            MultiviewStageAction("lut", "Disable Auto LUT"),
            MultiviewStageAction("reconnect", "Reconnect"),
            MultiviewStageAction("experimental", "Try experimental shared Wi-Fi"),
            MultiviewStageAction("remove", "Remove camera", MultiviewStageAction.Kind.DESTRUCTIVE),
        ),
    )

    /** A [width] x [height] dp viewport scaled to fit the device, as the toolbar fixture does. */
    @androidx.compose.runtime.Composable
    private fun Scaled(width: Float, height: Float, onScale: (Float) -> Unit = {}, content: @androidx.compose.runtime.Composable () -> Unit) {
        BoxWithConstraints(Modifier.fillMaxSize()) {
            val scale = minOf(constraints.maxWidth / width, constraints.maxHeight / height)
            onScale(scale)
            CompositionLocalProvider(LocalDensity provides Density(scale, 1f)) {
                Box(Modifier.requiredSize(width.dp, height.dp)) { content() }
            }
        }
    }

    /** The shared stage over fixed values; every action lands in [dispatched]. */
    @androidx.compose.runtime.Composable
    private fun FixtureStage(
        tiles: List<MultiviewTile?>, layout: MultiviewPresentationLayout, arrangement: MultiviewArrangement,
        dispatched: MutableList<String>, selected: Int = 0,
    ) {
        val plan = RecordPlan.make(RecordDirection.START, TargetPolicy.STRICT, emptyList(), MulticamGroup(), MulticamSnapshot())
        MultiviewStage(
            tiles, layout, arrangement, selected = selected, fill = false, tools = MultiviewTool.entries,
            readouts = null, recording = true, groupBusy = false, confirmsRecord = false,
            actions = MultiviewStageActions(
                select = {}, arrange = {}, setFill = {},
                openLiveView = { dispatched += MultiviewStageAction.LIVE_VIEW }, add = {},
                perform = { action, _ -> dispatched += action }, close = {},
                recordContext = { MultiviewRecordContext(plan) },
                record = { _, _ -> dispatched += "record" },
            ),
        ) {}
    }

    /** Grid's selected tile carries its values inline, between storage and the tally, past the palette. */
    @Test fun selectedGridTileCarriesItsValuesInlineBesideThePalette() {
        val width = 780f
        val height = 520f
        // Camera C sits over the bottom-leading View Assist palette, so its footer starts past it.
        val layout = MultiviewPresentationLayout.compute(width, height, MultiviewSafeArea(),
            MultiviewArrangement.GRID, selected = 2)
        val frame = layout.tiles[2]
        assertTrue(layout.readouts.x > frame.x, "The palette must reach under camera C's footer: $layout")
        val values = listOf(MultiviewReadout("ISO", "400"), MultiviewReadout("SHUTTER", "1/50"),
            MultiviewReadout("WB", "5600K"))
        val origin = android.graphics.PointF()
        var density = 1f
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    MaterialTheme {
                        Scaled(width, height, onScale = { density = it }) {
                            Box(Modifier.fillMaxSize().onGloballyPositioned {
                                val screen = it.positionOnScreen()
                                origin.set(screen.x, screen.y)
                            }) {
                                FixtureStage(listOf(null, null, tile("Main camera").copy(readouts = values), null), layout,
                                    MultiviewArrangement.GRID, mutableListOf(), selected = 2)
                            }
                        }
                    }
                }
            }
            fun hit(label: String) = android.graphics.Rect().also { awaitNode(label).getBoundsInScreen(it) }
            val footer = listOf(hit("Camera battery 73 percent"), hit("Storage 8 GB")) +
                values.map { hit(it.value) } + listOf(hit("REC 1:24"))
            val start = origin.x + layout.readouts.x * density
            val bottom = origin.y + frame.maxY * density
            val palette = android.graphics.RectF(origin.x + layout.assists.x * density, origin.y + layout.assists.y * density,
                origin.x + layout.assists.maxX * density, origin.y + layout.assists.maxY * density)
            for (rect in footer) {
                assertTrue(rect.left >= start - 1 && rect.bottom <= bottom + 1 && rect.bottom >= bottom - 14 * density,
                    "Footer $rect must sit on camera C's bottom row, from the value row's start $start, bottom $bottom")
                assertTrue(!android.graphics.RectF(rect).intersect(palette), "Footer $rect must clear the palette $palette")
            }
            footer.zipWithNext().forEach { (left, right) ->
                assertTrue(left.right <= right.left + 1, "Battery, storage, values and tally keep their order: $footer")
            }
            awaitNode("Timecode 01:02:03")
            awaitNode("Camera C options")
        }
    }

    @Test fun compactPortraitFeedShowsTelemetryAndEveryCameraAction() {
        val layout = MultiviewPresentationLayout.compute(390f, 844f, MultiviewSafeArea(),
            MultiviewArrangement.CENTER_STAGE, selected = 0)
        val actions = Collections.synchronizedList(mutableListOf<String>())
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    MaterialTheme {
                        Scaled(390f, 844f) {
                            FixtureStage(listOf(null, tile("Side angle"), null, null), layout,
                                MultiviewArrangement.CENTER_STAGE, actions)
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
            awaitCondition { actions.size == labels.size }
            assertEquals(listOf(MultiviewStageAction.LIVE_VIEW, "record", "lut", "reconnect", "experimental", "remove"),
                actions.toList())
        }
    }

    @Test fun cleanDisplayKeepsRecoveryStatusAndOptionsReachableOnCompactFeeds() {
        val layout = MultiviewPresentationLayout.compute(390f, 844f, MultiviewSafeArea(),
            MultiviewArrangement.CENTER_STAGE, selected = 0)
        val restoring = MultiviewTileStatus("Restoring picture…", inProgress = false)
        ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                activity.setContent {
                    MaterialTheme {
                        Scaled(390f, 844f) {
                            FixtureStage(listOf(null, tile("Side angle", restoring), null, null), layout,
                                MultiviewArrangement.CENTER_STAGE, mutableListOf())
                        }
                    }
                }
            }
            awaitNode("Exit Multiview")
            click(awaitNode("Change display mode"))
            // Clean display closes open options when it applies; tap the status after it has.
            val deadline = SystemClock.uptimeMillis() + 5_000
            while (find("Exit Multiview") != null) {
                assertTrue(SystemClock.uptimeMillis() < deadline, "Clean display must hide the stage chrome")
                SystemClock.sleep(32)
            }
            click(awaitNode("Restoring picture… Camera B options"))
            awaitNode("Open Live View")
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

    /** The first node, in the active window or any interactive window, that [matches]. */
    private fun find(label: String, matches: (AccessibilityNodeInfo) -> Boolean = {
        it.text?.toString() == label || it.contentDescription?.toString() == label || it.viewIdResourceName == label
    }): AccessibilityNodeInfo? {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        fun find(node: AccessibilityNodeInfo?): AccessibilityNodeInfo? {
            if (node == null) return null
            if (matches(node)) return node
            for (index in 0 until node.childCount) find(node.getChild(index))?.let { return it }
            return null
        }
        find(automation.rootInActiveWindow)?.let { return it }
        for (window in automation.windows.orEmpty()) find(window.root)?.let { return it }
        return null
    }

    private fun awaitNode(label: String, matches: (AccessibilityNodeInfo) -> Boolean = {
        it.text?.toString() == label || it.contentDescription?.toString() == label || it.viewIdResourceName == label
    }): AccessibilityNodeInfo {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        val deadline = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < deadline) {
            InstrumentationRegistry.getInstrumentation().waitForIdleSync()
            find(label, matches)?.let { return it }
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

/**
 * Live View's expanded landscape palette is two cells plus 11 dp tall (MonitorAssistPalette, as on
 * Pocket main): 4 + 48 + 6 + 48 + 4 needs 14, so its lower row is 3 dp short of a full cell.
 */
private const val PALETTE_PLATE_EXTRA = 11f
