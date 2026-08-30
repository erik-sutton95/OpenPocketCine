package com.opencapture.openpocketcine.media

import com.opencapture.openpocketcine.session.DumlFrame
import java.nio.charset.Charset
import java.util.Locale
import kotlin.math.roundToInt

/** Strip `0x00/0x27` 10-byte sub-headers and concat data chunks in arrival order. */
class MediaChunkAssembler {
    private val chunksByCounter = LinkedHashMap<Int, ByteArray>()
    var chunkCount: Int = 0
        private set
    var sawEnd: Boolean = false
        private set

    fun reset() {
        chunksByCounter.clear()
        chunkCount = 0
        sawEnd = false
    }

    fun ingest(frame: DumlFrame): Boolean {
        if (frame.cmdSet != MediaCommands.SET_GENERAL || frame.cmdId != MediaCommands.CMD_MEDIA_CHUNK) {
            return false
        }
        return ingestPayload(frame.payload)
    }

    fun ingest(cmdSet: Int, cmdId: Int, payload: ByteArray): Boolean {
        if (cmdSet != MediaCommands.SET_GENERAL || cmdId != MediaCommands.CMD_MEDIA_CHUNK) return false
        return ingestPayload(payload)
    }

    fun ingestPayload(payload: ByteArray): Boolean {
        if (payload.size < 10 || payload[0] != 0x4A.toByte()) return false
        val subtype = payload[1].toInt() and 0xFF
        if (subtype == 0x03) {
            sawEnd = true
            return true
        }
        if (subtype != 0x01 || payload.size <= 10) return false
        val counter = payload[4].toInt() and 0xFF
        val chunk = payload.copyOfRange(10, payload.size)
        val existing = chunksByCounter[counter]
        chunksByCounter[counter] =
            if (existing == null) chunk else existing + chunk
        chunkCount += 1
        return true
    }

    fun assembled(counter: Int): ByteArray = chunksByCounter[counter] ?: ByteArray(0)

    fun assembledMerged(): ByteArray {
        if (chunksByCounter.isEmpty()) return ByteArray(0)
        val keys = chunksByCounter.keys.sorted()
        val total = keys.sumOf { chunksByCounter[it]?.size ?: 0 }
        val out = ByteArray(total)
        var offset = 0
        for (key in keys) {
            val chunk = chunksByCounter[key] ?: continue
            chunk.copyInto(out, offset)
            offset += chunk.size
        }
        return out
    }

    val isEmpty: Boolean get() = chunkCount == 0
}

/** CompositePack TLV decode. Port of Osmosis `CameraSession.decodeComposite`. */
object MediaManifest {
    val videoExtensions: Set<String> =
        setOf("MP4", "MOV", "OSV", "INSV", "LRF", "LRV", "XRF")
    val photoExtensions: Set<String> =
        setOf("JPG", "JPEG", "DNG", "HEIC", "TIF", "TIFF", "PANO")

    private val latin1: Charset = Charset.forName("ISO-8859-1")

    fun decode(bytes: ByteArray): List<MediaFile> =
        flagHandleCollisions(withCmdHandles(decodeComposite(bytes)))

    /** Split one collected blob into SD (ctr 1) and internal (ctr 2) when the camera echoed counters. */
    fun decodeStores(assembler: MediaChunkAssembler): List<MediaFile> {
        val sdBytes = assembler.assembled(MediaListCommand.SD_COUNTER)
        val internalBytes = assembler.assembled(MediaListCommand.INTERNAL_COUNTER)
        val sd = if (sdBytes.isEmpty()) emptyList() else decode(sdBytes)
        val intern = if (internalBytes.isEmpty()) emptyList() else decode(internalBytes)
        val sdPaths = sd.map { it.path }.toSet()
        val inPaths = intern.map { it.path }.toSet()
        if (sd.isNotEmpty() && intern.isNotEmpty() && sdPaths == inPaths) {
            return stampStorage(decode(assembler.assembledMerged()), fallback = true)
        }
        if (sd.isEmpty() && intern.isEmpty()) {
            val merged = assembler.assembledMerged()
            return if (merged.isEmpty()) emptyList() else stampStorage(decode(merged), fallback = true)
        }
        val out = ArrayList<MediaFile>(sd.size + intern.size)
        sd.forEach { out.add(stamp(it, storage = 0, group = 0)) }
        intern.forEach { out.add(stamp(it, storage = 1, group = 1)) }
        return out
    }

    fun headerCount(bytes: ByteArray): Int {
        if (bytes.size < 4) return 0
        return u32(bytes, 0).toInt()
    }

    private data class MediaAnchor(val pos: Int, val end: Int, val path: String)

    private data class PathField(val value: String, val end: Int)

    private fun decodeComposite(bytes: ByteArray): List<MediaFile> {
        val medias = ArrayList<MediaAnchor>()
        var i = 0
        while (i < bytes.size) {
            val field = readPath(bytes, i, sub = 1, prefix = "DCIM/")
            if (field != null) {
                medias.add(MediaAnchor(pos = i, end = field.end, path = field.value))
                i = field.end
            } else {
                i += 1
            }
        }
        if (medias.isEmpty()) return emptyList()

        val boundary = listBoundary(bytes, medias.size)
        val byPath = LinkedHashMap<String, MediaFile>()
        val order = ArrayList<String>()
        for ((k, media) in medias.withIndex()) {
            val lo = if (k > 0) medias[k - 1].end else 0
            val hi = if (k + 1 < medias.size) medias[k + 1].pos else bytes.size
            val group = if (boundary > 0 && k >= boundary) 1 else 0
            if (!byPath.containsKey(media.path)) {
                val file =
                    resolveRecord(bytes, media.path, media.pos, lo, hi).copy(group = group)
                byPath[media.path] = file
                order.add(media.path)
            }
        }
        return order.mapNotNull { byPath[it] }
    }

    private fun readPath(bytes: ByteArray, i: Int, sub: Int, prefix: String): PathField? {
        if (i + 6 > bytes.size) return null
        if (u8(bytes, i) != 0x1A) return null
        if (u8(bytes, i + 2) != 0 || u8(bytes, i + 3) != 0 || u8(bytes, i + 4) != 0) return null
        if (u8(bytes, i + 5) != sub) return null
        val slen = u8(bytes, i + 1) - 6
        if (slen < prefix.toByteArray(latin1).size || i + 6 + slen > bytes.size) return null
        val raw = bytes.copyOfRange(i + 6, i + 6 + slen)
        if (raw.any { (it.toInt() and 0xFF) !in 0x20..0x7E }) return null
        val value = String(raw, latin1)
        if (!value.startsWith(prefix)) return null
        return PathField(value = value, end = i + 6 + slen)
    }

    private fun listBoundary(bytes: ByteArray, records: Int): Int {
        if (bytes.size < 4) return -1
        val declared = u32(bytes, 0).toInt()
        return if (declared in 1 until records) declared else -1
    }

    private fun resolveRecord(
        bytes: ByteArray,
        mediaDir: String,
        selfPos: Int,
        lo: Int,
        hi: Int,
    ): MediaFile {
        val base = mediaDir.substringAfterLast('/')
        var thumb: String? = null
        var t = lo
        while (t < hi) {
            val field = readPath(bytes, t, sub = 2, prefix = "MISC/")
            if (field != null && field.value.endsWith(base)) {
                thumb = field.value
                break
            }
            t += 1
        }

        var ext = ""
        var proxyExt: String? = null
        var n = lo
        while (n < hi - 2) {
            if (u8(bytes, n) == 0x0D) {
                val len = u8(bytes, n + 1)
                if (len > base.toByteArray(latin1).size && n + 2 + len <= bytes.size) {
                    val raw = bytes.copyOfRange(n + 2, n + 2 + len)
                    val value = String(raw, latin1)
                    if (value.length > base.length + 1 &&
                        value.startsWith(base) &&
                        value.getOrNull(base.length) == '.'
                    ) {
                        val e = value.substring(base.length + 1).uppercase(Locale.US)
                        if (e in videoExtensions || e in photoExtensions) {
                            ext = e
                        } else if (e == "LRF" || e == "LRV" || e == "XRF") {
                            proxyExt = e
                        }
                    }
                }
            }
            n += 1
        }

        var head = -1
        var m = lo
        while (m < hi - 4) {
            val kind = u8(bytes, m)
            val star = u8(bytes, m + 1)
            if ((kind == 0x03 || kind == 0x00) &&
                (star == 0xFF || star == 0xFE) &&
                u8(bytes, m + 2) == 0x19 &&
                u8(bytes, m + 3) == 0x06 &&
                m >= 8
            ) {
                head = m - 8
                break
            }
            m += 1
        }
        val hasMarker = head >= 0
        val isVideo = ext in videoExtensions

        var photoSize = 0L
        var photoRes: String? = null
        if (!isVideo) {
            var q = lo
            while (q < hi - 3) {
                if ((u8(bytes, q) == 0xFF || u8(bytes, q) == 0xFE) &&
                    u8(bytes, q + 1) == 0x19 &&
                    u8(bytes, q + 2) == 0x06
                ) {
                    val mk = q + 1
                    if (mk >= 14) photoSize = u32(bytes, mk - 14).toLong()
                    if (base.startsWith("DJI_") && mk + 66 <= bytes.size) {
                        val w = u32(bytes, mk + 58).toInt()
                        val h = u32(bytes, mk + 62).toInt()
                        if (w in 1..60_000 && h in 1..60_000) {
                            photoRes = "${w}x$h"
                        }
                    }
                    break
                }
                q += 1
            }
        }

        val path = if (ext.isEmpty()) mediaDir else "$mediaDir.$ext"
        val thumbBase =
            thumb
                ?: if (mediaDir.startsWith("DCIM/")) {
                    "MISC/THM/" + mediaDir.removePrefix("DCIM/")
                } else {
                    mediaDir
                }
        val thumbPath = "$thumbBase.scr"
        val handle = if (hasMarker) u32(bytes, head).toLong() else 0L
        // The handle at the marker fixed position — u32-LE at (19 06) - 10, the same tag the media
        // type is read from. Unlike the scan above this needs no guard byte and cannot run into the
        // next record, so it finds the stills a Pocket 3 writes with f6/c7 guard bytes that the scan
        // walks straight past. Untrusted here: withCmdHandles promotes it only where the independent
        // base+step fit agrees. Osmosis CameraSession.kt (#22).
        val handleCandidate =
            if (selfPos >= 17 && selfPos <= bytes.size &&
                u8(bytes, selfPos - 7) == 0x19 && u8(bytes, selfPos - 6) == 0x06
            ) {
                u32(bytes, selfPos - 17).toLong()
            } else {
                0L
            }
        val size =
            if (isVideo && hasMarker && head >= 4) {
                u32(bytes, head - 4).toLong()
            } else {
                photoSize
            }
        val fps = if (isVideo && hasMarker) fpsInRange(bytes, head, hi) else null
        val duration =
            if (isVideo && hasMarker && head + 6 <= bytes.size) {
                u8(bytes, head + 4) or (u8(bytes, head + 5) shl 8)
            } else {
                0
            }
        val resolution =
            if (isVideo && hasMarker && head + 7 < bytes.size) {
                resolutionForIndex(u8(bytes, head + 7))
            } else {
                photoRes
            }
        return MediaFile(
            path = path,
            thumbPath = thumbPath,
            handle = handle,
            sizeBytes = size,
            durationSeconds = duration,
            // Prefer the signature read where the record has one: it is the only thing that works
            // on a body whose stills carry no marker, and it agreed with the marker read everywhere
            // both fired.
            isStarred = starFlagBySignature(bytes, if (selfPos >= 0) selfPos else lo, hi)
                ?: starFlag(bytes, lo, hi),
            resolution = resolution,
            fps = fps,
            proxyPath = proxyExt?.let { "$mediaDir.$it" },
            handleCandidate = handleCandidate,
        )
    }

    /**
     * The favourite flag as a Pocket 3 writes it: a `00`/`01` byte after a fixed 12-byte signature
     * that sits *after* the record own media path, present once per record whatever the media type.
     *
     * [starFlag] cannot work on that body: it anchors on `[ff|fe] 19 06`, and a Pocket 3 still
     * carries no such marker, so a favourited photo could never show a heart at any offset. Returns
     * null where the signature is absent so the caller can fall back.
     *
     * Established in Osmosis by a controlled A/B on one card (2026-08-17): two dumps of the same nine
     * files differing in exactly three bytes, all three being the favourites changed between them.
     */
    private fun starFlagBySignature(bytes: ByteArray, lo: Int, hi: Int): Boolean? {
        var q = if (lo > 0) lo else 0
        val end = minOf(hi, bytes.size - STAR_SIG.size - 1)
        while (q <= end) {
            var k = 0
            while (k < STAR_SIG.size && bytes[q + k] == STAR_SIG[k]) k += 1
            if (k == STAR_SIG.size) return u8(bytes, q + STAR_SIG.size) == 1
            q += 1
        }
        return null
    }

    /** See [starFlagBySignature]. Constant across every Pocket 3 record dumped, once per record. */
    private val STAR_SIG =
        byteArrayOf(0x1b, 0x0a, 0x00, 0x00, 0x00, 0x02, 0x02, 0x01, 0x14, 0x02, 0x15, 0x03)

    /**
     * Star byte 9 past `[ff|fe] 19 06`. Trust only `== 1` (Nano). 44/48 on Action is a length.
     *
     * On an Xtra that offset lands on a *length* byte, so anything other than 0 or 1 means this is
     * not the layout the offset was derived from. Say "not starred" rather than guess: reading a
     * length as a flag would put a heart on every file at once. Xtra favourites therefore do not
     * survive a re-list; reading them needs the camera own 0x00/0x26 favourites filter.
     */
    private fun starFlag(bytes: ByteArray, lo: Int, hi: Int): Boolean {
        var q = lo
        while (q < hi - 9) {
            if ((u8(bytes, q) == 0xFF || u8(bytes, q) == 0xFE) &&
                u8(bytes, q + 1) == 0x19 &&
                u8(bytes, q + 2) == 0x06
            ) {
                return u8(bytes, q + 9) == 1
            }
            q += 1
        }
        return false
    }

    private fun resolutionForIndex(code: Int): String? =
        when (code) {
            10 -> "1920x1080" // 0x0A  1080p 16:9 (Xtra-verified)
            12 -> "1920x1440" // 0x0C  1080p 4:3
            16 -> "3840x2160" // 0x10  4K 16:9
            45 -> "2688x1512" // 0x2D  2.7K 16:9
            66 -> "1080x1920" // 0x42  1080p 9:16 vertical
            67 -> "1512x2688" // 0x43  2.7K 9:16 vertical
            95 -> "2688x2016" // 0x5F  2.7K 4:3
            103 -> "3840x2880" // 0x67  4K 4:3
            105 -> "1080x1080" // 0x69  1080p 1:1
            106 -> "2160x2160" // 0x6A  2160p 1:1
            107 -> "3072x3072" // 0x6B  3K 1:1
            108 -> "1728x3072" // 0x6C  3K 9:16 vertical
            125 -> "3840x3840" // 0x7D  4K 1:1, aka OpenGate
            else -> null
        }

    private fun fpsInRange(bytes: ByteArray, start: Int, end: Int): Int? {
        var fps: Int? = null
        var i = start.coerceAtLeast(0)
        val stop = minOf(end, bytes.size) - 8
        while (i <= stop) {
            val den = u32(bytes, i + 4)
            if (den == 1000u || den == 1001u) {
                val num = u32(bytes, i)
                if (num in 20_000u..250_000u) {
                    fps = (num.toDouble() / den.toDouble()).roundToInt()
                }
            }
            i += 1
        }
        return fps
    }

    private fun withCmdHandles(files: List<MediaFile>): List<MediaFile> {
        val fits = HashMap<Int, Pair<Long, Long>>()
        val groups = files.groupBy { it.group }
        for ((group, list) in groups) {
            val pts =
                list.filter { it.handle != 0L && it.sequenceNumber > 0 }
                    .map { it.sequenceNumber to it.handle }
            val unique =
                pts.groupBy { it.first }
                    .map { (seq, pairs) -> seq to pairs.first().second }
                    .sortedBy { it.first }
            if (unique.size < 2) continue
            val stepCounts = HashMap<Long, Int>()
            for (idx in 1 until unique.size) {
                val dSeq = unique[idx].first - unique[idx - 1].first
                if (dSeq <= 0) continue
                val dHandle = wrappingSub32(unique[idx].second, unique[idx - 1].second)
                if (dHandle > 0L) {
                    val step = dHandle / dSeq.toLong()
                    if (step > 0L) stepCounts[step] = (stepCounts[step] ?: 0) + 1
                }
            }
            val step = stepCounts.maxByOrNull { it.value }?.key ?: continue
            val baseCounts = HashMap<Long, Int>()
            for ((seq, handle) in unique) {
                val base = wrappingSub32(handle, wrappingMul32(seq.toLong(), step))
                baseCounts[base] = (baseCounts[base] ?: 0) + 1
            }
            val base = baseCounts.maxByOrNull { it.value }?.key ?: continue
            fits[group] = base to step
        }
        if (fits.isEmpty()) return files
        return files.map { file ->
            val fit = fits[file.group]
            if (fit == null || file.sequenceNumber <= 0) {
                file
            } else {
                val fitted =
                    wrappingAdd32(fit.first, wrappingMul32(file.sequenceNumber.toLong(), fit.second))
                when {
                    // Two independent sources agree: the bytes at the record fixed marker position,
                    // and a formula fitted to the handles the OTHER records exposed. That is the bar
                    // for a command that destroys a file — and it is how a Pocket 3 stills become
                    // deletable without inventing anything, since the handle was always in the record
                    // and only the guard-byte scan refused to read it.
                    file.handle == 0L && file.handleCandidate != 0L && file.handleCandidate == fitted ->
                        file.copy(handle = file.handleCandidate, cmdHandle = fitted)
                    // The scan produced a handle the fit contradicts. Something is being read out of
                    // the wrong place — a record-boundary overrun once handed a photo the neighbouring
                    // video handle — and there is no way to tell which is right. Drop it: losing
                    // delete on one file is recoverable, deleting whatever else lives at that handle
                    // is not.
                    file.handle != 0L && file.handle != fitted -> file.copy(handle = 0L, cmdHandle = fitted)
                    else -> file.copy(cmdHandle = fitted)
                }
            }
        }
    }

    private fun flagHandleCollisions(files: List<MediaFile>): List<MediaFile> {
        val counts = HashMap<Long, Int>()
        for (file in files) {
            if (file.handle != 0L) counts[file.handle] = (counts[file.handle] ?: 0) + 1
        }
        val shared = counts.filter { it.value > 1 }.keys
        if (shared.isEmpty()) return files
        return files.map { file ->
            if (file.handle in shared) file.copy(handleShared = true) else file
        }
    }

    private fun stampStorage(files: List<MediaFile>, fallback: Boolean): List<MediaFile> =
        files.map { file ->
            if (!fallback) {
                file
            } else {
                val handle = if (file.handle != 0L) file.handle else file.cmdHandle
                file.copy(storage = MediaHTTP.storageGuess(handle, singleSdStorage = false))
            }
        }

    private fun stamp(file: MediaFile, storage: Int, group: Int): MediaFile =
        file.copy(storage = storage, group = group)

    private fun u8(bytes: ByteArray, i: Int): Int = bytes[i].toInt() and 0xFF

    private fun u32(bytes: ByteArray, i: Int): UInt {
        val b0 = u8(bytes, i).toUInt()
        val b1 = u8(bytes, i + 1).toUInt()
        val b2 = u8(bytes, i + 2).toUInt()
        val b3 = u8(bytes, i + 3).toUInt()
        return b0 or (b1 shl 8) or (b2 shl 16) or (b3 shl 24)
    }
}
