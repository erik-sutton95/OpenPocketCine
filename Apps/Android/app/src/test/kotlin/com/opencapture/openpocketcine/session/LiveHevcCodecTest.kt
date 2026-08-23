package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LiveHevcCodecTest {
    @Test
    fun googleAndC2AndroidAreSoftware() {
        assertTrue(LiveHevcCodec.isSoftwareName("c2.android.hevc.decoder"))
        assertTrue(LiveHevcCodec.isSoftwareName("OMX.google.hevc.decoder"))
        assertFalse(LiveHevcCodec.isSoftwareName("c2.qti.hevc.decoder"))
        assertFalse(LiveHevcCodec.isSoftwareName("c2.exynos.hevc.decoder"))
        assertFalse(LiveHevcCodec.isSoftwareName("OMX.qcom.video.decoder.hevc"))
    }
}
