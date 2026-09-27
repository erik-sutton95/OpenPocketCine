import XCTest

/// Called only from the opted-in real-camera Multiview flow. All changes use
/// visible controls; the DEBUG probe supplies reported camera truth for checks.
func exercisePhysicalShutterAngle(
    testCase: XCTestCase, app: XCUIApplication, openSettings: @escaping () -> Void,
    readProbe: @escaping () -> [String: String]
) throws {
    let check = PhysicalShutterAngleCheck(
        app: app, openSettings: openSettings, readProbe: readProbe)
    let original = readProbe()
    let originalSettings = XCTAttachment(
        string: original.keys.sorted().map { "\($0)=\(original[$0]!)" }.joined(separator: "\n"))
    originalSettings.name = "shutter-original-reported-settings"
    originalSettings.lifetime = .keepAlways
    testCase.add(originalSettings)
    guard original["rec"] == "0", original["mode"] == "1",
        let fps = original["fps"], PhysicalShutterAngleCheck.rates[fps] != nil,
        let shutter = Int(original["shutter"] ?? ""), shutter > 0,
        let angle = Double(original["angle"] ?? ""),
        ["1", "4"].contains(original["expo"] ?? ""),
        ["0", "1"].contains(original["usesAngle"] ?? ""),
        (original["shutters"] ?? "").split(separator: ",").contains(Substring(String(shutter)))
    else {
        throw XCTSkip("Shutter proof requires idle Video with complete reported format/exposure")
    }

    var restored = false
    testCase.addTeardownBlock {
        guard !restored else { return }
        do {
            try check.restore(original, angle: angle, shutter: shutter)
            restored = true
        } catch {
            XCTFail("Could not restore original shutter/format settings: \(error)")
        }
    }
    try check.setExposure("Manual")
    try check.setFPS("25p", raw: "2")
    try check.setAngle(180)
    for (label, raw, denominator) in [("25p", "2", "50"), ("50p", "5", "100"), ("25p", "2", "50")] {
        try check.setFPS(label, raw: raw)
        try check.wait("Reported \(label) must preserve 180° at 1/\(denominator)") {
            let reported = readProbe()
            return reported["fps"] == raw && reported["shutter"] == denominator
                && Double(reported["angle"] ?? "") == 180 && reported["usesAngle"] == "1"
                && reported["res"] == original["res"] && reported["rec"] == "0"
        }
        try check.openCategory("shutter")
        XCTAssertEqual(check.drum.value as? String, "180°")
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "shutter-angle-180-\(label)"
        attachment.lifetime = .keepAlways
        testCase.add(attachment)
        // Cross the bounded optimistic-pin window; only raw reported state proves the SET.
        Thread.sleep(forTimeInterval: 2.2)
        XCTAssertEqual(readProbe()["shutter"], denominator)
        XCTAssertEqual(Double(readProbe()["angle"] ?? ""), 180)
    }
    try check.restore(original, angle: angle, shutter: shutter)
    restored = true
}

private final class PhysicalShutterAngleCheck {
    static let rates = ["1": "24p", "2": "25p", "3": "30p", "4": "48p", "5": "50p", "6": "60p"]
    private static let angles = [
        5.6, 11.2, 22.5, 45, 72, 86.4, 90, 108, 144, 172, 180, 216, 288, 346, 360,
    ]
    let app: XCUIApplication
    let openSettings: () -> Void
    let readProbe: () -> [String: String]

    init(
        app: XCUIApplication, openSettings: @escaping () -> Void,
        readProbe: @escaping () -> [String: String]
    ) {
        self.app = app
        self.openSettings = openSettings
        self.readProbe = readProbe
    }

    var panel: XCUIElement {
        app.descendants(matching: .any)["multiview.settings.panel"].firstMatch
    }
    var drum: XCUIElement { panel.descendants(matching: .any)["Value"].firstMatch }

    func openCategory(_ category: String) throws {
        if !panel.exists { openSettings() }
        guard panel.waitForExistence(timeout: 5) else {
            throw Failure("Camera settings unavailable")
        }
        let tab = app.buttons["multiview.settings.control.\(category)"]
        guard tab.waitForExistence(timeout: 5) else { throw Failure("Missing \(category) control") }
        if !tab.isHittable {
            // Categories are a vertical rail in the side panel.
            let rail = panel.scrollViews.allElementsBoundByIndex.first {
                $0.buttons["multiview.settings.control.iso"].exists
            }
            rail?.swipeDown()
            rail?.swipeDown()
            for _ in 0..<6 where !tab.isHittable { rail?.swipeUp() }
        }
        guard tab.isHittable else { throw Failure("Unreachable \(category) control") }
        tab.tap()
        guard drum.waitForExistence(timeout: 5), drum.isHittable else {
            throw Failure("Value drum unavailable")
        }
    }

    func setExposure(_ label: String) throws {
        try openCategory("exposure")
        try select(label, order: ["Auto", "Manual"])
        try wait("Exposure confirmation") {
            self.readProbe()["expo"] == (label == "Manual" ? "4" : "1")
        }
    }

    func setFPS(_ label: String, raw: String) throws {
        try openCategory("resolution")
        try select(label, order: ["24p", "25p", "30p", "48p", "50p", "60p"])
        try wait("Actual FPS confirmation") { self.readProbe()["fps"] == raw }
    }

    func setAngle(_ degrees: Double) throws {
        try openCategory("shutter")
        let angle = app.buttons["Angle"].firstMatch
        guard angle.waitForExistence(timeout: 5) else { throw Failure("Angle tab unavailable") }
        angle.tap()
        let labels = Self.angles.map(Self.label)
        let target = Self.label(degrees)
        // A selected detent is a no-op. If saved intent differs, make an explicit
        // neighboring choice before returning to the desired angle.
        if drum.value as? String == target, Double(readProbe()["angle"] ?? "") != degrees,
            let index = labels.firstIndex(of: target)
        {
            try select(labels[index == 0 ? 1 : index - 1], order: labels)
        }
        try select(target, order: labels)
        try wait("Saved angle confirmation") {
            Double(self.readProbe()["angle"] ?? "") == degrees
                && self.readProbe()["usesAngle"] == "1"
        }
    }

    func restore(_ original: [String: String], angle: Double, shutter: Int) throws {
        try setExposure("Manual")
        try setAngle(angle)
        try openCategory("shutter")
        app.buttons["Speed"].firstMatch.tap()  // Restore FPS without an automatic angle rematch.
        let fps = original["fps"]!
        try setFPS(Self.rates[fps]!, raw: fps)
        try openCategory("shutter")
        app.buttons["Speed"].firstMatch.tap()
        let order = (readProbe()["shutters"] ?? original["shutters"] ?? "")
            .split(separator: ",").compactMap { Int($0) }.map { "1/\($0)" }
        try select("1/\(shutter)", order: order)
        try wait("Original reported shutter restoration") {
            self.readProbe()["shutter"] == String(shutter)
        }
        if original["usesAngle"] == "1" { app.buttons["Angle"].firstMatch.tap() }
        if original["expo"] == "1" { try setExposure("Auto") }
        try wait("Original preferences and format restoration") {
            let state = self.readProbe()
            return state["fps"] == original["fps"] && state["res"] == original["res"]
                && state["expo"] == original["expo"] && state["usesAngle"] == original["usesAngle"]
                && Double(state["angle"] ?? "") == angle && state["rec"] == "0"
        }
        app.buttons["monitor.capture.close"].firstMatch.tap()
    }

    private static func label(_ value: Double) -> String {
        value == value.rounded() ? "\(Int(value))°" : "\(value)°"
    }

    private func select(_ wanted: String, order: [String]) throws {
        guard let target = order.firstIndex(of: wanted) else {
            throw Failure("Unsupported value \(wanted)")
        }
        for _ in 0..<40 {
            let current = drum.value as? String ?? ""
            if current == wanted { return }
            guard let origin = order.firstIndex(of: current) else {
                throw Failure("Unexpected value \(current)")
            }
            let center = drum.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            center.press(
                forDuration: 0.1,
                thenDragTo: center.withOffset(
                    CGVector(dx: target > origin ? -56 : 56, dy: 0)))
            try wait("Drum must settle after release", timeout: 3) {
                self.drum.value as? String != current
            }
        }
        throw Failure("Could not select \(wanted)")
    }

    func wait(_ message: String, timeout: TimeInterval = 12, until predicate: () -> Bool) throws {
        let deadline = Date().addingTimeInterval(timeout)
        repeat {
            if predicate() { return }
            Thread.sleep(forTimeInterval: 0.1)
        } while Date() < deadline
        throw Failure(message)
    }

    struct Failure: Error, CustomStringConvertible {
        let description: String
        init(_ description: String) { self.description = description }
    }
}
