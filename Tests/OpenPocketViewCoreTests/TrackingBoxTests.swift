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

    static let overlaySearch = TrackingBox(x: 0.2, y: 0.2, width: 0.5, height: 0.5)
    static let overlayCamera = TrackingBox(x: 0.41, y: 0.33, width: 0.16, height: 0.20)

    @Test(
        arguments: [
            (false, nil, nil, FocusOverlay.focus),
            (
                true, Self.overlaySearch, nil,
                .subject(TrackingBox.subject(from: Self.overlaySearch))
            ),
            (true, Self.overlaySearch, Self.overlayCamera, .subject(Self.overlayCamera)),
        ] as [(Bool, TrackingBox?, TrackingBox?, FocusOverlay)])
    func overlayResolvesFocusOrSubject(
        tracking: Bool, search: TrackingBox?, subject: TrackingBox?, expected: FocusOverlay
    ) {
        #expect(
            FocusOverlayPolicy.resolve(tracking: tracking, search: search, subject: subject)
                == expected)
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
        #expect(TrackingBox(x: 0.40, y: 0.40, width: 0.05, height: 0.05).isTooSmall)
        #expect(!TrackingBox(x: 0.40, y: 0.40, width: 0.12, height: 0.20).isTooSmall)
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
        // Padded head grown from `face`: it owns the face, so the two never paint side by side.
        let face = TrackingBox(x: 0.42, y: 0.20, width: 0.14, height: 0.16)
        let head = TrackingBox(x: 0.36, y: -0.08, width: 0.26, height: 0.46)
        #expect(FaceHeadHandoff.faceBelongsToHead(face: face, head: head))
        #expect(FaceHeadHandoff.isSamePerson(face, head))
        #expect(
            !FaceHeadHandoff.faceBelongsToHead(
                face: face, head: TrackingBox(x: 0.78, y: 0.20, width: 0.16, height: 0.20)))
        #expect(
            SceneFacePolicy.dimmed(faces: [face, head], hiding: face).isEmpty,
            "padded head must not sit next to its own face")
        let a = TrackingBox(x: 0.10, y: 0.10, width: 0.20, height: 0.20)
        let b = TrackingBox(x: 0.12, y: 0.11, width: 0.20, height: 0.20)
        let c = TrackingBox(x: 0.70, y: 0.10, width: 0.20, height: 0.20)
        #expect(SceneFacePolicy.assignments(detections: [b, c], previous: [a])[0] == 0)
        #expect(SceneFacePolicy.assignments(detections: [c], previous: [a]).isEmpty)
        let panned = TrackingBox(x: 0.40, y: 0.12, width: 0.20, height: 0.20)
        #expect(
            SceneFacePolicy.assignments(
                detections: [panned], previous: [a],
                maxCenterDistance: HeadTrackPolicy.jumpDistance)[0] == 0)
        #expect(
            SceneFacePolicy.assignments(
                detections: [c], previous: [a],
                maxCenterDistance: HeadTrackPolicy.jumpDistance
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

    @Test func gamepadCrossTracksFaceOrCancels() {
        let face = TrackingBox(x: 0.30, y: 0.20, width: 0.20, height: 0.28)
        let extra = TrackingBox(x: 0.70, y: 0.20, width: 0.10, height: 0.12)
        #expect(
            GamepadFaceTrack.action(
                trackingActive: true, overlay: .face(face), sceneFaces: [])
                == .cancel)
        #expect(
            GamepadFaceTrack.action(
                trackingActive: true, overlay: .subject(face), sceneFaces: [extra])
                == .cancel)
        #expect(
            GamepadFaceTrack.action(
                trackingActive: false, overlay: .face(face), sceneFaces: [extra])
                == .track(face))
        #expect(
            GamepadFaceTrack.action(
                trackingActive: false, overlay: .focus, sceneFaces: [extra, face])
                == .track(face))
        #expect(
            GamepadFaceTrack.action(
                trackingActive: false, overlay: .focus, sceneFaces: [])
                == .none)
        let tiny = TrackingBox(x: 0.46, y: 0.46, width: 0.06, height: 0.07)
        if case .track(let box) =
            GamepadFaceTrack.action(
                trackingActive: false, overlay: .face(tiny), sceneFaces: [])
        {
            #expect(!box.isTooSmall)
        } else {
            Issue.record("expected track")
        }
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
        // A stale pre-tap point must not pull the fresh tap back.
        #expect(
            !CameraFocusPolicy.shouldAdopt(
                currentX: 0.77, currentY: 0.48, cameraX: 0.50, cameraY: 0.50, secondsSinceTap: 0.2))
        #expect(
            CameraFocusPolicy.shouldAdopt(
                currentX: 0.77, currentY: 0.48, cameraX: 0.50, cameraY: 0.50, secondsSinceTap: 2))

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

    private func floatLE(_ v: Float) -> [UInt8] {
        var le = v.bitPattern.littleEndian
        return withUnsafeBytes(of: &le) { Array($0) }
    }
}
