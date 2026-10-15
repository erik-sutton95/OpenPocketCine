package com.opencapture.openpocketcine.multiview

import java.io.File
import kotlin.test.Test
import kotlin.test.assertFalse

/**
 * A4-29: the model owns the Multiview session, so the stage screen leaving composition (a late
 * root connect going live, the root route changing) never tears down its tiles.
 */
class MultiviewStageOwnerRuleTest {
    @Test
    fun theStageScreenNeitherCreatesNorDisposesTheSession() {
        val screen = File("src/main/kotlin/com/opencapture/openpocketcine/multiview/MultiviewScreen.kt").readText()
        assertFalse(Regex("""\bMultiviewSession\(""").containsMatchIn(screen), "MultiviewScreen creates the session")
        assertFalse(screen.contains("session.dispose()"), "MultiviewScreen disposes the session")
    }
}
