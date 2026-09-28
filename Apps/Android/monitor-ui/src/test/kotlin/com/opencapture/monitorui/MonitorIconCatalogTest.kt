package com.opencapture.monitorui

import java.io.File
import kotlin.test.Test
import kotlin.test.assertContentEquals
import kotlin.test.assertEquals

/** iOS is the icon baseline: Android ships the same SVG sources and the same Lucide names. */
class MonitorIconCatalogTest {
    private val android = File("src/main/assets/icons")
    private val ios = File("../../../Sources/MonitorUI/Resources/Icons")

    private fun svgs(dir: File) = dir.list().orEmpty().filter { it.endsWith(".svg") }.sorted()

    @Test
    fun catalogMatchesIosLucideSet() {
        val stems = svgs(File(ios, "lucide")).map { it.removeSuffix(".svg") }.toSet()
        assertEquals(stems, MonitorIcon.entries.map { it.lucideName }.toSet())
    }

    @Test
    fun svgSourcesMatchIosByteForByte() {
        for (set in listOf("lucide", "assist")) {
            val names = svgs(File(ios, set))
            assertEquals(names, svgs(File(android, set)), set)
            names.forEach {
                assertContentEquals(File(ios, "$set/$it").readBytes(), File(android, "$set/$it").readBytes(), "$set/$it")
            }
        }
    }
}
