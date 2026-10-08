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


/// This app's LUT looks: its official cubes, saved choices and custom LUT folder.
extension MonitorLUTLooks {
    /// Shared initialization may read the provider, but native lookup waits for app prefs.
    convenience init() {
        self.init(official: .app, preferences: .app, customLUTs: .app, preparationReady: false,
            lookProfile: DJICameraLUTProfile.make(family: .pocket, cameraName: nil),
            colorSourceProfile: DJIMonitorColorProfile.value)
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
            cleanPinCases: MonitorAssistSelection.cleanPinCases,
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
    static let common = MonitorOperatorPreferences(storage: .standard,
        keys: .init(keepScreenAwake: "OpenPocketCine.KeepScreenAwake", hdrDisplay: "OpenPocketCine.HDRDisplay",
            recordConfirmation: "OpenPocketCine.RecordConfirmation", haptics: "OpenPocketCine.HapticsEnabled",
            cacheOriginals: "OpenPocketCine.CacheFullResolution"))
    static let display = MonitorDisplayPreferences(
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
        get { common.keepScreenAwake }
        set { common.keepScreenAwake = newValue }
    }

    /// Outdoor HDR panel boost for live view. Off by default.
    static var hdrDisplay: Bool {
        get { common.hdrDisplay }
        set { common.hdrDisplay = newValue }
    }

    /// Download the original camera file when a clip is opened. Off keeps the 720p proxy.
    static var cacheFullResolution: Bool {
        get { common.cacheOriginals }
        set { common.cacheOriginals = newValue }
    }

    static var recordConfirmationEnabled: Bool {
        get { common.recordConfirmation }
        set { common.recordConfirmation = newValue }
    }

    static var hapticsEnabled: Bool {
        get { common.haptics }
        set { common.haptics = newValue }
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

    static var dispLive: MonitorDisplayChrome {
        get { display.live }
        set { display.live = newValue }
    }

    static var dispClean: MonitorDisplayChrome {
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

    static var playbackVisibleAssistTools: Set<MonitorAssistSelection> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: playbackAssistsKey) as? [String]
            else { return [] }
            return Set(raw.compactMap(MonitorAssistSelection.init(rawValue:)))
        }
        set {
            UserDefaults.standard.set(newValue.map(\.rawValue).sorted(), forKey: playbackAssistsKey)
        }
    }

    /// Absent key = never pinned, so the stock set. Stored empty = operator cleared every pin.
    static var cleanViewPinnedTools: Set<MonitorAssistSelection> {
        get {
            guard let raw = UserDefaults.standard.array(forKey: cleanPinsKey) as? [String] else {
                return LiveAssistState.cleanViewDefaultPinnedTools
            }
            let allowed = Set(MonitorAssistSelection.cleanPinCases)
            return Set(raw.compactMap(MonitorAssistSelection.init(rawValue:))).intersection(allowed)
        }
        set {
            let ordered = MonitorAssistSelection.cleanPinCases.filter { newValue.contains($0) }.map(
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

typealias FeedAlignedAssists = FeedAssistMarks<AppModel>

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
    var scale: MonitorFalseColorSelection
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
                ForEach(MonitorAssistSelection.settingsCases) { tool in
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
    let tool: MonitorAssistSelection
    let isOn: Bool
    var compact = false
    var body: some View {
        MonitorAssistChip(id: tool.rawValue, isOn: isOn, compact: compact) {
            AssistToolIcon(tool: tool, size: 19)
        }
    }
}

struct AssistToolIcon: View {
    let tool: MonitorAssistSelection
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
