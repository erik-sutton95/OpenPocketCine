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
        if monitorColorMode == nil { monitorColorMode = LUTPreferences.app.lastMonitorColorMode }
        looks.preparationReady = true
        if lutEnabled { refreshLUTCube() }
    }
}

enum OperatorPrefs {
    static let common = MonitorOperatorPreferences(storage: .standard,
        keys: .init(keepScreenAwake: "OpenPocketCine.KeepScreenAwake", hdrDisplay: "OpenPocketCine.HDRDisplay",
            recordConfirmation: "OpenPocketCine.RecordConfirmation", haptics: "OpenPocketCine.HapticsEnabled",
            cacheOriginals: "OpenPocketCine.CacheFullResolution",
            remoteShutter: "OpenPocketCine.RemoteShutter"),
        defaults: .init(remoteShutter: false))
    static let motion = MonitorMotionPreferences.camera(storage: .standard, prefix: "OpenPocketCine")
    static let sharing = MonitorSharingPreferences.camera(storage: .standard, prefix: "OpenPocketCine")
    private static let toolUsage = MonitorToolUsagePreferences(
        storage: .standard, key: "OpenPocketCine.AssistToolUsage.v1")
    static let capture = MonitorCaptureOperatorPreferences(storage: .standard, prefix: "OpenPocketCine")
    static let display = MonitorDisplayPreferences(
        storage: .standard,
        keys: .init(live: "OpenPocketCine.DispChrome.Live", clean: "OpenPocketCine.DispChrome.Clean"))
    private static let cleanPinsKey = "OpenPocketCine.CleanViewPins.v1"

    static var shareThisFeed: Bool {
        get { sharing.shareThisFeed }
        set { sharing.shareThisFeed = newValue }
    }

    static var controlRequests: Bool {
        get { sharing.controlRequests }
        set { sharing.controlRequests = newValue }
    }

    /// Ceiling index on the watcher-relay bitrate ladder. 0 = highest quality.
    static var broadcastPriority: Int {
        get { sharing.broadcastPriority }
        set { sharing.broadcastPriority = newValue }
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

    /// Volume and media presses toggle recording while the live view is in front (A2-32); off by default.
    static var remoteShutterEnabled: Bool {
        get { common.remoteShutter }
        set { common.remoteShutter = newValue }
    }

    static var hapticsEnabled: Bool {
        get { common.haptics }
        set { common.haptics = newValue }
    }

    static var assistToolUsage: MonitorToolUsage {
        get { toolUsage.value }
        set { toolUsage.value = newValue }
    }

    static var headTrackingEnabled: Bool {
        get { motion.headTrackingEnabled }
        set { motion.headTrackingEnabled = newValue }
    }

    /// Stick double-tap / gamepad Circle/B. Absent key is Recenter.
    static var gimbalDoubleTap: GimbalDoubleTap {
        get { motion.doubleTap }
        set { motion.doubleTap = newValue }
    }

    static var gimbalRamp: GimbalRamp {
        get { motion.ramp }
        set { motion.ramp = newValue }
    }

    static var gimbalStickSensitivity: Int {
        get { motion.gimbalStickSensitivity }
        set { motion.gimbalStickSensitivity = newValue }
    }

    static var virtualJoystickInvertPan: Bool {
        get { motion.virtualJoystickInvertPan }
        set { motion.virtualJoystickInvertPan = newValue }
    }

    static var virtualJoystickInvertTilt: Bool {
        get { motion.virtualJoystickInvertTilt }
        set { motion.virtualJoystickInvertTilt = newValue }
    }

    static var virtualJoystickDeadzonePercent: Int {
        get { motion.virtualJoystickDeadzonePercent }
        set { motion.virtualJoystickDeadzonePercent = newValue }
    }

    static var virtualJoystickResponseCurve: GimbalStick.ResponseCurve {
        get { motion.responseCurve }
        set { motion.responseCurve = newValue }
    }

    static var virtualJoystickSize: MonitorJoystickSize {
        get { motion.joystickSize }
        set { motion.joystickSize = newValue }
    }

    static var virtualJoystickMapping: GimbalStick.Mapping { motion.joystickMapping }

    static var dispLive: MonitorDisplayChrome {
        get { display.live }
        set { display.live = newValue }
    }

    static var dispClean: MonitorDisplayChrome {
        get { display.clean }
        set { display.clean = newValue }
    }

    static var shutterUsesAngle: Bool {
        get { capture.shutterUsesAngle }
        set { capture.shutterUsesAngle = newValue }
    }

    static var shutterAngleDegrees: Double {
        get { capture.shutterAngleDegrees }
        set { capture.shutterAngleDegrees = newValue }
    }

    static var portraitFeedAspect: PortraitFeedAspect {
        get { capture.portraitFeedAspect }
        set { capture.portraitFeedAspect = newValue }
    }

    /// Auto-expo: meter Vision faces to middle gray and write EV.
    static var facePriorityExposureEnabled: Bool {
        get { capture.facePriorityExposure }
        set { capture.facePriorityExposure = newValue }
    }

    /// D-Log 400 and D-Log2 1600 when the operator is still on native ISO.
    static var nativeISOHopEnabled: Bool {
        get { capture.nativeISOHop }
        set { capture.nativeISOHop = newValue }
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

    /// The shared assist state already loaded the snapshot, clean pins and playback tools.
    @MainActor
    static func load(into state: LiveAssistState) {
        LUTPreferences.app.migrateLegacySelectionIfNeeded(lutEnabled: state.lutEnabled)
        let migrated = LUTPreferences.app.lutSelection.migratedToDJICatalog
        if migrated != LUTPreferences.app.lutSelection {
            LUTPreferences.app.lutSelection = migrated
        }
        state.lutSelection = migrated
    }

    @MainActor
    static func encoded(_ state: LiveAssistState) -> Data? {
        state.encodedSnapshot()
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
                        LongPressGesture(minimumDuration: 0.25).onEnded { _ in configure(tool) }
                    )
                    // A Mac's right-click opens the tool's options, as the long press does.
                    .monitorSecondaryClick { configure(tool) }
                }
            }
            .padding(.horizontal, 2)
        }
        .monitorScrollFade(.horizontal)
        .allowsHitTesting(!isLocked)
    }

    private func configure(_ tool: MonitorAssistSelection) {
        guard !isLocked, tool.hasConfiguration else { return }
        assist.configureTool = tool
        if tool == .lut { assist.showLUTPicker = false }
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
