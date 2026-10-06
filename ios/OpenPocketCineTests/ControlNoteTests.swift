import OpenCineAppKit
import OpenCineCore
import XCTest

@testable import OpenPocketCine

/// Pocket main's write notes came from the session's send path ("ISO 800: <camera message>" on a
/// refusal) and stayed silent on a timeout or a write the camera did not show.
@MainActor
final class ControlNoteTests: XCTestCase {
    func testWritesKeepMainsNotes() {
        func note(_ stage: CommandStage) -> String? { AppModel.controlNote(for: stage, "ISO 800") }
        XCTAssertNil(note(.confirmed))
        XCTAssertNil(note(.rejected(.cameraRefused)), "the session already said the camera's message")
        XCTAssertNil(note(.timedOut))
        XCTAssertNil(note(.failed(.notApplied)))
        XCTAssertNil(note(.outcomeUnknown))
        XCTAssertNil(note(.failed(.notSent)))
        XCTAssertEqual(note(.rejected(.notConnected)), MonitorControlModel.connectFirst)
        XCTAssertEqual(
            note(.rejected(.staleEpoch)), "ISO 800 was not sent: the camera state changed. Try again.")
    }
}
