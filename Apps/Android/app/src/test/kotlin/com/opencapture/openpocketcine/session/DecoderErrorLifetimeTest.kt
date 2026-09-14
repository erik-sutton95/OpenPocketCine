package com.opencapture.openpocketcine.session

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNotNull
import kotlin.test.assertNull
import kotlin.test.assertTrue

class DecoderErrorLifetimeTest {
    @Test
    fun firstErrorAndClassChangeJournalImmediatelyThenRepeatOncePerSecond() {
        val life = DecoderErrorLifetime()
        val first =
            life.note(record("queue", "IllegalStateException", generation = 0), nowMs = 1_000)
        assertNotNull(first)
        assertTrue(life.failedThisGeneration)
        assertEquals(1, life.countThisGeneration)
        assertNull(life.note(record("queue", "IllegalStateException", generation = 0), nowMs = 1_400))
        val repeat =
            life.note(record("queue", "IllegalStateException", generation = 0), nowMs = 2_000)
        assertNotNull(repeat)
        val changed = life.note(record("output", "codec:12", generation = 0), nowMs = 2_100)
        assertNotNull(changed)
        assertEquals("output", changed.origin.wire)
    }

    @Test
    fun resetClearsPreviousLifetimeSoItCannotWedgeTheNextDecoder() {
        val life = DecoderErrorLifetime()
        life.note(record("configure", "IllegalStateException", generation = 0), nowMs = 10)
        assertTrue(life.failedThisGeneration)
        life.resetLifetime()
        assertFalse(life.failedThisGeneration)
        assertNull(life.lastError)
        assertEquals(0, life.countThisGeneration)
        val next = life.note(record("queue", "IllegalStateException", generation = 1), nowMs = 20)
        assertNotNull(next)
        assertEquals(life.generation, next.generation)
    }

    @Test
    fun journalLineOmitsPayloadAndStack() {
        val line =
            record("output", "codec:12", generation = 3).copy(inputIsIrap = false, lastOutputAgeMs = 3500)
                .journalLine()
        assertTrue(line.contains("origin=output"))
        assertTrue(line.contains("code=codec:12"))
        assertTrue(line.contains("gen=3"))
        assertFalse(line.contains("\n"))
        assertFalse(line.contains("at com."))
        assertFalse(line.contains("nal"))
    }

    private fun record(origin: String, code: String, generation: Int) =
        DecoderErrorRecord(
            origin = DecoderErrorOrigin.entries.first { it.wire == origin },
            code = code,
            generation = generation,
            formatGeneration = 1,
            codec = "HEVC",
            width = 1280,
            height = 720,
            inputIsIrap = null,
            lastOutputAgeMs = null,
            atElapsedMs = 0,
        )
}
