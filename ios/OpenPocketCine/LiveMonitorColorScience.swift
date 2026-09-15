import OpenPocketViewCore

/// Live picture color for LUT, scopes, and exposure tools.
/// Photo / Live Photo is Rec.709 even when `@2` still reports a log SET.
enum LiveMonitorColorScience {
    static func colorMode(isPhoto: Bool, colorMode: ColorMode?) -> ColorMode? {
        isPhoto ? .normal : colorMode
    }

    static func transfer(isPhoto: Bool, colorMode: ColorMode?) -> MonitorTransfer? {
        self.colorMode(isPhoto: isPhoto, colorMode: colorMode).map(MonitorTransfer.init)
    }

    static func transfer(status: CameraStatus) -> MonitorTransfer? {
        transfer(isPhoto: status.isPhoto, colorMode: status.colorMode)
    }
}

extension LUTSelection {
    /// DJI / official log conversions and log-specific custom slots. Not Creative or generic Custom.
    var appliesTechnicalLogConversion: Bool {
        switch self {
        case .auto, .djiAuto, .officialDLog, .officialDLog2, .djiDLog, .djiDLog2, .djiDLogM,
            .customDLog, .customDLog2:
            true
        default:
            false
        }
    }

    static func djiCatalog(isPhotoLive: Bool) -> [LUTSelection] {
        isPhotoLive ? [.djiAuto] : djiCases
    }
}

/// Shell LUT resolve. Forwards to core and suppresses technical log cubes in live Photo.
enum LiveLUTResolver {
    static func resolve(
        selection: LUTSelection,
        colorMode: ColorMode?,
        family: CameraBodyFamily = .pocket,
        cameraName: String? = nil,
        hasCustomDLog: Bool,
        hasCustomDLog2: Bool,
        hasCustomRec709: Bool = false,
        customFileName: String? = nil,
        isPhoto: Bool = false
    ) -> LUTSource {
        if isPhoto, selection.appliesTechnicalLogConversion { return .off }
        return LUTResolver.resolve(
            selection: selection,
            colorMode: colorMode,
            family: family,
            cameraName: cameraName,
            hasCustomDLog: hasCustomDLog,
            hasCustomDLog2: hasCustomDLog2,
            hasCustomRec709: hasCustomRec709,
            customFileName: customFileName)
    }
}
