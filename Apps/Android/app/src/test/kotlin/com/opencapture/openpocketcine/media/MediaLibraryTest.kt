package com.opencapture.openpocketcine.media

import java.io.ByteArrayInputStream
import java.io.ByteArrayOutputStream
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class MediaLibraryTest {
    private fun fixture(): ByteArray =
        javaClass.classLoader!!.getResourceAsStream("nano-manifest.bin")!!.readBytes()

    @Test
    fun emptyCopyDoesNotNameSisterApps() {
        val copy =
            listOf(
                MediaLibraryCopy.FILTER_EMPTY,
                MediaLibraryCopy.EMPTY_ALL,
                MediaLibraryCopy.EMPTY_FAVORITES,
                MediaLibraryCopy.EMPTY_VIDEOS,
                MediaLibraryCopy.EMPTY_PHOTOS,
                MediaLibraryCopy.DISCONNECTED,
                MediaLibraryCopy.DISCONNECTED_EMPTY_CACHE,
                MediaOperatorCopy.CLIP_NOT_CACHED,
            )
        for (text in copy) {
            assertFalse(text.contains("OpenZCine", ignoreCase = true))
            assertFalse(text.contains("Nikon", ignoreCase = true))
            assertFalse(text.contains("protocol is not", ignoreCase = true))
        }
    }

    @Test
    fun queryFiltersDateRangeAndColour() {
        val files = MediaManifest.decode(fixture())
        val august = MediaLibraryQuery.filtered(files, MediaLibraryTab.ALL, dateStart = "20260801")
        assertTrue(august.all { it.dateKey >= "20260801" })
        val april = MediaLibraryQuery.filtered(files, MediaLibraryTab.ALL, dateEnd = "20260430")
        assertTrue(april.all { it.dateKey <= "20260430" })
        val colored =
            MediaLibraryQuery.filtered(
                files,
                MediaLibraryTab.ALL,
                colors = setOf(0x41),
                shotColors = mapOf(files[0].path to 0x41),
            )
        assertEquals(listOf(files[0].path), colored.map { it.path })
        val key = "20260814"
        assertEquals(key, MediaLibraryQuery.dateKeyFromMillis(MediaLibraryQuery.millisFromDateKey(key)!!))
    }

    @Test
    fun decodesNanoManifestCountAndNames() {
        val files = MediaManifest.decode(fixture())
        assertEquals(34, files.size)
        assertEquals("DJI_20260814125250_0034_D.MP4", files.first().filename)
        assertEquals("DJI_20260404103742_0001_D.MP4", files.last().filename)
        assertTrue(files.all { it.kind == MediaKind.VIDEO })
        assertTrue(files.all { it.filename.endsWith(".MP4") })
    }

    @Test
    fun pairsThumbsHandlesAndDuration() {
        val files = MediaManifest.decode(fixture())
        val first = files[0]
        assertEquals("DCIM/DJI_001/DJI_20260814125250_0034_D.MP4", first.path)
        assertEquals("MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr", first.thumbPath)
        assertEquals(0x40100880L, first.handle)
        assertEquals(209, first.durationSeconds)
        assertEquals(25, first.fps)
        assertEquals("3840x2160", first.resolution)
        assertFalse(first.isStarred)
        assertTrue(first.sizeBytes > 0)

        val second = files[1]
        assertEquals("DJI_20260814122657_0033_D.MP4", second.filename)
        assertTrue(second.thumbPath.endsWith("DJI_20260814122657_0033_D.scr"))
        assertEquals(0x40100840L, second.handle)
        assertEquals(1551, second.durationSeconds)
    }

    @Test
    fun handleFitIsNanoGeometry() {
        val files = MediaManifest.decode(fixture())
        val withCmd = files.filter { it.cmdHandle != 0L }
        assertEquals(34, withCmd.size)
        assertEquals(0x40100880L, files[0].cmdHandle)
        assertEquals(files[0].handle, files[0].cmdHandle)
        val steps = files.zipWithNext { a, b -> wrappingSub32(a.handle, b.handle) }
        assertTrue(steps.all { it == 0x40L })
    }

    @Test
    fun httpPathsUseStorageAndScr() {
        val files = MediaManifest.decode(fixture())
        val file = files[0]
        val storage = MediaHTTP.storageGuess(file.handle, singleSdStorage = false)
        assertEquals(1, storage)
        assertEquals(
            0,
            MediaHTTP.resolvedStorage(
                stamped = 1,
                handle = file.handle,
                winner = 1,
                singleSdStorage = true,
            ),
        )
        assertEquals(
            1,
            MediaHTTP.resolvedStorage(
                stamped = 1,
                handle = file.handle,
                winner = null,
                singleSdStorage = false,
            ),
        )
        val thumb = MediaHTTP.pathUrlString(storage, file.thumbPath)
        assertEquals(
            "http://192.168.2.1/v2?storage=1&path=MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
            thumb,
        )
        val original = MediaHTTP.pathUrlString(storage, file.path)
        assertTrue(original.contains("DCIM/DJI_001/DJI_20260814125250_0034_D.MP4"))
        assertTrue(MediaHTTP.previewPaths(file).any { it.endsWith(".LRF") })
        val proxy = MediaHTTP.previewPaths(file).first()
        assertTrue(MediaHTTP.isProxyPath(proxy))
        assertFalse(MediaHTTP.isProxyPath(file.path))
        assertEquals(file.path, MediaHTTP.deliveryPath(file))
        assertFalse(MediaHTTP.isProxyPath(MediaHTTP.deliveryPath(file)))
        assertTrue(MediaHTTP.previewPaths(file).first() != MediaHTTP.deliveryPath(file))
        assertTrue(MediaHTTP.proxyPaths(file).all { MediaHTTP.isProxyPath(it) })
        assertTrue(MediaHTTP.proxyPaths(file).none { it == file.path })
        assertTrue(MediaHTTP.proxyPaths(file).isNotEmpty())
        assertEquals("video/mp4", MediaHTTP.playbackMIMEType(proxy))
        assertEquals("video/mp4", MediaHTTP.playbackMIMEType(file.path))
        assertTrue(MediaHTTP.playbackCacheFileName(proxy).endsWith(".mp4"))
        assertTrue(MediaHTTP.playbackCacheFileName(file.path).endsWith(".MP4"))
        assertEquals(MediaCacheGrade.ORIGINAL, MediaCacheGrade.resolve(true, true))
        assertEquals(MediaCacheGrade.PROXY, MediaCacheGrade.resolve(false, true))
        assertEquals(MediaCacheGrade.NONE, MediaCacheGrade.resolve(false, false))
        assertTrue(MediaCacheGrade.PROXY.isProxyOnly)
        assertTrue(MediaHTTP.pathUrl(storage, file.thumbPath).encodedPath == "/v2")
    }

    @Test
    fun listPayloadMatchesOsmosis() {
        val newest = MediaListCommand.listPayload(counter = 1, cursor = 1)
        assertEquals(1, newest[4].toInt() and 0xFF)
        assertEquals(listOf(0x01, 0x00, 0x00, 0x00), newest.slice(10..13).map { it.toInt() and 0xFF })
        assertEquals(0x2D, newest[14].toInt() and 0xFF)
        val onboard = MediaListCommand.listPayload(counter = 2, cursor = MediaListCommand.NEWEST_INTERNAL)
        assertEquals(2, onboard[4].toInt() and 0xFF)
        assertEquals(listOf(0x01, 0x00, 0x00, 0x40), onboard.slice(10..13).map { it.toInt() and 0xFF })
        assertEquals(
            listOf(0x01, 0x01, 0x00, 0x00),
            MediaCommands.exitPlaybackPayload().map { it.toInt() and 0xFF },
        )
        assertEquals(
            listOf(0x01, 0x01, 0x00, 0x01),
            MediaCommands.enterPlaybackPayload().map { it.toInt() and 0xFF },
        )
    }

    @Test
    fun deleteAndFavoritePayloadsMatchCapture() {
        val del = MediaCommands.deletePayload(handle = 0x40104480L, counter = 1)
        assertEquals(
            listOf(
                0x01,
                0x80, 0x44, 0x10, 0x40,
                0x01, 0x00, 0x00, 0x00,
                0x00,
                0x01, 0x00, 0x00, 0x00,
                0x01, 0x01, 0x00, 0x00,
            ),
            del.map { it.toInt() and 0xFF },
        )
        val fav = MediaCommands.favoritePayload(handle = 0x40104040L, on = true, counter = 1)
        assertEquals(
            listOf(
                0x01, 0x01,
                0x40, 0x40, 0x10, 0x40,
                0x01, 0x00, 0x00, 0x00,
                0x00, 0x01, 0x00, 0x00, 0x00,
            ),
            fav.map { it.toInt() and 0xFF },
        )
    }

    @Test
    fun chunkAssemblerStripsSubheader() {
        val assembler = MediaChunkAssembler()
        val payload =
            byteArrayOf(0x4A, 0x01, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00, 0xDE.toByte(), 0xAD.toByte())
        assertTrue(assembler.ingest(cmdSet = 0x00, cmdId = 0x27, payload = payload))
        assertEquals(listOf(0xDE, 0xAD), assembler.assembled(2).map { it.toInt() and 0xFF })
        val ended =
            assembler.ingest(
                cmdSet = 0x00,
                cmdId = 0x27,
                payload = byteArrayOf(0x4A, 0x03, 0x00, 0x00, 0x02, 0x00, 0x00, 0x00, 0x00, 0x00),
            )
        assertTrue(ended)
        assertTrue(assembler.sawEnd)
    }

    @Test
    fun nextCursorUsesOldestVideoHandle() {
        val files = MediaManifest.decode(fixture())
        val handles = files.map { it.handle }
        val oldest = handles.minOrNull()
        assertFalse(MediaListCommand.hasOlderPage(recordCount = 34, cursor = oldest))
        assertTrue(MediaListCommand.hasOlderPage(recordCount = 45, cursor = oldest))
        val older = MediaListCommand.nextCursor(handles, files[0].handle)
        assertEquals(files.drop(1).minOf { it.handle }, older)
    }

    @Test
    fun filterAndSortOfManifestFiles() {
        val videos =
            listOf(
                MediaFile(
                    path = "DCIM/DJI_001/DJI_20260814125250_0034_D.MP4",
                    thumbPath = "MISC/THM/DJI_001/DJI_20260814125250_0034_D.scr",
                    handle = 0x40100880L,
                    durationSeconds = 209,
                    resolution = "3840x2160",
                ),
                MediaFile(
                    path = "DCIM/DJI_001/DJI_20260404103742_0001_D.MP4",
                    thumbPath = "MISC/THM/DJI_001/DJI_20260404103742_0001_D.scr",
                    handle = 0x40100040L,
                    durationSeconds = 12,
                    isStarred = true,
                    resolution = "1920x1080",
                ),
            )
        val photo =
            MediaFile(
                path = "DCIM/DJI_001/DJI_20260801000000_0002_D.JPG",
                thumbPath = "MISC/THM/DJI_001/DJI_20260801000000_0002_D.scr",
            )
        val all = videos + photo
        assertEquals(2, MediaLibraryQuery.filtered(all, MediaLibraryTab.VIDEOS).size)
        assertEquals(1, MediaLibraryQuery.filtered(all, MediaLibraryTab.PHOTOS).size)
        assertEquals(1, MediaLibraryQuery.filtered(all, MediaLibraryTab.FAVORITES).size)
        assertEquals(2, MediaLibraryQuery.filtered(all, MediaLibraryTab.ALL, formats = setOf("MP4")).size)
        assertEquals(1, MediaLibraryQuery.filtered(all, MediaLibraryTab.ALL, resolutions = setOf("3840x2160")).size)
        val oldest = MediaLibraryQuery.sorted(all, MediaLibrarySort.OLDEST)
        assertEquals("DJI_20260404103742_0001_D.MP4", oldest.first().filename)
        val newest = MediaLibraryQuery.sorted(videos, MediaLibrarySort.NEWEST)
        assertEquals("DJI_20260814125250_0034_D.MP4", newest.first().filename)
        assertEquals("4K", MediaClipPresentation.resolutionLabel("3840x2160"))
        assertEquals("1080p", MediaClipPresentation.resolutionLabel("1920x1080"))
    }

    @Test
    fun offlineLibraryHidesThumbOnlyClips() {
        val cached =
            MediaFile(path = "DCIM/DJI_001/CACHED.MP4", thumbPath = "MISC/THM/CACHED.scr")
        val thumbOnly =
            MediaFile(path = "DCIM/DJI_001/THUMB_ONLY.MP4", thumbPath = "MISC/THM/THUMB_ONLY.scr")
        val shown = MediaLibraryQuery.cachedOnly(listOf(cached, thumbOnly), setOf(cached.path))
        assertEquals(listOf("CACHED.MP4"), shown.map { it.filename })
    }

    @Test
    fun starByteIsStrictlyOne() {
        val bytes = ByteArray(20)
        bytes[0] = 0xFF.toByte()
        bytes[1] = 0x19
        bytes[2] = 0x06
        bytes[9] = 44
        val files = MediaManifest.decode(bytes)
        assertTrue(files.isEmpty())
    }

    @Test
    fun liveResumeExitsUntilPlaybackClears() {
        assertEquals(
            MediaLiveResume.Action.EXIT_PLAYBACK,
            MediaLiveResume.action(attempt = 1, inPlayback = true, exitAcknowledged = false, pictureFresh = false),
        )
        assertEquals(
            MediaLiveResume.Action.ENABLE_LIVE_VIEW,
            MediaLiveResume.action(attempt = 2, inPlayback = false, exitAcknowledged = true, pictureFresh = false),
        )
        assertEquals(
            MediaLiveResume.Action.DONE,
            MediaLiveResume.action(attempt = 3, inPlayback = false, exitAcknowledged = true, pictureFresh = true),
        )
        assertEquals(
            MediaLiveResume.Action.EXIT_PLAYBACK,
            MediaLiveResume.strayPlaybackAction(browsing = false, inPlayback = true),
        )
        assertEquals(null, MediaLiveResume.strayPlaybackAction(browsing = true, inPlayback = true))
        val failed = MediaBrowsePolicy.afterEnterPlayback(false)
        assertTrue(failed.listNewestPage)
        assertFalse(failed.listOlderPages)
        assertTrue(failed.keepBrowsing)
        val entered = MediaBrowsePolicy.afterEnterPlayback(true)
        assertTrue(entered.listNewestPage)
        assertTrue(entered.listOlderPages)
        assertTrue(entered.keepBrowsing)
    }

    @Test
    fun downloadFinishesAtContentLengthWithoutWaitingForEof() {
        val body = ByteArray(100) { it.toByte() }
        val padded = body + ByteArray(40) { 0xFF.toByte() }
        val out = ByteArrayOutputStream()
        val written = MediaTransfer.readUntilLength(ByteArrayInputStream(padded), out, expected = 100) { }
        assertEquals(100L, written)
        assertEquals(100, out.size())
        assertEquals(body.toList(), out.toByteArray().toList())
    }

    @Test
    fun ramCopyEnforcesMaxBytesForKnownAndUnknownLengths() {
        data class Case(val name: String, val size: Int, val expected: Long, val rejects: Boolean)
        val cases =
            listOf(
                Case("unknown length past max is rejected", size = 200, expected = 0, rejects = true),
                Case("unknown length within max succeeds", size = 50, expected = 0, rejects = false),
                Case("unknown length at exact max succeeds", size = 100, expected = 0, rejects = false),
                Case("known length above max is rejected without copying", size = 200, expected = 200, rejects = true),
            )
        for (case in cases) {
            val body = ByteArray(case.size) { it.toByte() }
            val out = ByteArrayOutputStream()
            val read = {
                MediaTransfer.readUntilLength(
                    ByteArrayInputStream(body),
                    out,
                    expected = case.expected,
                    maxBytes = 100,
                ) { }
            }
            if (case.rejects) {
                assertFailsWith<MediaTransferError.BadResponse>(case.name) { read() }
                if (case.expected == 0L) {
                    assertTrue(out.size() <= 100, case.name)
                } else {
                    assertEquals(0, out.size(), case.name)
                }
            } else {
                assertEquals(case.size.toLong(), read(), case.name)
                assertEquals(body.toList(), out.toByteArray().toList(), case.name)
            }
        }
    }

    @Test
    fun downloadIsCompleteOnlyAtExactExpectedLength() {
        assertTrue(MediaCache.isCompleteDownload(100, 100))
        assertFalse(MediaCache.isCompleteDownload(90, 100))
        assertTrue(MediaCache.isCompleteDownload(1, 0))
        assertFalse(MediaCache.isCompleteDownload(0, 100))
    }
}
