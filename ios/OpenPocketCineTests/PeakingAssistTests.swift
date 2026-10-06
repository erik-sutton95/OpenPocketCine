import OpenCineCameraControls
import XCTest

@testable import OpenPocketCine

/// Pins PEAK's row taps and reset on this app's assist state (the rest is in
/// OpenCineCameraControlsTests).
final class PeakingAssistTests: XCTestCase {
    private let assistKey = "OpenPocketCine.Assist.v1"
    private var savedAssist: Data?

    override func setUp() {
        super.setUp()
        savedAssist = UserDefaults.standard.data(forKey: assistKey)
        UserDefaults.standard.removeObject(forKey: assistKey)
    }

    override func tearDown() {
        if let savedAssist {
            UserDefaults.standard.set(savedAssist, forKey: assistKey)
        } else {
            UserDefaults.standard.removeObject(forKey: assistKey)
        }
        super.tearDown()
    }

    @MainActor
    func testSelectAndResetMatchOpenZCineRows() {
        let assist = LiveAssistState()
        XCTAssertEqual(assist.peakingOptions, .default)

        PeakingAssist.selectSensitivity("High", assist: assist)
        XCTAssertEqual(assist.peakingSensitivity, .high)
        PeakingAssist.selectSensitivity("High", assist: assist)
        XCTAssertEqual(assist.peakingSensitivity, .high)
        PeakingAssist.selectSensitivity("nope", assist: assist)
        XCTAssertEqual(assist.peakingSensitivity, .high)

        PeakingAssist.selectColor("Blue", assist: assist)
        XCTAssertEqual(assist.peakingColor, .blue)
        PeakingAssist.selectColor("Blue", assist: assist)
        XCTAssertEqual(assist.peakingColor, .blue)
        PeakingAssist.selectColor("nope", assist: assist)
        XCTAssertEqual(assist.peakingColor, .blue)

        PeakingAssist.reset(assist)
        XCTAssertEqual(assist.peakingColor, .red)
        XCTAssertEqual(assist.peakingSensitivity, .medium)
        XCTAssertEqual(assist.peakingOptions, .default)
    }
}
