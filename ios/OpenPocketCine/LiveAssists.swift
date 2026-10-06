import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCameraControls
import OpenCineCameraVocabulary
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Cinema live-monitor set. MAG is retired; PLAY stays off the video toolbar.
typealias LiveAssistTool = MonitorAssistSelection

typealias GuideAspect = MonitorGuideAspect

/// This app's LUT looks: its official cubes, saved choices and custom LUT folder.
extension MonitorLUTLooks {
    /// Shared initialization may read the provider, but native lookup waits for app prefs.
    convenience init() {
        self.init(official: .app, preferences: .app, customLUTs: .app, preparationReady: false)
    }
}

typealias LiveAssistState = MonitorAssistState<MonitorLUTLooks>

extension MonitorAssistState where Looks == MonitorLUTLooks {
    convenience init() {
        weak var state: LiveAssistState?
        self.init(
            looks: MonitorLUTLooks(), storage: .standard,
            keys: .init(
                assist: "OpenPocketCine.Assist.v1", cleanPins: "OpenPocketCine.CleanViewPins.v1",
                playback: "OpenPocketCine.PlaybackAssists.v1"),
            cleanPinCases: LiveAssistTool.cleanPinCases,
            onToggle: { tool, enabled in
                guard tool == .falseColor, enabled, let state else { return }
                PocketFalseColorMap.warm(
                    scale: state.falseColorScale,
                    mode: state.monitorColorMode ?? .normal, rec709: state.falseColorRec709,
                    clipByte: nil, hasLUT: state.lutEnabled && state.hasPreparedLUT)
            })
        state = self
        OperatorPrefs.load(into: self)
        cleanViewPinnedTools = OperatorPrefs.cleanViewPinnedTools
        playbackVisibleTools = OperatorPrefs.playbackVisibleAssistTools
        if monitorColorMode == nil { monitorColorMode = LUTPreferences.app.lastMonitorColorMode }
        looks.preparationReady = true
        if lutEnabled { refreshLUTCube() }
    }
}

enum OperatorPrefs {
    private static let display = MonitorDisplayPreferences(
        storage: .standard,
        keys: .init(live: "OpenPocketCine.DispChrome.Live", clean: "OpenPocketCine.DispChrome.Clean"))
    private static let awakeKey = "OpenPocketCine.KeepScreenAwake"
    private static let hdrDisplayKey = "OpenPocketCine.HDRDisplay"
    private static let customRec709FileKey = "OpenPocketCine.CustomRec709File"
    private static let customDLog2FileKey = "OpenPocketCine.CustomDLog2File"
    private static let assistKey = "OpenPocketCine.Assist.v1"
    private static let recordConfirmKey = "OpenPocketCine.RecordConfirmation"
    private static let hapticsKey = "OpenPocketCine.HapticsEnabled"
    private static let headTrackingKey = "OpenPocketCine.HeadTrackingEnabled"
    private static let gimbalStickSensitivityKey = "OpenPocketCine.GimbalStickSensitivity"
    private static let virtualJoystickInvertPanKey = "OpenPocketCine.VirtualJoystickInvertPan"
    private static let virtualJoystickInvertTiltKey = "OpenPocketCine.VirtualJoystickInvertTilt"
    private static let virtualJoystickDeadzonePercentKey =
        "OpenPocketCine.VirtualJoystickDeadzonePercent"
    private static let virtualJoystickResponseCurveKey =
        "OpenPocketCine.VirtualJoystickResponseCurve"
    private static let virtualJoystickSizeKey = "OpenPocketCine.VirtualJoystickSize"
    private static let gimbalRampKey = "OpenPocketCine.GimbalRamp"
    private static let gimbalDoubleTapKey = "OpenPocketCine.GimbalDoubleTap"
    private static let cleanPinsKey = "OpenPocketCine.CleanViewPins.v1"
    private static let playbackAssistsKey = "OpenPocketCine.PlaybackAssists.v1"
    private static let cacheFullResolutionKey = "OpenPocketCine.CacheFullResolution"
    private static let portraitFeedAspectKey = "OpenPocketCine.PortraitFeedAspect"
    private static let nativeISOHopKey = "OpenPocketCine.NativeISOHop"
    private static let facePriorityExposureKey = "OpenPocketCine.FacePriorityExposure"
    private static let shutterUsesAngleKey = "OpenPocketCine.ShutterUsesAngle"
    private static let shutterAngleKey = "OpenPocketCine.ShutterAngleDegrees"
    private static let shareThisFeedKey = "OpenPocketCine.ShareThisFeed"
    private static let controlRequestsKey = "OpenPocketCine.ControlRequests"
    private static let broadcastPriorityKey = "OpenPocketCine.BroadcastPriority"
    private static let assistToolUsageKey = "OpenPocketCine.AssistToolUsage.v1"

    static var shareThisFeed: Bool {
        get { UserDefaults.standard.bool(forKey: shareThisFeedKey) }
        set { UserDefaults.standard.set(newValue, forKey: shareThisFeedKey) }
    }

    static var controlRequests: Bool {
        get {
            if UserDefaults.standard.object(forKey: controlRequestsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: controlRequestsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: controlRequestsKey) }
    }

    /// Ceiling index on the watcher-relay bitrate ladder. 0 = highest quality.
    static var broadcastPriority: Int {
        get {
            let v = UserDefaults.standard.integer(forKey: broadcastPriorityKey)
            return min(max(0, v), 3)
        }
        set { UserDefaults.standard.set(min(max(0, newValue), 3), forKey: broadcastPriorityKey) }
    }

    static var keepScreenAwake: Bool {
        get {
            if UserDefaults.standard.object(forKey: awakeKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: awakeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: awakeKey) }
    }

    /// Outdoor HDR panel boost for live view. Off by default.
    static var hdrDisplay: Bool {
        get { UserDefaults.standard.bool(forKey: hdrDisplayKey) }
        set { UserDefaults.standard.set(newValue, forKey: hdrDisplayKey) }
    }

    /// Download the original camera file when a clip is opened. Off keeps the 720p proxy.
    static var cacheFullResolution: Bool {
        get {
            if UserDefaults.standard.object(forKey: cacheFullResolutionKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: cacheFullResolutionKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: cacheFullResolutionKey) }
    }

    static var recordConfirmationEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: recordConfirmKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: recordConfirmKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: recordConfirmKey) }
    }

    static var hapticsEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: hapticsKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: hapticsKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: hapticsKey) }
    }

    static var assistToolUsage: MonitorToolUsage {
        get {
            guard let data = UserDefaults.standard.data(forKey: assistToolUsageKey),
                let value = try? JSONDecoder().decode(MonitorToolUsage.self, from: data)
            else { return MonitorToolUsage() }
            return value
        }
        set {
            if let data = try? JSONEncoder().encode(newValue) {
                UserDefaults.standard.set(data, forKey: assistToolUsageKey)
            }
        }
    }

    static var headTrackingEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: headTrackingKey) }
        set { UserDefaults.standard.set(newValue, forKey: headTrackingKey) }
    }

    /// Stick double-tap / gamepad Circle/B. Absent key is Recenter.
    static var gimbalDoubleTap: GimbalDoubleTap {
        get {
            GimbalDoubleTap(rawValue: UserDefaults.standard.integer(forKey: gimbalDoubleTapKey))
                ?? .recenter
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: gimbalDoubleTapKey) }
    }

    static var gimbalRamp: GimbalRamp {
        get {
            guard UserDefaults.standard.object(forKey: gimbalRampKey) != nil else {
                return .off
            }
            return GimbalRamp(rawValue: UserDefaults.standard.integer(forKey: gimbalRampKey))
                ?? .off
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: gimbalRampKey) }
    }

    static var gimbalStickSensitivity: Int {
        get {
            guard UserDefaults.standard.object(forKey: gimbalStickSensitivityKey) != nil else {
                return GimbalStick.defaultSensitivity
            }
            return GimbalStick.clampedSensitivity(
                UserDefaults.standard.integer(forKey: gimbalStickSensitivityKey))
        }
        set {
            UserDefaults.standard.set(
                GimbalStick.clampedSensitivity(newValue), forKey: gimbalStickSensitivityKey)
        }
    }

    static var virtualJoystickInvertPan: Bool {
        get { UserDefaults.standard.bool(forKey: virtualJoystickInvertPanKey) }
        set { UserDefaults.standard.set(newValue, forKey: virtualJoystickInvertPanKey) }
    }

    static var virtualJoystickInvertTilt: Bool {
        get { UserDefaults.standard.bool(forKey: virtualJoystickInvertTiltKey) }
        set { UserDefaults.standard.set(newValue, forKey: virtualJoystickInvertTiltKey) }
    }

    static var virtualJoystickDeadzonePercent: Int {
        get {
            guard UserDefaults.standard.object(forKey: virtualJoystickDeadzonePercentKey) != nil
            else {
                return GimbalStick.defaultDeadzonePercent
            }
            return GimbalStick.clampedDeadzonePercent(
                UserDefaults.standard.integer(forKey: virtualJoystickDeadzonePercentKey))
        }
        set {
            UserDefaults.standard.set(
                GimbalStick.clampedDeadzonePercent(newValue),
                forKey: virtualJoystickDeadzonePercentKey)
        }
    }

    static var virtualJoystickResponseCurve: GimbalStick.ResponseCurve {
        get {
            GimbalStick.ResponseCurve.parse(
                UserDefaults.standard.string(forKey: virtualJoystickResponseCurveKey))
        }
        set {
            UserDefaults.standard.set(newValue.rawValue, forKey: virtualJoystickResponseCurveKey)
        }
    }

    static var virtualJoystickSize: MonitorJoystickSize {
        get { MonitorJoystickSize.parse(UserDefaults.standard.string(forKey: virtualJoystickSizeKey)) }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: virtualJoystickSizeKey) }
    }

    static var virtualJoystickMapping: GimbalStick.Mapping {
        GimbalStick.Mapping(
            invertPan: virtualJoystickInvertPan,
            invertTilt: virtualJoystickInvertTilt,
            deadzone: GimbalStick.deadzoneFromPercent(virtualJoystickDeadzonePercent),
            curve: virtualJoystickResponseCurve)
    }

    static var dispLive: PocketDispChrome {
        get { display.live }
        set { display.live = newValue }
    }

    static var dispClean: PocketDispChrome {
        get { display.clean }
        set { display.clean = newValue }
    }

    static var shutterUsesAngle: Bool {
        get { UserDefaults.standard.bool(forKey: shutterUsesAngleKey) }
        set { UserDefaults.standard.set(newValue, forKey: shutterUsesAngleKey) }
    }

    static var shutterAngleDegrees: Double {
        get {
            let stored = UserDefaults.standard.double(forKey: shutterAngleKey)
            return stored > 0 ? ShutterAngle.nearestDegrees(stored) : ShutterAngle.defaultDegrees
        }
        set {
            UserDefaults.standard.set(
                ShutterAngle.nearestDegrees(newValue), forKey: shutterAngleKey)
        }
    }

    static var portraitFeedAspect: PortraitFeedAspect {
        get {
            PortraitFeedAspect(
                rawValue: UserDefaults.standard.string(forKey: portraitFeedAspectKey) ?? "")
                ?? .fit16x9
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: portraitFeedAspectKey) }
    }

    /// Auto-expo: meter Vision faces to middle gray and write EV.
    static var facePriorityExposureEnabled: Bool {
        get { UserDefaults.standard.bool(forKey: facePriorityExposureKey) }
        set { UserDefaults.standard.set(newValue, forKey: facePriorityExposureKey) }
    }

    /// D-Log 400 ↔ D-Log2 1600 when the operator is still on native ISO.
    static var nativeISOHopEnabled: Bool {
        get {
            if UserDefaults.standard.object(forKey: nativeISOHopKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: nativeISOHopKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: nativeISOHopKey) }
    }

    static var playbackVisibleAssistTools: Set<LiveAssistTool> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: playbackAssistsKey) as? [String]
            else { return [] }
            return Set(raw.compactMap(LiveAssistTool.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: playbackAssistsKey)
        }
    }

    /// Absent key = never pinned, so the stock set. Stored empty = operator cleared every pin.
    static var cleanViewPinnedTools: Set<LiveAssistTool> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: cleanPinsKey) as? [String] else {
                return LiveAssistState.cleanViewDefaultPinnedTools
            }
            let allowed = Set(LiveAssistTool.cleanPinCases)
            return Set(raw.compactMap(LiveAssistTool.init(rawValue:))).intersection(allowed)
        }
        set {
            let ordered = LiveAssistTool.cleanPinCases.filter { newValue.contains($0) }.map(
                \.rawValue)
            UserDefaults.standard.set(ordered, forKey: cleanPinsKey)
        }
    }

    @MainActor
    static func load(into state: LiveAssistState) {
        if let data = UserDefaults.standard.data(forKey: assistKey),
            let snap = try? JSONDecoder().decode(MonitorAssistSnapshot.self, from: data)
        {
            snap.apply(to: state)
        }
        LUTPreferences.app.migrateLegacySelectionIfNeeded(lutEnabled: state.lutEnabled)
        let migrated = LUTPreferences.app.lutSelection.migratedToDJICatalog
        if migrated != LUTPreferences.app.lutSelection {
            LUTPreferences.app.lutSelection = migrated
        }
        state.lutSelection = migrated
    }

    @MainActor
    static func save(_ state: LiveAssistState) {
        write(encoded(state))
    }

    @MainActor
    static func encoded(_ state: LiveAssistState) -> Data? {
        try? JSONEncoder().encode(MonitorAssistSnapshot(state))
    }

    static func write(_ data: Data?) {
        guard let data else { return }
        UserDefaults.standard.set(data, forKey: assistKey)
    }
}

struct FeedAlignedAssists: View {
    var grid: Bool
    var crosshair: Bool
    var guides: Bool
    var guideAspect: GuideAspect
    var focusPoint: CGPoint
    var overlay: FocusOverlay = .focus
    var sceneFaces: [TrackingBox] = []
    var showFocusChrome = true
    var showTapFocusBox = true
    /// AE lock: the focus / metering box turns yellow with an `AE-L` tag.
    var aeLocked = false
    /// Long-press lock on the tap-focus box: a lock tag at its lower corner.
    var focusLocked = false
    /// When set (letterboxed clip playback), framing overlays align to this rect
    /// instead of the full geometry \u{2014} OpenZCine `FeedAlignedAssists(feed:)`.
    var feed: CGRect? = nil
    /// Decoded raster aspect before the optical correction.
    var sourceAspect: CGFloat? = nil
    /// Recorded frame width/height. Live 1:1 sits as a square inside a 16:9 well.
    var pictureAspect: CGFloat? = nil
    /// Live 180 / MIRROR compose. Nil uses the assist chip only (playback).
    var pictureMirrored: Bool? = nil
    /// MIRROR Vertical. Nil uses the assist chip only.
    var pictureFlippedVertically: Bool? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let assist = model.assist
            let mirrored = pictureMirrored ?? assist.mirrorsHorizontally
            let flippedV = pictureFlippedVertically ?? assist.flipsVertically
            let shown = { (box: TrackingBox) in
                box.flipped(horizontal: mirrored, vertical: flippedV)
            }
            let shownFocus = CGPoint(
                x: mirrored ? 1 - focusPoint.x : focusPoint.x,
                y: flippedV ? 1 - focusPoint.y : focusPoint.y)
            // Live: framing aids sit on the de-squeezed picture. Playback already
            // letterboxes the raster (`feed`); do not re-apply live desqueeze there.
            let feed =
                self.feed
                ?? overlayFeedRect(
                    CGRect(origin: .zero, size: proxy.size), assist, pictureAspect: pictureAspect,
                    sourceAspect: sourceAspect)
            let focusFeed =
                self.feed
                ?? DesqueezeAssist.presentationRect(
                    sourceSize: sourceAspect.map { CGSize(width: $0, height: 1) } ?? proxy.size,
                    in: CGRect(origin: .zero, size: proxy.size), effects: assist.effects)
            let marks = trackingMarks(shown: shown, focus: shownFocus)
            ZStack {
                if guides {
                    GuidesAssist.overlay(feed: feed, assist: assist, fallback: guideAspect)
                }
                if grid {
                    MonitorFeedGrid(
                        feed: feed,
                        thirds: assist.gridThirds,
                        phi: assist.gridPhi,
                        diagonal: assist.gridDiagonal
                    )
                }
                if crosshair { MonitorFeedCrosshair(feed: feed) }
                if assist.splitComparison, assist.isVisible(.lut) {
                    MonitorFeedComparisonMarks(vertical: assist.splitVertical, feed: feed)
                }
                MonitorTrackingLayer(brackets: marks.brackets, focus: marks.focus, feed: focusFeed)
            }
        }
        .allowsHitTesting(false)
    }

    private func trackingMarks(shown: (TrackingBox) -> TrackingBox, focus: CGPoint) -> (
        brackets: [MonitorTrackingBracketValue], focus: MonitorFocusMark?
    ) {
        func bracket(_ box: TrackingBox, _ color: Color, _ width: CGFloat)
            -> MonitorTrackingBracketValue
        {
            let drawn = shown(box)
            return .init(
                normalizedRect: CGRect(
                    x: drawn.x, y: drawn.y, width: drawn.width, height: drawn.height),
                color: color, lineWidth: width)
        }
        var brackets = sceneFaces.map {
            bracket($0, LiveDesign.text.opacity(SceneFacePolicy.dimOpacity), 1.6)
        }
        var focusMark: MonitorFocusMark?
        if showFocusChrome {
            switch overlay {
            case .search(let box):
                brackets.append(bracket(box, LiveDesign.text.opacity(0.88), 1.5))
                focusMark = .init(
                    point: focus, color: aeLocked ? LiveDesign.aeLock : LiveDesign.accent,
                    aeLocked: aeLocked)
            case .subject(let box): brackets.append(bracket(box, LiveDesign.good, 2))
            case .face(let box): brackets.append(bracket(box, LiveDesign.text.opacity(0.92), 1.6))
            case .focus:
                if showTapFocusBox || aeLocked {
                    focusMark = .init(
                        point: focus, color: aeLocked ? LiveDesign.aeLock : LiveDesign.accent,
                        aeLocked: aeLocked, focusLocked: focusLocked)
                }
            }
        }
        return (brackets, focusMark)
    }
}

/// OpenZCine `desqueezedRect` \u{2014} framing aids sit on the visible (shrunk) picture, not the full frame.
@MainActor
func overlayFeedRect(
    _ full: CGRect, _ assist: LiveAssistState, pictureAspect: CGFloat?,
    sourceAspect: CGFloat? = nil
) -> CGRect {
    let effects = assist.effects
    let raster = DesqueezeAssist.presentationRect(
        sourceSize: sourceAspect.map { CGSize(width: $0, height: 1) } ?? full.size,
        in: full, effects: effects)
    guard let pictureAspect, pictureAspect > 0 else { return raster }
    // The recorded picture may be letterboxed inside the camera's live raster.
    return DesqueezeAssist.presentationRect(
        sourceSize: CGSize(width: pictureAspect, height: 1), in: raster, effects: effects)
}

private func feedRect(_ box: TrackingBox, in feed: CGRect) -> CGRect {
    CGRect(
        x: feed.minX + box.x * feed.width,
        y: feed.minY + box.y * feed.height,
        width: max(1, box.width * feed.width),
        height: max(1, box.height * feed.height)
    )
}

enum LiveTrackingChrome {
    static let cancelSize = MonitorTrackingGeometry.cancelSize
    static let cancelHitSize = MonitorTrackingGeometry.cancelHitSize
    static func cornerRadius(for rect: CGRect) -> CGFloat {
        MonitorTrackingGeometry.cornerRadius(for: rect)
    }
    static func cancelRect(
        box: TrackingBox, feed: CGRect, mirrored: Bool, flippedVertically: Bool = false
    ) -> CGRect {
        MonitorTrackingGeometry.cancelRect(
            for: feedRect(box.flipped(horizontal: mirrored, vertical: flippedVertically), in: feed))
    }
    static func bracketArm(along length: CGFloat) -> CGFloat {
        MonitorTrackingGeometry.bracketArm(along: length)
    }
    static func bracketPath(in size: CGSize) -> Path {
        MonitorTrackingGeometry.bracketPath(in: size)
    }
}

/// LEVEL: camera world attitude (`LevelReading`), not this phone. Gauges show
/// picture roll and look-up tilt from the horizon (OpenZCine `LevelGaugeView`);
/// near plumb a bubble shows the lens offset from straight down / up. Stale or
/// missing attitude shows `No level data` and never reads green.
enum LevelAssist {
    static let refresh: TimeInterval = 0.1
    static let rollLiftLandscape = MonitorLevelGeometry.rollLiftLandscape
    static let rollLiftPortrait = MonitorLevelGeometry.rollLiftPortrait

    @MainActor
    static func frames(feed: CGRect, viewport: CGRect, portrait: Bool) -> (roll: CGRect, tilt: CGRect) {
        MonitorLevelGeometry.frames(feed: feed, viewport: viewport, portrait: portrait)
    }

    static func display(_ mode: LevelReading.Mode) -> MonitorLevelDisplay {
        switch mode {
        case .unavailable: .unavailable
        case .gauges(let roll, let tilt): .gauges(rollDeg: roll, tiltDeg: tilt)
        case .bubble(let x, let y): .bubble(xDeg: x, yDeg: y)
        }
    }

    static func accessibilityValue(_ mode: LevelReading.Mode) -> String {
        MonitorLevelGeometry.accessibilityValue(
            display(mode), noDataLabel: WorldLevelSnap.noLevelData)
    }
}

struct FeedLevelView: View {
    let feed: CGRect
    let viewport: CGRect
    let portrait: Bool
    @Environment(AppModel.self) private var model

    var body: some View {
        TimelineView(.periodic(from: .now, by: LevelAssist.refresh)) { _ in
            let mode = model.session.gimbal.levelReading.mode(
                now: ProcessInfo.processInfo.systemUptime,
                // Picture-relative like the stick: TT180 mirrors the shown
                // picture in both Selfie Flip states. Either flip axis reverses
                // the on-screen roll; both (180°) restores it.
                viewFlip: GimbalStick.liveInvertPan(
                    poseInvert: model.session.gimbalPoseInvertPan,
                    assistMirror: model.assist.mirrorsHorizontally)
                    != model.assist.flipsVertically)
            MonitorLevelOverlay(
                display: LevelAssist.display(mode), feed: feed, viewport: viewport,
                portrait: portrait, noDataLabel: WorldLevelSnap.noLevelData)
        }
        .allowsHitTesting(false)
    }
}

/// WAVE / PARADE / HISTO / VECTOR / LIGHTS live in `LiveScopes.swift`.
/// AUDIO meters live in `Assists/AudioAssist.swift` (`AudioMetersPanelMini`).

/// OpenZCine `FalseColorReference` on the live feed.
struct FalseColorLegend: View {
    var scale: FalseColorScaleKind
    var colorMode: ColorMode = .normal
    var rec709: Bool
    var clipByte: Int

    var body: some View {
        FalseColorAssist.referenceDisplay(
            scale: scale, colorMode: colorMode, rec709: rec709, clipByte: clipByte,
            looks: .app
        )
        .allowsHitTesting(false)
    }
}

struct AssistToolRow: View {
    @Bindable var assist: LiveAssistState
    var isLocked = false

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 6) {
                ForEach(LiveAssistTool.settingsCases) { tool in
                    Button {
                        guard !isLocked else { return }
                        assist.toggle(tool)
                    } label: {
                        AssistToolChip(tool: tool, isOn: assist.isOn(tool))
                    }
                    .buttonStyle(.monitorTapTarget)
                    .simultaneousGesture(
                        LongPressGesture(minimumDuration: 0.25).onEnded { _ in
                            guard !isLocked, tool.hasConfiguration else { return }
                            assist.configureTool = tool
                            if tool == .lut { assist.showLUTPicker = false }
                        }
                    )
                }
            }
            .padding(.horizontal, 2)
        }
        .monitorScrollFade(.horizontal)
        .allowsHitTesting(!isLocked)
    }
}

struct AssistToolChip: View {
    let tool: LiveAssistTool
    let isOn: Bool
    var compact = false

    var body: some View {
        VStack(spacing: 3) {
            AssistToolIcon(tool: tool, size: 19)
                .frame(height: 23)
            Text(tool.rawValue)
                .font(MonitorTheme.font(9, weight: .medium)).monospacedDigit()
                .tracking(0.9)
                .lineLimit(1)
        }
        .foregroundStyle(isOn ? LiveDesign.accent : LiveDesign.muted)
        .padding(.vertical, 5)
        .padding(.horizontal, compact ? 5 : 8)
        .frame(minWidth: compact ? 48 : 52)
        .background {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                .fill(isOn ? LiveDesign.accentDim : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                .strokeBorder(isOn ? LiveDesign.accent : Color.clear, lineWidth: 1)
        }
    }
}

struct AssistToolIcon: View {
    let tool: LiveAssistTool
    /// Shared palettes supply their own size; legacy standalone chips keep 19 points.
    var size: CGFloat? = 19

    var body: some View {
        if let shared = tool.sharedTool {
            MonitorAssistToolGlyph(tool: shared, size: size)
        } else if let icon = tool.lucideIcon {
            icon.frame(width: size, height: size)
        }
    }
}
