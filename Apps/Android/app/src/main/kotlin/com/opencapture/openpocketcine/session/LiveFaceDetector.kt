package com.opencapture.openpocketcine.session

import android.graphics.Bitmap
import android.graphics.Rect
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import java.util.concurrent.Executors

/**
 * iOS `LiveFaceDetector`: latest-frame-wins on a 40 ms cadence.
 *
 * ML Kit Face Detection is the Android stand-in for Vision. The platform
 * `android.media.FaceDetector` is frontal-eyes-only and missed 3/4 views.
 * Boxes are camera/identity space. Compose mirrors them at draw time.
 *
 * Bitmap ownership: a frame handed to ML Kit is recycled **only once its
 * `Task` completes**. ML Kit reads the pixels off-thread on `MlKitThreadPool`
 * inside `ImageConvertUtils.convertToNv21Buffer`, so freeing a bitmap before
 * the task finishes aborts the process with
 * "cannot access an invalid/free'd bitmap here!" (#348). A hung Task may
 * unstick Face AF via a watchdog that posts empty boxes and schedules the
 * next frame; the watchdog never recycles — only the completion listener
 * does.
 */
class LiveFaceDetector {
    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())
    private val exec = Executors.newSingleThreadExecutor { Thread(it, "opc.face-af") }
    private val flight = FaceDetectFlight()
    private var finished = false
    private val detectorLazy =
        lazy {
            FaceDetection.getClient(
                FaceDetectorOptions.Builder()
                    .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                    .setMinFaceSize(MIN_FACE_SIZE)
                    .build(),
            )
        }
    private val detector by detectorLazy
    private var busy = false
    private var closed = false
    private var lastRun = 0L
    private var pending: Bitmap? = null
    private var pendingDone: ((List<TrackingBox>) -> Unit)? = null

    fun consider(src: Bitmap, done: (List<TrackingBox>) -> Unit) {
        synchronized(lock) {
            if (closed) {
                src.recycle()
                return
            }
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
        main.removeCallbacksAndMessages(null)
        val abandoned: Bitmap?
        val stopNow: Boolean
        synchronized(lock) {
            closed = true
            flight.invalidate()
            abandoned = pending
            pending = null
            pendingDone = null
            stopNow = !busy
        }
        abandoned?.recycle()
        // With no task in flight nothing else owns pixels, so tear down now.
        // Otherwise the in-flight completion listener finishes the shutdown,
        // because ML Kit may still be reading that frame.
        if (stopNow) finishShutdown()
    }

    private fun pump() {
        data class Job(val bmp: Bitmap, val done: (List<TrackingBox>) -> Unit)
        val job: Job?
        val abortClosed: Boolean
        synchronized(lock) {
            val next = pending
            val cb = pendingDone
            pending = null
            pendingDone = null
            if (closed) {
                busy = false
                next?.recycle()
                abortClosed = true
                job = null
            } else if (next == null || cb == null) {
                busy = false
                next?.recycle()
                abortClosed = false
                job = null
            } else {
                lastRun = SystemClock.elapsedRealtime()
                abortClosed = false
                job = Job(next, cb)
            }
        }
        if (abortClosed) {
            finishShutdown()
            return
        }
        val (bmp, done) = job ?: return
        val width = bmp.width
        val height = bmp.height
        if (width < 16 || height < 16) {
            bmp.recycle()
            main.post { done(emptyList()) }
            scheduleNext()
            return
        }
        val task =
            runCatching { detector.process(InputImage.fromBitmap(bmp, 0)) }.getOrNull()
        if (task == null) {
            bmp.recycle()
            main.post { done(emptyList()) }
            scheduleNext()
            return
        }
        val flightId =
            synchronized(lock) {
                if (closed) -1 else flight.begin()
            }
        val timeout =
            Runnable {
                val timedOut = synchronized(lock) { !closed && flightId >= 0 && flight.take(flightId) }
                if (!timedOut) return@Runnable
                // Unstick Face AF only. ML Kit may still be reading [bmp].
                main.post { done(emptyList()) }
                scheduleNext()
            }
        if (flightId >= 0) main.postDelayed(timeout, DETECT_TIMEOUT_MS)
        task.addOnCompleteListener(exec) { completed ->
            main.removeCallbacks(timeout)
            bmp.recycle()
            val deliver: Boolean
            val stop: Boolean
            synchronized(lock) {
                if (closed) {
                    busy = false
                    deliver = false
                    stop = true
                } else if (flightId < 0 || !flight.take(flightId)) {
                    deliver = false
                    stop = false
                } else {
                    deliver = true
                    stop = false
                }
            }
            if (stop) {
                finishShutdown()
                return@addOnCompleteListener
            }
            if (!deliver) return@addOnCompleteListener
            val hits =
                if (completed.isSuccessful) {
                    project(completed.result, width, height)
                } else {
                    emptyList()
                }
            main.post { done(hits) }
            scheduleNext()
        }
    }

    private fun scheduleNext() {
        val delay = INTERVAL_MS - (SystemClock.elapsedRealtime() - lastRun)
        val stop: Boolean
        synchronized(lock) {
            if (closed) {
                busy = false
                stop = true
            } else {
                stop = false
                exec.execute {
                    if (delay > 0) runCatching { Thread.sleep(delay) }
                    pump()
                }
            }
        }
        if (stop) finishShutdown()
    }

    private fun finishShutdown() {
        synchronized(lock) {
            if (finished) return
            finished = true
        }
        if (detectorLazy.isInitialized()) {
            runCatching { detector.close() }
        }
        exec.shutdown()
    }

    private fun project(faces: List<Face>, width: Int, height: Int): List<TrackingBox> {
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
                    width,
                    height,
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
        const val DETECT_TIMEOUT_MS = 2_000L
        const val TAP_WIDTH = 640
        const val TAP_HEIGHT = 360
        const val MIN_FACE_SIZE = 0.10f
    }
}
