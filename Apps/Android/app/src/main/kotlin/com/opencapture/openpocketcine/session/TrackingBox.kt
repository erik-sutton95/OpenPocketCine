package com.opencapture.openpocketcine.session

import kotlin.math.abs
import kotlin.math.exp
import kotlin.math.hypot
import kotlin.math.max
import kotlin.math.min

/** Normalized 0…1 box, top-left origin. Wire (`0xA6` / `0x89`) is centre + size. */
data class TrackingBox(
    val x: Double,
    val y: Double,
    val width: Double,
    val height: Double,
) {
    val minX: Double get() = x
    val minY: Double get() = y
    val maxX: Double get() = x + width
    val maxY: Double get() = y + height
    val centerX: Double get() = x + width / 2
    val centerY: Double get() = y + height / 2
    val area: Double get() = width * height
    val isTooSmall: Boolean get() = width < MIMO_MINIMUM_SIDE || height < MIMO_MINIMUM_SIDE

    fun contains(px: Double, py: Double, padding: Double = 0.0): Boolean =
        px >= minX - padding && px <= maxX + padding &&
            py >= minY - padding && py <= maxY + padding

    fun intersectionArea(other: TrackingBox): Double {
        val x0 = max(minX, other.minX)
        val y0 = max(minY, other.minY)
        val x1 = min(maxX, other.maxX)
        val y1 = min(maxY, other.maxY)
        return max(0.0, x1 - x0) * max(0.0, y1 - y0)
    }

    fun intersectionOverUnion(other: TrackingBox): Double {
        val inter = intersectionArea(other)
        val union = area + other.area - inter
        return if (union > 0) inter / union else 0.0
    }

    fun mirrored(): TrackingBox = copy(x = 1.0 - x - width)

    companion object {
        const val MINIMUM_NORMALIZED_SIZE = 0.05
        const val MIMO_MINIMUM_SIDE = 0.09

        fun normalized(fromX: Double, fromY: Double, toX: Double, toY: Double): TrackingBox {
            val x0 = min(max(min(fromX, toX), 0.0), 1.0)
            val y0 = min(max(min(fromY, toY), 0.0), 1.0)
            val x1 = min(max(max(fromX, toX), 0.0), 1.0)
            val y1 = min(max(max(fromY, toY), 0.0), 1.0)
            return TrackingBox(x0, y0, x1 - x0, y1 - y0)
        }

        fun fromCenter(cx: Double, cy: Double, width: Double, height: Double): TrackingBox {
            val w = min(max(width, 0.02), 1.0)
            val h = min(max(height, 0.02), 1.0)
            return TrackingBox(cx - w / 2, cy - h / 2, w, h)
        }

        fun subject(from: TrackingBox): TrackingBox {
            val width = min(max(from.width * 0.45, MINIMUM_NORMALIZED_SIZE), from.width)
            val height = min(max(from.height * 0.45, MINIMUM_NORMALIZED_SIZE), from.height)
            return TrackingBox(
                from.x + (from.width - width) / 2,
                from.y + (from.height - height) / 2,
                width,
                height,
            )
        }

        fun parseNormalized(
            bytes: ByteArray,
            offset: Int = 0,
            minimum: Double = MINIMUM_NORMALIZED_SIZE,
            requireOriginFits: Boolean = true,
        ): TrackingBox? {
            if (bytes.size < offset + 16) return null
            val x = f32(bytes, offset) ?: return null
            val y = f32(bytes, offset + 4) ?: return null
            val width = f32(bytes, offset + 8) ?: return null
            val height = f32(bytes, offset + 12) ?: return null
            if (width < minimum || height < minimum) return null
            if (requireOriginFits && (x + width > 1.02 || y + height > 1.02)) return null
            return TrackingBox(x, y, width, height)
        }

        /** `0x02/0x89` notify. 23 B: 5×`00` + tag + 4×f32 LE @7, centre + size. */
        fun parseLivePush(payload: ByteArray): TrackingBox? {
            if (payload.size < 23) return null
            if (payload[0] != 0.toByte() || payload[1] != 0.toByte() || payload[2] != 0.toByte() ||
                payload[3] != 0.toByte() || payload[4] != 0.toByte()
            ) {
                return null
            }
            val raw = parseNormalized(payload, offset = 7, minimum = 0.02, requireOriginFits = false)
                ?: return null
            return fromCenter(raw.x, raw.y, raw.width, raw.height)
        }

        private fun f32(bytes: ByteArray, offset: Int): Double? {
            if (bytes.size < offset + 4) return null
            val bits =
                (bytes[offset].toInt() and 0xFF) or
                    ((bytes[offset + 1].toInt() and 0xFF) shl 8) or
                    ((bytes[offset + 2].toInt() and 0xFF) shl 16) or
                    ((bytes[offset + 3].toInt() and 0xFF) shl 24)
            val value = Float.fromBits(bits).toDouble()
            if (!value.isFinite() || value < 0.0 || value > 1.0) return null
            return value
        }
    }
}

sealed class TrackingPoll {
    data class Locked(val box: TrackingBox?) : TrackingPoll()
    data object Idle : TrackingPoll()

    companion object {
        fun parse(payload: ByteArray): TrackingPoll? {
            if (payload.size < 4) return null
            if (payload[0] != 0.toByte() || payload[2] != 0.toByte() || payload[3] != 0.toByte()) {
                return null
            }
            return when (payload[1].toInt() and 0xFF) {
                0x01 -> {
                    val extra = if (payload.size >= 20) payload.copyOfRange(4, payload.size) else byteArrayOf()
                    val raw = TrackingBox.parseNormalized(extra, requireOriginFits = false)
                    Locked(
                        raw?.let { TrackingBox.fromCenter(it.x, it.y, it.width, it.height) },
                    )
                }
                0x00 -> Idle
                else -> null
            }
        }
    }
}

object TrackingBoxSmoothing {
    const val POSITION_TIME_CONSTANT = 0.10
    const val SIZE_TIME_CONSTANT = 0.42
    const val FACE_POSITION_TIME_CONSTANT = 0.16
    const val FACE_SIZE_TIME_CONSTANT = 0.70

    fun blend(
        from: TrackingBox?,
        toward: TrackingBox,
        dt: Double,
        position: Double = POSITION_TIME_CONSTANT,
        size: Double = SIZE_TIME_CONSTANT,
    ): TrackingBox {
        if (from == null || dt <= 0.0 || !dt.isFinite()) return toward
        val p = 1 - exp(-dt / max(position, 0.001))
        val s = 1 - exp(-dt / max(size, 0.001))
        val cx = from.centerX + (toward.centerX - from.centerX) * p
        val cy = from.centerY + (toward.centerY - from.centerY) * p
        val w = from.width + (toward.width - from.width) * s
        val h = from.height + (toward.height - from.height) * s
        return TrackingBox.fromCenter(cx, cy, w, h)
    }
}

object TrackingClearPolicy {
    const val LEFTOVER_IGNORE_SEC = 0.28
    const val PUSH_SILENCE_SEC = 0.35

    fun shouldApplyLivePush(operatorClearedAtElapsed: Long?, nowElapsed: Long): Boolean {
        if (operatorClearedAtElapsed == null) return true
        return (nowElapsed - operatorClearedAtElapsed) / 1000.0 >= LEFTOVER_IGNORE_SEC
    }

    fun shouldDropForSilence(lastPushElapsed: Long?, nowElapsed: Long): Boolean {
        if (lastPushElapsed == null) return false
        return (nowElapsed - lastPushElapsed) / 1000.0 >= PUSH_SILENCE_SEC
    }
}

sealed class FocusOverlay {
    data object Focus : FocusOverlay()
    data class Search(val box: TrackingBox) : FocusOverlay()
    data class Subject(val box: TrackingBox) : FocusOverlay()
    data class Face(val box: TrackingBox) : FocusOverlay()
}

object FocusOverlayPolicy {
    fun resolve(tracking: Boolean, search: TrackingBox?, subject: TrackingBox?): FocusOverlay {
        if (tracking) {
            if (subject != null) return FocusOverlay.Subject(subject)
            if (search != null) return FocusOverlay.Subject(TrackingBox.subject(search))
            return FocusOverlay.Focus
        }
        if (search != null) return FocusOverlay.Search(search)
        return FocusOverlay.Focus
    }
}

/**
 * iOS `FaceTrackHold` — keep the last AF-C face through a brief miss, then drop.
 * A leftover box on empty glass is not a lock.
 */
object FaceTrackHold {
    const val MISS_TIMEOUT_SEC = 0.22
    const val MOTION_MISS_TIMEOUT_SEC = 0.18
    const val MOTION_COAST_SEC = 0.30
    const val MOTION_MATCH_DISTANCE = 0.55
    const val MOTION_POSITION_TIME_CONSTANT = 0.04
    const val MOTION_SNAP_DISTANCE = 0.20
    const val REACQUIRE_CENTER_MAX = 0.14
    const val REACQUIRE_CENTER_SCALE = 0.50
    const val MIN_AREA_RATIO = 0.55
    const val MAX_AREA_RATIO = 2.6
    const val MIN_OVERLAP = 0.28
    const val UPDATE_CONFIDENCE = 0.68

    fun secondsSinceHit(lastHitElapsed: Long?, nowElapsed: Long): Double {
        if (lastHitElapsed == null) return Double.POSITIVE_INFINITY
        return (nowElapsed - lastHitElapsed) / 1000.0
    }

    fun isSceneMoving(secondsSinceGimbal: Double?): Boolean {
        val s = secondsSinceGimbal ?: return false
        return s >= 0.0 && s < MOTION_COAST_SEC
    }

    fun missTimeout(sceneMoving: Boolean): Double =
        if (sceneMoving) MOTION_MISS_TIMEOUT_SEC else MISS_TIMEOUT_SEC

    fun shouldDrop(secondsSinceHit: Double, sceneMoving: Boolean = false): Boolean =
        secondsSinceHit >= missTimeout(sceneMoving)

    fun shouldAccept(
        detected: TrackingBox,
        last: TrackingBox?,
        secondsSinceHit: Double,
        confidence: Double = 1.0,
        sceneMoving: Boolean = false,
    ): Boolean {
        if (sceneMoving) return confidence >= UPDATE_CONFIDENCE
        if (last == null || secondsSinceHit >= MISS_TIMEOUT_SEC) return true
        if (confidence < UPDATE_CONFIDENCE) return false
        val lastArea = last.area
        if (lastArea <= 0.0) return true
        val areaRatio = detected.area / lastArea
        if (areaRatio < MIN_AREA_RATIO || areaRatio > MAX_AREA_RATIO) return false
        val span = max(last.width, last.height)
        val maxCenter = min(REACQUIRE_CENTER_MAX, max(span * REACQUIRE_CENTER_SCALE, 0.06))
        val dx = detected.centerX - last.centerX
        val dy = detected.centerY - last.centerY
        if (hypot(dx, dy) > maxCenter) return false
        return detected.intersectionOverUnion(last) >= MIN_OVERLAP
    }

    fun follow(
        from: TrackingBox?,
        toward: TrackingBox,
        dt: Double,
        sceneMoving: Boolean,
    ): TrackingBox {
        if (from == null) return toward
        val jump = hypot(from.centerX - toward.centerX, from.centerY - toward.centerY)
        if (sceneMoving && jump >= MOTION_SNAP_DISTANCE) return toward
        return TrackingBoxSmoothing.blend(
            from,
            toward,
            dt,
            position =
                if (sceneMoving) MOTION_POSITION_TIME_CONSTANT
                else TrackingBoxSmoothing.FACE_POSITION_TIME_CONSTANT,
            size = TrackingBoxSmoothing.FACE_SIZE_TIME_CONSTANT,
        )
    }
}

object FaceAFPolicy {
    const val TAP_HOLD_SEC = 2.5

    fun shouldHoldTapBox(secondsSinceTap: Double?): Boolean {
        val s = secondsSinceTap ?: return false
        return s >= 0.0 && s < TAP_HOLD_SEC
    }

    /** iOS `CameraSession.wantsFaceAF` — AF-C after the first live picture. */
    fun wantsFaceAF(focusMode: Int, armed: Boolean): Boolean =
        armed && focusMode == CameraCommands.FOCUS_CONTINUOUS

    /** iOS `CameraSession.wantsFaceDetect`. */
    fun wantsFaceDetect(
        focusMode: Int,
        armed: Boolean,
        facePriority: Boolean,
        expoAuto: Boolean,
    ): Boolean = wantsFaceAF(focusMode, armed) || (facePriority && expoAuto)

    fun resolve(
        focusMode: Int,
        tracking: Boolean,
        search: TrackingBox?,
        subject: TrackingBox?,
        face: TrackingBox?,
    ): FocusOverlay {
        val base = FocusOverlayPolicy.resolve(tracking, search, subject)
        return when (base) {
            is FocusOverlay.Search, is FocusOverlay.Subject -> base
            is FocusOverlay.Focus, is FocusOverlay.Face ->
                if (focusMode == CameraCommands.FOCUS_CONTINUOUS && face != null) {
                    FocusOverlay.Face(face)
                } else {
                    FocusOverlay.Focus
                }
        }
    }
}

object SceneFacePolicy {
    const val DIM_OPACITY = 0.20
    const val MAX_FACES = 8
    const val OCCLUDER_OVERLAP = 0.28

    fun dimmed(
        faces: List<TrackingBox>,
        hiding: TrackingBox? = null,
        occluder: TrackingBox? = null,
    ): List<TrackingBox> =
        faces.filter { face ->
            if (hiding != null && conceals(hiding, face)) return@filter false
            if (occluder != null && conceals(occluder, face)) return@filter false
            true
        }

    fun conceals(owner: TrackingBox, other: TrackingBox): Boolean =
        other.intersectionOverUnion(owner) >= OCCLUDER_OVERLAP
}

object LiveFeedTapPolicy {
    enum class Action { TRACK_FACE, TAP_FOCUS, IGNORE }

    fun action(supportsTapFocus: Boolean, tappedFace: Boolean): Action =
        when {
            tappedFace -> Action.TRACK_FACE
            supportsTapFocus -> Action.TAP_FOCUS
            else -> Action.IGNORE
        }
}

object FaceTrackTap {
    const val HIT_PADDING = 0.03

    fun contains(x: Double, y: Double, box: TrackingBox): Boolean =
        box.contains(x, y, HIT_PADDING)

    fun trackingBox(from: TrackingBox): TrackingBox {
        val w = max(from.width, TrackingBox.MIMO_MINIMUM_SIDE)
        val h = max(from.height, TrackingBox.MIMO_MINIMUM_SIDE)
        if (w == from.width && h == from.height) return from
        return TrackingBox.fromCenter(from.centerX, from.centerY, w, h)
    }

    fun boxIfTapped(
        overlay: FocusOverlay,
        x: Double,
        y: Double,
        sceneFaces: List<TrackingBox> = emptyList(),
    ): TrackingBox? {
        if (overlay is FocusOverlay.Face && contains(x, y, overlay.box)) {
            return trackingBox(overlay.box)
        }
        val hits = sceneFaces.filter { contains(x, y, it) }
        val face = hits.minByOrNull { it.area } ?: return null
        return trackingBox(face)
    }
}

object FocusResetPolicy {
    const val OFF_CENTER_THRESHOLD = 0.04

    fun isAvailable(x: Double?, y: Double?, tracking: Boolean): Boolean {
        if (tracking) return true
        if (x == null || y == null) return false
        return abs(x - 0.5) > OFF_CENTER_THRESHOLD || abs(y - 0.5) > OFF_CENTER_THRESHOLD
    }
}

object CameraFocusPolicy {
    const val CHANGE_THRESHOLD = 0.012

    fun shouldAdopt(currentX: Double, currentY: Double, cameraX: Double, cameraY: Double): Boolean =
        abs(currentX - cameraX) >= CHANGE_THRESHOLD || abs(currentY - cameraY) >= CHANGE_THRESHOLD
}

object LiveTrackingChrome {
    const val CANCEL_SIZE = 28f
    const val CANCEL_HIT_SIZE = 44f

    data class CancelRect(val x: Float, val y: Float, val width: Float, val height: Float) {
        val midX: Float get() = x + width / 2f
        val midY: Float get() = y + height / 2f
    }

    /**
     * iOS `LiveTrackingChrome.cancelRect`: 44 pt hit whose centre sits on the
     * tracking box's top-right corner (`midX = box.maxX`, `midY = box.minY`).
     * [feedWidth]/[feedHeight] are the same units the caller will offset in.
     */
    fun cancelRect(
        box: TrackingBox,
        feedWidth: Float,
        feedHeight: Float,
        mirrored: Boolean,
    ): CancelRect {
        val drawn = if (mirrored) box.mirrored() else box
        val rectRight = ((drawn.x + drawn.width) * feedWidth).toFloat()
        val rectTop = (drawn.y * feedHeight).toFloat()
        val s = CANCEL_HIT_SIZE
        return CancelRect(x = rectRight - s / 2f, y = rectTop - s / 2f, width = s, height = s)
    }

    fun bracketArm(along: Float): Float {
        val proposed = along * 0.26f
        val minGap = max(8f, along * 0.28f)
        return min(max(10f, proposed), max(10f, (along - minGap) / 2f))
    }
}

object LiveFeedFocusGesture {
    enum class Kind { TAP, TRACK, DISP_CLEAN, DISP_LIVE }

    const val TRACK_MINIMUM = 24f
    const val TRACK_HOLD_SEC = 0.20
    const val TRACK_HOLD_SLOP = 10f

    fun classify(
        dx: Float,
        dy: Float,
        pinched: Boolean = false,
        armed: Boolean = false,
        swipeFloor: Float = 44f,
    ): Kind? {
        if (pinched) return null
        val distance = hypot(dx, dy)
        if (armed) return if (distance >= TRACK_MINIMUM) Kind.TRACK else Kind.TAP
        if (abs(dy) > abs(dx) + 8f && abs(dy) > swipeFloor) {
            return if (dy > 0f) Kind.DISP_CLEAN else Kind.DISP_LIVE
        }
        if (distance >= TRACK_MINIMUM) return null
        return Kind.TAP
    }
}

data class TrackingHud(
    val overlay: FocusOverlay = FocusOverlay.Focus,
    val sceneFaces: List<TrackingBox> = emptyList(),
    val dimmedFaces: List<TrackingBox> = emptyList(),
    val isTracking: Boolean = false,
    val draft: TrackingBox? = null,
)
