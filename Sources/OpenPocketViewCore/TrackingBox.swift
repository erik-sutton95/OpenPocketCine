import Foundation

/// Normalized 0…1 tracking box. Stored as top-left origin + size for drawing.
/// The wire (`0x02/0xA6` SET and `0x02/0x89` push) is **centre + size** —
/// Mimo 2026-08-18: drawing origin-as-centre put the top-left on the face.
public struct TrackingBox: Equatable, Sendable {
    public var x: Double
    public var y: Double
    public var width: Double
    public var height: Double

    /// Expand floor for a degenerate drag. Not the Mimo accept threshold.
    public static let minimumNormalizedSize: Double = 0.05
    /// Shortest side Mimo still locked in the 2026-08-18 take was ~0.095.
    /// Below this the official app toasts "Frame Too Small" and does not SET.
    public static let mimoMinimumSide: Double = 0.09

    public var minX: Double { x }
    public var minY: Double { y }
    public var maxX: Double { x + width }
    public var maxY: Double { y + height }
    public var centerX: Double { x + width / 2 }
    public var centerY: Double { y + height / 2 }
    public var area: Double { width * height }
    public var isTooSmall: Bool {
        width < Self.mimoMinimumSide || height < Self.mimoMinimumSide
    }

    public func intersectionArea(_ other: TrackingBox) -> Double {
        let x0 = max(minX, other.minX)
        let y0 = max(minY, other.minY)
        let x1 = min(maxX, other.maxX)
        let y1 = min(maxY, other.maxY)
        return max(0, x1 - x0) * max(0, y1 - y0)
    }

    public func intersectionOverUnion(_ other: TrackingBox) -> Double {
        let inter = intersectionArea(other)
        let union = area + other.area - inter
        guard union > 0 else { return 0 }
        return inter / union
    }

    public func contains(x: Double, y: Double, padding: Double = 0) -> Bool {
        x >= minX - padding && x <= maxX + padding
            && y >= minY - padding && y <= maxY + padding
    }

    /// Axis-aligned union. Used to size the painted lock from face + pose extent.
    public func union(_ other: TrackingBox) -> TrackingBox {
        let x0 = min(minX, other.minX)
        let y0 = min(minY, other.minY)
        return TrackingBox(
            x: x0, y: y0,
            width: max(maxX, other.maxX) - x0,
            height: max(maxY, other.maxY) - y0)
    }

    /// Camera box to screen box (and back) through the MIRROR flips. Both on is a 180° turn.
    public func flipped(horizontal: Bool, vertical: Bool) -> TrackingBox {
        TrackingBox(
            x: horizontal ? 1 - x - width : x, y: vertical ? 1 - y - height : y,
            width: width, height: height)
    }

    public init(x: Double, y: Double, width: Double, height: Double) {
        self.x = x
        self.y = y
        self.width = width
        self.height = height
    }

    public static func normalized(
        fromX: Double, fromY: Double, toX: Double, toY: Double
    ) -> TrackingBox {
        var x0 = min(max(min(fromX, toX), 0), 1)
        var y0 = min(max(min(fromY, toY), 0), 1)
        var x1 = min(max(max(fromX, toX), 0), 1)
        var y1 = min(max(max(fromY, toY), 0), 1)
        if x1 < x0 { swap(&x0, &x1) }
        if y1 < y0 { swap(&y0, &y1) }
        return TrackingBox(x: x0, y: y0, width: x1 - x0, height: y1 - y0)
    }

    public static func fromCenter(
        x: Double, y: Double, width: Double, height: Double
    ) -> TrackingBox {
        let w = min(max(width, 0.02), 1)
        let h = min(max(height, 0.02), 1)
        return TrackingBox(x: x - w / 2, y: y - h / 2, width: w, height: h)
    }

    /// Tighter box at the search centre — stand-in until `0xA5` carries a live subject rect.
    public static func subject(from search: TrackingBox) -> TrackingBox {
        let width = min(max(search.width * 0.45, minimumNormalizedSize), search.width)
        let height = min(max(search.height * 0.45, minimumNormalizedSize), search.height)
        return TrackingBox(
            x: search.x + (search.width - width) / 2,
            y: search.y + (search.height - height) / 2,
            width: width,
            height: height
        )
    }

    public static func parseNormalized(
        _ bytes: [UInt8], minimum: Double = minimumNormalizedSize,
        requireOriginFits: Bool = true
    ) -> TrackingBox? {
        guard bytes.count >= 16 else { return nil }
        func f32(_ offset: Int) -> Double? {
            let slice = Array(bytes[offset..<(offset + 4)])
            let bits =
                UInt32(slice[0])
                | (UInt32(slice[1]) << 8)
                | (UInt32(slice[2]) << 16)
                | (UInt32(slice[3]) << 24)
            let value = Double(Float(bitPattern: bits))
            guard value.isFinite, value >= 0, value <= 1 else { return nil }
            return value
        }
        guard let x = f32(0), let y = f32(4), let width = f32(8), let height = f32(12),
            width >= minimum, height >= minimum
        else { return nil }
        if requireOriginFits, x + width > 1.02 || y + height > 1.02 { return nil }
        return TrackingBox(x: x, y: y, width: width, height: height)
    }

    /// `0x02/0x89` notify. 23 B: 5×`00` + 2-byte tag (`a0 41` typical) + 4×f32 LE @7.
    /// Mimo 2026-08-18 take: ~15 Hz while locked; stops after `0xA6` clear.
    public static func parseLivePush(_ payload: [UInt8]) -> TrackingBox? {
        guard payload.count >= 23,
            payload[0] == 0, payload[1] == 0, payload[2] == 0,
            payload[3] == 0, payload[4] == 0
        else { return nil }
        guard
            let raw = parseNormalized(
                Array(payload[7...]), minimum: 0.02, requireOriginFits: false)
        else { return nil }
        return fromCenter(x: raw.x, y: raw.y, width: raw.width, height: raw.height)
    }
}

/// `0x02/0xA5` GET reply. Locked `00 01 00 00`, idle `00 00 00 00`.
/// Extra 4×f32 after the header is an unproven live subject rect — use when it looks legal.
public enum TrackingPoll: Equatable, Sendable {
    case locked(box: TrackingBox?)
    case idle

    public static func parse(_ payload: [UInt8]) -> TrackingPoll? {
        guard payload.count >= 4,
            payload[0] == 0x00, payload[2] == 0x00, payload[3] == 0x00
        else { return nil }
        switch payload[1] {
        case 0x01:
            let extra = payload.count >= 20 ? Array(payload[4...]) : []
            guard let raw = TrackingBox.parseNormalized(extra, requireOriginFits: false) else {
                return .locked(box: nil)
            }
            return .locked(
                box: TrackingBox.fromCenter(
                    x: raw.x, y: raw.y, width: raw.width, height: raw.height))
        case 0x00: return .idle
        default: return nil
        }
    }
}

/// Ease the painted box toward each `0x89` (~15 Hz). Size is slower than
/// centre so subject motion stays tight while bounding-box flicker settles.
public enum TrackingBoxSmoothing {
    public static let positionTimeConstant: Double = 0.10
    public static let sizeTimeConstant: Double = 0.42

    /// Face AF is sampled slower than the feed. Tick the painted box toward
    /// the last hit on every frame so it does not sit-and-jump.
    public static let facePositionTimeConstant: Double = 0.16
    public static let faceSizeTimeConstant: Double = 0.70

    public static func blend(
        from: TrackingBox?, toward: TrackingBox, dt: Double,
        position: Double = positionTimeConstant,
        size: Double = sizeTimeConstant
    ) -> TrackingBox {
        guard let from, dt > 0, dt.isFinite else { return toward }
        let p = 1 - exp(-dt / max(position, 0.001))
        let s = 1 - exp(-dt / max(size, 0.001))
        let cx = from.centerX + (toward.centerX - from.centerX) * p
        let cy = from.centerY + (toward.centerY - from.centerY) * p
        let w = from.width + (toward.width - from.width) * s
        let h = from.height + (toward.height - from.height) * s
        return TrackingBox.fromCenter(x: cx, y: cy, width: w, height: h)
    }
}

/// Operator CLEAR is local-first for a beat — leftover `0x89` after our
/// `0xA6` all-zero would resurrect the overlay. Then the camera is truth
/// again so a body-screen lock or cancel can land.
public enum TrackingClearPolicy {
    public static let leftoverIgnore: TimeInterval = 0.28
    /// No `0x89` for this long means the camera dropped the lock.
    public static let pushSilence: TimeInterval = 0.35

    public static func shouldApplyLivePush(operatorCleared: Bool) -> Bool {
        !operatorCleared
    }

    public static func shouldApplyLivePush(operatorClearedAt: Date?, now: Date) -> Bool {
        guard let operatorClearedAt else { return true }
        return now.timeIntervalSince(operatorClearedAt) >= leftoverIgnore
    }

    public static func shouldDropForSilence(lastPush: Date?, now: Date) -> Bool {
        guard let lastPush else { return false }
        return now.timeIntervalSince(lastPush) >= pushSilence
    }
}

/// What the feed should draw: AF box, the drag search rect, or a locked subject box.
public enum FocusOverlay: Equatable, Sendable {
    case focus
    case search(TrackingBox)
    case subject(TrackingBox)
    /// Local AF-C face box. Not a camera `0x89` — Vision on the live preview.
    case face(TrackingBox)
}

public enum FocusOverlayPolicy {
    public static func resolve(
        tracking: Bool, search: TrackingBox?, subject: TrackingBox?
    ) -> FocusOverlay {
        if tracking {
            if let subject { return .subject(subject) }
            if let search { return .subject(TrackingBox.subject(from: search)) }
            return .focus
        }
        if let search { return .search(search) }
        return .focus
    }
}

/// Extra AF-C faces stay on the feed while a subject is locked. Their
/// brackets are dim; the locked subject box stays full strength.
public enum SceneFacePolicy {
    public static let dimOpacity: Double = 0.20
    public static let maxFaces = 8
    public static let minMatchIoU: Double = 0.15
    /// Hide a face that is the primary AF-C box or the locked subject.
    public static let occluderOverlap: Double = 0.28

    public static func dimmed(
        faces: [TrackingBox],
        hiding: TrackingBox? = nil,
        occluder: TrackingBox? = nil
    ) -> [TrackingBox] {
        faces.filter { face in
            if let hiding, conceals(hiding, face) { return false }
            if let occluder, conceals(occluder, face) { return false }
            return true
        }
    }

    /// IoU or the face/head buffer — a small face inside a padded head is the
    /// same person, not a second box.
    public static func conceals(_ owner: TrackingBox, _ other: TrackingBox) -> Bool {
        if other.intersectionOverUnion(owner) >= occluderOverlap { return true }
        return FaceHeadHandoff.isSamePerson(other, owner)
    }

    /// Greedy previous→detection map. IoU first; leftover tracks may match by
    /// centre when the whole scene has translated (gimbal stick).
    public static func assignments(
        detections: [TrackingBox],
        previous: [TrackingBox],
        minIoU: Double = minMatchIoU,
        maxCenterDistance: Double? = nil
    ) -> [Int: Int] {
        var pairs: [(score: Double, prev: Int, det: Int)] = []
        for (pi, prev) in previous.enumerated() {
            for (di, det) in detections.enumerated() {
                let iou = prev.intersectionOverUnion(det)
                if iou >= minIoU { pairs.append((iou, pi, di)) }
            }
        }
        pairs.sort { $0.score > $1.score }
        var usedPrev = Set<Int>()
        var usedDet = Set<Int>()
        var map: [Int: Int] = [:]
        for pair in pairs {
            if usedPrev.contains(pair.prev) || usedDet.contains(pair.det) { continue }
            usedPrev.insert(pair.prev)
            usedDet.insert(pair.det)
            map[pair.prev] = pair.det
        }
        guard let maxCenterDistance, maxCenterDistance > 0 else { return map }
        var centre: [(dist: Double, prev: Int, det: Int)] = []
        for (pi, prev) in previous.enumerated() where !usedPrev.contains(pi) {
            for (di, det) in detections.enumerated() where !usedDet.contains(di) {
                let dist = hypot(prev.centerX - det.centerX, prev.centerY - det.centerY)
                if dist <= maxCenterDistance { centre.append((dist, pi, di)) }
            }
        }
        centre.sort { $0.dist < $1.dist }
        for pair in centre {
            if usedPrev.contains(pair.prev) || usedDet.contains(pair.det) { continue }
            usedPrev.insert(pair.prev)
            usedDet.insert(pair.det)
            map[pair.prev] = pair.det
        }
        return map
    }
}

/// AF-C primary face box sits under subject tracking. AF-S never shows it.
/// Other faces stay as dim scene boxes (`SceneFacePolicy`).
public enum FaceAFPolicy {
    /// Keep the tap AF box on top of the face overlay after a feed tap.
    public static let tapHold: TimeInterval = 2.5

    public static func shouldHoldTapBox(secondsSinceTap: TimeInterval?) -> Bool {
        guard let secondsSinceTap else { return false }
        return secondsSinceTap >= 0 && secondsSinceTap < tapHold
    }
    public static func resolve(
        focusMode: FocusMode?,
        tracking: Bool,
        search: TrackingBox?,
        subject: TrackingBox?,
        face: TrackingBox?
    ) -> FocusOverlay {
        let base = FocusOverlayPolicy.resolve(
            tracking: tracking, search: search, subject: subject)
        switch base {
        case .search, .subject: return base
        case .focus, .face:
            if focusMode == .continuous, let face { return .face(face) }
            return .focus
        }
    }
}

/// Hold the last AF-C face through brief occlusion (hand, turn). Drop only after
/// a timeout. A leftover blob on the hand is not a reacquire — it must still
/// look like the locked face (size, overlap, centre, confidence).
///
/// Operator gimbal drive is different: the whole scene translates, so the next
/// hit is already past `reacquireCenterMax`. Pinning the still-frame lock then
/// freezes the painted boxes on a moving picture.
public enum FaceTrackHold {
    /// Face-only: hide as soon as Vision misses for a couple of ticks.
    public static let missTimeout: TimeInterval = 0.22
    /// Drop stale paint before a pan has left the face sitting on empty glass.
    public static let motionMissTimeout: TimeInterval = 0.18
    /// Keep motion matching after stick lift so the first settled hits can snap.
    public static let motionCoast: TimeInterval = 0.30
    public static let motionPositionTimeConstant: Double = 0.04
    /// Skip ease when the detection has already jumped — blend would lag the pan.
    /// 0.06 snapped on pose-ear flicker and painted the chair.
    public static let motionSnapDistance: Double = 0.20
    /// Hard cap. Old 0.32 let a palm sitting on the face steal the lock.
    public static let reacquireCenterMax: Double = 0.14
    public static let reacquireCenterScale: Double = 0.50
    public static let minAreaRatio: Double = 0.55
    public static let maxAreaRatio: Double = 2.6
    public static let minOverlap: Double = 0.28
    public static let updateConfidence: Double = 0.68

    public static func secondsSinceHit(lastHit: Date?, now: Date) -> TimeInterval {
        guard let lastHit else { return .infinity }
        return now.timeIntervalSince(lastHit)
    }

    public static func isSceneMoving(secondsSinceGimbal: TimeInterval?) -> Bool {
        guard let secondsSinceGimbal else { return false }
        return secondsSinceGimbal >= 0 && secondsSinceGimbal < motionCoast
    }

    public static func missTimeout(sceneMoving: Bool) -> TimeInterval {
        sceneMoving ? motionMissTimeout : missTimeout
    }

    public static func shouldDrop(
        secondsSinceHit: TimeInterval, sceneMoving: Bool = false
    ) -> Bool {
        secondsSinceHit >= missTimeout(sceneMoving: sceneMoving)
    }

    public static func shouldAccept(
        detected: TrackingBox,
        last: TrackingBox?,
        secondsSinceHit: TimeInterval,
        confidence: Double = 1,
        sceneMoving: Bool = false
    ) -> Bool {
        if sceneMoving { return confidence >= updateConfidence }
        guard let last, secondsSinceHit < missTimeout else { return true }
        if confidence < updateConfidence { return false }
        let lastArea = last.area
        guard lastArea > 0 else { return true }
        let areaRatio = detected.area / lastArea
        if areaRatio < minAreaRatio || areaRatio > maxAreaRatio { return false }
        let span = max(last.width, last.height)
        let maxCenter = min(reacquireCenterMax, max(span * reacquireCenterScale, 0.06))
        let dx = detected.centerX - last.centerX
        let dy = detected.centerY - last.centerY
        if hypot(dx, dy) > maxCenter { return false }
        return detected.intersectionOverUnion(last) >= minOverlap
    }

    public static func shouldAccept(
        hit: FaceHit, last: TrackingBox?, secondsSinceHit: TimeInterval,
        sceneMoving: Bool = false
    ) -> Bool {
        shouldAccept(
            detected: hit.box, last: last,
            secondsSinceHit: secondsSinceHit, confidence: hit.confidence,
            sceneMoving: sceneMoving)
    }

    /// Follow a Vision face. Size is the detector's box — not a 1:1 square.
    /// Position eases when sitting still; a gimbal throw snaps the centre.
    public static func follow(
        from: TrackingBox?, toward: TrackingBox, dt: Double,
        sceneMoving: Bool
    ) -> TrackingBox {
        if let from {
            let jump = hypot(from.centerX - toward.centerX, from.centerY - toward.centerY)
            if sceneMoving, jump >= motionSnapDistance {
                return toward
            }
            let eased = TrackingBoxSmoothing.blend(
                from: from, toward: toward, dt: dt,
                position: sceneMoving
                    ? motionPositionTimeConstant
                    : TrackingBoxSmoothing.facePositionTimeConstant,
                size: 0.001)
            return TrackingBox.fromCenter(
                x: eased.centerX, y: eased.centerY,
                width: toward.width, height: toward.height)
        }
        return toward
    }
}

/// One head per person. A fast duck used to spawn a second box at the new
/// place and leave a ghost at the old one.
public enum HeadTrackPolicy {
    /// Same-size head this close is the same person, not a new one.
    public static let jumpDistance: Double = 0.48
    public static let minAreaRatio: Double = 0.55
    public static let maxAreaRatio: Double = 2.6
    public static let mergeIoU: Double = 0.12

    public static func isSameHead(_ a: TrackingBox, _ b: TrackingBox) -> Bool {
        if a.intersectionOverUnion(b) >= mergeIoU { return true }
        let dist = hypot(a.centerX - b.centerX, a.centerY - b.centerY)
        guard dist <= jumpDistance, a.area > 0, b.area > 0 else { return false }
        let ratio = b.area / a.area
        return ratio >= minAreaRatio && ratio <= maxAreaRatio
    }

    public static func mergeHits(_ hits: [FaceHit]) -> [FaceHit] {
        let ordered = hits.sorted { $0.confidence * $0.box.area > $1.confidence * $1.box.area }
        var kept: [FaceHit] = []
        for hit in ordered {
            if kept.contains(where: { isSameHead($0.box, hit.box) }) { continue }
            kept.append(hit)
        }
        return kept
    }

    public static func shouldSpawn(detection: TrackingBox, existing: [TrackingBox]) -> Bool {
        !existing.contains { isSameHead($0, detection) }
    }
}

/// On-device Vision face used by AF-C. Confidence is Vision's 0…1 score.
public struct FaceHit: Equatable, Sendable {
    public var box: TrackingBox
    public var confidence: Double
    /// Eyes or profile (eye+nose). A cap / occiput oval is not structured.
    public var structured: Bool

    public init(box: TrackingBox, confidence: Double = 1, structured: Bool = true) {
        self.box = box
        self.confidence = min(max(confidence, 0), 1)
        self.structured = structured
    }
}

public struct FaceDetectResult: Equatable, Sendable {
    public var faces: [FaceHit]
    /// Head-sized stand-in while the locked subject has turned (no face, still a person).
    public var hold: FaceHit?

    public init(faces: [FaceHit], hold: FaceHit? = nil) {
        self.faces = faces
        self.hold = hold
    }
}

/// Two-eye (or profile eye+nose) gate so a palm is not a face.
public enum FaceStructurePolicy {
    public static let minimumEyeSeparation: Double = 0.12
    public static let highConfidenceWithoutLandmarks: Double = 0.90

    /// Eyes or profile. A high-confidence oval with no landmarks is not this.
    public static func hasFaceLandmarks(
        leftEyeX: Double?,
        rightEyeX: Double?,
        leftEyePoints: Int,
        rightEyePoints: Int,
        nosePoints: Int
    ) -> Bool {
        let leftOk = leftEyePoints >= 3 && leftEyeX != nil
        let rightOk = rightEyePoints >= 3 && rightEyeX != nil
        if leftOk, rightOk, let leftEyeX, let rightEyeX {
            return abs(rightEyeX - leftEyeX) >= minimumEyeSeparation
        }
        if leftOk || rightOk, nosePoints >= 3 { return true }
        return false
    }

    public static func isLikelyFace(
        confidence: Double,
        leftEyeX: Double?,
        rightEyeX: Double?,
        leftEyePoints: Int,
        rightEyePoints: Int,
        nosePoints: Int
    ) -> Bool {
        if hasFaceLandmarks(
            leftEyeX: leftEyeX, rightEyeX: rightEyeX,
            leftEyePoints: leftEyePoints, rightEyePoints: rightEyePoints,
            nosePoints: nosePoints)
        {
            return true
        }
        if leftEyePoints == 0, rightEyePoints == 0, nosePoints == 0 {
            return confidence >= highConfidenceWithoutLandmarks
        }
        return false
    }
}

/// Face / padded-head zone so a face and its own head box never count as two people.
public enum FaceHeadHandoff {
    /// Grow the head before testing “same person” so a face on the cheek or
    /// under a cap still owns the skull and we never paint both boxes.
    public static let headMargin: Double = 0.16
    /// Fraction of the face that must sit inside the padded head.
    public static let faceInsideHead: Double = 0.58

    public static func paddedHead(_ head: TrackingBox, margin: Double = headMargin) -> TrackingBox {
        let padX = head.width * margin
        let padY = head.height * margin
        return TrackingBox(
            x: head.minX - padX,
            y: head.minY - padY,
            width: head.width + 2 * padX,
            height: head.height + 2 * padY)
    }

    public static func faceBelongsToHead(face: TrackingBox, head: TrackingBox) -> Bool {
        guard face.area > 0 else { return false }
        let zone = paddedHead(head)
        return face.intersectionArea(zone) / face.area >= faceInsideHead
    }

    public static func isSamePerson(_ a: TrackingBox, _ b: TrackingBox) -> Bool {
        // Containment / overlap only. `HeadTrackPolicy.isSameHead` allows a 0.48
        // jump so a duck does not spawn a ghost — that would glue two people
        // standing apart onto one box.
        if faceBelongsToHead(face: a, head: b) { return true }
        if faceBelongsToHead(face: b, head: a) { return true }
        if a.intersectionOverUnion(b) >= SceneFacePolicy.occluderOverlap { return true }
        let aInB = paddedHead(b).contains(x: a.centerX, y: a.centerY) && a.area <= b.area * 1.15
        let bInA = paddedHead(a).contains(x: b.centerX, y: b.centerY) && b.area <= a.area * 1.15
        return aInB || bInA
    }
}

/// AF-C head lock thresholds.
public enum HeadLock {
    /// Sitting still: reject a pose that leapt off the locked head.
    public static let stillJump: Double = 0.16
}

/// Choose the AF-C primary **head**. Every hit is already a head box.
public enum FaceAFPick {
    public static func primary(
        hits: [FaceHit],
        hold: FaceHit?,
        last: TrackingBox?,
        secondsSinceHit: TimeInterval,
        sceneMoving: Bool
    ) -> FaceHit? {
        let hit: FaceHit?
        if let last {
            let accepted = hits.filter {
                if FaceTrackHold.shouldAccept(
                    hit: $0, last: last, secondsSinceHit: secondsSinceHit,
                    sceneMoving: sceneMoving)
                {
                    return true
                }
                guard HeadTrackPolicy.isSameHead($0.box, last) else { return false }
                let dist = hypot($0.box.centerX - last.centerX, $0.box.centerY - last.centerY)
                return sceneMoving || dist <= HeadLock.stillJump
            }
            hit = accepted.min {
                hypot($0.box.centerX - last.centerX, $0.box.centerY - last.centerY)
                    < hypot($1.box.centerX - last.centerX, $1.box.centerY - last.centerY)
            }
        } else {
            hit = hits.max { $0.confidence * $0.box.area < $1.confidence * $1.box.area }
        }
        return hit ?? hold
    }
}

/// Feed tap: face → ActiveTrack; otherwise Pocket tap-focus or ignore on Nano.
public enum LiveFeedTapPolicy {
    public enum Action: Equatable, Sendable {
        case trackFace
        case tapFocus
        case ignore
    }

    public static func action(supportsTapFocus: Bool, tappedFace: Bool) -> Action {
        if tappedFace { return .trackFace }
        return supportsTapFocus ? .tapFocus : .ignore
    }
}

/// Right after an operator ActiveTrack SET the camera can still push its
/// previous subject (often a face). Drawing that paints the lock on the wrong
/// thing, then slides it across to the new target.
public enum TrackingStartPolicy {
    public static let settle: TimeInterval = 1.5
    /// Slack around the requested box: the camera's lock rarely matches it exactly.
    public static let padding: Double = 0.05

    public static func accepts(
        _ push: TrackingBox, requested: TrackingBox?, secondsSinceRequest: TimeInterval?
    ) -> Bool {
        guard let requested, let secondsSinceRequest, secondsSinceRequest >= 0,
            secondsSinceRequest < settle
        else { return true }
        return push.intersectionOverUnion(requested) > 0
            || requested.contains(x: push.centerX, y: push.centerY, padding: padding)
    }
}

/// Double-tap the same spot, as in Mimo and on the camera: the first tap
/// focuses as usual, the second starts ActiveTrack on a box centred there.
public struct FeedDoubleTapTrack: Sendable {
    public static let window: TimeInterval = 0.45
    /// Feed-normalised distance that still counts as the same spot.
    public static let radius: Double = 0.06
    /// Roughly square on a 16:9 picture; the camera's tracker finds the subject.
    public static let boxWidth: Double = 0.14
    public static let boxHeight: Double = 0.25

    private var lastX = 0.0
    private var lastY = 0.0
    private var lastAt: TimeInterval?

    public init() {}

    /// The tracking box when this tap completes a double tap, otherwise `nil`.
    public mutating func register(x: Double, y: Double, at time: TimeInterval) -> TrackingBox? {
        if let lastAt, time >= lastAt, time - lastAt <= Self.window,
            hypot(x - lastX, y - lastY) <= Self.radius
        {
            self.lastAt = nil
            return TrackingBox.fromCenter(x: x, y: y, width: Self.boxWidth, height: Self.boxHeight)
        }
        (lastX, lastY, lastAt) = (x, y, time)
        return nil
    }

    public mutating func reset() { lastAt = nil }
}

/// Tap the painted AF-C face box to SET gimbal ActiveTrack (`0x02/0xA6`)
/// with that rect, instead of tap-to-focus.
public enum FaceTrackTap {
    /// Extra hit slop so a tap on the bracket edge still counts.
    public static let hitPadding: Double = 0.03

    public static func contains(_ x: Double, _ y: Double, in box: TrackingBox) -> Bool {
        box.contains(x: x, y: y, padding: hitPadding)
    }

    /// Grow a Vision face to at least the Mimo accept floor so SET is not rejected.
    public static func trackingBox(from face: TrackingBox) -> TrackingBox {
        let w = max(face.width, TrackingBox.mimoMinimumSide)
        let h = max(face.height, TrackingBox.mimoMinimumSide)
        if w == face.width, h == face.height { return face }
        return TrackingBox.fromCenter(x: face.centerX, y: face.centerY, width: w, height: h)
    }

    public static func boxIfTapped(
        overlay: FocusOverlay, x: Double, y: Double,
        sceneFaces: [TrackingBox] = []
    ) -> TrackingBox? {
        if case .face(let face) = overlay, contains(x, y, in: face) {
            return trackingBox(from: face)
        }
        let hits = sceneFaces.filter { contains(x, y, in: $0) }
        guard let face = hits.min(by: { $0.area < $1.area }) else { return nil }
        return trackingBox(from: face)
    }
}

/// Triangle/Y: track a face in frame, or cancel if already tracking.
public enum GamepadFaceTrack {
    public enum Action: Equatable, Sendable {
        case cancel
        case track(TrackingBox)
        case none
    }

    public static func action(
        trackingActive: Bool,
        overlay: FocusOverlay,
        sceneFaces: [TrackingBox]
    ) -> Action {
        if trackingActive { return .cancel }
        if case .face(let face) = overlay {
            return .track(FaceTrackTap.trackingBox(from: face))
        }
        guard let face = sceneFaces.max(by: { $0.area < $1.area }) else { return .none }
        return .track(FaceTrackTap.trackingBox(from: face))
    }
}

/// Vision `boundingBox` is normalized, origin bottom-left. Feed overlays are top-left.
public enum VisionFaceBox {
    public static let minimumSide: Double = 0.05

    public static func fromVision(
        minX: Double, minY: Double, width: Double, height: Double
    ) -> TrackingBox? {
        guard width >= minimumSide, height >= minimumSide,
            minX.isFinite, minY.isFinite, width.isFinite, height.isFinite
        else { return nil }
        let x = min(max(minX, 0), 1)
        let y = min(max(1 - (minY + height), 0), 1)
        let w = min(max(width, 0), 1 - x)
        let h = min(max(height, 0), 1 - y)
        guard w >= minimumSide, h >= minimumSide else { return nil }
        return TrackingBox(x: x, y: y, width: w, height: h)
    }
}

/// OpenZCine recenter key: off-centre AF (>4%) or an active track.
public enum FocusResetPolicy {
    public static let offCenterThreshold = 0.04

    public static func isAvailable(x: Double?, y: Double?, tracking: Bool) -> Bool {
        if tracking { return true }
        guard let x, let y else { return false }
        return abs(x - 0.5) > offCenterThreshold || abs(y - 0.5) > offCenterThreshold
    }
}
