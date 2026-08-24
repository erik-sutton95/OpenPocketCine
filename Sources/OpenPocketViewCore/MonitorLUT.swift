import Foundation

/// Operator LUT choice. DJI Auto follows color + body; Creative looks are
/// generated; locked rows stay put until the operator picks something else.
public enum LUTSelection: String, CaseIterable, Sendable, Codable {
    case auto
    case officialDLog
    case officialDLog2
    case djiAuto
    case djiDLog
    case djiDLog2
    case djiDLogM
    case creativeMono
    case creativeContrast
    case creativeWarm
    case creativeCool
    case customRec709
    case customDLog
    case customDLog2
    case customFile

    public var title: String {
        switch self {
        case .auto, .djiAuto: "Auto"
        case .officialDLog: OfficialPocketLUT.dLogToRec709.title
        case .officialDLog2: OfficialPocketLUT.dLog2ToRec709.title
        case .djiDLog: OfficialDJILUT.pocketDLog.title
        case .djiDLog2: OfficialDJILUT.pocketDLog2.title
        case .djiDLogM: OfficialDJILUT.nanoDLogM.title
        case .creativeMono: BuiltInLook.mono.rawValue
        case .creativeContrast: BuiltInLook.contrast.rawValue
        case .creativeWarm: BuiltInLook.warm.rawValue
        case .creativeCool: BuiltInLook.cool.rawValue
        case .customRec709: CustomLUTSlot.rec709.title
        case .customDLog: CustomLUTSlot.dLog.title
        case .customDLog2: CustomLUTSlot.dLog2.title
        case .customFile: "Custom"
        }
    }

    public var isBuiltIn: Bool {
        self == .auto || self == .officialDLog || self == .officialDLog2
    }

    public var isDJI: Bool {
        self == .djiAuto || self == .djiDLog || self == .djiDLog2 || self == .djiDLogM
    }

    public var isCreative: Bool { creativeLook != nil }

    public var creativeLook: BuiltInLook? {
        switch self {
        case .creativeMono: .mono
        case .creativeContrast: .contrast
        case .creativeWarm: .warm
        case .creativeCool: .cool
        default: nil
        }
    }

    public var isCustom: Bool {
        customSlot != nil || self == .customFile
    }

    /// Built-in Rec.709 conversions are gone; Auto lives on the DJI tab.
    public var migratedToDJICatalog: LUTSelection {
        switch self {
        case .auto: .djiAuto
        case .officialDLog: .djiDLog
        case .officialDLog2: .djiDLog2
        default: self
        }
    }

    public var customSlot: CustomLUTSlot? {
        switch self {
        case .customRec709: .rec709
        case .customDLog: .dLog
        case .customDLog2: .dLog2
        default: nil
        }
    }

    public static let djiCases: [LUTSelection] = [.djiAuto, .djiDLog, .djiDLog2, .djiDLogM]
    public static let creativeCases: [LUTSelection] = [
        .creativeMono, .creativeContrast, .creativeWarm, .creativeCool,
    ]
    public static let customCases: [LUTSelection] = [.customRec709, .customDLog, .customDLog2]
}

/// App-authored Rec.709 looks shipped in the iOS bundle (Built-in tab).
public enum OfficialPocketLUT: String, CaseIterable, Sendable, Hashable {
    case dLogToRec709
    case dLog2ToRec709

    public var fileName: String {
        switch self {
        case .dLogToRec709: "DJI_Pocket4P_DLog_Rec709_33.cube"
        case .dLog2ToRec709: "DJI_Pocket4P_DLog2_Rec709_33.cube"
        }
    }

    public var resourceName: String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    public var title: String {
        switch self {
        case .dLogToRec709: "D-Log → Rec.709"
        case .dLog2ToRec709: "D-Log2 → Rec.709"
        }
    }
}

/// Manufacturer Rec.709 cubes shipped in the iOS bundle (DJI tab).
/// Unique files from `Osmo LUTS/` (vivid variants are Built-in / Custom, not here):
/// Pocket 4 = Pocket 4P D-Log; Nano = Pocket 3 = Action 4 = Action 5 Pro D-Log M.
public enum OfficialDJILUT: String, CaseIterable, Sendable, Hashable {
    case pocketDLog
    case pocketDLog2
    case nanoDLogM
    case action6DLogM

    public var fileName: String {
        switch self {
        case .pocketDLog: "DJI_Official_Pocket4P_DLog_Rec709_33.cube"
        case .pocketDLog2: "DJI_Official_Pocket4P_DLog2_Rec709_33.cube"
        case .nanoDLogM: "DJI_Official_Nano_DLogM_Rec709_33.cube"
        case .action6DLogM: "DJI_Official_Action6_DLogM_Rec709_33.cube"
        }
    }

    public var resourceName: String {
        URL(fileURLWithPath: fileName).deletingPathExtension().lastPathComponent
    }

    public var title: String {
        switch self {
        case .pocketDLog: "D-Log → Rec.709"
        case .pocketDLog2: "D-Log2 → Rec.709"
        case .nanoDLogM, .action6DLogM: "D-Log M → Rec.709"
        }
    }

    public var selection: LUTSelection {
        switch self {
        case .pocketDLog: .djiDLog
        case .pocketDLog2: .djiDLog2
        case .nanoDLogM, .action6DLogM: .djiDLogM
        }
    }

    /// Shared D-Log M cube unless this body has its own official file.
    public static func dLogM(cameraName: String?) -> OfficialDJILUT {
        let n = (cameraName ?? "").lowercased().replacingOccurrences(of: " ", with: "")
        if n.contains("action6") { return .action6DLogM }
        return .nanoDLogM
    }

    /// Official look for this body + color. Rec.709 / HDR have none.
    public static func auto(
        colorMode: ColorMode?,
        family: CameraBodyFamily,
        cameraName: String? = nil
    ) -> OfficialDJILUT? {
        switch colorMode {
        case .dLog2:
            return family == .nano ? dLogM(cameraName: cameraName) : .pocketDLog2
        case .dLog:
            return family == .nano ? dLogM(cameraName: cameraName) : .pocketDLog
        case .dLogM:
            return dLogM(cameraName: cameraName)
        default:
            return nil
        }
    }
}

/// Independent on-device custom cubes: Normal/HDR, D-Log, and D-Log2.
public enum CustomLUTSlot: String, CaseIterable, Sendable {
    case rec709
    case dLog
    case dLog2

    public var title: String {
        switch self {
        case .rec709: "Custom"
        case .dLog: "Custom D-Log"
        case .dLog2: "Custom D-Log2"
        }
    }

    public var selection: LUTSelection {
        switch self {
        case .rec709: .customRec709
        case .dLog: .customDLog
        case .dLog2: .customDLog2
        }
    }

    public var others: [CustomLUTSlot] { Self.allCases.filter { $0 != self } }
}

/// What the monitor should paint for a selection + color mode + body.
public enum LUTSource: Equatable, Sendable {
    case official(OfficialPocketLUT)
    case dji(OfficialDJILUT)
    case creative(BuiltInLook)
    case custom(CustomLUTSlot)
    case file(String)
    case off

    public var title: String {
        switch self {
        case .official(let lut): lut.title
        case .dji(let lut): lut.title
        case .creative(let look): look.rawValue
        case .custom(let slot): slot.title
        case .file(let name): CustomLUTIndex.displayName(fileName: name)
        case .off: "Off"
        }
    }
}

/// Resolves Auto vs locked official/custom cubes. No I/O — the shell loads the bytes.
public enum LUTResolver {
    public static func resolve(
        selection: LUTSelection,
        colorMode: ColorMode?,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil,
        hasCustomDLog: Bool,
        hasCustomDLog2: Bool,
        hasCustomRec709: Bool = false,
        customFileName: String? = nil
    ) -> LUTSource {
        switch selection {
        case .auto, .djiAuto:
            return OfficialDJILUT.auto(
                colorMode: colorMode, family: family, cameraName: cameraName
            ).map(LUTSource.dji) ?? .off
        case .officialDLog:
            return .dji(.pocketDLog)
        case .officialDLog2:
            return .dji(.pocketDLog2)
        case .creativeMono, .creativeContrast, .creativeWarm, .creativeCool:
            return selection.creativeLook.map(LUTSource.creative) ?? .off
        case .djiDLog:
            return .dji(.pocketDLog)
        case .djiDLog2:
            return .dji(.pocketDLog2)
        case .djiDLogM:
            return .dji(OfficialDJILUT.dLogM(cameraName: cameraName))
        case .customRec709:
            return hasCustomRec709 ? .custom(.rec709) : .off
        case .customDLog:
            return hasCustomDLog ? .custom(.dLog) : .off
        case .customDLog2:
            return hasCustomDLog2 ? .custom(.dLog2) : .off
        case .customFile:
            if let customFileName, CustomLUTIndex.isSafeFileName(customFileName) {
                return .file(customFileName)
            }
            return .off
        }
    }

    /// DJI Auto: official Rec.709 cube for this body + color. Rec.709 / HDR stay off.
    public static func builtInAutoSource(
        colorMode: ColorMode?, family: CameraBodyFamily, cameraName: String? = nil
    ) -> LUTSource {
        OfficialDJILUT.auto(colorMode: colorMode, family: family, cameraName: cameraName)
            .map(LUTSource.dji) ?? .off
    }

    /// Legacy name — same as DJI Auto.
    public static func autoSource(
        colorMode: ColorMode?,
        hasCustomDLog: Bool,
        hasCustomDLog2: Bool,
        hasCustomRec709: Bool = false
    ) -> LUTSource {
        builtInAutoSource(colorMode: colorMode, family: .pocket)
    }

    public static func statusLabel(
        enabled: Bool,
        selection: LUTSelection,
        source: LUTSource
    ) -> String {
        if !enabled { return "Off · \(selection.title)" }
        if selection == .auto || selection == .djiAuto { return "Auto · \(source.title)" }
        return selection.title
    }

    public static func autoCaption(source: LUTSource) -> String {
        switch source {
        case .official(let lut):
            return "Applying \(lut.title)"
        case .dji(let lut):
            return "Applying official \(lut.title)"
        case .creative(let look):
            return "Applying \(look.rawValue)"
        case .custom(let slot):
            return "Applying \(slot.title)"
        case .file(let name):
            return "Applying \(CustomLUTIndex.displayName(fileName: name))"
        case .off:
            return "No matching look for this color / camera"
        }
    }
}

/// Color for Auto LUT on a clip. `colr` / `nclx` is Rec.709 even for D-Log2;
/// the shot profile is QuickTime Keys `com.dji.camera.ColorGammaSxS` on the
/// **original** take. LRF / XRF proxies are Rec.709 even for log — pass `clip`
/// only from the original (or its `moov` tail). That value wins. Live `@2` is
/// the body's current SET — a Rec.709 live SET must not turn Auto off after
/// you just monitored D-Log2 when the original has no Keys atom.
public enum PlaybackLUTColor: Sendable {
    public static func resolve(
        clip: ColorMode? = nil, live: ColorMode?, last: ColorMode?
    ) -> ColorMode? {
        if let clip { return clip }
        if let last, last.bindsAutoLUT {
            if live == nil || live?.bindsAutoLUT == false { return last }
        }
        return live ?? last
    }
}
