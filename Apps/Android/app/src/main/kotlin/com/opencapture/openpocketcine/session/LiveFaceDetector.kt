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
 * "cannot access an invalid/free'd bitmap here!" (#348). Blocking with a
 * `Tasks.await` timeout cannot make that safe — a timeout does not cancel the
 * task — so we never time out and instead recycle from the completion
 * listener.
 */
class LiveFaceDetector {
    private val lock = Any()
    private val main = Handler(Looper.getMainLooper())
    private val exec = Executors.newSingleThreadExecutor { Thread(it, "opc.face-af") }
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
        val abandoned: Bitmap?
        synchronized(lock) {
            closed = true
            abandoned = pending
            pending = null
            pendingDone = null
        }
        abandoned?.recycle()
        // With no task in flight nothing else owns pixels, so tear down now.
        // Otherwise the in-flight completion listener finishes the shutdown,
        // because ML Kit may still be reading that frame.
        synchronized(lock) {
            if (!busy) finishShutdown()
        }
    }

    private fun pump() {
        val bmp: Bitmap
        val done: (List<TrackingBox>) -> Unit
        synchronized(lock) {
            val next = pending
            val cb = pendingDone
            pending = null
            pendingDone = null
            if (closed || next == null || cb == null) {
                busy = false
                if (closed) finishShutdown()
                return
            }
            lastRun = SystemClock.elapsedRealtime()
            bmp = next
            done = cb
        }
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
        task.addOnCompleteListener(exec) { completed ->
            // ML Kit is done with the pixels on success, failure, or cancel.
            bmp.recycle()
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
        synchronized(lock) {
            if (closed) {
                busy = false
                finishShutdown()
                return
            }
            exec.execute {
                if (delay > 0) runCatching { Thread.sleep(delay) }
                pump()
            }
        }
    }

    private fun finishShutdown() {
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
        const val TAP_WIDTH = 640
        const val TAP_HEIGHT = 360
        const val MIN_FACE_SIZE = 0.10f
    }
}