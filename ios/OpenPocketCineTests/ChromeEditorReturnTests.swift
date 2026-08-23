import OpenPocketViewCore
import XCTest

@testable import OpenPocketCine

/// OpenZCine `ChromeEditorReturnTests` — Edit view entry, exit, and force-mount.
final class ChromeEditorReturnTests: XCTestCase {
    @MainActor
    func testBecomingLiveDismissesSettingsAndHomePanels() {
        let model = AppModel()
        model.homePanel = .settings
        model.liveOperatorPanel = .settings
        model.operatorSettingsTab = .display
        model.chromeEditorMode = .live
        model.chromeEditorReturnMode = .live

        model.noteBecameLive()

        XCTAssertNil(model.homePanel)
        XCTAssertNil(model.liveOperatorPanel)
        XCTAssertNil(model.chromeEditorMode)
        XCTAssertNil(model.chromeEditorReturnMode)
        XCTAssertFalse(model.liveChromeInteractive)
    }

    @MainActor
    func testLeavingLiveDismissesOperatorSetup() {
        let model = AppModel()
        model.liveOperatorPanel = .settings
        model.chromeEditorMode = .clean

        model.noteLeftLive()

        XCTAssertNil(model.liveOperatorPanel)
        XCTAssertNil(model.chromeEditorMode)
        XCTAssertTrue(model.liveChromeInteractive)
    }

    @MainActor
    func testOpeningTheEditorLeavesSettingsAndSwitchesMode() {
        let model = AppModel()
        model.liveOperatorPanel = .settings
        model.assist.clean = false

        model.beginChromeEditing(.clean)

        XCTAssertNil(model.liveOperatorPanel)
        XCTAssertTrue(model.assist.clean)
        XCTAssertEqual(model.chromeEditorMode, .clean)
        XCTAssertEqual(model.currentDispMode, .clean)
    }

    @MainActor
    func testDoneReturnsToDisplaySettingsOnEditedSection() {
        let model = AppModel()
        model.beginChromeEditing(.clean)

        model.endChromeEditing()

        XCTAssertNil(model.chromeEditorMode)
        XCTAssertEqual(model.liveOperatorPanel, .settings)
        XCTAssertEqual(model.operatorSettingsTab, .display)
        XCTAssertEqual(model.chromeEditorReturnMode, .clean)
    }

    @MainActor
    func testToggleChromeOnlyTouchesTheEditedMode() {
        let model = AppModel()
        let savedLive = model.dispLive
        let savedClean = model.dispClean
        defer {
            model.dispLive = savedLive
            model.dispClean = savedClean
        }
        model.dispLive = .liveDefaults
        // Start clean from the same full set so the flip is unambiguous.
        model.dispClean = .liveDefaults

        model.toggleChrome(.statusBar, for: .clean)

        XCTAssertTrue(model.dispLive.statusBar)
        XCTAssertFalse(model.dispClean.statusBar)
        XCTAssertTrue(model.dispClean.railRecord)
    }

    @MainActor
    func testChromeForceMountsWhileEditingHiddenItems() {
        let model = AppModel()
        let savedLive = model.dispLive
        defer { model.dispLive = savedLive }
        model.dispLive = .liveDefaults
        model.dispLive.statusBar = false
        model.assist.clean = false

        XCTAssertFalse(model.chromeSectionMounts(.statusBar))

        model.beginChromeEditing(.live)

        XCTAssertTrue(model.chromeSectionMounts(.statusBar))
        XCTAssertTrue(model.isEditingChrome)
    }

    @MainActor
    func testSettingsRailRemainsReachableIfBothModesHideIt() {
        let model = AppModel()
        let savedLive = model.dispLive
        let savedClean = model.dispClean
        defer {
            model.dispLive = savedLive
            model.dispClean = savedClean
        }
        model.dispLive = .liveDefaults
        model.dispClean = .cleanDefaults
        model.dispLive.railSettings = false
        model.dispClean.railSettings = false
        model.assist.clean = false

        XCTAssertTrue(model.chromeSectionMounts(.railSettings))
    }

    func testDisplayModesDoNotIncludeCommand() {
        XCTAssertEqual(PocketDispMode.allCases.map(\.rawValue), ["live", "clean"])
        XCTAssertFalse(PocketDispMode.live.settingsTitle.contains("DISP 3"))
        XCTAssertFalse(PocketDispMode.clean.settingsTitle.contains("DISP 3"))
        XCTAssertFalse(
            PocketDispMode.live.settingsCaption.localizedCaseInsensitiveContains("command"))
        XCTAssertFalse(
            PocketDispMode.clean.settingsCaption.localizedCaseInsensitiveContains("command"))
    }

    func testBadgeFramesSitOnTopBarAndAvoidOverlap() throws {
        let statusBox = CGRect(x: 120, y: 12, width: 420, height: 40)
        let recBox = CGRect(x: 128, y: 16, width: 72, height: 32)
        let viewport = CGSize(width: 874, height: 402)
        let frames = PocketChromeEditLayout.badgeFrames(
            [
                .init(section: .statusBar, frame: statusBox),
                .init(section: .recReadout, frame: recBox),
            ],
            viewport: viewport
        )

        let status = try XCTUnwrap(frames[.statusBar])
        let rec = try XCTUnwrap(frames[.recReadout])
        let playable = PocketChromeEditLayout.playableRect(in: viewport)
        XCTAssertTrue(playable.contains(status))
        XCTAssertTrue(playable.contains(rec))
        // Top-deck eyes sit on the bar, not on the physical top edge.
        XCTAssertGreaterThan(status.minY, PocketChromeEditLayout.edgeInset - 0.5)
        XCTAssertTrue(statusBox.intersects(status))
        XCTAssertGreaterThan(status.midY, statusBox.midY - 1)
        XCTAssertGreaterThan(abs(status.midX - rec.midX) + abs(status.midY - rec.midY), 20)
        XCTAssertFalse(
            status.insetBy(
                dx: -PocketChromeEditLayout.badgeGap, dy: -PocketChromeEditLayout.badgeGap
            )
            .intersects(rec)
        )
    }

    func testBadgeFramesPullInwardFromTrailingRail() throws {
        let viewport = CGSize(width: 874, height: 402)
        let settings = CGRect(x: 792, y: 14, width: 64, height: 64)
        let frames = PocketChromeEditLayout.badgeFrames(
            [.init(section: .railSettings, frame: settings)],
            viewport: viewport
        )
        let badge = try XCTUnwrap(frames[.railSettings])
        let playable = PocketChromeEditLayout.playableRect(in: viewport)
        XCTAssertTrue(playable.contains(badge))
        XCTAssertLessThanOrEqual(
            badge.maxX, viewport.width - PocketChromeEditLayout.edgeInset + 0.5)
        XCTAssertTrue(settings.intersects(badge))
        // Right-rail control: eye on the leading (inward) side.
        XCTAssertLessThan(badge.midX, settings.midX)
    }

    func testBadgeFramesPullInwardFromLeadingGutter() throws {
        let viewport = CGSize(width: 874, height: 402)
        let lock = CGRect(x: 16, y: 14, width: 40, height: 40)
        let frames = PocketChromeEditLayout.badgeFrames(
            [.init(section: .lockButton, frame: lock)],
            viewport: viewport
        )
        let badge = try XCTUnwrap(frames[.lockButton])
        let playable = PocketChromeEditLayout.playableRect(in: viewport)
        XCTAssertTrue(playable.contains(badge))
        XCTAssertGreaterThanOrEqual(badge.minX, PocketChromeEditLayout.edgeInset - 0.5)
        XCTAssertTrue(lock.intersects(badge))
        // Left-gutter control: eye on the trailing (inward) side.
        XCTAssertGreaterThan(badge.midX, lock.midX)
    }

    func testCleanViewPinsFilterWithoutMutatingOnOff() {
        let assist = LiveAssistState()
        assist.histogram = true
        assist.peaking = true
        assist.cleanViewPinnedTools = [.peaking]
        assist.clean = false

        XCTAssertTrue(assist.isVisible(.peaking))
        XCTAssertTrue(assist.isVisible(.histogram))
        XCTAssertTrue(assist.effects.histogram)

        assist.clean = true

        XCTAssertTrue(assist.isVisible(.peaking))
        XCTAssertFalse(assist.isVisible(.histogram))
        XCTAssertTrue(assist.isOn(.histogram))
        XCTAssertTrue(assist.effects.peaking)
        XCTAssertFalse(assist.effects.histogram)
    }

    func testCleanViewPinCannotResurrectASwitchedOffTool() {
        let assist = LiveAssistState()
        assist.waveform = false
        assist.clean = true
        assist.cleanViewPinnedTools = [.waveform]
        XCTAssertFalse(assist.isVisible(.waveform))
        XCTAssertFalse(assist.effects.waveform)
    }

    func testCleanViewStockPinsExcludeOmittedTools() {
        XCTAssertEqual(
            LiveAssistState.cleanViewDefaultPinnedTools,
            [.lut, .peaking, .mirror]
        )
        XCTAssertFalse(LiveAssistTool.cleanPinCases.contains(.desqueeze))
        XCTAssertFalse(LiveAssistTool.cleanPinCases.contains(.level))
        XCTAssertFalse(LiveAssistTool.cleanPinCases.contains(.magnification))
    }

    func testAbsentCleanPinPrefsLoadStockSet() {
        let key = "OpenPocketCine.CleanViewPins.v1"
        let saved = UserDefaults.standard.object(forKey: key)
        UserDefaults.standard.removeObject(forKey: key)
        defer {
            if let saved {
                UserDefaults.standard.set(saved, forKey: key)
            } else {
                UserDefaults.standard.removeObject(forKey: key)
            }
        }
        XCTAssertEqual(
            OperatorPrefs.cleanViewPinnedTools,
            LiveAssistState.cleanViewDefaultPinnedTools
        )
    }

    func testFocusEditRectUsesTrackedBoxAndFallsBackToAFPoint() {
        let feed = CGRect(x: 0, y: 0, width: 1600, height: 900)
        let box = TrackingBox(x: 0.25, y: 0.2, width: 0.2, height: 0.3)
        let tracked = LiveChromeEditGeometry.focusEditRect(
            overlay: .face(box),
            faces: [],
            focusPoint: CGPoint(x: 0.5, y: 0.5),
            mirrored: false,
            in: feed
        )
        XCTAssertEqual(tracked.minX, 400, accuracy: 0.5)
        XCTAssertEqual(tracked.minY, 180, accuracy: 0.5)
        XCTAssertEqual(tracked.width, 320, accuracy: 0.5)
        XCTAssertEqual(tracked.height, 270, accuracy: 0.5)

        let fallback = LiveChromeEditGeometry.focusEditRect(
            overlay: .focus,
            faces: [],
            focusPoint: CGPoint(x: 0.5, y: 0.5),
            mirrored: false,
            in: feed
        )
        XCTAssertEqual(fallback.midX, 800, accuracy: 0.5)
        XCTAssertEqual(fallback.midY, 450, accuracy: 0.5)
        XCTAssertEqual(fallback.width, fallback.height, accuracy: 0.5)
    }
}
