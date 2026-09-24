import MonitorUI
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

    func testEVStripsStayOnTheVisibleFeed() {
        let viewport = CGRect(x: 0, y: 0, width: 390, height: 844)
        for (feed, portrait) in [
            (CGRect(x: 0, y: 0, width: 844, height: 390), false),
            (CGRect(x: -200, y: 120, width: 790, height: 444), true),
            (CGRect(x: 0, y: 200, width: 390, height: 219), true),
        ] {
            let frames = LevelAssist.frames(feed: feed, viewport: viewport, portrait: portrait)
            let visible = feed.intersection(viewport)
            XCTAssertTrue(visible.contains(frames.roll), "\(feed)")
            XCTAssertTrue(visible.contains(frames.tilt), "\(feed)")
            XCTAssertEqual(frames.tilt.width, MonitorLevelGauge.thickness)
            // Tilt centres vertically, right of centre by the roll strip's drop below centre.
            XCTAssertEqual(frames.tilt.width, MonitorLevelGauge.thickness)
            XCTAssertEqual(frames.tilt.midY, visible.midY)
            let offset = min(
                frames.roll.midY - visible.midY, visible.maxX - 6 - MonitorLevelGauge.thickness / 2 - visible.midX)
            XCTAssertEqual(frames.tilt.midX - visible.midX, offset, accuracy: 0.001)
            XCTAssertLessThanOrEqual(frames.tilt.height, MonitorLevelGauge.maxLength)
            XCTAssertEqual(frames.roll.height, MonitorLevelGauge.thickness)
            XCTAssertEqual(frames.roll.midX, visible.midX)
            XCTAssertEqual(
                frames.roll.midY,
                visible.maxY - (portrait ? LevelAssist.rollLiftPortrait : LevelAssist.rollLiftLandscape))
        }
        XCTAssertEqual(MonitorLevelGauge.label(nil), "—")
        XCTAssertEqual(MonitorLevelGauge.label(0.04), "+0.0°")
        XCTAssertEqual(MonitorLevelGauge.label(-2.35), "-2.4°")
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
