import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Cinema live-monitor set. MAG is retired; PLAY stays off the video toolbar.
typealias LiveAssistTool = MonitorAssistSelection

extension MonitorAssistSelection {
    var isRetired: Bool { self == .magnification }
    var isPhotographyOnly: Bool { self == .instantReview }

    /// Playback drops LEVEL (needs live camera attitude) and MAG (no on-feed key).
    /// AUDIO rides last, matching the live strip's trailing section.
    static var playbackToolbarCases: [LiveAssistTool] {
        toolbarCases.filter { $0 != .level && $0 != .magnification && $0 != .evMeter } + [
            .audioMeters
        ]
    }

    /// OpenZCine `activeCases` minus photography-only and AUDIO.
    /// AUDIO is appended as its own trailing section in `LiveAssistBar`.
    /// ND sits with the exposure meters (HISTO / VECTOR / LIGHTS).
    static var toolbarGroups: [[LiveAssistTool]] {
        [
            [.lut, .peaking, .falseColor],
            [.zebra, .waveform, .parade],
            [.histogram, .vectorscope, .trafficLights, .ndMeter, .evMeter],
            [.guides, .grid, .crosshair, .level],
            [.desqueeze, .mirror],
        ]
    }

    static var toolbarCases: [LiveAssistTool] { toolbarGroups.flatMap { $0 } }

    /// View Assist settings list - same cinema set as the bar, plus AUDIO.
    static var settingsCases: [LiveAssistTool] {
        toolbarCases + [.audioMeters]
    }

    /// Tools the operator can keep on DISP 2. Camera EV stays exclusive to DISP 1.
    static var cleanPinCases: [LiveAssistTool] { settingsCases.filter { $0 != .evMeter } }

    /// Compact label for the Display ▸ DISP 2 pin grid.
    var displaySettingsTitle: String { sharedTool?.displaySettingsTitle ?? title }

    var hasConfiguration: Bool { sharedTool?.hasConfiguration ?? false }

    /// The approved prototype owns these tool glyphs; app-only tools retain
    /// Lucide fallbacks without inventing a new visual language.
    var monitorIcon: MonitorAssistIcon? { sharedTool?.monitorIcon }

    /// Existing app-only assist glyphs use the shared Lucide catalog.
    var opcIcon: OpcIcon? {
        sharedTool?.fallbackIcon
            ?? (self == .instantReview ? .image : self == .magnification ? .zoomIn : nil)
    }

    var title: String {
        sharedTool?.title ?? (self == .instantReview ? "Instant Playback" : "Magnify")
    }
}

typealias GuideFamily = MonitorGuideFamily

typealias GuideAspect = MonitorGuideAspect

/// Catalog and camera source interpretation belong to the app; shared state receives media values.
@MainActor @Observable
final class AppMonitorLooks: MonitorLookProvider {
    // Shared initialization may read the provider, but native lookup waits for app prefs.
    var preparationReady = false
    var lutSelection: LUTSelection = .djiAuto
    var monitorColorMode: ColorMode?
    var monitorFamily: CameraBodyFamily = .pocket
    var monitorCameraName: String?
    var liveIsPhoto = false
    var referenceClipByte: Int {
        OpenCineDJI.ScopeExposureCeiling.referenceClipByte(transfer: transfer)
    }
    func lutExposureTransfer(for transfer: MonitorTransfer) -> MonitorTransfer {
        transfer.lutExposureTransfer
    }
    var selection: LUTSelection { lutSelection }
    var transfer: MonitorTransfer { MonitorTransfer(monitorColorMode ?? .normal) }
    func statusLabel(enabled: Bool) -> String {
        if liveIsPhoto, enabled, lutSelection == .auto || lutSelection == .djiAuto {
            return "Auto · Rec.709"
        }
        return LUTResolver.statusLabel(
            enabled: enabled, selection: lutSelection, source: resolvedSource())
    }
    func resolvedSource() -> LUTSource {
        LiveLUTResolver.resolve(
            selection: lutSelection,
            colorMode: monitorColorMode,
            family: monitorFamily,
            cameraName: monitorCameraName,
            hasCustomDLog: CustomLUTStore.hasCube(.dLog),
            hasCustomDLog2: CustomLUTStore.hasCube(.dLog2),
            hasCustomRec709: CustomLUTStore.hasCube(.rec709),
            customFileName: OperatorPrefs.selectedCustomFileName,
            isPhoto: liveIsPhoto
        )
    }

    var cube: CubeLUT? {
        guard preparationReady else { return nil }
        switch resolvedSource() {
        case .official(let id):
            return BundledPocketLUT.cube(id)
        case .dji(let id):
            return BundledOfficialDJILUT.cube(id)
        case .creative(let look):
            return look.cube()
        case .custom(let slot):
            return CustomLUTStore.cube(slot)
        case .file(let name):
            return CustomLUTStore.cube(fileName: name)
        case .off:
            return nil
        }
    }

}

typealias LiveAssistState = MonitorAssistState<AppMonitorLooks>

extension MonitorAssistState where Looks == AppMonitorLooks {
    convenience init() {
        weak var state: LiveAssistState?
        self.init(
            looks: AppMonitorLooks(), storage: .standard,
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
        if monitorColorMode == nil { monitorColorMode = OperatorPrefs.lastMonitorColorMode }
        looks.preparationReady = true
        if lutEnabled { refreshLUTCube() }
    }
    var lutSelection: LUTSelection {
        get { looks.lutSelection }
        set { looks.lutSelection = newValue }
    }
    var monitorColorMode: ColorMode? {
        get { looks.monitorColorMode }
        set { looks.monitorColorMode = newValue }
    }
    var monitorFamily: CameraBodyFamily {
        get { looks.monitorFamily }
        set { looks.monitorFamily = newValue }
    }
    var monitorCameraName: String? {
        get { looks.monitorCameraName }
        set { looks.monitorCameraName = newValue }
    }
    var liveIsPhoto: Bool {
        get { looks.liveIsPhoto }
        set { looks.liveIsPhoto = newValue; allowsTransferInference = !newValue }
    }
    var lutStatusLabel: String { looks.statusLabel(enabled: lutEnabled) }
    func resolvedSource() -> LUTSource { looks.resolvedSource() }
    var longPressAnchor: CGRect {
        get {
            CGRect(
                x: longPressAnchorRect.x, y: longPressAnchorRect.y,
                width: longPressAnchorRect.width, height: longPressAnchorRect.height)
        }
        set { longPressAnchorRect = MonitorRect(newValue) }
    }
    /// Picking a look turns LUT on. Auto stays Auto until the operator picks something else.
    func selectLUT(_ selection: LUTSelection) {
        lutSelection = selection
        lutEnabled = true
        OperatorPrefs.lutSelection = selection
        refreshLUTCube()
        persist()
    }

    /// Color / zoom / body changes only swap the cube while an Auto row is selected.
    /// Photo does not persist Rec.709 over last live log, and does not rewrite LUT prefs.
    func syncLUT(
        to colorMode: ColorMode?,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil,
        isPhoto: Bool = false,
        persistLast: Bool = true
    ) {
        liveIsPhoto = isPhoto && !gradesClip
        monitorColorMode = LiveMonitorColorScience.colorMode(
            isPhoto: liveIsPhoto, colorMode: colorMode)
        monitorFamily = family
        if let cameraName { monitorCameraName = cameraName }
        if persistLast, let colorMode, !liveIsPhoto {
            OperatorPrefs.lastMonitorColorMode = colorMode
        }
        refreshLUTCube()
    }

    /// Playback Auto follows the clip's ColorGammaSxS. Do not persist Rec.709
    /// from a Normal take over last live D-Log / D-Log2.
    func adoptPlaybackColor(
        _ colorMode: ColorMode,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil
    ) {
        liveIsPhoto = false
        monitorColorMode = colorMode
        monitorFamily = family
        if let cameraName { monitorCameraName = cameraName }
        refreshLUTCube()
    }

    /// LUT sheet appear. Live SET must not replace the clip's Auto cube -
    /// including disconnected library playback (`gradesClip`, no camera SET).
    /// Watcher isolation: do not restamp from the camera session.
    func bindLUTPicker(
        live: ColorMode?,
        inPlayback: Bool,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil,
        isPhoto: Bool = false,
        isWatching: Bool = false
    ) {
        if inPlayback || gradesClip {
            liveIsPhoto = false
            refreshLUTCube()
            return
        }
        if isWatching {
            refreshLUTCube()
            return
        }
        syncLUT(to: live, family: family, cameraName: cameraName, isPhoto: isPhoto)
    }

    /// Import adds a custom cube. Auto rows keep following color; otherwise this file arms.
    func importCustom(fileName: String) {
        OperatorPrefs.selectedCustomFileName = fileName
        if lutSelection != .auto, lutSelection != .djiAuto {
            lutSelection = .customFile
            OperatorPrefs.lutSelection = .customFile
        }
        lutEnabled = true
        refreshLUTCube()
        persist()
    }

    func importCustom(slot: CustomLUTSlot, fileName: String) {
        OperatorPrefs.setCustomFileName(fileName, for: slot)
        importCustom(fileName: fileName)
    }

    func clearCustomSlot(_ slot: CustomLUTSlot) {
        if lutSelection == slot.selection
            || OperatorPrefs.selectedCustomFileName == OperatorPrefs.customFileName(for: slot)
        {
            lutSelection = .auto
            OperatorPrefs.lutSelection = .auto
            OperatorPrefs.selectedCustomFileName = nil
        }
        refreshLUTCube()
        persist()
    }

    func selectCustomFile(_ fileName: String) {
        OperatorPrefs.selectedCustomFileName = fileName
        selectLUT(.customFile)
    }

    func clearCustomFile(_ fileName: String) {
        if OperatorPrefs.selectedCustomFileName == fileName || lutSelection == .customFile {
            lutSelection = .auto
            OperatorPrefs.lutSelection = .auto
            OperatorPrefs.selectedCustomFileName = nil
        }
        for slot in CustomLUTSlot.allCases where OperatorPrefs.customFileName(for: slot) == fileName
        {
            OperatorPrefs.setCustomFileName(nil, for: slot)
        }
        try? CustomLUTStore.remove(StoredCustomLUT(fileName: fileName))
        refreshLUTCube()
        persist()
    }

    func exportLUTCube(bakeExposure: Bool) -> CubeLUT? {
        let color = PlaybackLUTColor.resolve(
            clip: monitorColorMode, live: monitorColorMode,
            last: OperatorPrefs.lastMonitorColorMode)
        return exportCube(bakeExposure: bakeExposure, transfer: MonitorTransfer(color ?? .normal))
    }
}

enum OperatorPrefs {
    private static let display = MonitorDisplayPreferences(
        storage: .standard,
        keys: .init(live: "OpenPocketCine.DispChrome.Live", clean: "OpenPocketCine.DispChrome.Clean"))
    private static let awakeKey = "OpenPocketCine.KeepScreenAwake"
    private static let hdrDisplayKey = "OpenPocketCine.HDRDisplay"
    private static let lutKey = "OpenPocketCine.LastLUT"
    private static let customLUTKey = "OpenPocketCine.LastCustomLUT"
    private static let lutWasCustomKey = "OpenPocketCine.LastLUTWasCustom"
    private static let lutSelectionKey = "OpenPocketCine.LUTSelection"
    private static let customRec709FileKey = "OpenPocketCine.CustomRec709File"
    private static let customDLogFileKey = "OpenPocketCine.CustomDLogFile"
    private static let customDLog2FileKey = "OpenPocketCine.CustomDLog2File"
    private static let selectedCustomFileKey = "OpenPocketCine.SelectedCustomLUTFile"
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
    private static let lastMonitorColorModeKey = "OpenPocketCine.LastMonitorColorMode"
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

    /// Last live `ColorMode` so Auto LUT can bind a cube from the offline library.
    static var lastMonitorColorMode: ColorMode? {
        get {
            guard UserDefaults.standard.object(forKey: lastMonitorColorModeKey) != nil else {
                return nil
            }
            return ColorMode(
                rawValue: UInt8(
                    truncatingIfNeeded: UserDefaults.standard.integer(
                        forKey: lastMonitorColorModeKey)))
        }
        set {
            if let newValue {
                UserDefaults.standard.set(Int(newValue.rawValue), forKey: lastMonitorColorModeKey)
            } else {
                UserDefaults.standard.removeObject(forKey: lastMonitorColorModeKey)
            }
        }
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

    static var lastLUT: String {
        get {
            if lastLUTWasCustom, let file = lastCustomFileName {
                return CustomLUTIndex.displayName(fileName: file)
            }
            return lastBuiltInLUT
        }
        set { UserDefaults.standard.set(newValue, forKey: lutKey) }
    }

    static var lastBuiltInLUT: String {
        UserDefaults.standard.string(forKey: lutKey) ?? LUTSelection.auto.title
    }

    static var lastCustomFileName: String? {
        get { UserDefaults.standard.string(forKey: customLUTKey) }
        set { UserDefaults.standard.set(newValue, forKey: customLUTKey) }
    }

    static var lastLUTWasCustom: Bool {
        get { UserDefaults.standard.bool(forKey: lutWasCustomKey) }
        set { UserDefaults.standard.set(newValue, forKey: lutWasCustomKey) }
    }

    static var lutSelection: LUTSelection {
        get {
            if let raw = UserDefaults.standard.string(forKey: lutSelectionKey),
                let value = LUTSelection(rawValue: raw)
            {
                return value
            }
            return .djiAuto
        }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: lutSelectionKey) }
    }

    static func customFileName(for slot: CustomLUTSlot) -> String? {
        UserDefaults.standard.string(forKey: customFileKey(slot))
    }

    static func setCustomFileName(_ fileName: String?, for slot: CustomLUTSlot) {
        UserDefaults.standard.set(fileName, forKey: customFileKey(slot))
    }

    static var selectedCustomFileName: String? {
        get {
            let name = UserDefaults.standard.string(forKey: selectedCustomFileKey)
            guard let name, CustomLUTIndex.isSafeFileName(name) else { return nil }
            return name
        }
        set { UserDefaults.standard.set(newValue, forKey: selectedCustomFileKey) }
    }

    private static func customFileKey(_ slot: CustomLUTSlot) -> String {
        switch slot {
        case .rec709: customRec709FileKey
        case .dLog: customDLogFileKey
        case .dLog2: customDLog2FileKey
        }
    }

    @MainActor
    static func load(into state: LiveAssistState) {
        if let data = UserDefaults.standard.data(forKey: assistKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            snap.apply(to: state)
        }
        migrateLegacyLUTIfNeeded(into: state)
        let migrated = lutSelection.migratedToDJICatalog
        if migrated != lutSelection { lutSelection = migrated }
        state.lutSelection = migrated
    }

    /// One-shot: old Built-in looks become Auto; a stored custom file becomes Custom D-Log.
    @MainActor
    private static func migrateLegacyLUTIfNeeded(into state: LiveAssistState) {
        guard UserDefaults.standard.object(forKey: lutSelectionKey) == nil else { return }
        if lastLUTWasCustom, let file = lastCustomFileName,
            CustomLUTIndex.isSafeFileName(file)
        {
            setCustomFileName(file, for: .dLog)
            if state.lutEnabled {
                UserDefaults.standard.set(LUTSelection.customDLog.rawValue, forKey: lutSelectionKey)
                return
            }
        }
        UserDefaults.standard.set(LUTSelection.djiAuto.rawValue, forKey: lutSelectionKey)
    }

    @MainActor
    static func save(_ state: LiveAssistState) {
        write(encoded(state))
    }

    @MainActor
    static func encoded(_ state: LiveAssistState) -> Data? {
        try? JSONEncoder().encode(Snapshot(state))
    }

    static func write(_ data: Data?) {
        guard let data else { return }
        UserDefaults.standard.set(data, forKey: assistKey)
    }

    /// OpenZCine `operatorPreferences.v1` / `assistConfiguration.v1` analogue \u{2014} one blob.
    typealias Snapshot = MonitorAssistSnapshot
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
            ZStack {
                if guides {
                    GuidesAssist.overlay(feed: feed, assist: assist, fallback: guideAspect)
                }
                if grid {
                    FeedGridView(
                        feed: feed,
                        thirds: assist.gridThirds,
                        phi: assist.gridPhi,
                        diagonal: assist.gridDiagonal
                    )
                }
                if crosshair { FeedCrosshairView(feed: feed) }
                if assist.splitComparison, assist.isVisible(.lut) {
                    FeedSplitComparisonMarks(vertical: assist.splitVertical, feed: feed)
                }
                ForEach(Array(sceneFaces.enumerated()), id: \.offset) { _, box in
                    TrackingBracketView(
                        rect: feedRect(shown(box), in: focusFeed),
                        color: LiveDesign.text.opacity(SceneFacePolicy.dimOpacity),
                        lineWidth: 1.6
                    )
                }
                if showFocusChrome {
                    switch overlay {
                    case .search(let box):
                        TrackingBoxView(
                            feed: focusFeed, box: shown(box))
                        FocusBoxView(
                            feed: focusFeed,
                            normalized: shownFocus,
                            aeLocked: aeLocked
                        )
                    case .subject(let box):
                        SubjectBoxView(feed: focusFeed, box: shown(box))
                    case .face(let box):
                        TrackingBracketView(
                            rect: feedRect(shown(box), in: focusFeed),
                            color: LiveDesign.text.opacity(0.92),
                            lineWidth: 1.6
                        )
                    case .focus:
                        if showTapFocusBox || aeLocked {
                            FocusBoxView(
                                feed: focusFeed,
                                normalized: shownFocus,
                                aeLocked: aeLocked,
                                focusLocked: focusLocked
                            )
                        }
                    }
                }
            }
        }
        .allowsHitTesting(false)
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
    static let cancelSize: CGFloat = 28
    /// Visible disc is `cancelSize`; the module + pinch-well hole is HIG 44.
    static let cancelHitSize: CGFloat = 44

    static func cornerRadius(for rect: CGRect) -> CGFloat {
        min(LiveDesign.cornerRadius, max(6, min(rect.width, rect.height) * 0.12))
    }

    static func cancelRect(
        box: TrackingBox, feed: CGRect, mirrored: Bool, flippedVertically: Bool = false
    ) -> CGRect {
        let rect = feedRect(
            box.flipped(horizontal: mirrored, vertical: flippedVertically), in: feed)
        let s = cancelHitSize
        return CGRect(x: rect.maxX - s / 2, y: rect.minY - s / 2, width: s, height: s)
    }

    /// Corner-bracket arm. Leaves a gap ≥ 25% of the side so it reads as a
    /// traditional tracking box, not a closed frame.
    static func bracketArm(along length: CGFloat) -> CGFloat {
        let proposed = length * 0.26
        let minGap = max(8, length * 0.28)
        return min(max(10, proposed), max(10, (length - minGap) / 2))
    }

    static func bracketPath(in size: CGSize) -> Path {
        let w = size.width
        let h = size.height
        let ax = bracketArm(along: w)
        let ay = bracketArm(along: h)
        let r = min(
            cornerRadius(for: CGRect(origin: .zero, size: size)),
            max(0, ax - 1),
            max(0, ay - 1)
        )
        var path = Path()
        path.move(to: CGPoint(x: 0, y: ay))
        path.addLine(to: CGPoint(x: 0, y: r))
        if r >= 3 {
            path.addQuadCurve(to: CGPoint(x: r, y: 0), control: CGPoint(x: 0, y: 0))
        } else {
            path.addLine(to: CGPoint(x: 0, y: 0))
            path.addLine(to: CGPoint(x: r, y: 0))
        }
        path.addLine(to: CGPoint(x: ax, y: 0))
        path.move(to: CGPoint(x: w - ax, y: 0))
        path.addLine(to: CGPoint(x: w - r, y: 0))
        if r >= 3 {
            path.addQuadCurve(to: CGPoint(x: w, y: r), control: CGPoint(x: w, y: 0))
        } else {
            path.addLine(to: CGPoint(x: w, y: 0))
            path.addLine(to: CGPoint(x: w, y: r))
        }
        path.addLine(to: CGPoint(x: w, y: ay))
        path.move(to: CGPoint(x: w, y: h - ay))
        path.addLine(to: CGPoint(x: w, y: h - r))
        if r >= 3 {
            path.addQuadCurve(to: CGPoint(x: w - r, y: h), control: CGPoint(x: w, y: h))
        } else {
            path.addLine(to: CGPoint(x: w, y: h))
            path.addLine(to: CGPoint(x: w - r, y: h))
        }
        path.addLine(to: CGPoint(x: w - ax, y: h))
        path.move(to: CGPoint(x: ax, y: h))
        path.addLine(to: CGPoint(x: r, y: h))
        if r >= 3 {
            path.addQuadCurve(to: CGPoint(x: 0, y: h - r), control: CGPoint(x: 0, y: h))
        } else {
            path.addLine(to: CGPoint(x: 0, y: h))
            path.addLine(to: CGPoint(x: 0, y: h - r))
        }
        path.addLine(to: CGPoint(x: 0, y: h - ay))
        return path
    }
}

private struct TrackingBracketView: View {
    let rect: CGRect
    let color: Color
    var lineWidth: CGFloat = 2

    var body: some View {
        LiveTrackingChrome.bracketPath(in: rect.size)
            .stroke(
                color,
                style: StrokeStyle(lineWidth: lineWidth, lineCap: .round, lineJoin: .round)
            )
            .shadow(color: .black.opacity(0.55), radius: 1)
            .frame(width: rect.width, height: rect.height)
            .position(x: rect.midX, y: rect.midY)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
    }
}

private struct TrackingBoxView: View {
    let feed: CGRect
    let box: TrackingBox

    var body: some View {
        TrackingBracketView(
            rect: feedRect(box, in: feed),
            color: LiveDesign.text.opacity(0.88),
            lineWidth: 1.5
        )
    }
}

/// Locked subject: traditional corner-bracket box. Cancel X is chrome.
private struct SubjectBoxView: View {
    let feed: CGRect
    let box: TrackingBox

    var body: some View {
        TrackingBracketView(rect: feedRect(box, in: feed), color: LiveDesign.good)
    }
}

private struct FocusBoxView: View {
    let feed: CGRect
    let normalized: CGPoint
    var aeLocked = false
    var focusLocked = false

    var body: some View {
        let side = min(feed.width, feed.height) * LiveFeedFocusGesture.focusBoxSideFraction
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        let x = feed.minX + normalized.x * feed.width
        let y = feed.minY + normalized.y * feed.height
        // The tag sits right of the box, or left when the box is near the right edge.
        let tagLeading = x + side / 2 + 26 > feed.maxX
        ZStack {
            RoundedRectangle(
                cornerRadius: LiveTrackingChrome.cornerRadius(for: rect), style: .continuous
            )
            .stroke(aeLocked ? LiveDesign.aeLock : LiveDesign.accent, lineWidth: 1.5)
            .shadow(color: .black.opacity(0.6), radius: 1)
            .frame(width: side, height: side)
            .position(x: x, y: y)
            if aeLocked {
                Text("AE-L")
                    .font(MonitorTheme.font(9, weight: .semibold))
                    .kerning(0.5)
                    .foregroundStyle(LiveDesign.aeLock)
                    .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)
                    .fixedSize()
                    .position(
                        x: tagLeading ? x - side / 2 - 14 : x + side / 2 + 14, y: y - side / 2 + 6)
            }
            if focusLocked {
                OpcIcon.lock
                    .frame(width: 10, height: 10)
                    .foregroundStyle(aeLocked ? LiveDesign.aeLock : LiveDesign.accent)
                    .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)
                    .position(
                        x: tagLeading ? x - side / 2 - 10 : x + side / 2 + 10, y: y + side / 2 - 6)
            }
        }
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }
}

struct FeedGridView: View {
    let feed: CGRect
    var thirds = true
    var phi = false
    var diagonal = false

    var body: some View {
        Path { path in
            if thirds { fractions(&path, [1.0 / 3, 2.0 / 3]) }
            if phi { fractions(&path, [0.382, 0.618]) }
            if diagonal {
                path.move(to: CGPoint(x: feed.minX, y: feed.minY))
                path.addLine(to: CGPoint(x: feed.maxX, y: feed.maxY))
                path.move(to: CGPoint(x: feed.maxX, y: feed.minY))
                path.addLine(to: CGPoint(x: feed.minX, y: feed.maxY))
            }
        }
        .stroke(Color.white.opacity(0.22), lineWidth: 1)
    }

    private func fractions(_ path: inout Path, _ fractions: [CGFloat]) {
        for fraction in fractions {
            let x = feed.minX + feed.width * fraction
            let y = feed.minY + feed.height * fraction
            path.move(to: CGPoint(x: x, y: feed.minY))
            path.addLine(to: CGPoint(x: x, y: feed.maxY))
            path.move(to: CGPoint(x: feed.minX, y: y))
            path.addLine(to: CGPoint(x: feed.maxX, y: y))
        }
    }
}

struct FeedCrosshairView: View {
    let feed: CGRect

    var body: some View {
        ZStack {
            Rectangle().fill(Color.white.opacity(0.65)).frame(width: 1.4, height: 40)
            Rectangle().fill(Color.white.opacity(0.65)).frame(width: 40, height: 1.4)
        }
        .position(x: feed.midX, y: feed.midY)
    }
}

struct FeedSplitComparisonMarks: View {
    let vertical: Bool
    let feed: CGRect

    var body: some View {
        ZStack {
            Rectangle()
                .fill(Color.white.opacity(0.5))
                .frame(width: vertical ? 1 : feed.width, height: vertical ? feed.height : 1)
                .position(x: feed.midX, y: feed.midY)
            label("LOG")
                .position(
                    x: vertical ? feed.midX - 16 : feed.minX + feed.width * 0.16,
                    y: vertical ? feed.minY + feed.height * 0.16 : feed.midY - 10)
            label("LUT")
                .position(
                    x: vertical ? feed.midX + 16 : feed.minX + feed.width * 0.16,
                    y: vertical ? feed.minY + feed.height * 0.16 : feed.midY + 10)
        }
        .allowsHitTesting(false)
    }

    private func label(_ text: String) -> some View {
        Text(text)
            .font(MonitorTheme.font(8, weight: .semibold)).monospacedDigit()
            .kerning(0.5)
            .foregroundStyle(Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)
    }
}

/// LEVEL: camera world attitude (`LevelReading`), not this phone. Gauges show
/// picture roll and look-up tilt from the horizon (OpenZCine `LevelGaugeView`);
/// near plumb a bubble shows the lens offset from straight down / up. Stale or
/// missing attitude shows `No level data` and never reads green.
enum LevelAssist {
    static let refresh: TimeInterval = 0.1
    /// Roll strip centre above the visible picture's bottom edge; tilt mirrors the offset.
    static let rollLiftLandscape: CGFloat = 84
    static let rollLiftPortrait: CGFloat = 22

    /// Strips on the on-screen part of the feed (OpenZCine #47). Roll runs along
    /// the bottom, lifted clear of the landscape / portrait chrome; tilt centres
    /// vertically, right of centre by the same distance roll sits below centre,
    /// kept 6 pt inside the picture (portrait fill).
    static func frames(feed: CGRect, viewport: CGRect, portrait: Bool) -> (roll: CGRect, tilt: CGRect) {
        var visible = feed.intersection(viewport)
        if visible.isNull || visible.isEmpty { visible = feed }
        let t = MonitorLevelGauge.thickness
        let rollWidth = max(0, min(MonitorLevelGauge.maxLength, visible.width - 24))
        let rollMidY = visible.maxY - (portrait ? rollLiftPortrait : rollLiftLandscape)
        let tiltHeight = max(0, min(MonitorLevelGauge.maxLength, visible.height - 12))
        let tiltMidX = min(visible.midX + (rollMidY - visible.midY), visible.maxX - 6 - t / 2)
        return (
            CGRect(x: visible.midX - rollWidth / 2, y: rollMidY - t / 2, width: rollWidth, height: t),
            CGRect(x: tiltMidX - t / 2, y: visible.midY - tiltHeight / 2, width: t, height: tiltHeight)
        )
    }

    static func accessibilityValue(_ mode: LevelReading.Mode) -> String {
        switch mode {
        case .unavailable: WorldLevelSnap.noLevelData
        case .gauges(let roll, let tilt): String(format: "Roll %+.1f°, tilt %+.1f°", roll, tilt)
        case .bubble(let x, let y): String(format: "Off plumb %+.1f° / %+.1f°", x, y)
        }
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
            content(mode)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel("Level")
                .accessibilityValue(LevelAssist.accessibilityValue(mode))
                .accessibilityIdentifier("monitor.level")
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func content(_ mode: LevelReading.Mode) -> some View {
        let frames = LevelAssist.frames(
            feed: feed, viewport: viewport, portrait: portrait)
        switch mode {
        case .bubble(let x, let y):
            let visible = feed.intersection(viewport).isNull ? feed : feed.intersection(viewport)
            MonitorLevelBubble(xDeg: x, yDeg: y)
                .position(x: visible.midX, y: visible.midY)
        case .gauges(let roll, let tilt):
            strips(roll: roll, tilt: tilt, frames: frames, caption: nil)
        case .unavailable:
            strips(roll: nil, tilt: nil, frames: frames, caption: WorldLevelSnap.noLevelData)
        }
    }

    private func strips(roll: Double?, tilt: Double?, frames: (roll: CGRect, tilt: CGRect), caption: String?)
        -> some View
    {
        ZStack {
            MonitorLevelGauge(axis: .horizontal, value: roll)
                .frame(width: frames.roll.width, height: frames.roll.height)
                .position(x: frames.roll.midX, y: frames.roll.midY)
            if let caption {
                LevelCaption(text: caption)
                    .position(x: frames.roll.midX, y: frames.roll.maxY + 6)
            }
            if !frames.tilt.isEmpty {
                MonitorLevelGauge(axis: .vertical, value: tilt)
                    .frame(width: frames.tilt.width, height: frames.tilt.height)
                    .position(x: frames.tilt.midX, y: frames.tilt.midY)
            }
        }
    }
}

private struct LevelCaption: View {
    let text: String

    var body: some View {
        Text(text)
            .font(MonitorTheme.font(8, weight: .medium))
            .kerning(0.5)
            .foregroundStyle(LiveDesign.muted)
            .shadow(color: .black.opacity(0.6), radius: 1.5)
            .fixedSize()
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
            scale: scale, colorMode: colorMode, rec709: rec709, clipByte: clipByte
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
        if tool == .evMeter {
            Text("EV")
                .font(MonitorTheme.font(size.map { $0 * 0.7 } ?? 17, weight: .semibold))
                .frame(width: size, height: size)
        } else if let icon = tool.monitorIcon {
            icon.frame(width: size, height: size)
        } else if let icon = tool.opcIcon {
            icon.frame(width: size, height: size)
                .rotationEffect(.degrees(tool == .desqueeze ? 90 : 0))
        }
    }
}
