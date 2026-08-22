import CoreMotion
import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `MonitorAssistTool` — cinema live-monitor set. MAG is retired; EV / PLAY are
/// photography-only and stay off the video toolbar.
enum LiveAssistTool: String, CaseIterable, Identifiable {
    case lut = "LUT"
    case peaking = "PEAK"
    case falseColor = "FALSE"
    case zebra = "ZEBRA"
    case waveform = "WAVE"
    case parade = "PARADE"
    case histogram = "HISTO"
    case vectorscope = "VECTOR"
    case trafficLights = "LIGHTS"
    case audioMeters = "AUDIO"
    case guides = "GUIDES"
    case grid = "GRID"
    case crosshair = "CROSS"
    case level = "LEVEL"
    case evMeter = "EV"
    case desqueeze = "DE-SQ"
    case mirror = "MIRROR"
    case instantReview = "PLAY"
    case magnification = "MAG"

    var id: String { rawValue }

    var isRetired: Bool { self == .magnification }
    var isPhotographyOnly: Bool { self == .instantReview || self == .evMeter }

    /// Playback drops horizon (needs the camera) and MAG (no on-feed key).
    /// AUDIO rides last, matching the live strip's trailing section.
    static var playbackToolbarCases: [LiveAssistTool] {
        toolbarCases.filter { $0 != .level && $0 != .magnification } + [.audioMeters]
    }

    /// OpenZCine `activeCases` minus photography-only, AUDIO, Level, and De-SQ.
    /// AUDIO is appended as its own trailing section in `LiveAssistBar`.
    static var toolbarCases: [LiveAssistTool] {
        allCases.filter {
            !$0.isRetired && !$0.isPhotographyOnly && !$0.isPocketOmitted && $0 != .audioMeters
        }
    }

    /// View Assist settings list — same cinema set as the bar, plus AUDIO.
    static var settingsCases: [LiveAssistTool] {
        toolbarCases + [.audioMeters]
    }

    /// Tools the operator can keep on the DISP 2 picture. Same cinema set as settings.
    static var cleanPinCases: [LiveAssistTool] { settingsCases }

    /// Compact label for the Display ▸ DISP 2 pin grid.
    var displaySettingsTitle: String {
        switch self {
        case .parade: "Parade"
        case .audioMeters: "Audio Levels"
        default: title
        }
    }

    /// Pocket does not ship Level (unproven gimbal roll) or De-SQ (no anamorphic squeeze).
    var isPocketOmitted: Bool { self == .level || self == .desqueeze }

    var hasConfiguration: Bool {
        switch self {
        // AUDIO / MIRROR match OpenZCine: tap-only. No channel picker, no H/V flip.
        case .audioMeters, .mirror, .evMeter, .instantReview, .magnification, .level, .desqueeze:
            false
        default: true
        }
    }

    /// OpenZCine `MonitorAssistTool.icon`. ZEBRA draws `ZebraStripesShape` instead.
    var opcIcon: OpcIcon? {
        switch self {
        case .lut: .blend
        case .peaking: .mountain
        case .falseColor: .contrast
        case .zebra: nil
        case .waveform: .audioWaveform
        case .parade: .chartColumn
        case .histogram: .audioLines
        case .vectorscope: .crosshair
        case .trafficLights: .sun
        case .audioMeters: .slidersVertical
        case .guides: .squareDashed
        case .grid: .grid3x3
        case .crosshair: .plus
        case .level: .circle
        case .evMeter: .plus
        case .desqueeze: .chevronsUpDown
        case .mirror: .flipHorizontal2
        case .magnification: .zoomIn
        case .instantReview: .image
        }
    }

    var title: String {
        switch self {
        case .lut: "LUT"
        case .peaking: "Peaking"
        case .falseColor: "False Color"
        case .zebra: "Zebra"
        case .waveform: "Waveform"
        case .parade: "RGB Parade"
        case .histogram: "Histogram"
        case .vectorscope: "Vectorscope"
        case .trafficLights: "Traffic Lights"
        case .audioMeters: "Audio Levels"
        case .guides: "Guides"
        case .grid: "Grid"
        case .crosshair: "Crosshair"
        case .level: "Horizon"
        case .evMeter: "EV Meter"
        case .desqueeze: "Desqueeze"
        case .mirror: "Mirror"
        case .magnification: "Magnify"
        case .instantReview: "Instant Playback"
        }
    }
}

enum GuideFamily: String, CaseIterable, Codable, Identifiable {
    case film = "Film"
    case social = "Social"
    var id: String { rawValue }
}

enum GuideAspect: String, CaseIterable, Identifiable, Codable {
    case cinema276 = "2.76:1"
    case cinema = "2.39:1"
    case cinema235 = "2.35:1"
    case twoK = "2.00:1"
    case wide = "1.85:1"
    case hd = "16:9"
    case euro = "1.66:1"
    case imax = "1.43:1"
    case academy = "4:3"
    case vertical = "9:16"
    case social = "4:5"
    case square = "1:1"
    case portrait = "2:3"
    case feed = "1.91:1"

    var id: String { rawValue }

    var ratio: CGFloat {
        let parts = rawValue.split(separator: ":").compactMap { Double($0) }
        guard parts.count == 2, parts[1] > 0 else { return 1 }
        return CGFloat(parts[0] / parts[1])
    }

    static func ratios(for family: GuideFamily) -> [GuideAspect] {
        switch family {
        case .film: [.cinema276, .cinema, .cinema235, .twoK, .wide, .hd, .euro, .imax, .academy]
        case .social: [.vertical, .social, .square, .portrait, .hd, .feed]
        }
    }
}

enum LevelStyle: String, CaseIterable, Codable {
    case horizon = "Horizon"
    case gauge = "Gauge"
}

enum DesqueezeRatio: String, CaseIterable, Codable {
    case x1 = "1x"
    case x133 = "1.33x"
    case x15 = "1.5x"
    case x16 = "1.6x"
    case x165 = "1.65x"
    case x18 = "1.8x"
    case x2 = "2x"

    var factor: Double {
        switch self {
        case .x1: 1
        case .x133: 1.33
        case .x15: 1.5
        case .x16: 1.6
        case .x165: 1.65
        case .x18: 1.8
        case .x2: 2
        }
    }

    static func matching(_ factor: Double) -> DesqueezeRatio? {
        allCases.first { abs($0.factor - factor) < 0.02 }
    }
}

@Observable
final class LiveAssistState {
    var peaking = false
    var zebra = false
    var falseColor = false
    var histogram = false
    var waveform = false
    var parade = false
    var vectorscope = false
    var trafficLights = false
    var audioMeters = false
    var grid = false
    var crosshair = false
    var guides = false
    var level = false
    var desqueeze = false
    var mirror = false
    var evMeter = false
    var instantReview = false
    var guideAspect: GuideAspect = .cinema
    var guideFamily: GuideFamily = .film
    var selectedGuides: Set<GuideAspect> = [.cinema]
    var guideMask = false
    var gridThirds = true
    var gridPhi = false
    var gridDiagonal = false
    var levelStyle: LevelStyle = .horizon
    var peakingColor: PeakingPaint = .red
    var peakingSensitivity: PeakingSense = .medium
    var falseColorScale: FalseColorScaleKind = .stops
    var falseColorReference = true
    var zebraHighlight = true
    var zebraMidtone = true
    var zebraHighlightIRE: Double = LiveZebra.highlightIRE
    var zebraMidtoneIRE: Double = LiveZebra.midtoneIRE
    var zebraHighlightColor: ZebraPaint = .white
    var zebraMidtoneColor: ZebraPaint = .amber
    var desqueezeFactor: Double = 1.33
    var desqueezeHorizontal = true
    var splitComparison = false
    var splitVertical = true
    /// DISP 2. Chrome follows `PocketDispChrome`; assists follow `cleanViewPinnedTools`.
    var clean = false
    /// View-assist tools that stay on the picture in DISP 2. Filter only — never mutates `isOn`.
    var cleanViewPinnedTools: Set<LiveAssistTool> = LiveAssistState.cleanViewDefaultPinnedTools
    /// OpenZCine `playbackVisibleAssistTools` — independent of the live toolbar.
    var playbackVisibleTools: Set<LiveAssistTool> = []
    var showLUTPicker = false
    var configureTool: LiveAssistTool?
    /// Icon (or toolbar) frame in `LiveCanvasSpace` for the long-press options popup.
    var longPressAnchor: CGRect = .zero
    /// OpenZCine `scopes.crushClipCompensation` — shared by HISTO edge lights and LIGHTS.
    var crushClipCompensation = TrafficLightsAssist.defaultCompensation
    var trafficLightsScale = TrafficLightsAssist.defaultScale
    var trafficLightsPosition: TrafficLightsAssist.StoredCenter?
    /// First-launch default is on — Auto applies the matching official cube.
    var lutEnabled = true
    var lutSelection: LUTSelection = .auto
    var monitorColorMode: ColorMode?
    var monitorFamily: CameraBodyFamily = .pocket
    var monitorCameraName: String?

    @ObservationIgnored private var lutCube: CubeLUT?
    @ObservationIgnored private var lutDimension = 0
    @ObservationIgnored private var lutRGBA = Data()
    @ObservationIgnored private var lastSaved: Data?

    var lutArmed: Bool { lutEnabled }

    var lutStatusLabel: String {
        LUTResolver.statusLabel(
            enabled: lutEnabled,
            selection: lutSelection,
            source: resolvedSource()
        )
    }

    func resolvedSource() -> LUTSource {
        LUTResolver.resolve(
            selection: lutSelection,
            colorMode: monitorColorMode,
            family: monitorFamily,
            cameraName: monitorCameraName,
            hasCustomDLog: CustomLUTStore.hasCube(.dLog),
            hasCustomDLog2: CustomLUTStore.hasCube(.dLog2),
            hasCustomRec709: CustomLUTStore.hasCube(.rec709),
            customFileName: OperatorPrefs.selectedCustomFileName
        )
    }

    /// WAVE / PARADE / VECTOR / LIGHTS share one source-frame sample in `HevcDecoder`.
    /// Flags are what the monitor *shows* — DISP 2 applies the pin filter here.
    var effects: LiveImageEffects {
        LiveImageEffects(
            peaking: isVisible(.peaking),
            zebra: isVisible(.zebra),
            falseColor: isVisible(.falseColor),
            histogram: isVisible(.histogram),
            waveform: isVisible(.waveform),
            parade: isVisible(.parade),
            vectorscope: isVisible(.vectorscope),
            trafficLights: isVisible(.trafficLights),
            lutDimension: isVisible(.lut) ? lutDimension : 0,
            lutRGBA: isVisible(.lut) ? lutRGBA : Data(),
            peakingColor: peakingColor,
            peakingSensitivity: peakingSensitivity,
            falseColorScale: falseColorScale,
            zebraHighlight: zebraHighlight,
            zebraMidtone: zebraMidtone,
            zebraHighlightIRE: zebraHighlightIRE,
            zebraMidtoneIRE: zebraMidtoneIRE,
            zebraHighlightColor: zebraHighlightColor,
            zebraMidtoneColor: zebraMidtoneColor,
            splitComparison: splitComparison && isVisible(.lut),
            splitVertical: splitVertical,
            mirror: isVisible(.mirror),
            desqueezeFactor: isVisible(.desqueeze) ? desqueezeFactor : 1,
            desqueezeHorizontal: desqueezeHorizontal,
            trafficThreshold: crushClipCompensation.pixelFractionThreshold
        )
    }

    /// Same graph as live, gated by playback-visible tools (OpenZCine `playbackImageEffects`).
    var playbackEffects: LiveImageEffects {
        var fx = effects
        fx.peaking = isPlaybackVisible(.peaking)
        fx.zebra = isPlaybackVisible(.zebra)
        fx.falseColor = isPlaybackVisible(.falseColor)
        fx.histogram = isPlaybackVisible(.histogram)
        fx.waveform = isPlaybackVisible(.waveform)
        fx.parade = isPlaybackVisible(.parade)
        fx.vectorscope = isPlaybackVisible(.vectorscope)
        fx.trafficLights = isPlaybackVisible(.trafficLights)
        fx.lutDimension = isPlaybackVisible(.lut) ? lutDimension : 0
        fx.lutRGBA = isPlaybackVisible(.lut) ? lutRGBA : Data()
        fx.splitComparison = splitComparison && isPlaybackVisible(.lut)
        fx.mirror = isPlaybackVisible(.mirror)
        fx.desqueezeFactor = isPlaybackVisible(.desqueeze) ? desqueezeFactor : 1
        return fx
    }

    init() {
        OperatorPrefs.load(into: self)
        cleanViewPinnedTools = OperatorPrefs.cleanViewPinnedTools
        playbackVisibleTools = OperatorPrefs.playbackVisibleAssistTools
        level = false
        desqueeze = false
        if lutEnabled { refreshLUTCube() }
        lastSaved = OperatorPrefs.encoded(self)
    }

    /// Grade, peaking, and mirror — the picture, not chrome. Pocket has no de-squeeze.
    static let cleanViewDefaultPinnedTools: Set<LiveAssistTool> = [
        .lut, .peaking, .mirror,
    ]

    func isOn(_ tool: LiveAssistTool) -> Bool {
        switch tool {
        case .lut: lutArmed
        case .peaking: peaking
        case .zebra: zebra
        case .falseColor: falseColor
        case .waveform: waveform
        case .parade: parade
        case .histogram: histogram
        case .vectorscope: vectorscope
        case .trafficLights: trafficLights
        case .audioMeters: audioMeters
        case .guides: guides
        case .grid: grid
        case .crosshair: crosshair
        case .level: level
        case .desqueeze: desqueeze
        case .mirror: mirror
        case .evMeter: evMeter
        case .instantReview: instantReview
        case .magnification: false
        }
    }

    /// OpenZCine `MonitorChromePolicy.isToolVisible`. Pins filter DISP 2; they never flip `isOn`.
    func isVisible(_ tool: LiveAssistTool) -> Bool {
        guard isOn(tool) else { return false }
        if clean { return cleanViewPinnedTools.contains(tool) }
        return true
    }

    func toggleCleanViewPin(_ tool: LiveAssistTool) {
        guard LiveAssistTool.cleanPinCases.contains(tool) else { return }
        var pins = cleanViewPinnedTools
        if pins.contains(tool) {
            pins.remove(tool)
        } else {
            pins.insert(tool)
        }
        cleanViewPinnedTools = pins
        OperatorPrefs.cleanViewPinnedTools = pins
    }

    func isPlaybackVisible(_ tool: LiveAssistTool) -> Bool {
        playbackVisibleTools.contains(tool)
    }

    func togglePlayback(_ tool: LiveAssistTool) {
        if playbackVisibleTools.contains(tool) {
            playbackVisibleTools.remove(tool)
        } else {
            playbackVisibleTools.insert(tool)
        }
        OperatorPrefs.playbackVisibleAssistTools = playbackVisibleTools
    }

    func toggle(_ tool: LiveAssistTool) {
        switch tool {
        case .lut:
            if lutEnabled {
                lutEnabled = false
                refreshLUTCube()
            } else {
                armLastLUT()
            }
        case .peaking: peaking.toggle()
        case .zebra: zebra.toggle()
        case .falseColor:
            falseColor.toggle()
            if falseColor {
                PocketFalseColorMap.warm(
                    scale: falseColorScale,
                    mode: monitorColorMode ?? .normal,
                    hasLUT: lutEnabled && lutDimension >= 2)
            }
        case .waveform: waveform.toggle()
        case .parade: parade.toggle()
        case .histogram: histogram.toggle()
        case .vectorscope: vectorscope.toggle()
        case .trafficLights: trafficLights.toggle()
        case .audioMeters: audioMeters.toggle()
        case .guides:
            guides.toggle()
            if guides, selectedGuides.isEmpty { selectedGuides = [guideAspect] }
        case .grid: grid.toggle()
        case .crosshair: crosshair.toggle()
        case .level: level.toggle()
        case .desqueeze: desqueeze.toggle()
        case .mirror: mirror.toggle()
        case .evMeter: evMeter.toggle()
        case .instantReview: instantReview.toggle()
        case .magnification: break
        }
        OperatorPrefs.save(self)
    }

    /// Picking a look turns LUT on. Auto stays Auto until the operator picks something else.
    func selectLUT(_ selection: LUTSelection) {
        lutSelection = selection
        lutEnabled = true
        OperatorPrefs.lutSelection = selection
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    /// Re-arms the last selection. The bar chip is the only off.
    func armLastLUT() {
        lutEnabled = true
        refreshLUTCube()
        OperatorPrefs.save(self)
    }

    /// Color / zoom / body changes only swap the cube while an Auto row is selected.
    func syncLUT(
        to colorMode: ColorMode?,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil
    ) {
        monitorColorMode = colorMode
        monitorFamily = family
        if let cameraName { monitorCameraName = cameraName }
        refreshLUTCube()
    }

    func refreshLUTCube() {
        guard lutEnabled else {
            lutCube = nil
            lutDimension = 0
            lutRGBA = Data()
            return
        }
        switch resolvedSource() {
        case .official(let id):
            if let cube = BundledPocketLUT.cube(id) {
                cache(cube)
            } else {
                lutCube = nil
                lutDimension = 0
                lutRGBA = Data()
            }
        case .dji(let id):
            if let cube = BundledOfficialDJILUT.cube(id) {
                cache(cube)
            } else {
                lutCube = nil
                lutDimension = 0
                lutRGBA = Data()
            }
        case .custom(let slot):
            if let cube = CustomLUTStore.cube(slot) {
                cache(cube)
            } else {
                lutCube = nil
                lutDimension = 0
                lutRGBA = Data()
            }
        case .file(let name):
            if let cube = CustomLUTStore.cube(fileName: name) {
                cache(cube)
            } else {
                lutCube = nil
                lutDimension = 0
                lutRGBA = Data()
            }
        case .off:
            lutCube = nil
            lutDimension = 0
            lutRGBA = Data()
        }
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
        OperatorPrefs.save(self)
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
        OperatorPrefs.save(self)
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
        OperatorPrefs.save(self)
    }

    func cycleGuide() {
        let all = GuideAspect.ratios(for: guideFamily)
        guard let idx = all.firstIndex(of: guideAspect) else {
            guideAspect = all.first ?? .cinema
            selectedGuides = [guideAspect]
            guides = true
            OperatorPrefs.save(self)
            return
        }
        guideAspect = all[(idx + 1) % all.count]
        selectedGuides = [guideAspect]
        guides = true
        OperatorPrefs.save(self)
    }

    func toggleGuide(_ aspect: GuideAspect) {
        if selectedGuides.contains(aspect) {
            selectedGuides.remove(aspect)
        } else {
            selectedGuides.insert(aspect)
        }
        guideAspect = aspect
        guides = !selectedGuides.isEmpty
        OperatorPrefs.save(self)
    }

    func persist() {
        persistIfNeeded(force: true)
    }

    private func persistIfNeeded(force: Bool = false) {
        let data = OperatorPrefs.encoded(self)
        if !force, data == lastSaved { return }
        lastSaved = data
        OperatorPrefs.write(data)
    }

    private func cache(_ cube: CubeLUT) {
        lutCube = cube
        let gpu = cube.colorCube
        lutDimension = gpu.size
        lutRGBA = gpu.rgbaComponents.withUnsafeBytes { Data($0) }
    }
}

enum OperatorPrefs {
    private static let awakeKey = "OpenPocketCine.KeepScreenAwake"
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
    private static let gimbalStickSensitivityKey = "OpenPocketCine.GimbalStickSensitivity"
    private static let dispLiveKey = "OpenPocketCine.DispChrome.Live"
    private static let dispCleanKey = "OpenPocketCine.DispChrome.Clean"
    private static let cleanPinsKey = "OpenPocketCine.CleanViewPins.v1"
    private static let playbackAssistsKey = "OpenPocketCine.PlaybackAssists.v1"
    private static let portraitFeedAspectKey = "OpenPocketCine.PortraitFeedAspect"
    private static let nativeISOHopKey = "OpenPocketCine.NativeISOHop"
    private static let facePriorityExposureKey = "OpenPocketCine.FacePriorityExposure"
    private static let shutterUsesAngleKey = "OpenPocketCine.ShutterUsesAngle"
    private static let shutterAngleKey = "OpenPocketCine.ShutterAngleDegrees"

    static var keepScreenAwake: Bool {
        get {
            if UserDefaults.standard.object(forKey: awakeKey) == nil { return true }
            return UserDefaults.standard.bool(forKey: awakeKey)
        }
        set { UserDefaults.standard.set(newValue, forKey: awakeKey) }
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

    static var dispLive: PocketDispChrome {
        get { loadChrome(key: dispLiveKey) ?? .liveDefaults }
        set { saveChrome(newValue, key: dispLiveKey) }
    }

    static var dispClean: PocketDispChrome {
        get { loadChrome(key: dispCleanKey) ?? .cleanDefaults }
        set { saveChrome(newValue, key: dispCleanKey) }
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

    private static func loadChrome(key: String) -> PocketDispChrome? {
        guard let data = UserDefaults.standard.data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(PocketDispChrome.self, from: data)
    }

    private static func saveChrome(_ value: PocketDispChrome, key: String) {
        if let data = try? JSONEncoder().encode(value) {
            UserDefaults.standard.set(data, forKey: key)
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
            return .auto
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

    static func load(into state: LiveAssistState) {
        if let data = UserDefaults.standard.data(forKey: assistKey),
            let snap = try? JSONDecoder().decode(Snapshot.self, from: data)
        {
            snap.apply(to: state)
        }
        migrateLegacyLUTIfNeeded(into: state)
        state.lutSelection = lutSelection
    }

    /// One-shot: old Built-in looks become Auto; a stored custom file becomes Custom D-Log.
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
        UserDefaults.standard.set(LUTSelection.auto.rawValue, forKey: lutSelectionKey)
    }

    static func save(_ state: LiveAssistState) {
        write(encoded(state))
    }

    static func encoded(_ state: LiveAssistState) -> Data? {
        try? JSONEncoder().encode(Snapshot(state))
    }

    static func write(_ data: Data?) {
        guard let data else { return }
        UserDefaults.standard.set(data, forKey: assistKey)
    }

    /// OpenZCine `operatorPreferences.v1` / `assistConfiguration.v1` analogue — one blob.
    struct Snapshot: Codable {
        var tools: [String]
        var guideAspect: String
        var guideFamily: String
        var selectedGuides: [String]
        var guideMask: Bool
        var gridThirds: Bool
        var gridPhi: Bool
        var gridDiagonal: Bool
        var levelStyle: String
        var peakingColor: String
        var peakingSensitivity: String
        var falseColorScale: String
        var falseColorReference: Bool
        var zebraHighlight: Bool
        var zebraMidtone: Bool
        var zebraHighlightIRE: Double
        var zebraMidtoneIRE: Double
        var zebraHighlightColor: String
        var zebraMidtoneColor: String
        var desqueezeFactor: Double
        var desqueezeHorizontal: Bool
        var splitComparison: Bool
        var splitVertical: Bool
        var lutArmed: Bool
        var crushClipCompensation: Int?

        init(_ s: LiveAssistState) {
            tools = LiveAssistTool.allCases.filter { s.isOn($0) }.map(\.rawValue)
            guideAspect = s.guideAspect.rawValue
            guideFamily = s.guideFamily.rawValue
            selectedGuides = s.selectedGuides.map(\.rawValue)
            guideMask = s.guideMask
            gridThirds = s.gridThirds
            gridPhi = s.gridPhi
            gridDiagonal = s.gridDiagonal
            levelStyle = s.levelStyle.rawValue
            peakingColor = s.peakingColor.rawValue
            peakingSensitivity = s.peakingSensitivity.rawValue
            falseColorScale = s.falseColorScale.rawValue
            falseColorReference = s.falseColorReference
            zebraHighlight = s.zebraHighlight
            zebraMidtone = s.zebraMidtone
            zebraHighlightIRE = s.zebraHighlightIRE
            zebraMidtoneIRE = s.zebraMidtoneIRE
            zebraHighlightColor = s.zebraHighlightColor.rawValue
            zebraMidtoneColor = s.zebraMidtoneColor.rawValue
            desqueezeFactor = s.desqueezeFactor
            desqueezeHorizontal = s.desqueezeHorizontal
            splitComparison = s.splitComparison
            splitVertical = s.splitVertical
            lutArmed = s.lutEnabled
            crushClipCompensation = s.crushClipCompensation.rawValue
        }

        func apply(to s: LiveAssistState) {
            let on = Set(tools)
            s.peaking = on.contains(LiveAssistTool.peaking.rawValue)
            s.zebra = on.contains(LiveAssistTool.zebra.rawValue)
            s.falseColor = on.contains(LiveAssistTool.falseColor.rawValue)
            s.histogram = on.contains(LiveAssistTool.histogram.rawValue)
            s.waveform = on.contains(LiveAssistTool.waveform.rawValue)
            s.parade = on.contains(LiveAssistTool.parade.rawValue)
            s.vectorscope = on.contains(LiveAssistTool.vectorscope.rawValue)
            s.trafficLights = on.contains(LiveAssistTool.trafficLights.rawValue)
            s.audioMeters = on.contains(LiveAssistTool.audioMeters.rawValue)
            s.guides = on.contains(LiveAssistTool.guides.rawValue)
            s.grid = on.contains(LiveAssistTool.grid.rawValue)
            s.crosshair = on.contains(LiveAssistTool.crosshair.rawValue)
            s.level = on.contains(LiveAssistTool.level.rawValue)
            s.desqueeze = on.contains(LiveAssistTool.desqueeze.rawValue)
            s.mirror = on.contains(LiveAssistTool.mirror.rawValue)
            s.evMeter = on.contains(LiveAssistTool.evMeter.rawValue)
            s.instantReview = on.contains(LiveAssistTool.instantReview.rawValue)
            s.guideAspect = GuideAspect(rawValue: guideAspect) ?? .cinema
            s.guideFamily = GuideFamily(rawValue: guideFamily) ?? .film
            let restored = Set(selectedGuides.compactMap(GuideAspect.init(rawValue:)))
            s.selectedGuides = restored.isEmpty ? [s.guideAspect] : restored
            s.guideMask = guideMask
            s.gridThirds = gridThirds
            s.gridPhi = gridPhi
            s.gridDiagonal = gridDiagonal
            s.levelStyle = LevelStyle(rawValue: levelStyle) ?? .horizon
            s.peakingColor = PeakingPaint(rawValue: peakingColor) ?? .red
            s.peakingSensitivity = PeakingSense(rawValue: peakingSensitivity) ?? .medium
            s.falseColorScale = FalseColorScaleKind(rawValue: falseColorScale) ?? .stops
            s.falseColorReference = falseColorReference
            s.zebraHighlight = zebraHighlight
            s.zebraMidtone = zebraMidtone
            s.zebraHighlightIRE = zebraHighlightIRE
            s.zebraMidtoneIRE = zebraMidtoneIRE
            s.zebraHighlightColor = ZebraPaint(rawValue: zebraHighlightColor) ?? .white
            s.zebraMidtoneColor = ZebraPaint(rawValue: zebraMidtoneColor) ?? .amber
            s.desqueezeFactor = desqueezeFactor
            s.desqueezeHorizontal = desqueezeHorizontal
            s.splitComparison = splitComparison
            s.splitVertical = splitVertical
            if let raw = crushClipCompensation,
                let value = TrafficLightsAssist.CrushClipCompensation(rawValue: raw)
            {
                s.crushClipCompensation = value
            }
            s.lutEnabled = lutArmed
        }
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
    /// When set (letterboxed clip playback), framing overlays align to this rect
    /// instead of the full geometry — OpenZCine `FeedAlignedAssists(feed:)`.
    var feed: CGRect? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        GeometryReader { proxy in
            let assist = model.assist
            // Live: framing aids sit on the de-squeezed picture. Playback already
            // letterboxes the raster (`feed`); do not re-apply live desqueeze there.
            let feed = self.feed ?? overlayFeedRect(CGRect(origin: .zero, size: proxy.size), assist)
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
                        rect: feedRect(mirroredBox(box, assist.isVisible(.mirror)), in: feed),
                        color: LiveDesign.text.opacity(SceneFacePolicy.dimOpacity),
                        lineWidth: 1.6
                    )
                }
                if showFocusChrome {
                    switch overlay {
                    case .search(let box):
                        TrackingBoxView(
                            feed: feed, box: mirroredBox(box, assist.isVisible(.mirror)))
                        FocusBoxView(
                            feed: feed,
                            normalized: assist.isVisible(.mirror)
                                ? CGPoint(x: 1 - focusPoint.x, y: focusPoint.y)
                                : focusPoint
                        )
                    case .subject(let box):
                        SubjectBoxView(feed: feed, box: mirroredBox(box, assist.isVisible(.mirror)))
                    case .face(let box):
                        TrackingBracketView(
                            rect: feedRect(mirroredBox(box, assist.isVisible(.mirror)), in: feed),
                            color: LiveDesign.text.opacity(0.92),
                            lineWidth: 1.6
                        )
                    case .focus:
                        if showTapFocusBox {
                            FocusBoxView(
                                feed: feed,
                                normalized: assist.isVisible(.mirror)
                                    ? CGPoint(x: 1 - focusPoint.x, y: focusPoint.y)
                                    : focusPoint
                            )
                        }
                    }
                }
                VStack {
                    Spacer()
                    HStack(alignment: .bottom, spacing: 8) {
                        extraScopes(assist)
                        Spacer(minLength: 0)
                        if assist.isVisible(.audioMeters) {
                            AudioAssist.meter(
                                levels: model.session.status.audioMeters,
                                sensitivity: model.session.status.audioChannel?.label
                            )
                        }
                    }
                    .padding(.horizontal, 14)
                    .padding(.bottom, 86)
                }
            }
        }
        .allowsHitTesting(false)
    }

    @ViewBuilder
    private func extraScopes(_ assist: LiveAssistState) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            if assist.isVisible(.falseColor), assist.falseColorReference {
                FalseColorLegend(
                    scale: assist.falseColorScale,
                    colorMode: model.session.status.colorMode ?? .normal
                )
            }
            if assist.evMeter {
                EVMeterOverlay()
            }
        }
    }
}

/// OpenZCine `desqueezedRect` — framing aids sit on the visible (shrunk) picture, not the full frame.
private func overlayFeedRect(_ full: CGRect, _ assist: LiveAssistState) -> CGRect {
    guard assist.desqueeze, assist.desqueezeFactor > 1 else { return full }
    let factor = CGFloat(assist.desqueezeFactor)
    if assist.desqueezeHorizontal {
        let width = full.width / factor
        return CGRect(x: full.midX - width / 2, y: full.minY, width: width, height: full.height)
    }
    let height = full.height / factor
    return CGRect(x: full.minX, y: full.midY - height / 2, width: full.width, height: height)
}

private func mirroredBox(_ box: TrackingBox, _ mirror: Bool) -> TrackingBox {
    guard mirror else { return box }
    return TrackingBox(
        x: 1 - box.x - box.width, y: box.y, width: box.width, height: box.height)
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

    static func cancelRect(box: TrackingBox, feed: CGRect, mirrored: Bool) -> CGRect {
        let rect = feedRect(mirroredBox(box, mirrored), in: feed)
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

    var body: some View {
        let side = min(feed.width, feed.height) * 0.14
        let rect = CGRect(x: 0, y: 0, width: side, height: side)
        RoundedRectangle(
            cornerRadius: LiveTrackingChrome.cornerRadius(for: rect), style: .continuous
        )
        .stroke(LiveDesign.accent, lineWidth: 1.5)
        .shadow(color: .black.opacity(0.6), radius: 1)
        .frame(width: side, height: side)
        .position(
            x: feed.minX + normalized.x * feed.width,
            y: feed.minY + normalized.y * feed.height
        )
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
            .font(.system(size: 8, weight: .semibold, design: .monospaced))
            .kerning(0.5)
            .foregroundStyle(Color.white.opacity(0.85))
            .shadow(color: .black.opacity(0.8), radius: 1.5, y: 0.5)
    }
}

/// Horizon overlay. OpenZCine reads PTP `AngleLevelYawing`; Pocket `0x04/0x05` gimbal bytes are
/// on the wire but the roll layout is not proven — CoreMotion on this phone is the fallback.
struct FeedLevelView: View {
    let style: LevelStyle
    let feed: CGRect
    @State private var device = DeviceLevel()

    var body: some View {
        Group {
            if style == .gauge {
                LevelGaugeView(roll: device.roll, pitch: device.pitch, feed: feed)
            } else {
                LevelHorizonView(roll: device.roll)
                    .position(x: feed.midX, y: feed.midY)
            }
        }
        .onAppear { device.start() }
        .onDisappear { device.stop() }
    }
}

/// OpenZCine `DeviceLevel` — gravity in the device frame, mapped for Portrait / LandscapeRight.
@Observable
final class DeviceLevel {
    var roll: Double = 0
    var pitch: Double = 0
    var isPortrait = false
    @ObservationIgnored private let manager = CMMotionManager()

    static func displayRoll(gravityX: Double, gravityY: Double, isPortrait: Bool) -> Double {
        let radians =
            isPortrait
            ? atan2(gravityX, -gravityY)
            : atan2(-gravityY, -gravityX)
        return radians * 180 / .pi
    }

    func start() {
        refreshOrientation()
        guard manager.isDeviceMotionAvailable, !manager.isDeviceMotionActive else { return }
        manager.deviceMotionUpdateInterval = 1.0 / 30.0
        manager.startDeviceMotionUpdates(to: .main) { [weak self] motion, _ in
            guard let self, let g = motion?.gravity else { return }
            self.refreshOrientation()
            let newRoll = Self.displayRoll(gravityX: g.x, gravityY: g.y, isPortrait: isPortrait)
            let newPitch = atan2(g.z, (g.x * g.x + g.y * g.y).squareRoot()) * 180 / .pi
            roll = roll * 0.75 + newRoll * 0.25
            pitch = pitch * 0.75 + newPitch * 0.25
        }
    }

    func stop() {
        if manager.isDeviceMotionActive { manager.stopDeviceMotionUpdates() }
    }

    private func refreshOrientation() {
        let portrait =
            UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first?.interfaceOrientation.isPortrait ?? false
        isPortrait = portrait
    }
}

/// Rolling horizon: two accent wings around a centre ring, rotating with roll; green when level.
struct LevelHorizonView: View {
    let roll: Double

    var body: some View {
        let level = abs(roll) < 0.8
        let color = level ? LiveDesign.good : LiveDesign.accent
        HStack(spacing: 10) {
            Capsule().fill(color).frame(width: 64, height: 2)
            Circle().stroke(color, lineWidth: 1.6).frame(width: 10, height: 10)
            Capsule().fill(color).frame(width: 64, height: 2)
        }
        .rotationEffect(.degrees(roll))
        .animation(.easeOut(duration: 0.18), value: level)
    }
}

/// OpenZCine `LevelGaugeView` — graduated roll + pitch tracks, correction chevrons, degree readout.
private struct LevelGaugeView: View {
    let roll: Double
    let pitch: Double
    let feed: CGRect

    var body: some View {
        ZStack {
            LevelAxisGauge(orientation: .horizontal, value: roll)
                .position(x: feed.midX, y: feed.maxY - 104)
            LevelAxisGauge(orientation: .vertical, value: pitch)
                .position(x: feed.maxX - 44, y: feed.midY)
        }
        .allowsHitTesting(false)
    }
}

private struct LevelAxisGauge: View {
    enum Orientation { case horizontal, vertical }
    let orientation: Orientation
    let value: Double

    private let span = 84.0
    private let maxAngle = 8.0
    private let tickStep = 2.0
    private let threshold = 0.6

    private var isHorizontal: Bool { orientation == .horizontal }
    private var isLevel: Bool { abs(value) < threshold }
    private var tint: Color { isLevel ? LiveDesign.good : LiveDesign.accent }
    private var beadOffset: CGFloat { CGFloat(max(-1, min(1, value / maxAngle)) * span) }

    private var urgency: Int {
        switch abs(value) {
        case ..<(maxAngle / 3): 1
        case ..<(2 * maxAngle / 3): 2
        default: 3
        }
    }

    var body: some View {
        let trackLen = CGFloat(span * 2 + 28)
        ZStack {
            graduations
                .frame(
                    width: isHorizontal ? trackLen : 26,
                    height: isHorizontal ? 26 : trackLen)
            if !isLevel { chevrons }
            bead
            readout
        }
        .animation(.easeOut(duration: 0.12), value: isLevel)
        .animation(.easeOut(duration: 0.09), value: value)
    }

    private var graduations: some View {
        Canvas { ctx, size in
            let mid = CGPoint(x: size.width / 2, y: size.height / 2)
            var base = Path()
            if isHorizontal {
                base.move(to: CGPoint(x: mid.x - CGFloat(span), y: mid.y))
                base.addLine(to: CGPoint(x: mid.x + CGFloat(span), y: mid.y))
            } else {
                base.move(to: CGPoint(x: mid.x, y: mid.y - CGFloat(span)))
                base.addLine(to: CGPoint(x: mid.x, y: mid.y + CGFloat(span)))
            }
            ctx.stroke(base, with: .color(.white.opacity(0.22)), lineWidth: 2)

            var deg = -maxAngle
            while deg <= maxAngle + 0.001 {
                let t = CGFloat(deg / maxAngle * span)
                let centre = abs(deg) < 0.001
                let half: CGFloat = centre ? 9 : 5
                var tick = Path()
                if isHorizontal {
                    tick.move(to: CGPoint(x: mid.x + t, y: mid.y - half))
                    tick.addLine(to: CGPoint(x: mid.x + t, y: mid.y + half))
                } else {
                    tick.move(to: CGPoint(x: mid.x - half, y: mid.y - t))
                    tick.addLine(to: CGPoint(x: mid.x + half, y: mid.y - t))
                }
                ctx.stroke(
                    tick, with: .color(.white.opacity(centre ? 0.75 : 0.34)),
                    lineWidth: centre ? 2 : 1)
                deg += tickStep
            }
        }
    }

    private var bead: some View {
        Circle()
            .fill(tint)
            .frame(width: 13, height: 13)
            .overlay(Circle().stroke(.black.opacity(0.45), lineWidth: 2))
            .shadow(color: .black.opacity(0.5), radius: 3)
            .offset(
                x: isHorizontal ? beadOffset : 0,
                y: isHorizontal ? 0 : -beadOffset)
    }

    private var chevrons: some View {
        let toNegative = value > 0
        let icon: OpcIcon =
            isHorizontal
            ? (toNegative ? .chevronLeft : .chevronRight)
            : (toNegative ? .chevronDown : .chevronUp)
        let gap: CGFloat = 16
        let sign = CGFloat(value > 0 ? 1 : -1)
        return Group {
            if isHorizontal {
                HStack(spacing: -2) {
                    ForEach(Array(0..<urgency), id: \.self) { i in chevronGlyph(icon, index: i) }
                }
            } else {
                VStack(spacing: -2) {
                    ForEach(Array(0..<urgency), id: \.self) { i in chevronGlyph(icon, index: i) }
                }
            }
        }
        .offset(
            x: isHorizontal ? beadOffset - sign * gap : 0,
            y: isHorizontal ? 0 : -beadOffset + sign * gap)
    }

    private func chevronGlyph(_ icon: OpcIcon, index: Int) -> some View {
        icon
            .frame(width: 10, height: 10)
            .foregroundStyle(LiveDesign.accent)
            .opacity(1.0 - Double(index) * 0.22)
    }

    private var readout: some View {
        let shown = abs(value) < 0.05 ? 0 : value
        return Text(String(format: "%+.1f°", shown))
            .font(.system(size: 11, weight: .semibold, design: .monospaced))
            .foregroundStyle(isLevel ? LiveDesign.good : LiveDesign.text.opacity(0.85))
            .fixedSize()
            .offset(
                x: isHorizontal ? 0 : -42,
                y: isHorizontal ? -24 : 0)
    }
}

/// WAVE / PARADE / HISTO / VECTOR / LIGHTS live in `LiveScopes.swift`.
/// AUDIO meters live in `Assists/AudioAssist.swift` (`AudioMetersPanelMini`).

/// OpenZCine `FalseColorReference` on the live feed.
struct FalseColorLegend: View {
    var scale: FalseColorScaleKind
    var colorMode: ColorMode = .normal

    var body: some View {
        FalseColorAssist.referenceDisplay(scale: scale, colorMode: colorMode)
            .allowsHitTesting(false)
    }
}

/// Photography EV needle. Pocket has no Nikon stills meter — the strip is drawn at 0 so the
/// control is not dead. Do not treat this as camera-fed exposure.
struct EVMeterOverlay: View {
    var body: some View {
        HStack(spacing: 10) {
            Text("+0.0")
                .font(.system(size: 11.5, weight: .semibold, design: .monospaced))
                .foregroundStyle(LiveDesign.text)
                .frame(width: 34, alignment: .trailing)
            Capsule().fill(LiveDesign.hairlineStrong).frame(width: 120, height: 3)
                .overlay(alignment: .center) {
                    Capsule().fill(LiveDesign.accent).frame(width: 2, height: 12)
                }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 6)
        .liveChromeCapsule()
        .allowsHitTesting(false)
        .accessibilityLabel("EV meter unavailable on Pocket")
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
                    .buttonStyle(.zcTapTarget)
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
                .font(.system(size: 9, weight: .medium, design: .monospaced))
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
    var size: CGFloat = 19

    var body: some View {
        if tool == .zebra {
            ZebraStripesShape()
                .stroke(
                    style: StrokeStyle(
                        lineWidth: max(1.6, size * 0.13), lineCap: .round, lineJoin: .round)
                )
                .frame(width: size, height: size)
        } else if let icon = tool.opcIcon {
            icon
                .frame(width: size, height: size)
        }
    }
}

struct ZebraStripesShape: Shape {
    var count = 3

    func path(in rect: CGRect) -> Path {
        var path = Path()
        let side = min(rect.width, rect.height)
        let diag = CGFloat(0.5).squareRoot()
        let halfLen = side * 0.40 / 2
        let step = side * 0.27
        for index in 0..<count {
            let offset = CGFloat(index) - CGFloat(count - 1) / 2
            let cx = rect.midX + offset * step * diag
            let cy = rect.midY + offset * step * diag
            path.move(to: CGPoint(x: cx - halfLen * diag, y: cy + halfLen * diag))
            path.addLine(to: CGPoint(x: cx + halfLen * diag, y: cy - halfLen * diag))
        }
        return path
    }
}
