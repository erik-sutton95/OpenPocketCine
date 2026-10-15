import OpenCineDJIApple
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// SIMULATED native mailbox and telemetry; the endpoint opens no camera socket.
@MainActor
final class NativeIsoAdmissionTests: XCTestCase {
    func testAnExplicitNativeHopRetainsItsAwaitingObservationBehavior() {
        let saved = OperatorPrefs.nativeISOHopEnabled
        OperatorPrefs.nativeISOHopEnabled = true
        defer { OperatorPrefs.nativeISOHopEnabled = saved }
        let session = fixture(nativeISO: .init(hop: true))
        defer { session.disconnect() }
        session.setColorMode(.dLog2)
        var value = [UInt8](repeating: 0, count: 23)
        value[2] = 50
        value[3] = 0x80
        value[5] = IsoIndex.iso800.rawValue
        value[7] = ExpoMode.manual.rawValue
        value[16] = 0x20
        value[17] = 0x03
        session.applyIncomingStatus(
            Duml.Frame(
                sender: 0, receiver: 0, seq: 0, flags: 0,
                cmdSet: 0, cmdId: 0x99,
                payload: SubscribePush.pack(name: "cam_expo_param", value: value)))
        XCTAssertEqual(
            session.status.isoIndex, .iso400,
            "A declared hop retains its bounded pin until its requested native ISO is reported")
    }

    func testAnUndeclaredNativeHopCannotHoldBackAnActualIsoReport() {
        let saved = OperatorPrefs.nativeISOHopEnabled
        OperatorPrefs.nativeISOHopEnabled = true
        defer { OperatorPrefs.nativeISOHopEnabled = saved }
        let session = fixture()
        defer { session.disconnect() }
        session.setColorMode(.dLog2)
        var value = [UInt8](repeating: 0, count: 23)
        value[2] = 50
        value[3] = 0x80
        value[5] = IsoIndex.iso800.rawValue
        value[7] = ExpoMode.manual.rawValue
        value[16] = 0x20
        value[17] = 0x03
        session.applyIncomingStatus(
            Duml.Frame(
                sender: 0, receiver: 0, seq: 0, flags: 0,
                cmdSet: 0, cmdId: 0x99,
                payload: SubscribePush.pack(name: "cam_expo_param", value: value)))
        XCTAssertEqual(
            session.status.isoIndex, .iso800,
            "The saved preference cannot invent a native ISO request that hides actual telemetry")
        XCTAssertEqual(session.status.iso, 800)
    }

    func testAnUndeclaredCeilingCannotCreateAnOptimisticLimit() {
        let session = fixture()
        defer { session.disconnect() }
        XCTAssertNil(session.status.isoLimit)
        session.setIsoLimit(.max800)
        XCTAssertNil(session.status.isoLimit, "No writable native ceiling was declared")
    }

    func testExplicitNativeDeclarationsReachTheHostAndRetainTheDeclaredCeiling() {
        let session = fixture(nativeISO: .init(hop: true, ceiling: true))
        defer { session.disconnect() }
        let model = AppModel(session: session)
        XCTAssertTrue(model.captureCapabilities.nativeIsoHop)
        XCTAssertTrue(model.captureCapabilities.isoLimit)
        session.setIsoLimit(.max800)
        XCTAssertEqual(session.status.isoLimit, .max800)
    }

    func testKnownUnsupportedNativeServicesRetainTheirFalseDeclarations() {
        let session = fixture(nativeISO: .init(hop: false, ceiling: false))
        defer { session.disconnect() }
        XCTAssertEqual(session.nativeISOCapabilities.hop, false)
        XCTAssertEqual(session.nativeISOCapabilities.ceiling, false)
        session.setIsoLimit(.max800)
        XCTAssertNil(session.status.isoLimit)
    }

    private func fixture(nativeISO: CaptureNativeISOCapabilities = .init())
        -> OpenPocketCine.CameraSession
    {
        let session = OpenPocketCine.CameraSession(borrowing: HevcDecoder())
        var status = CameraStatus()
        status.shootingMode = 1
        status.expoMode = .manual
        status.colorMode = .dLog
        status.isoIndex = .iso400
        status.iso = 400
        status.availableColorModes = [.dLog, .dLog2]
        var body = CameraModel.resolve(modelId: 0x22, name: "SIMULATED")
        var profile = body.captureProfile ?? CameraCaptureProfile()
        profile.nativeISO = nativeISO
        body.captureProfile = profile
        session.updateMultiview(
            camera: DjiAppleSighting(
                id: UUID(), name: "SIMULATED",
                model: body, modelId: 0x22),
            driver: DjiAppleDatalink(port: 9004, tcpPoke: false, pairingToken: ""), status: status)
        return session
    }
}
