import XCTest

@testable import OpenPocketCine

final class FalseColorReferencePlacementTests: XCTestCase {
    func testUnsetReferenceRemainsCenteredAcrossRotationWithoutCreatingAStoredPosition() {
        let positions = FalseColorReferencePositions()
        for bounds in [
            CGRect(x: 0, y: 0, width: 390, height: 844),
            CGRect(x: 0, y: 0, width: 844, height: 390),
        ] {
            let center = positions.center(
                in: bounds, size: FalseColorReference.panelSize,
                movement: bounds.insetBy(dx: 14, dy: 20))
            XCTAssertEqual(center.x, bounds.midX)
            XCTAssertEqual(center.y, bounds.midY)
        }
        XCTAssertNil(positions.landscape)
        XCTAssertNil(positions.portrait)
    }

    @MainActor
    func testDraggedPositionsPersistIndependentlyAndClampWithoutOverwritingThePreference() throws {
        let suite = "FalseColorReferencePlacementTests.\(UUID().uuidString)"
        let defaults = try XCTUnwrap(UserDefaults(suiteName: suite))
        defer { defaults.removePersistentDomain(forName: suite) }
        let store = FalseColorReferencePositionStore(defaults: defaults)
        let landscape = CGRect(x: 0, y: 0, width: 844, height: 390)
        let portrait = CGRect(x: 0, y: 0, width: 390, height: 844)
        let landscapePoint = CGPoint(x: 670, y: 180)
        let portraitPoint = CGPoint(x: 195, y: 640)
        store.setCenter(landscapePoint, in: landscape)
        store.setCenter(portraitPoint, in: portrait)
        let restored = FalseColorReferencePositionStore(defaults: defaults)
        let landscapeCenter = restored.positions.center(
            in: landscape, size: FalseColorReference.panelSize, movement: landscape)
        let portraitCenter = restored.positions.center(
            in: portrait, size: FalseColorReference.panelSize, movement: portrait)
        XCTAssertEqual(landscapeCenter.x, landscapePoint.x, accuracy: 0.000_001)
        XCTAssertEqual(landscapeCenter.y, landscapePoint.y, accuracy: 0.000_001)
        XCTAssertEqual(portraitCenter.x, portraitPoint.x, accuracy: 0.000_001)
        XCTAssertEqual(portraitCenter.y, portraitPoint.y, accuracy: 0.000_001)
        let original = restored.positions
        let reduced = CGRect(x: 40, y: 30, width: 500, height: 200)
        let clamped = restored.positions.center(
            in: landscape, size: FalseColorReference.panelSize, movement: reduced)
        XCTAssertLessThanOrEqual(clamped.x + FalseColorReference.panelSize.width / 2, reduced.maxX)
        XCTAssertLessThanOrEqual(clamped.y + FalseColorReference.panelSize.height / 2, reduced.maxY)
        XCTAssertEqual(restored.positions, original)
    }
}
