package com.opencapture.openpocketcine

import com.opencapture.opencine.appkit.MonitorActivityConfigChanges
import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/** A4-26: no configuration change the activity can handle recreates it and drops the session. */
class MonitorActivityManifestTest {
    @Test
    fun mainActivityHandlesEveryMonitorConfigurationChange() {
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertEquals(emptyList(), MonitorActivityConfigChanges.missingIn(manifest, ".MainActivity"))
    }
}
