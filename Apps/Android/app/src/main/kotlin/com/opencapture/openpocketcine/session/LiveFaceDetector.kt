package com.opencapture.openpocketcine.session

import android.graphics.Bitmap
import android.graphics.PointF
import android.media.FaceDetector
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import java.util.concurrent.Executors

/**
 * iOS `LiveFaceDetector`: latest-frame-wins on a 40 ms cadence.
 * `android.media.FaceDetector` needs RGB_565 with even width.
 */
class LiveFaceDetector {
    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())
    private val exec = Executors.newSingleThreadExecutor { Thread(it, "opc.face-af") }
    private var busy = false
    private var lastRun = 0L
    private var pending: Bitmap? = null
    private var pendingDone: ((List<TrackingBox>) -> Unit)? = null

    fun consider(src: Bitmap, done: (List<TrackingBox>) -> Unit) {
        synchronized(lock) {
            pending?.recycle()
            pending = src
            pendingDone = done
            if (!busy) {
                busy = true
                exec.execute { pump() }
            }
        }
    }

    fun shutdown() {
        synchronized(lock) {
            pending?.recycle()
            pending = null
            pendingDone = null
        }
        exec.shutdownNow()
    }

    private fun pump() {
        while (true) {
            val wait: Long
            synchronized(lock) {
                wait = INTERVAL_MS - (SystemClock.elapsedRealtime() - lastRun)
            }
            if (wait > 0) {
                try {
                    Thread.sleep(wait)
                } catch (_: InterruptedException) {
                    synchronized(lock) { busy = false }
                    return
                }
            }
            val (bmp, done) =
                synchronized(lock) {
                    val next = pending
                    val cb = pendingDone
                    pending = null
                    pendingDone = null
                    if (next == null || cb == null) {
                        busy = false
                        return
                    }
                    lastRun = SystemClock.elapsedRealtime()
                    next to cb
                }
            val hits =
                try {
                    detect(bmp)
                } finally {
                    bmp.recycle()
                }
            main.post { done(hits) }
        }
    }

    fun detect(src: Bitmap): List<TrackingBox> {
        if (src.width < 16 || src.height < 16) return emptyList()
        val w = DETECT_WIDTH and 1.inv()
        val h = ((DETECT_WIDTH.toDouble() * src.height / src.width).toInt() and 1.inv()).coerceAtLeast(16)
        val scaled =
            if (src.width == w && src.height == h) src else Bitmap.createScaledBitmap(src, w, h, true)
        val rgb =
            if (scaled.config == Bitmap.Config.RGB_565) scaled
            else scaled.copy(Bitmap.Config.RGB_565, false)
        val faces = arrayOfNulls<FaceDetector.Face>(SceneFacePolicy.MAX_FACES)
        val n = FaceDetector(rgb.width, rgb.height, faces.size).findFaces(rgb, faces)
        val hits = ArrayList<TrackingBox>(n)
        val mid = PointF()
        val bwDen = rgb.width.toDouble()
        val bhDen = rgb.height.toDouble()
        for (i in 0 until n) {
            val face = faces[i] ?: continue
            if (face.confidence() < MIN_CONFIDENCE) continue
            face.getMidPoint(mid)
            val eyes = face.eyesDistance().toDouble()
            val bw = (eyes * 2.4) / bwDen
            val bh = (eyes * 3.0) / bhDen
            hits.add(
                TrackingBox.fromCenter(
                    mid.x / bwDen,
                    mid.y / bhDen,
                    bw,
                    bh,
                ),
            )
        }
        if (rgb !== scaled) rgb.recycle()
        if (scaled !== src) scaled.recycle()
        return hits
    }

    companion object {
        const val INTERVAL_MS = 40L
        const val DETECT_WIDTH = 320
        const val MIN_CONFIDENCE = 0.40f
    }
}
