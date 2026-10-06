import MonitorPresentation
import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// The cameras and pair pages in the words main showed (its `OsmoCameraPageAdapter`): the four
/// Pocket and Nano pages, the pre-check and still-looking hint, a Bluetooth failure with main's
/// action, and the nearby card.
@MainActor
final class CameraPagePresentationTests: XCTestCase {
    func testScanShowsTheFourPagesThePreCheckThenStillLookingHint() {
        let model = AppModel()
        var page = CamerasMapping.wizard(model.cameras, model.pairingWizard())
        XCTAssertEqual(
            page.steps.map(\.title),
            ["Find your camera", "Approve on the camera", "Join camera Wi-Fi", "Open video link"])
        XCTAssertEqual(
            page.body,
            "Turn the camera on and keep the phone nearby. Pocket and Nano both appear. Choose the one you want.")
        XCTAssertEqual(
            page.instructions.first?.lines, ["Before pairing, turn off DJI Frame Tap and force quit DJI Mimo."])
        model.session.scanLooksEmpty = true
        page = CamerasMapping.wizard(model.cameras, model.pairingWizard())
        XCTAssertEqual(page.instructions.count, 1)
        XCTAssertEqual(
            page.instructions.first?.lines,
            [
                "Turn off DJI Frame Tap and force quit DJI Mimo on every phone near the camera. Make sure the camera is on and activated, then move closer."
            ])
        let wizard = model.pairingWizard()
        XCTAssertEqual(Array(wizard.bodies.dropFirst()), [
            "If the camera shows Approve, tap it on that camera's screen. First-time pairing can wait up to 90 seconds.",
            "We read the camera's network over Bluetooth, then join its Wi-Fi for you.",
            "Exposure, LUTs and scopes go live as soon as the video link is up.",
        ])
        XCTAssertEqual(wizard.approveLines, ["Look for an Approve / pairing prompt", "Tap it on the camera screen"])
        XCTAssertEqual(
            wizard.joinLines,
            ["Leave the camera on. It brings up its own Wi-Fi", "On 5.8 GHz that can take about a minute; we keep trying"])
        XCTAssertEqual(wizard.label, "Scanning for camera…")
    }

    func testBluetoothFailuresShowMainsErrorAndAction() {
        let model = AppModel()
        model.session.phase = .failed(StartupConnectionCopy.bluetoothDenied)
        var page = CamerasMapping.wizard(model.cameras, model.pairingWizard())
        XCTAssertEqual(page.error, StartupConnectionCopy.bluetoothDenied)
        XCTAssertEqual(page.primaryAction, "Open Settings")
        XCTAssertTrue(page.primaryActionEnabled)
        XCTAssertNil(page.progress)
        XCTAssertTrue(page.instructions.isEmpty)
        model.session.phase = .failed(StartupConnectionCopy.bluetoothOff)
        page = CamerasMapping.wizard(model.cameras, model.pairingWizard())
        XCTAssertEqual(page.error, StartupConnectionCopy.bluetoothOff)
        XCTAssertEqual(page.primaryAction, "Try again")
        for raw in [
            "camera never answered the datalink handshake",
            "camera Wi-Fi path was not ready for the datalink",
        ] {
            XCTAssertEqual(StartupConnectionCopy.friendly(raw), StartupConnectionCopy.datalinkSilent)
        }
    }

    func testANearbyCameraReadsAsMain() {
        let camera = NearbyCamera(
            id: "n1", name: "OsmoPocket3-4D5E", model: "Osmo Pocket 3", routes: [.cameraAccessPoint])
        XCTAssertEqual(
            AppModel.nearbyCard(camera, verified: true),
            NearbyCardCopy(
                name: "OsmoPocket3-4D5E", subtitle: "Pocket · Osmo Pocket 3 · nearby",
                status: "Needs approval on the camera"))
        XCTAssertEqual(
            AppModel.nearbyCard(camera, verified: false).subtitle, "Pocket · Osmo Pocket 3 · nearby · unverified")
        let nameless = NearbyCamera(id: "n2", name: "DJI Camera", model: "Osmo Nano", routes: [.cameraAccessPoint])
        XCTAssertEqual(AppModel.nearbyCard(nameless, verified: nil).name, "Osmo Nano")
        XCTAssertEqual(AppModel.nearbyCard(nameless, verified: nil).subtitle, "Nano · nearby")
    }
}
