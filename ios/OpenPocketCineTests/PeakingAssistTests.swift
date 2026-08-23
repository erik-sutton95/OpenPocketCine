import XCTest

@testable import OpenPocketCine

/// Pins PEAK to OpenZCine `Peaking` + `AssistQuickSettingsContent.peakingRows`.
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

    func testOpenZCineOptionSet() {
        XCTAssertEqual(
            PeakingAssist.Color.allCases.map(\.rawValue),
            ["White", "Blue", "Red", "Green"])
        XCTAssertEqual(
            PeakingAssist.Sensitivity.allCases.map(\.rawValue),
            ["Low", "Med", "High"])
        XCTAssertEqual(PeakingAssist.palette.map(\.rawValue), ["White", "Blue", "Red", "Green"])
        XCTAssertEqual(PeakingAssist.sensitivityOptions, ["Low", "Med", "High"])
        XCTAssertEqual(PeakingAssist.Options.default.color, .red)
        XCTAssertEqual(PeakingAssist.Options.default.sensitivity, .medium)
        XCTAssertEqual(PeakingAssist.longPressPanelWidth, 400)
        XCTAssertEqual(PeakingAssist.panelWidth, 400)
    }

    func testPopupCopyMatchesOpenZCine() {
        XCTAssertEqual(
            PeakingAssist.sensitivityHelp,
            "Higher sensitivity catches finer edges but can get noisy on detailed scenes.")
        XCTAssertEqual(
            PeakingAssist.colorHelp,
            "Choose the edge color that stays readable over your typical scene.")
    }

    func testOverlayRGBMatchesOpenZCinePaint() {
        assertRGB(PeakingAssist.Color.white.rgb, 246, 241, 226)
        assertRGB(PeakingAssist.Color.blue.rgb, 64, 142, 255)
        assertRGB(PeakingAssist.Color.red.rgb, 255, 72, 64)
        assertRGB(PeakingAssist.Color.green.rgb, 74, 220, 132)
    }

    func testOverlayHookMatchesOpenZCineDetector() {
        let low = PeakingAssist.overlay(color: .white, sensitivity: .low)
        XCTAssertEqual(low.ratioThreshold, 2.30)
        XCTAssertEqual(low.noiseGate, 0.00522)
        XCTAssertEqual(low.rgb.0, 246.0 / 255, accuracy: 1e-12)

        let med = PeakingAssist.overlay(from: .default)
        XCTAssertEqual(med.color, .red)
        XCTAssertEqual(med.sensitivity, .medium)
        XCTAssertEqual(med.ratioThreshold, 2.10)
        XCTAssertEqual(med.noiseGate, 0.00174)
        XCTAssertEqual(med.rgb.0, 255.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(med.rgb.1, 72.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(med.rgb.2, 64.0 / 255, accuracy: 1e-12)

        let high = PeakingAssist.Sensitivity.high
        XCTAssertEqual(high.ratioThreshold, 1.90)
        XCTAssertEqual(high.noiseGate, 0.00058)
    }

    func testSensitivityStepsAreOrderedLikeOpenZCine() {
        let low = PeakingAssist.Sensitivity.low
        let medium = PeakingAssist.Sensitivity.medium
        let high = PeakingAssist.Sensitivity.high
        XCTAssertGreaterThan(low.ratioThreshold, medium.ratioThreshold)
        XCTAssertGreaterThan(medium.ratioThreshold, high.ratioThreshold)
        XCTAssertGreaterThan(low.noiseGate, medium.noiseGate)
        XCTAssertGreaterThan(medium.noiseGate, high.noiseGate)
        XCTAssertGreaterThan(low.noiseGate / high.noiseGate, 8)
        for step in PeakingAssist.Sensitivity.allCases {
            XCTAssertGreaterThan(step.ratioThreshold, 1)
            XCTAssertLessThan(step.ratioThreshold, 4)
        }
    }

    func testGPUEffectsReadOverlayHook() {
        var fx = LiveImageEffects()
        fx.peakingColor = .green
        fx.peakingSensitivity = .high
        let overlay = PeakingAssist.overlay(from: fx)
        XCTAssertEqual(overlay.color, .green)
        XCTAssertEqual(overlay.sensitivity, .high)
        XCTAssertEqual(fx.peakingOptions.overlay.noiseGate, 0.00058)
        XCTAssertEqual(PeakingPaint.red.rgb.1, 72.0 / 255, accuracy: 1e-12)
        XCTAssertEqual(PeakingSense.medium.ratioThreshold, 2.10)
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

    private func assertRGB(
        _ rgb: (Double, Double, Double), _ r: Double, _ g: Double, _ b: Double
    ) {
        XCTAssertEqual(rgb.0, r / 255, accuracy: 1e-12)
        XCTAssertEqual(rgb.1, g / 255, accuracy: 1e-12)
        XCTAssertEqual(rgb.2, b / 255, accuracy: 1e-12)
    }
}
