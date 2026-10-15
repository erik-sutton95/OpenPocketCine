package com.opencapture.openpocketcine.media

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/**
 * The gallery, its player and photo pages and their Back order come from the one shared media host
 * (A4-13), and the gallery's library owner lives in the app model for the current camera, so a
 * recomposition cannot swap it and Settings counts the same library.
 */
class MediaHostRuleTest {
    private val sources: Map<String, String> = File("src/main/kotlin").walkTopDown()
        .filter { it.isFile && it.name.endsWith(".kt") }.associate { it.name to it.readText() }

    private fun filesUsing(token: String): List<String> = sources.filterValues { token in it }.keys.sorted()

    @Test
    fun theSharedHostOwnsTheGalleryAndTheAppModelOwnsItsLibrary() {
        assertEquals(emptyList(), filesUsing("MonitorOperatorCatalogScreen("))
        assertEquals(listOf("MediaLibraryScreen.kt"), filesUsing("MonitorOperatorMediaScreen("))
        assertEquals(false, "BackHandler" in sources.getValue("MediaLibraryScreen.kt"))
        assertEquals(listOf("AppModel.kt"), filesUsing("MediaLibraryController(").filter { it != "MediaLibraryController.kt" })
    }
}
