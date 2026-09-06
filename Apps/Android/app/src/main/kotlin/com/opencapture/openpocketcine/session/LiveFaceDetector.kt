package com.opencapture.openpocketcine.session

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.android.gms.tasks.Tasks
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit

/**
 * iOS `LiveFaceDetector`: latest-frame-wins on a 40 ms cadence.
 *
 * ML Kit Face Detection is the Android stand-in for Vision. The platform
 * `android.media.FaceDetector` is frontal-eyes-only and missed 3/4 views.
 * Boxes are camera/identity space. Compose mirrors them at draw time.
 */
class LiveFaceDetector {
    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())
    private val exec = Executors.newSingleThreadExecutor { Thread(it, "opc.face-af") }
    private val detector by lazy {
        FaceDetection.getClient(
            FaceDetectorOptions.Builder()
                .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                .setMinFaceSize(MIN_FACE_SIZE)
                .build(),
        )
    }
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
        runCatching { detector.close() }
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
        val image = InputImage.fromBitmap(src, 0)
        val faces =
            try {
                Tasks.await(detector.process(image), DETECT_TIMEOUT_MS, TimeUnit.MILLISECONDS)
            } catch (_: Exception) {
                return emptyList()
            }
        val hits = ArrayList<TrackingBox>(faces.size)
        for (face in faces) {
            val rect = face.boundingBox
            if (rect.width() < 8 || rect.height() < 8) continue
            if (
                !FaceStructurePolicy.hasFaceLandmarks(
                    leftEyeX = landmarkX(face, FaceLandmark.LEFT_EYE, rect),
                    rightEyeX = landmarkX(face, FaceLandmark.RIGHT_EYE, rect),
                    hasNose = face.getLandmark(FaceLandmark.NOSE_BASE) != null,
                )
            ) {
                continue
            }
            val box =
                TrackingBox.fromImageRect(
                    rect.left,
                    rect.top,
                    rect.right,
                    rect.bottom,
                    src.width,
                    src.height,
                ) ?: continue
            if (box.isTooSmall) continue
            hits.add(box)
        }
        return hits
    }

    private fun landmarkX(face: Face, type: Int, rect: Rect): Double? {
        val bw = rect.width().toDouble()
        if (bw < 1.0) return null
        val pos = face.getLandmark(type)?.position ?: return null
        return (pos.x - rect.left) / bw
    }

    companion object {
        const val INTERVAL_MS = 40L
        const val TAP_WIDTH = 640
        const val TAP_HEIGHT = 360
        const val MIN_FACE_SIZE = 0.10f
        private const val DETECT_TIMEOUT_MS = 50L
    }
}
