package com.opencapture.monitorui

import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.SnapshotStateObserver
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class MonitorFloatingDragTest {
    @Test fun pointerSamplesInvalidateOnlyPlacementUntilReleaseStoresOnce() {
        val drag = MonitorFloatingDrag<Int>()
        val stored = mutableStateOf<Int?>(null)
        var modelInvalidations = 0
        var placementInvalidations = 0
        var stores = 0
        val onModelChanged: (String) -> Unit = { modelInvalidations++ }
        val onPlacementChanged: (String) -> Unit = { placementInvalidations++ }
        val observer = SnapshotStateObserver { it() }
        observer.start()
        try {
            observer.observeReads("model", onModelChanged) { stored.value }
            drag.begin(0)
            repeat(120) { index ->
                observer.observeReads("placement", onPlacementChanged) { drag.preview }
                drag.move(index + 1)
                Snapshot.sendApplyNotifications()
            }
            assertEquals(0, modelInvalidations)
            assertEquals(120, placementInvalidations)
            assertEquals(120, drag.preview)
            drag.end { stores++; stored.value = it }
            Snapshot.sendApplyNotifications()
            assertEquals(1, modelInvalidations)
            assertEquals(1, stores)
            assertEquals(120, stored.value)
            drag.end { stores++ }
            assertEquals(1, stores)
        } finally { observer.stop(); observer.clear() }
    }

    @Test fun holdAndCancellationNeverStorePlacement() {
        val drag = MonitorFloatingDrag<Int>()
        var stores = 0
        drag.begin(20)
        drag.end { stores++ }
        drag.begin(20)
        drag.move(80)
        drag.cancel()
        drag.end { stores++ }
        assertEquals(0, stores)
        assertNull(drag.preview)
        assertNull(drag.origin)
    }
}
