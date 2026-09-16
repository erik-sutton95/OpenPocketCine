package com.opencapture.openpocketcine.media

/**
 * MediaStore insert rules that are easy to get wrong and crash when wrong (#348).
 *
 * `MediaProvider` validates the top of `RELATIVE_PATH` against the target
 * collection: photos must live under `Pictures`/`DCIM`, video under `Movies`.
 * Inserting a photo into the Images collection with `RELATIVE_PATH = Movies/…`
 * is rejected with `IllegalArgumentException`, so the directory follows the
 * MIME and never a fixed default.
 *
 * Literals, not `Environment.DIRECTORY_*`: AGP's mockable `android.jar` nils
 * those constants in unit tests, and the platform values are stable.
 */
internal object MediaStoreInsertPolicy {
    const val PICTURES = "Pictures"
    const val MOVIES = "Movies"
    const val ALBUM = "OpenPocketCine"
    const val FALLBACK_NAME = "OpenPocketCine_media"

    fun isImage(mime: String): Boolean = mime.startsWith("image/")

    fun relativePath(mime: String): String =
        if (isImage(mime)) {
            "$PICTURES/$ALBUM"
        } else {
            "$MOVIES/$ALBUM"
        }

    /** Filesystem-safe `DISPLAY_NAME`; a path separator or NUL is rejected by MediaStore. */
    fun sanitizeDisplayName(name: String): String {
        val cleaned =
            name.replace('/', '_').replace('\u0000', '_').filterNot { it.isISOControl() }.trim()
        return cleaned.ifEmpty { FALLBACK_NAME }
    }
}
