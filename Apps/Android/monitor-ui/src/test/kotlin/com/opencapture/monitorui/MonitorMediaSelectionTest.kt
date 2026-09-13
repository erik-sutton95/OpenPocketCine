package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MonitorMediaSelectionTest {
    private val ids = (0 until 12).map { it.toString() }
    private val letters = listOf("a", "b", "c", "d", "e", "f", "g", "h", "i", "j")

    @Test fun selectionSweepsInBothDirectionsAndRestoresOriginalStateOnReversal() {
        val sweep = MonitorMediaDragSelection.start(ids, "4", setOf("1", "6", "hidden"))
        assertNotNull(sweep)
        assertEquals(setOf("1", "4", "6", "hidden"), sweep.selectedIds)
        assertTrue(sweep.move(8))
        assertEquals(setOf("1", "4", "5", "6", "7", "8", "hidden"), sweep.selectedIds)
        assertTrue(sweep.move(2))
        assertEquals(setOf("1", "2", "3", "4", "6", "hidden"), sweep.selectedIds)
        assertTrue(sweep.move(4))
        assertEquals(setOf("1", "4", "6", "hidden"), sweep.selectedIds)
        assertFalse(sweep.move(4))
    }

    @Test fun selectedOriginDeselectsAndRestoresMixedPriorSelection() {
        val sweep = MonitorMediaDragSelection.start(ids, "4", setOf("1", "4", "6", "9"))
        assertNotNull(sweep)
        assertEquals(setOf("1", "6", "9"), sweep.selectedIds)
        sweep.move(9)
        assertEquals(setOf("1"), sweep.selectedIds)
        sweep.move(2)
        assertEquals(setOf("1", "6", "9"), sweep.selectedIds)
        sweep.move(0)
        assertEquals(setOf("6", "9"), sweep.selectedIds)
        sweep.move(4)
        assertEquals(setOf("1", "6", "9"), sweep.selectedIds)
    }

    @Test fun missingOriginIsRejectedAndIndexJumpsAreBounded() {
        assertNull(MonitorMediaDragSelection.start(emptyList(), "0", emptySet()))
        val sweep = MonitorMediaDragSelection.start(ids, "0", emptySet())
        assertNotNull(sweep)
        sweep.move(Int.MAX_VALUE)
        assertEquals(ids.toSet(), sweep.selectedIds)
        sweep.move(Int.MIN_VALUE)
        assertEquals(setOf("0"), sweep.selectedIds)
    }

    @Test fun autoScrollHasQuietCenterEasedEdgesAndFiniteSpeed() {
        assertEquals(0f, MonitorMediaSelectionPolicy.edgeVelocity(200f, 400f))
        assertEquals(-180f, MonitorMediaSelectionPolicy.edgeVelocity(28f, 400f))
        assertEquals(180f, MonitorMediaSelectionPolicy.edgeVelocity(372f, 400f))
        assertEquals(-720f, MonitorMediaSelectionPolicy.edgeVelocity(-100f, 400f))
        assertEquals(720f, MonitorMediaSelectionPolicy.edgeVelocity(500f, 400f))
        assertEquals(0f, MonitorMediaSelectionPolicy.edgeVelocity(Float.NaN, 400f))
        assertEquals(0f, MonitorMediaSelectionPolicy.edgeVelocity(0f, 0f))
        assertEquals(0f, MonitorMediaSelectionPolicy.edgeVelocity(15f, 30f))
        assertEquals(minOf(56f, 400f / 3f), MonitorMediaSelectionPolicy.edgeBand(400f))
        assertEquals(10f, MonitorMediaSelectionPolicy.edgeBand(30f))
    }

    @Test fun controllerHoldThenSweepPublishesOncePerEndpoint() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("b", 10f, 10f, 1_000L)
        assertNull(controller.holdDue(1_279L))
        val began = controller.holdDue(1_280L) as MonitorMediaSelectionController.News.Selection
        assertTrue(began.selecting)
        assertEquals(setOf("b"), began.selected)
        assertNull(controller.move("b", 10f, 12f))
        val sweep = controller.move("e", 10f, 80f) as MonitorMediaSelectionController.News.Selection
        assertEquals(setOf("b", "c", "d", "e"), sweep.selected)
        assertNull(controller.move("e", 12f, 82f))
        controller.up(false)
        assertFalse(controller.consuming)
        assertEquals(setOf("b", "c", "d", "e"), controller.selected)
    }

    @Test fun slopBeforeHoldCancelsAndDoesNotOpen() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("a", 0f, 0f, 0L)
        assertNull(controller.move("a", 6f, 0f))
        assertNull(controller.holdDue(280L))
        assertNull(controller.up(false))
        assertFalse(controller.selecting)
        assertTrue(controller.selected.isEmpty())
    }

    @Test fun tapOpensWhileBrowsingAndTogglesWhileSelecting() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("d", 0f, 0f, 0L)
        val open = controller.up(false) as MonitorMediaSelectionController.News.Open
        assertEquals("d", open.id)

        controller.bind(letters, true, setOf("a"))
        controller.down("a", 0f, 0f, 0L)
        val off = controller.up(false) as MonitorMediaSelectionController.News.Selection
        assertEquals(emptySet(), off.selected)
        controller.down("c", 0f, 0f, 0L)
        val on = controller.up(false) as MonitorMediaSelectionController.News.Selection
        assertEquals(setOf("c"), on.selected)
    }

    @Test fun childConsumedTapDoesNotOpenOrToggle() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("a", 0f, 0f, 0L)
        assertNull(controller.up(childConsumed = true))
    }

    @Test fun selectingDragStartsFromUnselectedAndSelectedOrigins() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, true, setOf("a", "b", "c"))
        controller.down("e", 0f, 0f, 0L)
        val select = controller.move("g", 8f, 0f) as MonitorMediaSelectionController.News.Selection
        assertEquals(setOf("a", "b", "c", "e", "f", "g"), select.selected)

        controller.cancel()
        controller.bind(letters, true, setOf("a", "b", "c", "d"))
        controller.down("b", 0f, 0f, 0L)
        val deselect = controller.move("d", 8f, 0f) as MonitorMediaSelectionController.News.Selection
        assertEquals(setOf("a"), deselect.selected)
    }

    @Test fun selectingVerticalSwipeYieldsToScrollAndLocksTheTouch() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, true, setOf("a"))
        controller.down("a", 0f, 0f, 0L)
        assertNull(controller.move("c", 2f, 8f))
        assertTrue(controller.shouldYieldToScroll())
        assertNull(controller.move("e", 20f, 8f))
        assertFalse(controller.consuming)
        assertEquals(setOf("a"), controller.selected)
        assertNull(controller.holdDue(280L))
    }

    @Test fun holdThenVerticalSweepStaysASelectionGesture() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, true, emptySet())
        controller.down("a", 0f, 0f, 0L)
        controller.holdDue(280L)
        val sweep = controller.move("d", 0f, 40f) as MonitorMediaSelectionController.News.Selection
        assertEquals(setOf("a", "b", "c", "d"), sweep.selected)
        assertFalse(controller.shouldYieldToScroll())
    }

    @Test fun cancelStopsConsumingAndKeepsLastPublishedSelection() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("a", 0f, 0f, 0L)
        controller.holdDue(280L)
        controller.move("c", 0f, 20f)
        assertTrue(controller.consuming)
        controller.cancel()
        assertFalse(controller.consuming)
        assertEquals(setOf("a", "b", "c"), controller.selected)
        assertNull(controller.up(false))
    }

    @Test fun reorderCancelsAnActiveGesture() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("a", 0f, 0f, 0L)
        controller.holdDue(280L)
        assertTrue(controller.consuming)
        controller.bind(letters.reversed(), true, controller.selected)
        assertFalse(controller.consuming)
    }

    @Test fun stationaryEdgeTickCapsDtAndStopsRebuildingUnchangedEndpoints() {
        val controller = MonitorMediaSelectionController()
        controller.bind(letters, false, emptySet())
        controller.down("a", 10f, 800f, 0L)
        controller.holdDue(280L)
        val capped = controller.edgeScroll(0.2f, 800f)
        assertEquals(MonitorMediaSelectionPolicy.MAX_EDGE_VELOCITY * 0.05f, capped, 0.01f)
        assertNull(controller.afterScroll("a"))
        val next = controller.afterScroll("c") as MonitorMediaSelectionController.News.Selection
        assertEquals(setOf("a", "b", "c"), next.selected)
        assertNull(controller.afterScroll("c"))
        controller.move("c", 10f, 400f)
        assertEquals(0f, controller.edgeScroll(0.1f, 800f))
    }

    @Test fun hitRegistryIgnoresOffscreenCellsAndPicksNearestVisibleColumn() {
        val registry = MonitorMediaHitRegistry()
        registry.put("off", 0f, -180f, 80f, -20f)
        registry.put("left", 0f, 0f, 80f, 80f)
        registry.put("right", 90f, 0f, 170f, 80f)
        registry.put("low", 90f, 400f, 170f, 480f)
        assertEquals("left", registry.resolve(20f, 20f, 200f, 200f, nearest = false))
        assertNull(registry.resolve(20f, -40f, 200f, 200f, nearest = false))
        assertEquals("right", registry.resolve(160f, 10f, 200f, 200f, nearest = true))
        assertNull(registry.resolve(Float.NaN, 10f, 200f, 200f, nearest = true))
        registry.remove("left")
        assertEquals("right", registry.resolve(20f, 10f, 200f, 200f, nearest = true))
    }
}
