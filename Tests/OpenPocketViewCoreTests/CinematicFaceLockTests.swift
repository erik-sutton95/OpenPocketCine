import Foundation
import Testing

@testable import OpenPocketViewCore

@Suite struct CinematicFaceLockTests {
    private func face(_ x: Double, width: Double = 0.1, confidence: Double = 0.95) -> FaceHit {
        FaceHit(
            box: TrackingBox(x: x - width / 2, y: 0.3, width: width, height: 0.15),
            confidence: confidence)
    }

    @Test func followsSelectedFaceInsteadOfLargerBystander() throws {
        var lock = CinematicFaceLock(box: face(0.3).box, measuredAt: 0)
        for step in 1...20 {
            let x = 0.3 + Double(step) * 0.009
            let chosen = lock.update(
                faces: [face(0.8, width: 0.2), face(x)],
                measuredAt: Double(step) * 0.04, minimumConfidence: 0.5)
            #expect(try #require(chosen).box.centerX == x)
        }
    }

    @Test func briefMissRetainsAnchorAndCanRecoverNearby() throws {
        var lock = CinematicFaceLock(box: face(0.3).box, measuredAt: 1)
        #expect(lock.update(faces: [], measuredAt: 1.1, minimumConfidence: 0.5) == nil)
        #expect(lock.measuredAt == 1)
        #expect(
            lock.update(faces: [face(0.8)], measuredAt: 1.2, minimumConfidence: 0.5) == nil)
        let recovered = lock.update(
            faces: [face(0.31)], measuredAt: 1.5, minimumConfidence: 0.5)
        #expect(try #require(recovered).box == face(0.31).box)
    }

    @Test func crossingFacesAndLongLossCannotSwitchSubjects() {
        var lock = CinematicFaceLock(box: face(0.4).box, measuredAt: 0)
        #expect(
            lock.update(
                faces: [face(0.38), face(0.42)], measuredAt: 0.04, minimumConfidence: 0.5) == nil)
        #expect(lock.measuredAt == 0)
        #expect(lock.isAmbiguous)
        #expect(
            lock.update(faces: [face(0.4)], measuredAt: 0.08, minimumConfidence: 0.5) == nil,
            "The remaining face after a crossing is not proof of the selected person's identity")
        #expect(
            lock.update(faces: [face(0.4)], measuredAt: 1.01, minimumConfidence: 0.5) == nil)
    }

    @Test func lowerConfidenceCanBridgeAValidDetectionWithoutAcceptingAJunkHit() {
        var lock = CinematicFaceLock(box: face(0.4).box, measuredAt: 0)
        #expect(
            lock.update(
                faces: [face(0.4, confidence: 0.55)], measuredAt: 0.04, minimumConfidence: 0.5)
                != nil)
        #expect(
            lock.update(
                faces: [face(0.4, confidence: 0.35)], measuredAt: 0.08, minimumConfidence: 0.5)
                == nil)
    }

    @Test func weakStaleAndImplausibleScaleDetectionsDoNotRefreshLock() {
        var lock = CinematicFaceLock(box: face(0.4).box, measuredAt: 1)
        for (hit, time) in [
            (face(0.4, confidence: 0.4), 1.1), (face(0.4), 0.9),
            (face(0.4, width: 0.4), 1.1), (face(0.4), Double.nan),
        ] {
            #expect(lock.update(faces: [hit], measuredAt: time, minimumConfidence: 0.5) == nil)
            #expect(lock.measuredAt == 1)
        }
    }

    @Test func singlePersonDragUsesTheirFaceButGroupSelectionStaysAnObject() {
        let selection = TrackingBox(x: 0.1, y: 0.1, width: 0.8, height: 0.8)
        #expect(CinematicFaceLock.selectedFace(in: selection, faces: [face(0.4)]) == face(0.4))
        #expect(
            CinematicFaceLock.selectedFace(in: selection, faces: [face(0.3), face(0.7)]) == nil)
    }
}
