package com.opencapture.openpocketcine.media

import com.opencapture.opencine.appkit.MonitorMediaCacheDirectory
import com.opencapture.opencine.media.MediaTransferReceipt
import java.io.File
import java.util.UUID
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.ensureActive

/** Captured host IO admission. Model/content/source facts are checked on the presentation owner. */
internal class PocketMediaOperation(
    val directory: MonitorMediaCacheDirectory,
    private val admitted: () -> Boolean,
) {
    val id: UUID = UUID.randomUUID()
    val generation: Long = directory.generation
    fun isCurrent(): Boolean = directory.generation == generation && admitted()
    fun requireCurrent() {
        if (!isCurrent()) throw CancellationException("Media operation retired")
    }

    /** Original HTTP streaming runs into a unique temporary; only this lease can commit its destination. */
    suspend fun download(
        address: String,
        temporaryRoot: File,
        ownerDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate,
        fetch: suspend (File) -> Unit,
    ): File {
        val writer = withContext(ownerDispatcher) { requireCurrent(); directory.beginWrite(address) }
        val staged = File(temporaryRoot, "$id.incoming")
        try {
            fetch(staged)
            withContext(Dispatchers.IO) {
                if (!staged.isFile || staged.length() <= 0L) throw MediaTransferError.BadResponse
                staged.inputStream().use { input ->
                    val buffer = ByteArray(64 * 1024)
                    while (true) {
                        val count = input.read(buffer)
                        if (count < 0) break
                        if (count > 0) writer.write(buffer.copyOf(count))
                    }
                }
            }
            return withContext(ownerDispatcher) {
                requireCurrent()
                writer.commit(MediaTransferReceipt(staged.length()))
            }
        } finally { writer.abort(); staged.delete() }
    }

    suspend fun thumbnail(address: String, bytes: ByteArray,
        ownerDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate) {
        withContext(ownerDispatcher) {
            requireCurrent()
            if (bytes.isEmpty()) throw MediaTransferError.BadResponse
            directory.write(bytes, address)
        }
    }
}

/** File reads stay on IO; shared sink admission and any native retirement stay on the captured owner. */
internal suspend fun pumpPocketPlaybackFile(staged: File,
    sink: com.opencapture.opencine.media.MediaByteSink, operation: PocketMediaOperation,
    ownerDispatcher: CoroutineDispatcher = Dispatchers.Main.immediate) {
    withContext(Dispatchers.IO) {
        staged.inputStream().use { input ->
            val buffer = ByteArray(64 * 1024)
            while (true) {
                kotlinx.coroutines.currentCoroutineContext().ensureActive()
                val count = input.read(buffer)
                if (count < 0) break
                if (count > 0) {
                    val chunk = buffer.copyOf(count)
                    withContext(ownerDispatcher) { operation.requireCurrent(); sink.write(chunk) }
                }
            }
        }
    }
}

/** The donor's one delete command and 400ms optimistic removal, under captured actual authority. */
internal suspend fun deletePocketCapturedContent(asset: com.opencapture.opencine.media.MediaAssetID,
    admitted: () -> Boolean, send: () -> Unit, remove: () -> Boolean,
    wait: suspend () -> Unit = { kotlinx.coroutines.delay(400) }): com.opencapture.opencine.media.MediaAssetID? {
    if (!admitted()) return null
    send()
    wait()
    if (!admitted()) return null
    return asset.takeIf { remove() }
}
