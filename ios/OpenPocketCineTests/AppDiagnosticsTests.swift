import OpenCineAppKit
import XCTest

@testable import OpenPocketCine

/// The holder wires the host values this app shipped with before diagnostics moved to OpenCine.
final class AppDiagnosticsTests: XCTestCase {
    func testHolderWiresThisAppsNamesDestinationAndRedaction() {
        let host = AppDiagnostics.host
        XCTAssertEqual(host.product, "OpenPocketCine")
        XCTAssertEqual(host.listingName, "OpenPocketCine")
        XCTAssertEqual(
            host.release(version: "0.1.0", build: "107"), "com.opencapture.openpocketcine@0.1.0+107")
        XCTAssertEqual(host.supportEmail, "support@openpocketcine.app")
        // Tests run a development build: reinstalls must not read as watchdog kills.
        XCTAssertEqual(host.environment, "development")
        XCTAssertFalse(host.tracksWatchdogTerminations)
        XCTAssertEqual(AppDiagnostics.gate.cameraIPv4Prefix, "192.168.2.")
        // DJI redaction: the camera's access point stays readable, other networks do not.
        XCTAssertEqual(host.redact("ssid=OsmoPocket3-A1B2"), "ssid=OsmoPocket3-A1B2")
        XCTAssertEqual(host.redact("ssid=CafeWiFi"), "ssid=<redacted>")
        XCTAssertTrue(AppDiagnostics.reporting.gate === AppDiagnostics.gate)
        XCTAssertTrue(AppDiagnostics.reporting.consent === AppDiagnostics.consent)
        XCTAssertTrue(AppDiagnostics.reporting.origin === AppDiagnostics.origin)
        XCTAssertEqual(ReliabilityReportingConsent.defaultsKey, "opc.reliabilityReporting.optIn")
    }
}
