package com.opencapture.openpocketcine

import java.io.File
import kotlin.test.Test
import kotlin.test.assertEquals

/** A4-43: the scripted review pipeline is debug source only, so release builds never compile or run it. */
class ReviewFixtureRuleTest {
    @Test
    fun noMainSourceReachesTheReviewFixture() {
        val reaching = File("src/main").walk().filter { it.extension == "kt" }
            .filter { file -> file.readText().contains("ReviewCameras") }.map { it.name }.toList()
        assertEquals(emptyList(), reaching)
    }
}
