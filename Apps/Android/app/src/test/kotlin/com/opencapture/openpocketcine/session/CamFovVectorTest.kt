package com.opencapture.openpocketcine.session

import java.io.File
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue
import kotlin.test.fail

/**
 * The Kotlin half of `Tests/Fixtures/camfov-vectors.tsv`.
 *
 * This file re-implements `CamFov` and `VideoResolution` from the Swift core by hand, and nothing
 * in the build links the two. Both suites read the same rows so a change that lands on one side and
 * not the other fails a test instead of shipping. See `CamFovVectorTests.swift`.
 */
class CamFovVectorTest {
    private companion object {
        /** Gradle starts unit tests in the module dir; the fixture sits at the repo root. */
        val vectors: List<List<String>> by lazy {
            var dir: File? = File("").absoluteFile
            var found: File? = null
            while (dir != null && found == null) {
                val candidate = File(dir, "Tests/Fixtures/camfov-vectors.tsv")
                if (candidate.isFile) found = candidate
                dir = dir.parentFile
            }
            found
                ?.readLines()
                .orEmpty()
                .filter { it.isNotBlank() && !it.startsWith("#") }
                .map { it.split("\t") }
        }

        fun num(field: String): Double? = if (field == "-") null else field.toDouble()

        fun list(field: String): List<Double> =
            if (field == "-") emptyList() else field.split(",").map { it.toDouble() }

        /** Same tolerance both suites use: the fixture is 4-decimal text, not bits. */
        fun close(a: Double?, b: Double?): Boolean =
            if (a == null || b == null) a == null && b == null else abs(a - b) < 1e-4

        fun resolution(field: String): VideoResolution? =
            if (field == "-") null else VideoResolution(field.toInt(16))
    }

    @Test
    fun `fixture is present and covers every kind`() {
        assertTrue(vectors.size > 250, "fixture missing or truncated: ${vectors.size} rows")
        assertEquals(
            setOf(
                "factorRaw",
                "factorLens",
                "lensPosition",
                "displayLabel",
                "displayTenths",
                "matches",
                "nextJump",
                "previousJump",
                "stopWithinCycle",
                "pocket3ZoomMax",
                "sizeTitle",
                "activeZoomStops",
                "ceilingNote",
            ),
            vectors.map { it[0] }.toSet(),
        )
    }

    @Test
    fun `kotlin core matches every vector`() {
        for (row in vectors) {
            val want = row.last()
            val where = row.dropLast(1).joinToString(" ")
            when (row[0]) {
                "factorRaw" ->
                    assertTrue(close(CamFov.factor(row[1].toInt()), num(want)), where)
                "factorLens" ->
                    assertTrue(close(CamFov.factorFromLens(row[1].toInt()), num(want)), where)
                "lensPosition" ->
                    assertEquals(want, CamFov.lensPosition(row[1].toDouble()).toString(), where)
                "displayLabel" ->
                    assertEquals(want, CamFov.displayLabel(row[1].toDouble()), where)
                "displayTenths" ->
                    assertTrue(close(CamFov.displayTenths(row[1].toDouble()), num(want)), where)
                "matches" ->
                    assertEquals(
                        want == "true",
                        CamFov.matches(row[1].toDouble(), row[2].toDouble()),
                        where,
                    )
                "nextJump" ->
                    assertTrue(
                        close(CamFov.nextJump(row[1].toDouble(), list(row[2])), num(want)),
                        where,
                    )
                "previousJump" ->
                    assertTrue(
                        close(CamFov.previousJump(row[1].toDouble(), list(row[2])), num(want)),
                        where,
                    )
                "stopWithinCycle" ->
                    assertTrue(
                        close(CamFov.stopWithinCycle(row[1].toDouble(), list(row[2])), num(want)),
                        where,
                    )
                "pocket3ZoomMax" ->
                    assertTrue(close(resolution(row[1])?.pocket3ZoomMax, num(want)), where)
                "sizeTitle" -> assertEquals(want, resolution(row[1])?.sizeTitle, where)
                "activeZoomStops" -> {
                    // Swift derives `family` from the name; Kotlin carries it as
                    // a field. The fixture pins both readings to the same answer.
                    val model = CameraModel(name = row[1], family = row[2])
                    val got =
                        model.activeZoomStops(
                            resolution(row[3])?.rawValue ?: -1,
                            row[4].toInt(),
                        )
                    val expected = list(want)
                    assertEquals(expected.size, got.size, where)
                    got.zip(expected).forEach { (a, b) -> assertTrue(close(a, b), where) }
                }
                "ceilingNote" ->
                    assertEquals(
                        want,
                        CamFov.ceilingNote(row[1], row[2].toDouble(), list(row[3])) ?: "-",
                        where,
                    )
                else -> fail("unknown vector kind ${row[0]}")
            }
        }
    }
}
