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
    /// A 25 Hz miss during a stick throw can move a face this far.
    public static let motionMatchDistance: Double = 0.55
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

/// Pose / person helpers for the **head** box used when the face has turned
/// away. The painted lock itself is `FaceHeadHandoff`: face while they look
/// at the camera, head after they turn.
public enum FaceBodyFallback {
    /// Last face must still sit mostly inside the person.
    public static let minFaceCoverage: Double = 0.30
    public static let minPersonConfidence: Double = 0.45
    public static let minJointConfidence: Double = 0.50
    /// Head is the top slice of an upper-body rect, inset so padding is not "head".
    public static let personHeadHeight: Double = 0.30
    public static let personHeadTopInset: Double = 0.06
    /// Headphones sit outside the ears; the cap sits above them.
    public static let posePadX: Double = 0.48
    public static let posePadAbove: Double = 0.48
    public static let posePadBelow: Double = 0.08
    /// Close-up heads (cap + cups) need more than 0.48 of the frame.
    public static let poseMaxSide: Double = 0.58
    /// Inter-eye span is ~0.45 of head width. Eye-only hulls must scale by this.
    public static let eyeSpanToHead: Double = 2.25
    /// Visibility floor only — a typical head is much larger. 0.18 pinned
    /// distant heads to a fixed slab.
    public static let poseMinSide: Double = 0.06
    public static let poseMaxWidth: Double = poseMaxSide
    public static let poseMaxHeight: Double = poseMaxSide
    /// Pocket live is 16:9. Stored 0…1 extents map independently onto the
    /// picture, so a visual 1:1 box is taller in normalised space
    /// (`width = height / pictureAspect`). Equal stored sides paint 16:9.
    public static let defaultPictureAspect: Double = 16.0 / 9.0

    public static func pictureAspect(width: Int, height: Int) -> Double {
        guard width > 0, height > 0 else { return defaultPictureAspect }
        return sanitizedPictureAspect(Double(width) / Double(height))
    }

    public static func sanitizedPictureAspect(_ aspect: Double) -> Double {
        guard aspect.isFinite, aspect > 0.2, aspect < 5 else { return defaultPictureAspect }
        return aspect
    }

    /// Covering visual 1:1 box. Long pose hulls stay square on the picture;
    /// a lone ear stays head-sized. Extra height grows up (cap), not into the chest.
    public static func squareHead(
        centerX: Double, centerY: Double, width: Double, height: Double,
        prior: TrackingBox? = nil,
        pictureAspect: Double = defaultPictureAspect
    ) -> TrackingBox {
        let aspect = sanitizedPictureAspect(pictureAspect)
        let visual = max(width * aspect, height)
        var floor = poseMinSide
        if let prior {
            let priorVisual = min(max(prior.width * aspect, prior.height), poseMaxSide)
            // Resist jitter, not a walk-away or a leftover huge oval.
            if priorVisual <= max(visual, poseMinSide) * 2.2 {
                floor = max(floor, priorVisual * 0.85)
            }
        }
        let side = min(max(visual, floor), poseMaxSide)
        let storedW = side / aspect
        let storedH = side
        let extraH = max(0, storedH - height)
        return TrackingBox.fromCenter(
            x: centerX, y: centerY - extraH / 2,
            width: storedW, height: storedH)
    }
    /// Grow a Vision face oval into the head (cap, ears, cups). The detector
    /// box is the inner face — 1.5× still clipped headphones on a close-up.
    public static let faceToHeadScaleX: Double = 1.85
    public static let faceToHeadScaleY: Double = 1.80
    public static let faceToHeadLift: Double = 0.36

    public static func needsHold(faces: [FaceHit], last: TrackingBox?) -> Bool {
        guard let last else { return false }
        return matchingFace(in: faces, last: last) == nil
    }

    public static func matchingFace(in faces: [FaceHit], last: TrackingBox) -> FaceHit? {
        faces
            .filter {
                $0.structured
                    && $0.box.intersectionOverUnion(last) >= SceneFacePolicy.minMatchIoU
            }
            .max {
                $0.box.intersectionOverUnion(last) < $1.box.intersectionOverUnion(last)
            }
    }

    public static func shouldHold(lastFace: TrackingBox, person: TrackingBox) -> Bool {
        guard lastFace.area > 0 else { return false }
        return lastFace.intersectionArea(person) / lastFace.area >= minFaceCoverage
    }

    /// Face oval → head. Extra height goes up (cap), not into the chest.
    public static func headFromFace(
        _ face: TrackingBox, prior: TrackingBox? = nil,
        pictureAspect: Double = defaultPictureAspect
    ) -> TrackingBox {
        let w = face.width * faceToHeadScaleX
        let h = face.height * faceToHeadScaleY
        let cy = face.centerY - (h - face.height) * faceToHeadLift
        return squareHead(
            centerX: face.centerX, centerY: cy, width: w, height: h,
            prior: prior, pictureAspect: pictureAspect)
    }

    /// One painted lock: visual 1:1 around the **union** of the grown face and
    /// the pose hull. Never smaller than either detector's extent.
    public static func coveringBox(
        face: TrackingBox?,
        head: TrackingBox?,
        prior: TrackingBox? = nil,
        pictureAspect: Double = defaultPictureAspect
    ) -> TrackingBox? {
        let grownFace = face.map {
            headFromFace($0, prior: prior, pictureAspect: pictureAspect)
        }
        switch (grownFace, head) {
        case (let f?, let h?):
            let cover = f.union(h)
            return squareHead(
                centerX: cover.centerX, centerY: cover.centerY,
                width: cover.width, height: cover.height,
                prior: prior, pictureAspect: pictureAspect)
        case (let f?, nil):
            return f
        case (nil, let h?):
            return squareHead(
                centerX: h.centerX, centerY: h.centerY,
                width: h.width, height: h.height,
                prior: prior, pictureAspect: pictureAspect)
        case (nil, nil):
            return nil
        }
    }

    /// Person-rect fallback: visual 1:1 head at the top-centre of the body.
    public static func heldHead(
        lastFace: TrackingBox, person: TrackingBox,
        pictureAspect: Double = defaultPictureAspect
    ) -> TrackingBox? {
        guard shouldHold(lastFace: lastFace, person: person) else { return nil }
        let w = min(max(lastFace.width, person.width * 0.50), person.width)
        let inset = person.height * personHeadTopInset
        let headH = min(
            max(lastFace.height, person.height * personHeadHeight),
            person.height - inset)
        let sized = squareHead(
            centerX: person.centerX, centerY: 0.5,
            width: w, height: headH, prior: lastFace, pictureAspect: pictureAspect)
        let cx = min(
            max(person.centerX, person.minX + sized.width / 2),
            person.maxX - sized.width / 2)
        let cy = person.minY + inset + sized.height / 2
        return TrackingBox.fromCenter(
            x: cx, y: cy, width: sized.width, height: sized.height)
    }

    public static func bestHold(
        lastFace: TrackingBox, people: [TrackingBox],
        pictureAspect: Double = defaultPictureAspect
    ) -> TrackingBox? {
        people
            .compactMap {
                heldHead(lastFace: lastFace, person: $0, pictureAspect: pictureAspect)
            }
            .max { $0.intersectionOverUnion(lastFace) < $1.intersectionOverUnion(lastFace) }
    }

    /// Full head from nose / eyes / ears / neck (top-left normalised).
    /// Size comes from the joints so a leftover face oval cannot inflate the box.
    public static func headFromPose(
        lastFace: TrackingBox?,
        neckX: Double?, neckY: Double?,
        leftEarX: Double?, leftEarY: Double?,
        rightEarX: Double?, rightEarY: Double?,
        leftShoulderX: Double?, leftShoulderY: Double?,
        rightShoulderX: Double?, rightShoulderY: Double?,
        noseX: Double? = nil, noseY: Double? = nil,
        leftEyeX: Double? = nil, leftEyeY: Double? = nil,
        rightEyeX: Double? = nil, rightEyeY: Double? = nil,
        pictureAspect: Double = defaultPictureAspect
    ) -> TrackingBox? {
        var xs: [Double] = []
        var ys: [Double] = []
        func add(_ x: Double?, _ y: Double?) {
            if let x, let y {
                xs.append(x)
                ys.append(y)
            }
        }
        add(leftEarX, leftEarY)
        add(rightEarX, rightEarY)
        add(leftEyeX, leftEyeY)
        add(rightEyeX, rightEyeY)
        add(noseX, noseY)
        add(neckX, neckY)
        if xs.count >= 2 {
            let minX = xs.min() ?? 0
            let maxX = xs.max() ?? 1
            let minY = ys.min() ?? 0
            let maxY = ys.max() ?? 1
            let spanX = max(maxX - minX, 0.02)
            let spanY = max(maxY - minY, 0.02)
            var w = min(spanX * (1 + posePadX), poseMaxSide)
            var h = min(spanY * (1 + posePadAbove + posePadBelow), poseMaxSide)
            let hasEars = leftEarX != nil || rightEarX != nil
            // Eyes are ~0.45 of head width. Padding an eye-only hull still
            // paints a feature square; scale from inter-eye instead.
            if !hasEars, let lx = leftEyeX, let rx = rightEyeX {
                let head = min(abs(rx - lx) * eyeSpanToHead, poseMaxSide)
                w = max(w, head)
                h = max(h, head)
            }
            let headJoints = [leftEarX, rightEarX, noseX, leftEyeX, rightEyeX]
                .compactMap { $0 }.count
            // Shoulders pull the box onto the chest when ears/nose already exist.
            if headJoints < 2, let ls = leftShoulderX, let rs = rightShoulderX {
                let shoulder = abs(rs - ls) * 0.58
                w = max(w, shoulder)
                h = max(h, shoulder)
            }
            let cx = (minX + maxX) / 2
            let top = minY - spanY * posePadAbove
            let cy = top + h / 2
            return squareHead(
                centerX: cx, centerY: cy, width: w, height: h, prior: lastFace,
                pictureAspect: pictureAspect)
        }
        if let nx = neckX, let ny = neckY {
            var cx = nx
            if let ls = leftShoulderX, let rs = rightShoulderX {
                cx = (ls + rs) / 2
            }
            if let lastFace {
                let seed = headFromFace(lastFace, pictureAspect: pictureAspect)
                return TrackingBox.fromCenter(
                    x: cx, y: ny - seed.height * 0.42, width: seed.width, height: seed.height)
            }
            var seedW = 0.08
            var seedH = 0.10
            if let ls = leftShoulderX, let rs = rightShoulderX {
                let shoulder = abs(rs - ls) * 0.50
                seedW = max(seedW, shoulder)
                seedH = max(seedH, shoulder)
            }
            return squareHead(
                centerX: cx, centerY: ny - seedH * 0.42,
                width: seedW, height: seedH, pictureAspect: pictureAspect)
        }
        return nil
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

/// Face is the lock while the person looks at the camera. Pose head takes over
/// only after the face has been gone long enough; a padded head zone keeps the
/// two boxes from stacking on the same person.
public enum FaceHeadHandoff {
    public enum Mode: String, Equatable, Sendable {
        case face
        case head
    }

    /// Grow the head before testing “same person” so a face on the cheek or
    /// under a cap still owns the skull and we never paint both boxes.
    public static let headMargin: Double = 0.16
    /// Fraction of the face that must sit inside the padded head.
    public static let faceInsideHead: Double = 0.58
    /// Structured-face confidence to *enter* face mode.
    public static let faceEnterConfidence: Double = 0.74
    /// Floor to *keep* face mode through a soft profile.
    public static let faceHoldConfidence: Double = 0.62
    /// Face must be gone this long before the head box is allowed on.
    public static let faceLostDuration: TimeInterval = 0.24
    /// Face must be back this long before we leave head mode.
    public static let faceRecoverDuration: TimeInterval = 0.20

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

    public static func isUsableFace(
        _ hit: FaceHit, entering: Bool, sceneMoving: Bool
    ) -> Bool {
        let floor = entering ? faceEnterConfidence : faceHoldConfidence
        if hit.confidence < floor { return false }
        if hit.structured { return true }
        // Gimbal pans drop landmarks (`rectanglesOnly`). Keep face mode; do not enter it.
        return sceneMoving && !entering
    }

    public static func nextMode(
        current: Mode,
        hasUsableFace: Bool,
        hasHead: Bool,
        faceVisibleFor: TimeInterval,
        faceMissingFor: TimeInterval
    ) -> Mode {
        switch current {
        case .face:
            if hasUsableFace { return .face }
            if hasHead, faceMissingFor >= faceLostDuration { return .head }
            return .face
        case .head:
            if hasUsableFace, faceVisibleFor >= faceRecoverDuration { return .face }
            if hasHead { return .head }
            if hasUsableFace { return .face }
            return .head
        }
    }

    public static func pickBox(
        mode: Mode, face: TrackingBox?, head: TrackingBox?
    ) -> TrackingBox? {
        switch mode {
        case .face: return face
        case .head: return head ?? face
        }
    }
}

/// Fuse the stable Vision face with pose. One box per person: the face while
/// they look at the camera, the head after they turn away.
public enum HeadLock {
    /// Sitting still: reject a pose that leapt off the locked head.
    public static let stillJump: Double = 0.16
    public static let movingJump: Double = 0.40
    public static let poseExpandIoU: Double = 0.08

    public static func maxJump(sceneMoving: Bool) -> Double {
        sceneMoving ? movingJump : stillJump
    }

    public static func fuse(
        faces: [FaceHit],
        poses: [TrackingBox],
        last: TrackingBox?,
        pictureAspect: Double = FaceBodyFallback.defaultPictureAspect,
        sceneMoving: Bool = false,
        lastMode: FaceHeadHandoff.Mode = .face,
        faceVisibleFor: TimeInterval = 0,
        faceMissingFor: TimeInterval = .infinity
    ) -> [FaceHit] {
        resolve(
            faces: faces, poses: poses, last: last, pictureAspect: pictureAspect,
            sceneMoving: sceneMoving, lastMode: lastMode,
            faceVisibleFor: faceVisibleFor, faceMissingFor: faceMissingFor
        ).hits
    }

    public struct Result: Equatable, Sendable {
        public var hits: [FaceHit]
        public var primaryMode: FaceHeadHandoff.Mode
        public var primarySawFace: Bool

        public init(
            hits: [FaceHit],
            primaryMode: FaceHeadHandoff.Mode,
            primarySawFace: Bool
        ) {
            self.hits = hits
            self.primaryMode = primaryMode
            self.primarySawFace = primarySawFace
        }
    }

    public static func resolve(
        faces: [FaceHit],
        poses: [TrackingBox],
        last: TrackingBox?,
        pictureAspect: Double = FaceBodyFallback.defaultPictureAspect,
        sceneMoving: Bool = false,
        lastMode: FaceHeadHandoff.Mode = .face,
        faceVisibleFor: TimeInterval = 0,
        faceMissingFor: TimeInterval = .infinity
    ) -> Result {
        let jump = maxJump(sceneMoving: sceneMoving)
        let usableFaces = faces.filter {
            FaceHeadHandoff.isUsableFace($0, entering: false, sceneMoving: sceneMoving)
        }
        let usableHeads: [TrackingBox] = poses.compactMap { pose in
            if let last {
                let dist = hypot(pose.centerX - last.centerX, pose.centerY - last.centerY)
                if dist > jump, pose.intersectionOverUnion(last) < poseExpandIoU {
                    return nil
                }
                return FaceBodyFallback.squareHead(
                    centerX: pose.centerX, centerY: pose.centerY,
                    width: pose.width, height: pose.height,
                    prior: last, pictureAspect: pictureAspect)
            }
            return pose
        }

        var pairs: [(face: Int, head: Int, score: Double)] = []
        for (fi, face) in usableFaces.enumerated() {
            for (hi, head) in usableHeads.enumerated()
            where FaceHeadHandoff.isSamePerson(face.box, head) {
                pairs.append((fi, hi, face.box.intersectionOverUnion(head)))
            }
        }
        pairs.sort { $0.score > $1.score }

        var usedFaces = Set<Int>()
        var usedHeads = Set<Int>()
        var clusters: [(face: FaceHit?, head: TrackingBox?)] = []
        for pair in pairs {
            if usedFaces.contains(pair.face) || usedHeads.contains(pair.head) { continue }
            usedFaces.insert(pair.face)
            usedHeads.insert(pair.head)
            clusters.append((usableFaces[pair.face], usableHeads[pair.head]))
        }
        for (index, face) in usableFaces.enumerated() where !usedFaces.contains(index) {
            clusters.append((face, nil))
        }
        for (index, head) in usableHeads.enumerated() where !usedHeads.contains(index) {
            clusters.append((nil, head))
        }

        var hits: [FaceHit] = []
        var primaryMode = lastMode
        var primarySawFace = false
        var assignedPrimary = false

        for cluster in clusters {
            let isPrimary = matchesPrimary(cluster.face?.box, cluster.head, last: last)
            let enteringFace =
                cluster.face.map {
                    FaceHeadHandoff.isUsableFace($0, entering: true, sceneMoving: sceneMoving)
                } ?? false
            let holdingFace = cluster.face != nil
            let mode: FaceHeadHandoff.Mode
            if isPrimary || (last == nil && !assignedPrimary) {
                let visible = isPrimary ? faceVisibleFor : (holdingFace ? .infinity : 0)
                let missing = isPrimary ? faceMissingFor : (holdingFace ? 0 : .infinity)
                mode = FaceHeadHandoff.nextMode(
                    current: last == nil ? .face : lastMode,
                    hasUsableFace: isPrimary
                        ? (lastMode == .head ? enteringFace : holdingFace) : enteringFace,
                    hasHead: cluster.head != nil,
                    faceVisibleFor: visible,
                    faceMissingFor: missing)
                if isPrimary || last == nil {
                    primaryMode = mode
                    primarySawFace = holdingFace
                    assignedPrimary = true
                }
            } else {
                mode = holdingFace ? .face : .head
            }

            // Face-mode grace: no new hit. CameraSession keeps the last face.
            if mode == .face, cluster.face == nil { continue }
            if let painted = FaceBodyFallback.coveringBox(
                face: cluster.face?.box,
                head: cluster.head,
                prior: isPrimary ? last : nil,
                pictureAspect: pictureAspect)
            {
                hits.append(
                    FaceHit(
                        box: painted,
                        confidence: cluster.face?.confidence ?? 0.80,
                        structured: mode == .face && cluster.face != nil))
            }
        }

        return Result(
            hits: HeadTrackPolicy.mergeHits(hits),
            primaryMode: primaryMode,
            primarySawFace: primarySawFace)
    }

    private static func matchesPrimary(
        _ face: TrackingBox?, _ head: TrackingBox?, last: TrackingBox?
    ) -> Bool {
        guard let last else { return false }
        if let face, FaceHeadHandoff.isSamePerson(face, last) { return true }
        if let head, FaceHeadHandoff.isSamePerson(head, last) { return true }
        return false
    }
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
