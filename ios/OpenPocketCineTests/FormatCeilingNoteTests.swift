import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// The ceiling note has to survive the shutter-angle rematch that follows a
/// format change. Angle mode rewrites 1/N for the new fps, and that send used
/// to clear the note the format change had just written.
@MainActor
final class FormatCeilingNoteTests: XCTestCase {
    private static let pocket3 = CameraModel.resolve(modelId: nil, name: "OsmoPocket3-Test")

    /// 1080/60 held at 12×, manual expo on 1/120. 4K caps this body well below
    /// 12×, so the change earns a ceiling note.
    private func pocket3Session() -> CameraSession {
        let session = CameraSession(borrowing: HevcDecoder())
        // An unopened driver admits the command without opening a socket.
        let driver = DatalinkDriver(port: 9004, tcpPoke: false, pairingToken: "")
        let camera = FoundCamera(
            id: UUID(), name: "OsmoPocket3-Test", model: Self.pocket3, modelId: nil)
        var status = CameraStatus()
        status.shootingMode = Int(ShootingMode.video.rawValue)
        status.videoFormat = VideoFormat(resolution: .p1080, frameRate: .fps60)
        status.videoResolution = .p1080
        status.fps = 60
        status.expoMode = .manual
        status.shutterDenom = 120
        status.zoomFactorRaw = CamFov.rawAt12x
        session.updateMultiview(camera: camera, driver: driver, status: status)
        return session
    }

    /// What the operator should be told after moving to 4K while held past its
    /// ceiling — derived from the model rather than spelled out, so the test
    /// follows the stop table instead of pinning a second copy of it.
    private func expectedNote(_ session: CameraSession) -> String? {
        CamFov.ceilingNote(
            size: VideoResolution.p4K.sizeTitle,
            held: session.status.zoomFactor ?? 0,
            stops: Self.pocket3.activeZoomStops(
                resolution: .p4K, shootingMode: Int(ShootingMode.video.rawValue)))
    }

    /// 1080/60 at 12× to 4K/30 with a 180° shutter: the rematch calls
    /// `setShutterDenom` after the note is written, which used to clear it
    /// before the operator could see it.
    func testCeilingNoteSurvivesTheShutterAngleRematch() {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        defer {
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let session = pocket3Session()
        defer { session.disconnect() }
        let expected = expectedNote(session)
        XCTAssertNotNil(expected, "Fixture must actually be held past the 4K ceiling")
        // 180° at 60 fps is 1/120; at 30 fps it is 1/60. The rematch only fires
        // because those differ, so the clearing send really does run.
        XCTAssertEqual(ShutterAngle.denom(degrees: 180, fps: 60, available: []), 120)
        XCTAssertNotEqual(ShutterAngle.denom(degrees: 180, fps: 30, available: []), 120)

        session.setVideoFormat(resolution: .p4K, frameRate: .fps30, fromOperator: false)

        XCTAssertEqual(session.status.fps, 30, "The rematch only runs when fps changed")
        XCTAssertEqual(
            session.controlNote, expected, "The rematch must not clear the ceiling note")
    }

    /// Without angle mode no rematch runs, so nothing clears the note. Keeps
    /// the test above honest if the rematch ever stops firing there.
    func testCeilingNoteIsWrittenWhenNoRematchRuns() {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        defer { OperatorPrefs.shutterUsesAngle = usesAngle }
        OperatorPrefs.shutterUsesAngle = false
        let session = pocket3Session()
        defer { session.disconnect() }
        let expected = expectedNote(session)
        XCTAssertNotNil(expected)

        session.setVideoFormat(resolution: .p4K, frameRate: .fps30, fromOperator: false)

        XCTAssertEqual(session.controlNote, expected)
    }

    /// A failed format send leaves its own note, and that one outranks the
    /// ceiling note — the operator needs to know the change did not go.
    func testFailedFormatSendKeepsItsNoteThroughTheRematch() {
        let usesAngle = OperatorPrefs.shutterUsesAngle
        let degrees = OperatorPrefs.shutterAngleDegrees
        defer {
            OperatorPrefs.shutterUsesAngle = usesAngle
            OperatorPrefs.shutterAngleDegrees = degrees
        }
        OperatorPrefs.shutterUsesAngle = true
        OperatorPrefs.shutterAngleDegrees = 180
        let session = pocket3Session()
        defer { session.disconnect() }
        // No transport: `fireCamera` takes its early out and writes the failure.
        session.datalink = nil

        session.setVideoFormat(resolution: .p4K, frameRate: .fps30, fromOperator: false)

        XCTAssertEqual(
            session.controlNote, "not live",
            "A send failure outranks the ceiling note and must survive the rematch")
    }
}
