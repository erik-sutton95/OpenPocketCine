package com.opencapture.openpocketcine.session

import android.graphics.Bitmap
import com.google.mlkit.vision.common.InputImage
import com.google.mlkit.vision.face.Face
import com.google.mlkit.vision.face.FaceDetection
import com.google.mlkit.vision.face.FaceDetectorOptions
import com.google.mlkit.vision.face.FaceLandmark
import com.opencapture.opencine.cameracontrols.DetectedFace
import com.opencapture.opencine.cameracontrols.FaceDetectionBackend
import com.opencapture.opencine.cameracontrols.FaceDetectionFrame
import com.opencapture.opencine.cameracontrols.FaceDetectionPump
import com.opencapture.opencine.dji.FaceDetectorPort
import com.opencapture.opencine.dji.FaceFrame
import com.opencapture.opencine.vocabulary.TrackingBox
import java.util.concurrent.Executor

/**
 * iOS `LiveFaceDetector`: camera-controls' [FaceDetectionPump] (cadence, latest frame wins, watchdog) on
 * ML Kit Face Detection, the Android stand-in for Vision. The platform `android.media.FaceDetector` is
 * frontal-eyes-only and missed 3/4 views.
 *
 * Vulkan hands NV21 bytes (no conversion in ML Kit). GLES / PixelCopy hand bitmaps. ML Kit reads the pixels
 * off-thread on `MlKitThreadPool` inside `ImageConvertUtils.convertToNv21Buffer`, so a bitmap is recycled
 * only once its `Task` completes ("cannot access an invalid/free'd bitmap here!", #348).
 */
class LiveFaceDetector : FaceDetectionPump<LiveFaceDetector.Frame>(MlKitFaceBackend()), FaceDetectorPort {
    /** One detector input; [release] runs once ML Kit is done reading it. */
    class Frame(val image: InputImage, override val width: Int, override val height: Int, private val onRelease: () -> Unit = {}) :
        FaceDetectionFrame, FaceFrame {
        override fun release() = onRelease()

        companion object {
            fun of(bitmap: Bitmap) = Frame(InputImage.fromBitmap(bitmap, 0), bitmap.width, bitmap.height, bitmap::recycle)

            fun nv21(bytes: ByteArray, width: Int, height: Int) =
                Frame(InputImage.fromByteArray(bytes, width, height, 0, InputImage.IMAGE_FORMAT_NV21), width, height)
        }
    }

    /** Frames come from this app's [Frame] factories only. */
    override fun consider(frame: FaceFrame, done: (List<TrackingBox>) -> Unit) = consider(frame as Frame, done)

    companion object {
        const val INTERVAL_MS = FaceDetectionPump.INTERVAL_MS

        /**
         * Detector input. ML Kit found the same faces at 320x180 as at 640x360 down to
         * 8% of frame width (below MIN_FACE_SIZE) in 30-54% less time per run on an S25.
         */
        const val TAP_WIDTH = 320
        const val TAP_HEIGHT = 180
        const val MIN_FACE_SIZE = 0.10f
    }
}

private class MlKitFaceBackend : FaceDetectionBackend<LiveFaceDetector.Frame> {
    private val detectorLazy =
        lazy {
            FaceDetection.getClient(
                FaceDetectorOptions.Builder()
                    .setPerformanceMode(FaceDetectorOptions.PERFORMANCE_MODE_FAST)
                    .setLandmarkMode(FaceDetectorOptions.LANDMARK_MODE_ALL)
                    .setMinFaceSize(LiveFaceDetector.MIN_FACE_SIZE)
                    .build(),
            )
        }
    private val detector by detectorLazy

    override fun detect(frame: LiveFaceDetector.Frame, executor: Executor, done: (List<DetectedFace>?) -> Unit): Boolean {
        val task = runCatching { detector.process(frame.image) }.getOrNull() ?: return false
        task.addOnCompleteListener(executor) { completed ->
            done(if (completed.isSuccessful) completed.result.map(::detectedFace) else null)
        }
        return true
    }

    override fun close() {
        if (detectorLazy.isInitialized()) runCatching { detector.close() }
    }
}

private fun detectedFace(face: Face): DetectedFace {
    val rect = face.boundingBox
    return DetectedFace(
        rect.left, rect.top, rect.right, rect.bottom,
        leftEyeX = face.getLandmark(FaceLandmark.LEFT_EYE)?.position?.x,
        rightEyeX = face.getLandmark(FaceLandmark.RIGHT_EYE)?.position?.x,
        hasNose = face.getLandmark(FaceLandmark.NOSE_BASE) != null,
    )
}
