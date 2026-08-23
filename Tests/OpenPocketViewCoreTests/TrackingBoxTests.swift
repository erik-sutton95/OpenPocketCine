import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct TrackingBoxTests {
    @Test func setTrackingBoxMatchesMimoLayout() {
        let frame = Commands.setTrackingBox(
            id: 0x2726, x: 0.418, y: 0.525, width: 0.484, height: 0.461)
        #expect(frame.cmdSet == 0x02)
        #expect(frame.cmdId == 0xA6)
        #expect(frame.receiver == Duml.rxCamera)
        #expect(frame.flags == Duml.flagRequest)
        #expect(frame.payload.count == 21)
        #expect(Array(frame.payload.prefix(5)) == [0x01, 0x00, 0x00, 0x26, 0x27])
        #expect(Array(frame.payload[5..<9]) == floatLE(0.418))
        #expect(Array(frame.payload[9..<13]) == floatLE(0.525))
        #expect(Array(frame.payload[13..<17]) == floatLE(0.484))
        #expect(Array(frame.payload[17..<21]) == floatLE(0.461))
    }

    @Test func clearTrackingBoxIsTwentyOneZeros() {
        let frame = Commands.clearTrackingBox()
        #expect(frame.cmdId == 0xA6)
        #expect(frame.payload == [UInt8](repeating: 0, count: 21))
    }

    @Test func pollTrackingIsEmptyGet() {
        let frame = Commands.pollTracking()
        #expect(frame.cmdSet == 0x02)
        #expect(frame.cmdId == 0xA5)
        #expect(frame.payload == [0x00])
    }

    @Test func trackingPollParsesLockedAndIdle() {
        #expect(TrackingPoll.parse([0x00, 0x01, 0x00, 0x00]) == .locked(box: nil))
        #expect(TrackingPoll.parse([0x00, 0x00, 0x00, 0x00]) == .idle)
        #expect(TrackingPoll.parse([0x00]) == nil)
        #expect(TrackingPoll.parse([]) == nil)
    }

    @Test func livePushParsesMimoSubjectBox() throws {
        // /tmp/mimo-tracking-box-20260818.pcapng pkt#1 0x02/0x89 notify.
        let payload: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0xA0, 0x41,
            0x85, 0x10, 0x05, 0x3F, 0xC5, 0x4C, 0xC5, 0x3E,
            0xC0, 0x88, 0x3F, 0x3E, 0xCA, 0x30, 0xCA, 0x3E,
        ]
        let box = try #require(TrackingBox.parseLivePush(payload))
        // Wire is centre + size. Origin is centre − half extent.
        #expect(abs(box.width - 0.187) < 0.001)
        #expect(abs(box.height - 0.395) < 0.001)
        #expect(abs(box.centerX - 0.520) < 0.001)
        #expect(abs(box.centerY - 0.385) < 0.001)
        #expect(abs(box.x - (0.520 - 0.187 / 2)) < 0.001)
        #expect(abs(box.y - (0.385 - 0.395 / 2)) < 0.001)
    }

    @Test func livePushAcceptsAlternateHeaderTag() throws {
        // Same take, one `00 80 3f` header. Floats still at @7.
        let payload: [UInt8] = [
            0x00, 0x00, 0x00, 0x00, 0x00, 0x80, 0x3F,
            0xCE, 0x45, 0xCE, 0x3E, 0xD6, 0x9A, 0xD5, 0x3E,
            0xDE, 0x04, 0x5D, 0x3E, 0xD0, 0xB0, 0xD0, 0x3D,
        ]
        let box = try #require(TrackingBox.parseLivePush(payload))
        #expect(abs(box.centerX - 0.403) < 0.001)
        #expect(abs(box.height - 0.102) < 0.001)
    }

    @Test func livePushRejectsShortOrBadPrefix() {
        #expect(TrackingBox.parseLivePush([0x00, 0x01, 0x00, 0x00]) == nil)
        var bad = [UInt8](repeating: 0, count: 23)
        bad[0] = 0x01
        #expect(TrackingBox.parseLivePush(bad) == nil)
    }

    @Test func trackingPollReadsSubjectBoxWhenReplyCarriesFloats() {
        var payload: [UInt8] = [0x00, 0x01, 0x00, 0x00]
        payload += floatLE(0.40) + floatLE(0.30) + floatLE(0.18) + floatLE(0.22)
        let parsed = TrackingPoll.parse(payload)
        guard case .locked(let box) = parsed, let box else {
            Issue.record("expected locked subject box")
            return
        }
        #expect(abs(box.centerX - 0.40) < 0.0001)
        #expect(abs(box.centerY - 0.30) < 0.0001)
        #expect(abs(box.width - 0.18) < 0.0001)
        #expect(abs(box.height - 0.22) < 0.0001)
    }

    @Test func overlayShowsFocusWhenIdle() {
        #expect(
            FocusOverlayPolicy.resolve(
                tracking: false, search: Optional<TrackingBox>.none,
                subject: Optional<TrackingBox>.none)
                == .focus
        )
    }

    @Test func overlayShowsSearchUntilLock() {
        let search = TrackingBox(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        #expect(
            FocusOverlayPolicy.resolve(
                tracking: false, search: search, subject: Optional<TrackingBox>.none)
                == .search(search)
        )
    }

    @Test func overlayReplacesSearchWithSubjectOnLock() {
        let search = TrackingBox(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
        #expect(
            FocusOverlayPolicy.resolve(
                tracking: true, search: search, subject: Optional<TrackingBox>.none)
                == .subject(TrackingBox.subject(from: search))
        )
        let camera = TrackingBox(x: 0.41, y: 0.33, width: 0.16, height: 0.20)
        #expect(
            FocusOverlayPolicy.resolve(tracking: true, search: search, subject: camera)
                == .subject(camera)
        )
    }

    @Test func subjectBoxIsTighterAndCenteredOnSearch() {
        let search = TrackingBox(x: 0.10, y: 0.20, width: 0.60, height: 0.50)
        let subject = TrackingBox.subject(from: search)
        #expect(subject.width < search.width)
        #expect(subject.height < search.height)
        let subjectMidX = subject.x + subject.width / 2
        let searchMidX = search.x + search.width / 2
        let subjectMidY = subject.y + subject.height / 2
        let searchMidY = search.y + search.height / 2
        #expect(abs(subjectMidX - searchMidX) < 0.0001)
        #expect(abs(subjectMidY - searchMidY) < 0.0001)
        #expect(subject.minX >= search.minX)
        #expect(subject.maxX <= search.maxX)
    }

    @Test func trackingRectNormalizesAnyDragDirection() {
        let box = TrackingBox.normalized(fromX: 0.70, fromY: 0.80, toX: 0.20, toY: 0.30)
        #expect(abs(box.x - 0.20) < 0.0001)
        #expect(abs(box.y - 0.30) < 0.0001)
        #expect(abs(box.width - 0.50) < 0.0001)
        #expect(abs(box.height - 0.50) < 0.0001)
    }

    @Test func trackingRectClampsAndEnforcesMinimumSize() {
        let box = TrackingBox.normalized(fromX: -0.2, fromY: 0.49, toX: 1.4, toY: 0.51)
        #expect(box.minX >= 0)
        #expect(box.minY >= 0)
        #expect(box.maxX <= 1)
        #expect(box.maxY <= 1)
        #expect(box.isTooSmall)
    }

    @Test func mimoRejectsTinySearchFrames() {
        let tiny = TrackingBox(x: 0.40, y: 0.40, width: 0.05, height: 0.05)
        let ok = TrackingBox(x: 0.40, y: 0.40, width: 0.12, height: 0.20)
        #expect(tiny.isTooSmall)
        #expect(!ok.isTooSmall)
    }

    @Test func setTrackingBoxSendsCenterNotOrigin() {
        let box = TrackingBox(x: 0.20, y: 0.30, width: 0.40, height: 0.20)
        let frame = Commands.setTrackingBox(
            id: 1,
            x: Float(box.centerX),
            y: Float(box.centerY),
            width: Float(box.width),
            height: Float(box.height)
        )
        #expect(Array(frame.payload[5..<9]) == floatLE(0.40))
        #expect(Array(frame.payload[9..<13]) == floatLE(0.40))
    }

    @Test func smoothingBlendsSizeSlowerThanCenter() {
        let from = TrackingBox(x: 0.20, y: 0.20, width: 0.20, height: 0.20)
        let toward = TrackingBox(x: 0.40, y: 0.40, width: 0.40, height: 0.40)
        let dt = 1.0 / 15.0
        let step = TrackingBoxSmoothing.blend(from: from, toward: toward, dt: dt)
        let centerTravel = abs(step.centerX - from.centerX)
        let sizeTravel = abs(step.width - from.width)
        #expect(centerTravel > sizeTravel)
        #expect(step.width > from.width)
        #expect(step.width < toward.width)
        #expect(TrackingBoxSmoothing.blend(from: nil, toward: toward, dt: dt) == toward)
        let settled = TrackingBoxSmoothing.blend(from: from, toward: toward, dt: 5)
        #expect(abs(settled.width - toward.width) < 0.001)
        #expect(abs(settled.centerX - toward.centerX) < 0.001)
        let frame = 1.0 / 25.0
        let a = TrackingBoxSmoothing.blend(
            from: from, toward: toward, dt: frame,
            position: TrackingBoxSmoothing.facePositionTimeConstant,
            size: TrackingBoxSmoothing.faceSizeTimeConstant)
        let b = TrackingBoxSmoothing.blend(
            from: a, toward: toward, dt: frame,
            position: TrackingBoxSmoothing.facePositionTimeConstant,
            size: TrackingBoxSmoothing.faceSizeTimeConstant)
        #expect(abs(b.centerX - toward.centerX) < abs(a.centerX - toward.centerX))
        #expect(abs(b.centerX - from.centerX) > abs(a.centerX - from.centerX))
    }

    @Test func faceOverlayOnlyInContinuousWhenIdle() {
        let face = TrackingBox(x: 0.30, y: 0.20, width: 0.20, height: 0.28)
        #expect(
            FaceAFPolicy.resolve(
                focusMode: .continuous, tracking: false, search: nil, subject: nil, face: face)
                == .face(face)
        )
        #expect(
            FaceAFPolicy.resolve(
                focusMode: .single, tracking: false, search: nil, subject: nil, face: face)
                == .focus
        )
        let search = TrackingBox(x: 0.1, y: 0.1, width: 0.4, height: 0.4)
        #expect(
            FaceAFPolicy.resolve(
                focusMode: .continuous, tracking: false, search: search, subject: nil, face: face)
                == .search(search)
        )
        #expect(
            FaceAFPolicy.resolve(
                focusMode: .continuous, tracking: true, search: search, subject: nil, face: face)
                == .subject(TrackingBox.subject(from: search))
        )
        #expect(FaceAFPolicy.shouldHoldTapBox(secondsSinceTap: 0.4))
        #expect(FaceAFPolicy.shouldHoldTapBox(secondsSinceTap: 2.4))
        #expect(!FaceAFPolicy.shouldHoldTapBox(secondsSinceTap: 2.5))
        #expect(!FaceAFPolicy.shouldHoldTapBox(secondsSinceTap: nil))
    }

    @Test func dimmedFacesHidePrimaryAndSubjectKeepOthers() {
        let primary = TrackingBox(x: 0.30, y: 0.20, width: 0.20, height: 0.28)
        let extra = TrackingBox(x: 0.70, y: 0.18, width: 0.16, height: 0.22)
        let subject = TrackingBox(x: 0.29, y: 0.19, width: 0.22, height: 0.30)
        #expect(
            SceneFacePolicy.dimmed(faces: [primary, extra], hiding: primary)
                == [extra])
        #expect(
            SceneFacePolicy.dimmed(faces: [primary, extra], occluder: subject)
                == [extra])
        #expect(SceneFacePolicy.dimOpacity == 0.20)
        let a = TrackingBox(x: 0.10, y: 0.10, width: 0.20, height: 0.20)
        let b = TrackingBox(x: 0.12, y: 0.11, width: 0.20, height: 0.20)
        let c = TrackingBox(x: 0.70, y: 0.10, width: 0.20, height: 0.20)
        #expect(SceneFacePolicy.assignments(detections: [b, c], previous: [a])[0] == 0)
        #expect(SceneFacePolicy.assignments(detections: [c], previous: [a]).isEmpty)
        let panned = TrackingBox(x: 0.40, y: 0.12, width: 0.20, height: 0.20)
        #expect(
            SceneFacePolicy.assignments(
                detections: [panned], previous: [a],
                maxCenterDistance: FaceTrackHold.motionMatchDistance)[0] == 0)
        #expect(
            SceneFacePolicy.assignments(
                detections: [c], previous: [a],
                maxCenterDistance: FaceTrackHold.motionMatchDistance
            )
            .isEmpty)
    }

    @Test func tapOnFaceBoxStartsTrackingWithThatRect() {
        let face = TrackingBox(x: 0.30, y: 0.20, width: 0.20, height: 0.28)
        let overlay = FocusOverlay.face(face)
        #expect(FaceTrackTap.boxIfTapped(overlay: overlay, x: 0.40, y: 0.34) == face)
        #expect(FaceTrackTap.boxIfTapped(overlay: overlay, x: 0.31, y: 0.21) == face)
        #expect(FaceTrackTap.boxIfTapped(overlay: overlay, x: 0.10, y: 0.10) == nil)
        #expect(FaceTrackTap.boxIfTapped(overlay: overlay, x: 0.80, y: 0.80) == nil)
        #expect(
            FaceTrackTap.boxIfTapped(overlay: .focus, x: 0.40, y: 0.34) == nil)
        #expect(
            FaceTrackTap.boxIfTapped(overlay: .search(face), x: 0.40, y: 0.34) == nil)
        #expect(
            FaceTrackTap.boxIfTapped(overlay: .subject(face), x: 0.40, y: 0.34) == nil)
        let extra = TrackingBox(x: 0.70, y: 0.20, width: 0.16, height: 0.22)
        #expect(
            FaceTrackTap.boxIfTapped(
                overlay: .subject(face), x: 0.78, y: 0.31, sceneFaces: [extra])
                == extra)
        #expect(
            FaceTrackTap.boxIfTapped(
                overlay: .subject(face), x: 0.40, y: 0.34, sceneFaces: [extra])
                == nil)
        // Bracket-edge slop.
        #expect(
            FaceTrackTap.boxIfTapped(overlay: overlay, x: 0.30 - 0.02, y: 0.34) == face)
        #expect(
            FaceTrackTap.boxIfTapped(overlay: overlay, x: 0.30 - 0.05, y: 0.34) == nil)
    }

    @Test func tapOnSmallFaceExpandsToMimoFloor() throws {
        let tiny = TrackingBox(x: 0.46, y: 0.46, width: 0.06, height: 0.07)
        let box = try #require(
            FaceTrackTap.boxIfTapped(overlay: .face(tiny), x: 0.49, y: 0.49))
        #expect(!box.isTooSmall)
        #expect(abs(box.centerX - tiny.centerX) < 0.0001)
        #expect(abs(box.centerY - tiny.centerY) < 0.0001)
        #expect(box.width >= TrackingBox.mimoMinimumSide)
        #expect(box.height >= TrackingBox.mimoMinimumSide)
        let large = TrackingBox(x: 0.20, y: 0.20, width: 0.30, height: 0.40)
        #expect(FaceTrackTap.trackingBox(from: large) == large)
    }

    @Test func nanoFeedTapDoesNotFirePocketFocusBurst() {
        #expect(
            LiveFeedTapPolicy.action(supportsTapFocus: false, tappedFace: false) == .ignore)
        #expect(
            LiveFeedTapPolicy.action(supportsTapFocus: false, tappedFace: true) == .trackFace)
        #expect(
            LiveFeedTapPolicy.action(supportsTapFocus: true, tappedFace: false) == .tapFocus)
        #expect(
            LiveFeedTapPolicy.action(supportsTapFocus: true, tappedFace: true) == .trackFace)
    }

    @Test func faceHoldSurvivesBriefMissAndDropsAfterTimeout() {
        let locked = TrackingBox(x: 0.40, y: 0.30, width: 0.20, height: 0.25)
        #expect(!FaceTrackHold.shouldDrop(secondsSinceHit: 0.15))
        #expect(FaceTrackHold.shouldDrop(secondsSinceHit: 0.22))
        let nearby = TrackingBox(x: 0.44, y: 0.32, width: 0.18, height: 0.24)
        #expect(
            FaceTrackHold.shouldAccept(detected: nearby, last: locked, secondsSinceHit: 0.10))
        let far = TrackingBox(x: 0.05, y: 0.70, width: 0.18, height: 0.22)
        #expect(!FaceTrackHold.shouldAccept(detected: far, last: locked, secondsSinceHit: 0.10))
        #expect(FaceTrackHold.shouldAccept(detected: far, last: locked, secondsSinceHit: 0.25))
        #expect(FaceTrackHold.shouldAccept(detected: far, last: nil, secondsSinceHit: 0))
    }

    @Test func faceHoldRejectsHandSizedLeftoverAndLowConfidence() {
        let locked = TrackingBox(x: 0.40, y: 0.30, width: 0.20, height: 0.25)
        let sliver = TrackingBox(x: 0.42, y: 0.32, width: 0.08, height: 0.10)
        #expect(
            !FaceTrackHold.shouldAccept(detected: sliver, last: locked, secondsSinceHit: 0.10))
        let nearby = TrackingBox(x: 0.44, y: 0.32, width: 0.18, height: 0.24)
        #expect(
            !FaceTrackHold.shouldAccept(
                detected: nearby, last: locked, secondsSinceHit: 0.10, confidence: 0.40))
        #expect(
            FaceTrackHold.shouldAccept(
                detected: nearby, last: locked, secondsSinceHit: 0.10, confidence: 0.90))
        let shifted = TrackingBox(x: 0.55, y: 0.30, width: 0.20, height: 0.25)
        #expect(
            !FaceTrackHold.shouldAccept(detected: shifted, last: locked, secondsSinceHit: 0.10))
    }

    @Test func gimbalPanDoesNotPinStillFrameLock() {
        let locked = TrackingBox(x: 0.40, y: 0.30, width: 0.20, height: 0.25)
        let panned = TrackingBox(x: 0.05, y: 0.32, width: 0.20, height: 0.25)
        #expect(
            !FaceTrackHold.shouldAccept(detected: panned, last: locked, secondsSinceHit: 0.12))
        #expect(
            FaceTrackHold.shouldAccept(
                detected: panned, last: locked, secondsSinceHit: 0.12, sceneMoving: true))
        #expect(
            !FaceTrackHold.shouldAccept(
                detected: panned, last: locked, secondsSinceHit: 0.12,
                confidence: 0.40, sceneMoving: true))
        #expect(!FaceTrackHold.shouldDrop(secondsSinceHit: 0.12, sceneMoving: true))
        #expect(FaceTrackHold.shouldDrop(secondsSinceHit: 0.18, sceneMoving: true))
        #expect(!FaceTrackHold.shouldDrop(secondsSinceHit: 0.18))
        #expect(FaceTrackHold.isSceneMoving(secondsSinceGimbal: 0))
        #expect(FaceTrackHold.isSceneMoving(secondsSinceGimbal: 0.29))
        #expect(!FaceTrackHold.isSceneMoving(secondsSinceGimbal: 0.30))
        #expect(!FaceTrackHold.isSceneMoving(secondsSinceGimbal: nil))
        let jumped = FaceTrackHold.follow(
            from: locked, toward: panned, dt: 1.0 / 25.0, sceneMoving: true)
        #expect(abs(jumped.centerX - panned.centerX) < 0.02)
        #expect(abs(jumped.width - panned.width) < 0.001)
        #expect(abs(jumped.height - panned.height) < 0.001)
        let tall = TrackingBox(x: 0.40, y: 0.22, width: 0.14, height: 0.28)
        let vision = FaceTrackHold.follow(
            from: locked, toward: tall, dt: 1.0 / 25.0, sceneMoving: false)
        #expect(abs(vision.width - tall.width) < 0.001)
        #expect(abs(vision.height - tall.height) < 0.001)
        #expect(abs(vision.width - vision.height) > 0.05, "Vision oval is not forced 1:1")
        let eased = FaceTrackHold.follow(
            from: locked, toward: TrackingBox(x: 0.41, y: 0.30, width: 0.20, height: 0.25),
            dt: 1.0 / 25.0, sceneMoving: true)
        #expect(eased != locked)
        #expect(eased.centerX > locked.centerX)
        #expect(eased.centerX < 0.51)
        let ducked = FaceTrackHold.follow(
            from: locked, toward: panned, dt: 1.0 / 25.0, sceneMoving: false)
        #expect(ducked != panned, "still frame must ease, not snap onto a pose flicker")
        #expect(ducked.centerX < locked.centerX)
        #expect(ducked.centerX > panned.centerX)
    }

    @Test func headTrackMergesJumpAndDropsGhost() throws {
        let here = TrackingBox(x: 0.50, y: 0.20, width: 0.18, height: 0.22)
        let ducked = TrackingBox(x: 0.18, y: 0.28, width: 0.17, height: 0.21)
        let stranger = TrackingBox(x: 0.78, y: 0.18, width: 0.10, height: 0.12)
        #expect(HeadTrackPolicy.isSameHead(here, ducked))
        #expect(!HeadTrackPolicy.isSameHead(here, stranger))
        #expect(!HeadTrackPolicy.shouldSpawn(detection: ducked, existing: [here]))
        #expect(HeadTrackPolicy.shouldSpawn(detection: stranger, existing: [here]))
        let merged = HeadTrackPolicy.mergeHits([
            FaceHit(box: here, confidence: 0.8, structured: false),
            FaceHit(box: ducked, confidence: 0.7, structured: false),
        ])
        #expect(merged.count == 1)
        #expect(
            FaceAFPick.primary(
                hits: [FaceHit(box: ducked, confidence: 0.8, structured: false)],
                hold: nil, last: here, secondsSinceHit: 0.08, sceneMoving: false) == nil,
            "still frame must not snap the lock onto a far pose")
        let jumped = try #require(
            FaceAFPick.primary(
                hits: [FaceHit(box: ducked, confidence: 0.8, structured: false)],
                hold: nil, last: here, secondsSinceHit: 0.08, sceneMoving: true))
        #expect(jumped.box == ducked)
    }

    @Test func personHoldKeepsHeadBoxWhenFaceTurnsAway() throws {
        let face = TrackingBox(x: 0.40, y: 0.18, width: 0.16, height: 0.20)
        let person = TrackingBox(x: 0.36, y: 0.16, width: 0.24, height: 0.62)
        #expect(FaceBodyFallback.shouldHold(lastFace: face, person: person))
        #expect(FaceBodyFallback.needsHold(faces: [], last: face))
        #expect(
            !FaceBodyFallback.needsHold(
                faces: [FaceHit(box: face, confidence: 0.9, structured: true)], last: face))
        // A cap / occiput oval overlapping the last face is not a reacquire.
        #expect(
            FaceBodyFallback.needsHold(
                faces: [FaceHit(box: face, confidence: 0.95, structured: false)], last: face))
        let head = try #require(FaceBodyFallback.heldHead(lastFace: face, person: person))
        // Top-centre of the person — not the last face centre (that is the occiput).
        #expect(abs(head.centerX - person.centerX) < 0.001)
        #expect(head.minY > person.minY + 0.01)
        #expect(head.centerY < person.centerY)
        #expect(head.maxY < person.minY + person.height * 0.60)
        #expect(isVisualSquare(head))
        let stranger = TrackingBox(x: 0.02, y: 0.70, width: 0.20, height: 0.25)
        #expect(!FaceBodyFallback.shouldHold(lastFace: face, person: stranger))
        #expect(FaceBodyFallback.heldHead(lastFace: face, person: stranger) == nil)
        #expect(FaceBodyFallback.bestHold(lastFace: face, people: [stranger, person]) == head)
        let walked = TrackingBox(x: 0.60, y: 0.10, width: 0.22, height: 0.70)
        let movedFace = TrackingBox(x: 0.20, y: 0.20, width: 0.14, height: 0.16)
        #expect(FaceBodyFallback.shouldHold(lastFace: movedFace, person: walked) == false)
        let trailing = TrackingBox(x: 0.50, y: 0.12, width: 0.16, height: 0.18)
        #expect(FaceBodyFallback.shouldHold(lastFace: trailing, person: walked))
        #expect(!walked.contains(x: trailing.centerX, y: trailing.centerY))
        let relocated = try #require(FaceBodyFallback.heldHead(lastFace: trailing, person: walked))
        #expect(relocated.minY > walked.minY + 0.01)
        #expect(relocated.centerY < walked.centerY)
        #expect(relocated.maxY < walked.minY + walked.height * 0.60)
        #expect(abs(relocated.centerX - walked.centerX) < 0.001)
        #expect(isVisualSquare(relocated))
    }

    @Test func poseHeadUsesEarsAndNeckNotTorso() throws {
        let face = TrackingBox(x: 0.42, y: 0.20, width: 0.14, height: 0.18)
        let head = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: face,
                neckX: 0.50, neckY: 0.38,
                leftEarX: 0.44, leftEarY: 0.24,
                rightEarX: 0.56, rightEarY: 0.24,
                leftShoulderX: 0.40, leftShoulderY: 0.48,
                rightShoulderX: 0.60, rightShoulderY: 0.48))
        #expect(head.centerY < 0.38)
        #expect(head.maxY <= 0.42)
        #expect(head.minY < 0.24)
        #expect(head.width < 0.40)
        #expect(isVisualSquare(head))
        let neckOnly = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: face,
                neckX: 0.50, neckY: 0.40,
                leftEarX: nil, leftEarY: nil,
                rightEarX: nil, rightEarY: nil,
                leftShoulderX: 0.42, leftShoulderY: 0.50,
                rightShoulderX: 0.58, rightShoulderY: 0.50))
        #expect(abs(neckOnly.centerX - 0.50) < 0.02)
        #expect(neckOnly.centerY < 0.40)
        #expect(
            FaceBodyFallback.headFromPose(
                lastFace: face,
                neckX: nil, neckY: nil,
                leftEarX: nil, leftEarY: nil,
                rightEarX: nil, rightEarY: nil,
                leftShoulderX: nil, leftShoulderY: nil,
                rightShoulderX: nil, rightShoulderY: nil) == nil)
    }

    @Test func poseHeadInProfileSpansEarToNoseNotOcciput() throws {
        let lastFace = TrackingBox(x: 0.38, y: 0.18, width: 0.14, height: 0.18)
        let head = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: lastFace,
                neckX: 0.48, neckY: 0.40,
                leftEarX: 0.40, leftEarY: 0.24,
                rightEarX: nil, rightEarY: nil,
                leftShoulderX: 0.42, leftShoulderY: 0.50,
                rightShoulderX: 0.56, rightShoulderY: 0.50,
                noseX: 0.58, noseY: 0.26))
        #expect(head.minX < 0.42)
        #expect(head.maxX > 0.56)
        #expect(head.centerX > 0.46)
        #expect(head.centerX < 0.56)
        #expect(head.centerY < 0.40)
        #expect(head.maxY < 0.48)
        #expect(isVisualSquare(head))
        let earNeckOnly = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: lastFace,
                neckX: 0.48, neckY: 0.40,
                leftEarX: 0.40, leftEarY: 0.24,
                rightEarX: nil, rightEarY: nil,
                leftShoulderX: 0.42, leftShoulderY: 0.50,
                rightShoulderX: 0.56, rightShoulderY: 0.50))
        #expect(head.maxX > earNeckOnly.maxX)
        #expect(head.centerX > earNeckOnly.centerX)
    }

    @Test func primaryPickFollowsHeadNotASecondOval() throws {
        let last = TrackingBox(x: 0.40, y: 0.16, width: 0.20, height: 0.24)
        let head = FaceHit(box: last, confidence: 0.80, structured: false)
        let stranger = FaceHit(
            box: TrackingBox(x: 0.78, y: 0.20, width: 0.14, height: 0.16),
            confidence: 0.90, structured: false)
        let picked = try #require(
            FaceAFPick.primary(
                hits: [stranger, head], hold: nil, last: last,
                secondsSinceHit: 0.1, sceneMoving: false))
        #expect(picked == head)
        let first = try #require(
            FaceAFPick.primary(
                hits: [head], hold: nil, last: nil,
                secondsSinceHit: .infinity, sceneMoving: false))
        #expect(first == head)
    }

    @Test func headFromFaceGrowsUpAndOutNotIntoChest() {
        let face = TrackingBox(x: 0.40, y: 0.22, width: 0.14, height: 0.16)
        let head = FaceBodyFallback.headFromFace(face)
        #expect(head.width > face.width)
        #expect(head.height > face.height)
        #expect(isVisualSquare(head))
        #expect(head.minY < face.minY)
        #expect(head.maxY >= face.maxY - 0.01)
        #expect(abs(head.centerX - face.centerX) < 0.001)
        #expect(head.width <= FaceBodyFallback.poseMaxSide)
        #expect(head.height <= FaceBodyFallback.poseMaxSide)
    }

    @Test func poseHeadIgnoresHugeLastFaceSize() throws {
        let huge = TrackingBox(x: 0.20, y: 0.02, width: 0.42, height: 0.52)
        let head = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: huge,
                neckX: 0.50, neckY: 0.38,
                leftEarX: 0.44, leftEarY: 0.24,
                rightEarX: 0.56, rightEarY: 0.24,
                leftShoulderX: 0.40, leftShoulderY: 0.48,
                rightShoulderX: 0.60, rightShoulderY: 0.48))
        #expect(head.width <= FaceBodyFallback.poseMaxSide)
        #expect(head.height <= FaceBodyFallback.poseMaxSide)
        #expect(isVisualSquare(head))
        #expect(head.height < huge.height)
        #expect(head.maxY < huge.maxY)
        #expect(head.maxY < 0.50)
    }

    @Test func faceStructureNeedsTwoEyesOrProfile() {
        #expect(
            FaceStructurePolicy.isLikelyFace(
                confidence: 0.95, leftEyeX: 0.30, rightEyeX: 0.70,
                leftEyePoints: 6, rightEyePoints: 6, nosePoints: 4))
        #expect(
            !FaceStructurePolicy.isLikelyFace(
                confidence: 0.95, leftEyeX: 0.48, rightEyeX: 0.52,
                leftEyePoints: 6, rightEyePoints: 6, nosePoints: 4))
        #expect(
            FaceStructurePolicy.isLikelyFace(
                confidence: 0.80, leftEyeX: 0.35, rightEyeX: nil,
                leftEyePoints: 6, rightEyePoints: 0, nosePoints: 4))
        #expect(
            !FaceStructurePolicy.isLikelyFace(
                confidence: 0.80, leftEyeX: nil, rightEyeX: nil,
                leftEyePoints: 0, rightEyePoints: 0, nosePoints: 0))
        #expect(
            FaceStructurePolicy.isLikelyFace(
                confidence: 0.92, leftEyeX: nil, rightEyeX: nil,
                leftEyePoints: 0, rightEyePoints: 0, nosePoints: 0))
        #expect(
            FaceStructurePolicy.hasFaceLandmarks(
                leftEyeX: 0.30, rightEyeX: 0.70,
                leftEyePoints: 6, rightEyePoints: 6, nosePoints: 4))
        #expect(
            !FaceStructurePolicy.hasFaceLandmarks(
                leftEyeX: nil, rightEyeX: nil,
                leftEyePoints: 0, rightEyePoints: 0, nosePoints: 0))
    }

    @Test func visionFaceBoxFlipsOriginToTopLeft() {
        let box = VisionFaceBox.fromVision(minX: 0.20, minY: 0.30, width: 0.25, height: 0.40)
        #expect(box?.x == 0.20)
        #expect(abs((box?.y ?? -1) - 0.30) < 0.0001)  // 1 - (0.30 + 0.40)
        #expect(box?.width == 0.25)
        #expect(box?.height == 0.40)
        #expect(VisionFaceBox.fromVision(minX: 0.4, minY: 0.4, width: 0.02, height: 0.02) == nil)
    }

    @Test func livePushIsIgnoredAfterOperatorClear() {
        #expect(TrackingClearPolicy.shouldApplyLivePush(operatorCleared: false))
        #expect(!TrackingClearPolicy.shouldApplyLivePush(operatorCleared: true))
        let now = Date()
        #expect(
            TrackingClearPolicy.shouldApplyLivePush(
                operatorClearedAt: now, now: now) == false)
        #expect(
            TrackingClearPolicy.shouldApplyLivePush(
                operatorClearedAt: now.addingTimeInterval(-0.30), now: now))
        #expect(TrackingClearPolicy.shouldApplyLivePush(operatorClearedAt: nil, now: now))
        #expect(
            !TrackingClearPolicy.shouldDropForSilence(
                lastPush: now.addingTimeInterval(-0.20), now: now))
        #expect(
            TrackingClearPolicy.shouldDropForSilence(
                lastPush: now.addingTimeInterval(-0.35), now: now))
    }

    @Test func lensStateCarriesCameraFocusPoint() {
        // mimo-tap-focus-20260818 after tap (0.772, 0.483).
        let tapped: [UInt8] = [
            0xB1, 0xC6, 0xB5, 0x45, 0x3F, 0xF7, 0x14, 0xF7, 0x3E, 0x00, 0xD9, 0x00,
            0x2C, 0x0A, 0xD9, 0x00,
        ]
        let point = CamLensState.focusPoint(tapped)
        #expect(point != nil)
        #expect(abs((point?.x ?? 0) - 0.772) < 0.001)
        #expect(abs((point?.y ?? 0) - 0.483) < 0.001)
        let idle: [UInt8] = [
            0xB1, 0x00, 0xFF, 0xFF, 0x3E, 0x00, 0xFF, 0xFF, 0x3E, 0x00, 0xD9, 0x00,
        ]
        let centre = CamLensState.focusPoint(idle)
        #expect(abs((centre?.x ?? 0) - 0.5) < 0.002)
        #expect(abs((centre?.y ?? 0) - 0.5) < 0.002)
        #expect(CamLensState.focusPoint([0xB1]) == nil)
        #expect(
            CameraFocusPolicy.shouldAdopt(
                currentX: 0.50, currentY: 0.50, cameraX: 0.77, cameraY: 0.48))
        #expect(
            !CameraFocusPolicy.shouldAdopt(
                currentX: 0.772, currentY: 0.483, cameraX: 0.773, cameraY: 0.484))

        var status = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_lens_state", value: tapped), to: &status))
        #expect(status.hasCameraFocusPoint)
        #expect(abs(status.focusX - 0.772) < 0.001)
        #expect(abs(status.focusY - 0.483) < 0.001)
        #expect(status.focusMode == .single)
    }

    @Test func focusResetShowsWhenOffCenterOrTracking() {
        #expect(!FocusResetPolicy.isAvailable(x: nil, y: nil, tracking: false))
        #expect(!FocusResetPolicy.isAvailable(x: 0.50, y: 0.50, tracking: false))
        #expect(!FocusResetPolicy.isAvailable(x: 0.53, y: 0.51, tracking: false))
        #expect(FocusResetPolicy.isAvailable(x: 0.55, y: 0.50, tracking: false))
        #expect(FocusResetPolicy.isAvailable(x: 0.50, y: 0.10, tracking: false))
        #expect(FocusResetPolicy.isAvailable(x: 0.50, y: 0.50, tracking: true))
        #expect(FocusResetPolicy.isAvailable(x: nil, y: nil, tracking: true))
    }

    @Test func faceHeadHandoffKeepsOneBoxAndWaitsToSwap() throws {
        let face = TrackingBox(x: 0.42, y: 0.20, width: 0.14, height: 0.16)
        let head = FaceBodyFallback.headFromFace(face)
        #expect(FaceHeadHandoff.faceBelongsToHead(face: face, head: head))
        #expect(FaceHeadHandoff.isSamePerson(face, head))
        #expect(
            !FaceHeadHandoff.faceBelongsToHead(
                face: face, head: TrackingBox(x: 0.78, y: 0.20, width: 0.16, height: 0.20)))

        #expect(
            FaceHeadHandoff.nextMode(
                current: .face, hasUsableFace: true, hasHead: true,
                faceVisibleFor: 1, faceMissingFor: 0) == .face)
        #expect(
            FaceHeadHandoff.nextMode(
                current: .face, hasUsableFace: false, hasHead: true,
                faceVisibleFor: 0, faceMissingFor: 0.10) == .face,
            "brief miss must not flip to head")
        #expect(
            FaceHeadHandoff.nextMode(
                current: .face, hasUsableFace: false, hasHead: true,
                faceVisibleFor: 0, faceMissingFor: FaceHeadHandoff.faceLostDuration)
                == .head)
        #expect(
            FaceHeadHandoff.nextMode(
                current: .head, hasUsableFace: true, hasHead: true,
                faceVisibleFor: 0.08, faceMissingFor: 0) == .head,
            "brief face flicker must not leave head")
        #expect(
            FaceHeadHandoff.nextMode(
                current: .head, hasUsableFace: true, hasHead: true,
                faceVisibleFor: FaceHeadHandoff.faceRecoverDuration, faceMissingFor: 0)
                == .face)

        let faceHit = FaceHit(box: face, confidence: 0.92, structured: true)
        let facing = HeadLock.fuse(faces: [faceHit], poses: [head], last: face)
        #expect(facing.count == 1)
        #expect(facing.first?.structured == true)
        let painted = try #require(facing.first?.box)
        #expect(painted.width + 0.001 >= face.width)
        #expect(painted.height + 0.001 >= face.height)
        #expect(painted.intersectionArea(face) / face.area > 0.9)
        #expect(isVisualSquare(painted))

        let stillFace = HeadLock.fuse(
            faces: [], poses: [head], last: face, lastMode: .face,
            faceVisibleFor: 0, faceMissingFor: 0.10)
        #expect(
            stillFace.isEmpty, "grace holds the last face in CameraSession, does not add a head")

        let turned = HeadLock.fuse(
            faces: [], poses: [head], last: face, lastMode: .face,
            faceVisibleFor: 0, faceMissingFor: FaceHeadHandoff.faceLostDuration)
        #expect(turned.count == 1)
        #expect(turned.first?.structured == false)

        let flicker = HeadLock.fuse(
            faces: [faceHit], poses: [head], last: head, lastMode: .head,
            faceVisibleFor: 0.08, faceMissingFor: 0)
        #expect(flicker.count == 1)
        #expect(flicker.first?.structured == false, "recover wait keeps the head")

        let back = HeadLock.fuse(
            faces: [faceHit], poses: [head], last: head, lastMode: .head,
            faceVisibleFor: FaceHeadHandoff.faceRecoverDuration, faceMissingFor: 0)
        #expect(back.count == 1)
        let recovered = try #require(back.first?.box)
        #expect(recovered.intersectionArea(face) / face.area > 0.9)
        #expect(isVisualSquare(recovered))

        #expect(
            SceneFacePolicy.dimmed(faces: [face, head], hiding: face).isEmpty,
            "padded head must not sit next to its own face")
        #expect(FaceHeadHandoff.pickBox(mode: .face, face: face, head: head) == face)
        #expect(FaceHeadHandoff.pickBox(mode: .head, face: face, head: head) == head)
    }

    @Test func headLockPrefersFaceAndRejectsChairPose() throws {
        let face = FaceHit(
            box: TrackingBox(x: 0.42, y: 0.18, width: 0.14, height: 0.18),
            confidence: 0.92, structured: true)
        let chair = TrackingBox(x: 0.08, y: 0.22, width: 0.16, height: 0.22)
        let last = TrackingBox(x: 0.40, y: 0.16, width: 0.20, height: 0.24)
        let fused = HeadLock.fuse(faces: [face], poses: [chair], last: last)
        #expect(fused.count == 1)
        let head = try #require(fused.first)
        #expect(head.structured)
        #expect(abs(head.box.centerX - face.box.centerX) < 0.04)
        #expect(head.box.centerX > 0.35)
        let poseOnly = HeadLock.fuse(faces: [], poses: [chair], last: last)
        #expect(poseOnly.isEmpty, "pose on the chair must not steal a still lock")
        let poseHold = HeadLock.fuse(
            faces: [],
            poses: [TrackingBox(x: 0.41, y: 0.17, width: 0.18, height: 0.22)],
            last: last)
        #expect(poseHold.count == 1)
        let moving = HeadLock.fuse(
            faces: [], poses: [chair], last: last, sceneMoving: true)
        #expect(moving.count == 1, "gimbal may translate the whole scene")
    }

    @Test func headBoxScalesUniformlyWithPoseHull() throws {
        let far = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: nil,
                neckX: 0.50, neckY: 0.34,
                leftEarX: 0.485, leftEarY: 0.30,
                rightEarX: 0.515, rightEarY: 0.30,
                leftShoulderX: 0.47, leftShoulderY: 0.40,
                rightShoulderX: 0.53, rightShoulderY: 0.40))
        let near = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: nil,
                neckX: 0.50, neckY: 0.42,
                leftEarX: 0.40, leftEarY: 0.22,
                rightEarX: 0.60, rightEarY: 0.22,
                leftShoulderX: 0.34, leftShoulderY: 0.52,
                rightShoulderX: 0.66, rightShoulderY: 0.52))
        #expect(isVisualSquare(far))
        #expect(isVisualSquare(near))
        #expect(far.height < 0.16, "distant head must not sit on the old 0.18 floor")
        #expect(near.height > far.height * 1.6)
        #expect(abs(far.width / far.height - near.width / near.height) < 0.001)
        let small = FaceBodyFallback.squareHead(
            centerX: 0.50, centerY: 0.30, width: 0.05, height: 0.06)
        let large = FaceBodyFallback.squareHead(
            centerX: 0.50, centerY: 0.30, width: 0.20, height: 0.24)
        #expect(isVisualSquare(small))
        #expect(isVisualSquare(large))
        #expect(small.height < large.height)
        #expect(abs(small.width / small.height - large.width / large.height) < 0.001)
    }

    @Test func coveringBoxUsesFaceAndPoseExtent() {
        let face = TrackingBox(x: 0.42, y: 0.22, width: 0.12, height: 0.14)
        let pose = TrackingBox(x: 0.38, y: 0.16, width: 0.22, height: 0.24)
        let cover = FaceBodyFallback.coveringBox(face: face, head: pose)
        #expect(cover != nil)
        #expect(cover!.minX <= min(face.minX, pose.minX) + 0.001)
        #expect(cover!.maxX + 0.001 >= max(face.maxX, pose.maxX))
        #expect(cover!.minY <= min(face.minY, pose.minY) + 0.001)
        #expect(isVisualSquare(cover!))
        let faceOnly = FaceBodyFallback.coveringBox(face: face, head: nil)
        #expect(faceOnly != nil)
        #expect(faceOnly!.width > face.width)
        #expect(faceOnly!.height > face.height)
        #expect(isVisualSquare(faceOnly!))
    }

    @Test func eyeOnlyPoseIsHeadSizedNotFeatureSquare() throws {
        let box = try #require(
            FaceBodyFallback.headFromPose(
                lastFace: nil,
                neckX: 0.50, neckY: 0.36,
                leftEarX: nil, leftEarY: nil,
                rightEarX: nil, rightEarY: nil,
                leftShoulderX: 0.40, leftShoulderY: 0.48,
                rightShoulderX: 0.60, rightShoulderY: 0.48,
                noseX: 0.50, noseY: 0.30,
                leftEyeX: 0.44, leftEyeY: 0.28,
                rightEyeX: 0.56, rightEyeY: 0.28))
        let eyeSpan = 0.12
        #expect(
            box.width * FaceBodyFallback.defaultPictureAspect + 0.001
                >= eyeSpan * FaceBodyFallback.eyeSpanToHead)
        #expect(isVisualSquare(box))
        #expect(box.height > 0.20)
    }

    @Test func squareHeadPaintsOneToOneOnSixteenByNine() {
        let aspect = FaceBodyFallback.defaultPictureAspect
        #expect(abs(aspect - 16.0 / 9.0) < 0.0001)
        let equalNorm = FaceBodyFallback.squareHead(
            centerX: 0.50, centerY: 0.30, width: 0.22, height: 0.22)
        #expect(isVisualSquare(equalNorm, aspect: aspect))
        #expect(equalNorm.height > equalNorm.width)
        // Independent 0…1 mapping onto 16:9 must not paint a wide rectangle.
        let paintedW = equalNorm.width * 1920
        let paintedH = equalNorm.height * 1080
        #expect(abs(paintedW - paintedH) < 1)
        let wideHull = FaceBodyFallback.squareHead(
            centerX: 0.50, centerY: 0.30, width: 0.28, height: 0.14)
        #expect(isVisualSquare(wideHull, aspect: aspect))
        #expect(abs(FaceBodyFallback.pictureAspect(width: 1920, height: 1080) - aspect) < 0.0001)
        #expect(FaceBodyFallback.pictureAspect(width: 0, height: 1080) == aspect)
        #expect(FaceBodyFallback.sanitizedPictureAspect(.nan) == aspect)
        // Square picture keeps equal stored sides.
        let squarePic = FaceBodyFallback.squareHead(
            centerX: 0.50, centerY: 0.30, width: 0.20, height: 0.20,
            pictureAspect: 1)
        #expect(abs(squarePic.width - squarePic.height) < 0.001)
    }

    @Test func liveControlIncludesTrackingOpcodes() {
        #expect(Duml.isLiveCameraControl(set: 0x02, cmd: 0xA5))
        #expect(Duml.isLiveCameraControl(set: 0x02, cmd: 0xA6))
        #expect(Duml.shouldHoldReply(set: 0x02, cmd: 0xA6))
    }

    private func isVisualSquare(
        _ box: TrackingBox, aspect: Double = FaceBodyFallback.defaultPictureAspect
    ) -> Bool {
        abs(box.width * aspect - box.height) < 0.001
    }

    private func floatLE(_ v: Float) -> [UInt8] {
        var le = v.bitPattern.littleEndian
        return withUnsafeBytes(of: &le) { Array($0) }
    }
}
