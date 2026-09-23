import OpenPocketViewCore
import SwiftUI
import XCTest

@testable import OpenPocketCine

@MainActor
final class LevelAssistTests: XCTestCase {
    func testLevelSitsWithFramingAidsAndPersists() {
        XCTAssertEqual(LiveAssistTool.toolbarGroups[3], [.guides, .grid, .crosshair, .level])
        XCTAssertFalse(LiveAssistTool.playbackToolbarCases.contains(.level))
        XCTAssertFalse(LiveAssistTool.level.hasConfiguration)
        XCTAssertEqual(LiveAssistTool.level.title, "Level")
        XCTAssertEqual(LiveAssistTool.level.monitorIcon, .level)
        let assist = LiveAssistState()
        assist.clean = false
        assist.level = true
        XCTAssertTrue(assist.isVisible(.level))
        let restored = LiveAssistState()
        OperatorPrefs.Snapshot(assist).apply(to: restored)
        XCTAssertTrue(restored.level)
    }

    func testGaugeSeatsStayOnTheVisibleFeed() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        for (feed, portrait) in [
            (CGRect(x: 0, y: 0, width: 844, height: 390), false),
            (CGRect(x: -200, y: 120, width: 790, height: 444), true),
            (CGRect(x: 0, y: 200, width: 390, height: 219), true),
        ] {
            let seats = LevelAssist.seats(feed: feed, viewport: viewport, portrait: portrait)
            let visible = feed.intersection(viewport)
            XCTAssertTrue(visible.contains(seats.roll), "\(feed)")
            XCTAssertTrue(visible.contains(seats.tilt), "\(feed)")
            XCTAssertEqual(seats.roll.x, visible.midX)
            XCTAssertEqual(seats.tilt.x, visible.maxX - 44)
            XCTAssertEqual(seats.roll.y, visible.maxY - (portrait ? 30 : 104))
        }
    }
}

@MainActor
final class GimbalDoubleTapTests: XCTestCase {
    func testDoubleTapPreferenceDefaultsToRecenterAndPersists() {
        let key = "OpenPocketCine.GimbalDoubleTap"
        let saved = UserDefaults.standard.object(forKey: key)
        defer { UserDefaults.standard.set(saved, forKey: key) }
        UserDefaults.standard.removeObject(forKey: key)
        XCTAssertEqual(OperatorPrefs.gimbalDoubleTap, .recenter)
        OperatorPrefs.gimbalDoubleTap = .level
        XCTAssertEqual(OperatorPrefs.gimbalDoubleTap, .level)
    }

    func testLevelDoubleTapWithoutAttitudeRefusesAndSaysSo() {
        let session = CameraSession()
        session.gimbalDoubleTap = .level
        session.performGimbalDoubleTap()
        XCTAssertEqual(session.controlNote, WorldLevelSnap.noLevelData)
    }
}
