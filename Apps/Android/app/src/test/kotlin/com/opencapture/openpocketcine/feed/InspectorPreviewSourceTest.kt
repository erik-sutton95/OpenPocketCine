package com.opencapture.openpocketcine.feed

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class InspectorPreviewSourceTest {
    @Test fun changingClipsWaitsForAFrameLatchedAfterTheNewSourceIsReady() {
        val source = InspectorPreviewSource()
        source.configure("first", true)
        source.didLatch(source.beginLatch())
        val old = assertNotNull(source.captureEpoch())
        source.configure("second", false)
        assertFalse(source.isCurrent(old))
        source.didLatch(source.beginLatch())
        assertNull(source.captureEpoch())
        source.configure("second", true)
        assertNull(source.captureEpoch())
        source.didLatch(source.beginLatch())
        assertNotNull(source.captureEpoch())
    }

    @Test fun resizeDuringLatchingRejectsTheOldFrameWithoutChangingTheDisplay() {
        val source = InspectorPreviewSource()
        val oldLatch = source.beginLatch()
        source.invalidate()
        source.didLatch(oldLatch)
        assertNull(source.captureEpoch())
        source.didLatch(source.beginLatch())
        val frame = assertNotNull(source.captureEpoch())
        assertTrue(source.isCurrent(frame))
    }
}
