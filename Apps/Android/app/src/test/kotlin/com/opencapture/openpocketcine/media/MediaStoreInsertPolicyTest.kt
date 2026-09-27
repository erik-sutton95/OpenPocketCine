package com.opencapture.openpocketcine.media

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse

class MediaStoreInsertPolicyTest {
    @Test
    fun photosAreNeverPlacedUnderMovies() {
        // Play #348: Images collection + RELATIVE_PATH Movies/… is rejected by
        // MediaProvider with IllegalArgumentException.
        for (mime in listOf("image/jpeg", "image/heic", "image/x-adobe-dng")) {
            assertFalse(
                MediaStoreInsertPolicy.relativePath(mime).startsWith("Movies"),
                "$mime must not be inserted under Movies",
            )
        }
        assertEquals("Movies/OpenPocketCine", MediaStoreInsertPolicy.relativePath("video/mp4"))
    }

    @Test
    fun displayNameStripsPathSeparatorsAndControlChars() {
        assertEquals("a_b.jpg", MediaStoreInsertPolicy.sanitizeDisplayName("a/b.jpg"))
        assertEquals("a_b.jpg", MediaStoreInsertPolicy.sanitizeDisplayName("a\u0000b.jpg"))
        assertEquals("clip.mp4", MediaStoreInsertPolicy.sanitizeDisplayName("  clip.mp4  "))
    }

    @Test
    fun displayNameFallsBackWhenEmpty() {
        assertEquals(MediaStoreInsertPolicy.FALLBACK_NAME, MediaStoreInsertPolicy.sanitizeDisplayName(""))
        assertEquals(MediaStoreInsertPolicy.FALLBACK_NAME, MediaStoreInsertPolicy.sanitizeDisplayName("   "))
    }
}
