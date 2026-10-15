@file:androidx.media3.common.util.UnstableApi
package com.opencapture.openpocketcine.media

import androidx.media3.exoplayer.ExoPlayer
import com.opencapture.opencine.appkit.*
import com.opencapture.opencine.media.*
import com.opencapture.opencine.media.MonitorPlaybackItemToken
import com.opencapture.opencine.media3.Media3PlaybackPort
import kotlinx.coroutines.test.runTest
import java.lang.reflect.Proxy
import java.util.UUID
import kotlin.test.Test
import kotlin.test.assertEquals

/** The host pump and SDK release on the captured owner; port-only goldens live with Core's Media3PlaybackPortTest. */
class PocketMedia3PlaybackPortTest {
    @Test fun actualHostPumpKeepsSharedSinkAndSDKRetirementOnCapturedOwner() = runTest {
        val ownerThread = Thread.currentThread()
        val dispatcher = kotlinx.coroutines.test.StandardTestDispatcher(testScheduler)
        val parent = java.nio.file.Files.createTempDirectory("pocket-player-pump-").toFile()
        val directory = com.opencapture.opencine.appkit.MonitorMediaCacheDirectory(java.io.File(parent, "canonical"))
        val staged = java.io.File(parent, "incoming")
        staged.writeBytes(ByteArray(128 * 1024 + 7) { (it % 127).toByte() })
        val codec = PocketMediaLibraryCodec({ null }, { false }, { -1 })
        val cache = MonitorMediaCache(directory, codec, MonitorMediaOriginalEligibility.ExactSize,
            "index.json", listOf("index.json", "color.json"), persistEmptyCatalog = false)
        val favorites = object : MonitorMediaFavoritesStore {
            override fun favorites() = emptySet<String>()
            override fun saveFavorites(keys: Set<String>) {}
        }
        val library = MonitorMediaLibraryModel(cache, favorites,
            scope = kotlinx.coroutines.CoroutineScope(backgroundScope.coroutineContext + dispatcher),
            cacheScanning = MonitorMediaCacheScanning.IMMEDIATE, initialCatalog = MediaCatalog(),
            initialRecords = emptyList(), catalogBase = MonitorMediaCatalogBase.FRESH_LISTING)
        val operation = PocketMediaOperation(library,
            library.captureIO(MonitorMediaLibraryIOKey("captured-player"), null) {
                kotlin.test.assertSame(ownerThread, Thread.currentThread())
                true
            })
        val plan = MediaTransferPlan(expectedByteCount = staged.length(), attempts = listOf({ sink ->
            sink.write(staged.readBytes())
            MediaTransferReceipt(staged.length(), staged.length())
        }), retry = { false })
        val sizes = mutableListOf<Int>()
        try {
            kotlinx.coroutines.withContext(dispatcher) {
                library.transferHostFile(operation.authority, object : com.opencapture.opencine.media.MediaByteSink {
                override suspend fun write(chunk: ByteArray) {
                    kotlin.test.assertSame(dispatcher,
                        kotlinx.coroutines.currentCoroutineContext()[kotlin.coroutines.ContinuationInterceptor])
                    sizes += chunk.size
                }
                }, plan, parent)
            }
            assertEquals(listOf(64 * 1024, 64 * 1024, 7), sizes)
            var releases = 0
            val player = Proxy.newProxyInstance(ExoPlayer::class.java.classLoader, arrayOf(ExoPlayer::class.java)) { _, method, _ ->
                if (method.name == "release") {
                    kotlin.test.assertSame(ownerThread, Thread.currentThread())
                    releases += 1
                }
                null
            } as ExoPlayer
            val native = Media3PlaybackPort(player, backgroundScope)
            val token = MonitorPlaybackItemToken(UUID.randomUUID(), 0)
            native.retireItem(token)
            var writes = 0
            val refusal = kotlin.test.assertFailsWith<MediaServiceException> {
                kotlinx.coroutines.withContext(dispatcher) {
                    library.transferHostFile(operation.authority, object : com.opencapture.opencine.media.MediaByteSink {
                    override suspend fun write(chunk: ByteArray) {
                        kotlin.test.assertSame(dispatcher,
                            kotlinx.coroutines.currentCoroutineContext()[kotlin.coroutines.ContinuationInterceptor])
                        writes += 1
                        native.close(token)
                        directory.clear(emptyList())
                    }
                    }, plan, parent)
                }
            }
            assertEquals(MediaServiceFailure.RETIRED, refusal.failure)
            assertEquals(1, writes, "Clear retires later chunks before they reach the shared sink")
            assertEquals(1, releases, "Actual SDK release stays on the captured presentation owner")
        } finally { parent.deleteRecursively() }
    }


}
