package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class HevcDecoderRandomAccessTest {
    @Test
    fun decoderEndHoldUsesValidPriorReferencesOnly() {
        val decoder = HevcDecoder()
        decoder.beginIDRHold()
        assertTrue(decoder.awaitingIdr)
        assertFalse(decoder.endIDRHold())
        assertTrue(decoder.awaitingIdr)
        decoder.randomAccess.adoptDecodableReferencesForTest()
        assertTrue(decoder.endIDRHold())
        assertFalse(decoder.awaitingIdr)
        decoder.rebuildPresentation()
        assertTrue(decoder.awaitingIdr)
        assertFalse(decoder.hasDecodableReferences)
        assertFalse(decoder.endIDRHold())
        assertTrue(decoder.awaitingIdr)
        decoder.reset()
        assertFalse(decoder.awaitingIdr)
        assertFalse(decoder.failedThisGeneration)
    }
}
