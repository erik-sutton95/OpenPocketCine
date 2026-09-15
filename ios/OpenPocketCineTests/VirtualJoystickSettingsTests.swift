import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

final class VirtualJoystickSettingsTests: XCTestCase {
    private let keys = [
        "OpenPocketCine.VirtualJoystickInvertPan",
        "OpenPocketCine.VirtualJoystickInvertTilt",
        "OpenPocketCine.VirtualJoystickDeadzonePercent",
        "OpenPocketCine.VirtualJoystickResponseCurve",
    ]

    private var saved: [String: Any] = [:]

    override func setUp() {
        super.setUp()
        saved = [:]
        for key in keys {
            saved[key] = UserDefaults.standard.object(forKey: key)
            UserDefaults.standard.removeObject(forKey: key)
        }
    }

    override func tearDown() {
        for key in keys {
            if let value = saved[key] {
                UserDefaults.standard.set(value, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        super.tearDown()
    }

    func testMissingKeysAreCapturedDefaults() {
        XCTAssertFalse(OperatorPrefs.virtualJoystickInvertPan)
        XCTAssertFalse(OperatorPrefs.virtualJoystickInvertTilt)
        XCTAssertEqual(OperatorPrefs.virtualJoystickDeadzonePercent, 8)
        XCTAssertEqual(OperatorPrefs.virtualJoystickResponseCurve, .standard)
        let mapping = OperatorPrefs.virtualJoystickMapping
        XCTAssertEqual(mapping, .defaults)
        XCTAssertEqual(mapping.deadzone, GimbalStick.deadzone)
    }

    func testRoundTripPersists() {
        OperatorPrefs.virtualJoystickInvertPan = true
        OperatorPrefs.virtualJoystickInvertTilt = true
        OperatorPrefs.virtualJoystickDeadzonePercent = 0
        OperatorPrefs.virtualJoystickResponseCurve = .fine
        XCTAssertTrue(OperatorPrefs.virtualJoystickInvertPan)
        XCTAssertTrue(OperatorPrefs.virtualJoystickInvertTilt)
        XCTAssertEqual(OperatorPrefs.virtualJoystickDeadzonePercent, 0)
        XCTAssertEqual(OperatorPrefs.virtualJoystickResponseCurve, .fine)
        XCTAssertEqual(OperatorPrefs.virtualJoystickMapping.curve, .fine)
        XCTAssertEqual(OperatorPrefs.virtualJoystickMapping.deadzone, 0)
    }

    func testCorruptStoredValuesClampToSafeDefaults() {
        UserDefaults.standard.set(99, forKey: keys[2])
        XCTAssertEqual(OperatorPrefs.virtualJoystickDeadzonePercent, 25)
        UserDefaults.standard.set(-12, forKey: keys[2])
        XCTAssertEqual(OperatorPrefs.virtualJoystickDeadzonePercent, 0)
        OperatorPrefs.virtualJoystickDeadzonePercent = 40
        XCTAssertEqual(
            UserDefaults.standard.integer(forKey: keys[2]), 25)
        UserDefaults.standard.set("cubic", forKey: keys[3])
        XCTAssertEqual(OperatorPrefs.virtualJoystickResponseCurve, .standard)
        UserDefaults.standard.set("linear", forKey: keys[3])
        XCTAssertEqual(OperatorPrefs.virtualJoystickResponseCurve, .linear)
    }
}
