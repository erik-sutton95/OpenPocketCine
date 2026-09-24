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
 * iOS `LiveFaceDetector`: latest-frame-wins on a 40 ms cadence, 100 ms after
 * about a second without a face (see [pace]).
 *
 * ML Kit Face Detection is the Android stand-in for Vision. The platform
 * `android.media.FaceDetector` is frontal-eyes-only and missed 3/4 views.
 * Boxes are camera/identity space. Compose mirrors them at draw time.
 *
 * Vulkan hands NV21 bytes (no conversion in ML Kit). GLES / PixelCopy hand bitmaps.
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
    /** One detector input; [release] runs once ML Kit is done reading it. */
    class Frame(val image: InputImage, val width: Int, val height: Int, val release: () -> Unit = {}) {
        companion object {
            fun of(bitmap: Bitmap) = Frame(InputImage.fromBitmap(bitmap, 0), bitmap.width, bitmap.height, bitmap::recycle)

            fun nv21(bytes: ByteArray, width: Int, height: Int) =
                Frame(InputImage.fromByteArray(bytes, width, height, 0, InputImage.IMAGE_FORMAT_NV21), width, height)
        }
    }

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
    private var emptyRuns = 0
    private var pending: Frame? = null
    private var pendingDone: ((List<TrackingBox>) -> Unit)? = null

    /** Whether a frame offered now would be detected; skip the readback otherwise. */
    fun wantsFrame(): Boolean =
        synchronized(lock) {
            !closed && wantsFrame(emptyRuns, SystemClock.elapsedRealtime() - lastRun)
        }

    fun consider(src: Frame, done: (List<TrackingBox>) -> Unit) {
        synchronized(lock) {
            if (closed) {
                src.release()
                return
            }
            pending?.release()
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
        val abandoned: Frame?
        val stopNow: Boolean
        synchronized(lock) {
            closed = true
            flight.invalidate()
            abandoned = pending
            pending = null
            pendingDone = null
            stopNow = !busy
        }
        abandoned?.release()
        // With no task in flight nothing else owns pixels, so tear down now.
        // Otherwise the in-flight completion listener finishes the shutdown,
        // because ML Kit may still be reading that frame.
        if (stopNow) finishShutdown()
    }

    private fun pump() {
        data class Job(val frame: Frame, val done: (List<TrackingBox>) -> Unit)
        val job: Job?
        val abortClosed: Boolean
        synchronized(lock) {
            val next = pending
            val cb = pendingDone
            pending = null
            pendingDone = null
            if (closed) {
                busy = false
                next?.release()
                abortClosed = true
                job = null
            } else if (next == null || cb == null) {
                busy = false
                next?.release()
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
        val (frame, done) = job ?: return
        val width = frame.width
        val height = frame.height
        if (width < 16 || height < 16) {
            frame.release()
            main.post { done(emptyList()) }
            scheduleNext()
            return
        }
        val task =
            runCatching { detector.process(frame.image) }.getOrNull()
        if (task == null) {
            frame.release()
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
                // Unstick Face AF only. ML Kit may still be reading [frame].
                main.post { done(emptyList()) }
                scheduleNext()
            }
        if (flightId >= 0) main.postDelayed(timeout, DETECT_TIMEOUT_MS)
        task.addOnCompleteListener(exec) { completed ->
            main.removeCallbacks(timeout)
            frame.release()
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
            synchronized(lock) { emptyRuns = if (hits.isEmpty()) emptyRuns + 1 else 0 }
            main.post { done(hits) }
            scheduleNext()
        }
    }

    private fun scheduleNext() {
        val delay = synchronized(lock) { pace(emptyRuns) } - (SystemClock.elapsedRealtime() - lastRun)
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

        /** No face for about a second: look at 10 Hz until one appears (iOS parity). */
        const val IDLE_INTERVAL_MS = 100L
        const val IDLE_AFTER_EMPTY_RUNS = 25
        const val DETECT_TIMEOUT_MS = 2_000L
        /**
         * Detector input. ML Kit found the same faces at 320x180 as at 640x360 down to
         * 8% of frame width (below MIN_FACE_SIZE) in 30-54% less time per run on an S25.
         */
        const val TAP_WIDTH = 320
        const val TAP_HEIGHT = 180
        const val MIN_FACE_SIZE = 0.10f

        fun pace(emptyRuns: Int): Long = if (emptyRuns >= IDLE_AFTER_EMPTY_RUNS) IDLE_INTERVAL_MS else INTERVAL_MS

        /**
         * Tracking takes every frame (latest wins while busy). Idle takes one within
         * a feed tick of its next run, so the pump skips readbacks that would be dropped.
         */
        fun wantsFrame(emptyRuns: Int, sinceLastRunMs: Long): Boolean =
            sinceLastRunMs >= pace(emptyRuns) - INTERVAL_MS
    }
}
