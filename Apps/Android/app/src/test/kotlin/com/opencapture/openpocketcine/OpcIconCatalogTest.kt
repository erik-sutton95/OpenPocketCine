package com.opencapture.openpocketcine

import kotlin.test.Test
import kotlin.test.assertEquals

class OpcIconCatalogTest {
    @Test
    fun catalogNamesMatchVendoredLucideFiles() {
        assertEquals(
            listOf(
                "camera",
                "chevron-left",
                "chevron-right",
                "contrast",
                "crosshair",
                "grid-3x3",
                "layers",
                "lock",
                "pause",
                "play",
                "settings",
                "share",
                "star",
                "trash",
                "video",
                "x",
                "zap",
            ),
            OpcIcon.entries.map { it.lucideName },
        )
    }
}
