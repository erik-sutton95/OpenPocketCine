import Foundation

/// Shared side length for live system controls and View Assist cells.
public enum MonitorSystemButtonMetrics: Sendable {
    public static func side(tablet: Bool) -> Double { 48 }
    public static func iconSide(tablet: Bool) -> Double { side(tablet: tablet) * 29 / 54 }
}

/// Camera-value type: iPhone 16/9 is operator-approved; tablet uses the 18 pt value.
public enum MonitorReadoutTypography: Sendable {
    public static let phoneValueSize: Double = 16
    public static let tabletValueSize: Double = 18
    public static let labelSize: Double = 9
    /// 0.14 em of the 9 pt label.
    public static let labelTracking: Double = 1.26

    public static func valueSize(tablet: Bool) -> Double {
        tablet ? tabletValueSize : phoneValueSize
    }
}

/// Operator Setup cards keep the title block out of the first row by a measured gap.
public enum MonitorSettingsCardMetrics: Sendable {
    public static let titleTopPadding: Double = 11
    public static let titleMinHeight: Double = 24
    public static let titleContentGap: Double = 8
    public static let titlePointSize: Double = 13
    public static let rowTitlePointSize: Double = 12.5

    /// Lowest Y of the title glyphs relative to the card top, then the gap.
    public static func contentOriginY(titleLineHeight: Double = 17) -> Double {
        let titleBlock = titleTopPadding + max(titleMinHeight, titleLineHeight)
        return titleBlock + titleContentGap
    }
}

/// Compact hold chrome hugs header + 86 pt drum. Category tabs are portrait-only.
public enum MonitorCapturePopupChrome: Sendable {
    public static let compactHeight: Double = 128
    public static let drumHeight: Double = 86
    public static let headerHeight: Double = 22
    public static let stackSpacing: Double = 8
    public static let dispTracking: Double = 0.48
    public static let dispSize: Double = 12

    public static func compactBottomPadding(topPadding: Double) -> Double {
        max(
            0,
            compactHeight - topPadding - headerHeight - stackSpacing - drumHeight)
    }

    public static func compactHeight(topPadding: Double) -> Double {
        topPadding + headerHeight + stackSpacing + drumHeight
            + compactBottomPadding(topPadding: topPadding)
    }

    public static func showsRecordingCategoryTabs(portrait: Bool, kind: MonitorCapturePopupKind)
        -> Bool
    {
        portrait && kind == .details
    }

    public static func showsGrabber(kind: MonitorCapturePopupKind, edge: MonitorCapturePopupEdge)
        -> Bool
    {
        kind == .details && edge == .bottom
    }
}
