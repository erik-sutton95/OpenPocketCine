package com.opencapture.monitorui

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertIs
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class MonitorQuickControlTest {
    private val control = MonitorQuickControl(listOf("100", "200", "400", "800"), "200", identity = "source-a")

    @Test fun holdArmsAt280msWithoutCommittingUntilOriginalRelease() {
        val interaction = MonitorQuickInteraction(control)
        interaction.hold(279)
        assertNull(interaction.preview)
        interaction.hold(280)
        assertEquals("200", interaction.preview?.selection)
        interaction.move(-56f, 0f)
        assertEquals("400", interaction.preview?.selection)
        assertFalse(interaction.finished, "moving only updates the read-only projection")
        assertEquals(MonitorQuickInteraction.Release.Commit(control, "400"), interaction.release(control, true))
        assertNull(interaction.preview)
        assertNull(interaction.release(control, true), "a second up cannot dispatch again")
    }

    @Test fun dragRequiresMoreThan14PointsAndStartsAtTheArmingLocation() {
        val interaction = MonitorQuickInteraction(control)
        interaction.move(-14f, 0f)
        assertNull(interaction.preview)
        interaction.move(-14.1f, 0f)
        assertEquals(1f, interaction.preview?.position)
        interaction.move(-70.1f, 0f)
        assertEquals("400", assertIs<MonitorQuickInteraction.Release.Commit>(interaction.release(control, true)).value)
    }

    @Test fun aTapOpensButAnUnchangedHoldNeverSends() {
        val tap = MonitorQuickInteraction(control)
        tap.move(3f, 2f)
        assertEquals(MonitorQuickInteraction.Release.Open, tap.release(control, true))
        val hold = MonitorQuickInteraction(control)
        hold.hold(500)
        assertNull(hold.release(control, true))
        val returned = MonitorQuickInteraction(control)
        returned.hold(280)
        returned.move(-56f, 0f)
        returned.move(0f, 0f)
        assertNull(returned.release(control, true))
    }

    @Test fun consumedScrollVerticalIntentAndSecondPointerCancelPermanently() {
        val scrolling = MonitorQuickInteraction(control)
        scrolling.move(2f, 14.1f)
        assertTrue(scrolling.finished)
        scrolling.hold(1000)
        assertNull(scrolling.preview)
        assertNull(scrolling.release(control, true))
        for (consumed in listOf(false, true)) {
            val interaction = MonitorQuickInteraction(control)
            interaction.hold(280)
            interaction.move(-56f, 0f)
            interaction.move(-70f, 0f, consumed = consumed, pointerCount = if (consumed) 1 else 2)
            assertNull(interaction.preview)
            assertNull(interaction.release(control, true))
        }
    }

    @Test fun changedSourceOptionsSelectionOrAccessCannotCommit() {
        val replacements = listOf(
            control.copy(identity = "source-b"),
            control.copy(options = listOf("100", "200", "300")),
            control.copy(selection = "100"),
            control.copy(context = "new-mode"),
            control.copy(enabled = false),
            null,
        )
        for (next in replacements) {
            val interaction = MonitorQuickInteraction(control)
            interaction.hold(280)
            interaction.move(-56f, 0f)
            assertNull(interaction.release(next, true))
        }
        val locked = MonitorQuickInteraction(control)
        locked.hold(280)
        locked.move(-56f, 0f)
        assertNull(locked.release(control, false))
        assertNull(locked.release(control, true))
    }

    @Test fun remountOrRapidSwitchCannotReviveAnOldGesture() {
        val old = MonitorQuickInteraction(control)
        old.hold(280)
        old.move(-56f, 0f)
        old.cancel()
        val newControl = control.copy(identity = "new-owner")
        val new = MonitorQuickInteraction(newControl)
        new.hold(280)
        new.move(-112f, 0f)
        assertNull(old.release(control, true))
        assertEquals(MonitorQuickInteraction.Release.Commit(newControl, "800"), new.release(newControl, true))
    }

    @Test fun unknownSelectionRemainsUnselectedUntilThePointerChangesDetent() {
        val unknown = control.copy(selection = "")
        val interaction = MonitorQuickInteraction(unknown)
        interaction.hold(280)
        assertEquals("", interaction.preview?.selection)
        assertNull(interaction.release(unknown, true))
        val moved = MonitorQuickInteraction(unknown)
        moved.hold(280)
        moved.move(-56f, 0f)
        assertEquals("200", moved.preview?.selection)
        assertNotNull(moved.release(unknown, true))
    }

    @Test fun exclusiveLeaseCannotBeTakenOrReleasedByAnotherPointerOwner() {
        val owner = MonitorQuickGestureOwner()
        val first = assertNotNull(owner.acquire("first"))
        assertNull(owner.acquire("second"))
        owner.setActive(first, true)
        assertEquals("first", owner.active)
        owner.release(first)
        val second = assertNotNull(owner.acquire("second"))
        owner.setActive(second, true)
        owner.release(first)
        assertEquals("second", owner.active)
        owner.release(second)
        assertNull(owner.active)
        assertNull(owner.owner)
    }
}
