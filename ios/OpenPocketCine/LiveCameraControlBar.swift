import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorCaptureStrip` + `CaptureSettingButton` for Pocket:
/// ISO — SHUTTER — MODE — WB — FOCUS — AUDIO. Parent already sizes this to ~2/3 width.
struct LiveCameraControlBar: View {
    var columns = 6
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @State private var readoutOwnership = MonitorReadoutOwnership()

    var body: some View {
        tileStrip
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onChange(of: interfaceLocked) { _, locked in
                if locked {
                    model.captureSheet = nil
                    model.captureDrum = nil
                }
            }
            .onChange(of: model.session.isLocked) { _, locked in
                if locked {
                    model.captureSheet = nil
                    model.captureDrum = nil
                }
            }
            .onChange(of: columns) { _, _ in model.captureDrum = nil }
            .onChange(of: model.session.supportsFocusMode) { _, on in
                if !on, model.captureSheet == .focus { model.captureSheet = nil }
            }
            .onChange(of: model.session.status.isPhoto) { _, photo in
                if photo, model.captureSheet == .audio { model.captureSheet = nil }
                if photo, model.captureDrum?.sheet == .audio { model.captureDrum = nil }
            }
    }

    private var tilesLocked: Bool {
        interfaceLocked || model.session.isLocked
    }

    private var showsAudio: Bool { !model.session.status.isPhoto }

    private var visibleTileCount: Int {
        4 + (model.session.supportsFocusMode ? 1 : 0) + (showsAudio ? 1 : 0)
    }

    private var gridColumns: Int { columns == 3 ? 3 : max(visibleTileCount, 1) }

    private var tileStrip: some View {
        MonitorControlGrid(
            columns: gridColumns, spacing: columns == 3 ? 8 : 12, equalColumns: columns == 3
        ) {
            tile(.iso, label: "ISO", value: isoValue, widest: "25600")
            if model.session.status.expoMode == .auto {
                tile(
                    .shutter,
                    label: MonitorExposureReadout.autoEvCaption(
                        shutterDenom: model.session.status.shutterDenom),
                    value: evValue, widest: "+3.0",
                    badgeIcon: model.facePriorityExposureEnabled
                        ? CaptureLists.facePriorityBadgeIcon : nil)
            } else {
                tile(
                    .shutter, label: "SHUTTER", value: shutterValue,
                    widest: OperatorPrefs.shutterUsesAngle
                        && !model.session.status.isPhoto ? "346°" : "1/16000")
            }
            tile(.exposure, label: "EXPOSURE", value: expoValue, widest: "Manual")
            tile(.wb, label: "WB", value: wbValue, widest: "10000K", valueIcon: wbIcon)
            if model.session.supportsFocusMode {
                tile(.focus, label: "FOCUS", value: focusValue, widest: "Showcase")
            }
            if showsAudio {
                tile(.audio, label: "AUDIO", value: audioValue, widest: "Spatial")
            }
        }
        .frame(maxWidth: .infinity)
        .contentShape(Rectangle())
        .onTapGesture {}
        .opacity(tilesLocked ? 0.4 : 1)
        .allowsHitTesting(!tilesLocked)
    }

    private func tile(
        _ sheet: CaptureSheet,
        label: String,
        value: String,
        widest: String,
        valueIcon: OpcIcon? = nil,
        badgeIcon: OpcIcon? = nil
    ) -> some View {
        let isActive = model.captureSheet == sheet || model.captureDrum?.sheet == sheet
        let acceptsTouch =
            !tilesLocked && (model.captureDrum == nil || model.captureDrum?.sheet == sheet)
        return CaptureBarReadout(
            label: label,
            value: value,
            widest: widest,
            isActive: isActive,
            valueIcon: valueIcon,
            badgeIcon: badgeIcon
        )
        .modifier(
            CaptureReadoutGesture(
                sheet: sheet, locked: tilesLocked, ownership: $readoutOwnership
            ) { open(sheet) }
        )
        .disabled(tilesLocked)
        .allowsHitTesting(acceptsTouch)
        .frame(maxWidth: .infinity)
        .geometryGroup()
        .background {
            GeometryReader { proxy in
                Color.clear.preference(
                    key: LiveCaptureTileFramesKey.self,
                    value: [sheet: proxy.frame(in: .named(LiveCanvasSpace.name))]
                )
            }
        }
        .accessibilityIdentifier("monitor.capture.\(sheet.rawValue)")
        .accessibilityLabel(label)
        .accessibilityValue(
            badgeIcon == nil ? value : "\(value), \(CaptureLists.facePriorityTitle)")
    }

    private func open(_ sheet: CaptureSheet) {
        guard !tilesLocked, model.captureDrum == nil, readoutOwnership.owner == nil else { return }
        model.captureDrum = nil
        model.captureSheet = CaptureReadoutAdmission.replacing(
            model.captureSheet,
            with: CaptureReadoutAdmission.opening(
                sheet, isPhoto: model.session.status.isPhoto))
    }

    private var isoValue: String {
        if model.session.status.isoIndex == .auto { return "Auto" }
        let iso = model.session.status.iso
        return iso > 0 ? "\(iso)" : (model.session.status.isoIndex?.label ?? "—")
    }

    private var shutterValue: String {
        CaptureQuickSnapshot.shutterReadout(
            status: model.session.status,
            shutterUsesAngle: OperatorPrefs.shutterUsesAngle,
            shutterAngleDegrees: OperatorPrefs.shutterAngleDegrees)
    }

    private var evValue: String {
        model.session.status.evComp?.label ?? "—"
    }

    private var wbIcon: OpcIcon? {
        model.session.status.whiteBalance?.mode == .custom ? nil : .aperture
    }

    private var wbValue: String {
        switch model.session.status.whiteBalance?.mode {
        case .custom:
            let k = model.session.status.whiteBalanceKelvin
            return k > 0 ? "\(k)K" : "Custom"
        case .auto:
            return "Auto"
        case nil:
            return "—"
        }
    }

    private var focusValue: String {
        FocusOption.resolve(
            mode: model.session.status.focusMode,
            track: model.session.status.focusTrack
        )?.chip ?? "—"
    }

    private var expoValue: String {
        model.session.status.expoMode == .manual
            ? "M" : model.session.status.expoMode == .auto ? "A" : "—"
    }

    private var audioValue: String {
        model.session.status.audioChannel?.label ?? "—"
    }
}

/// OpenZCine `CaptureSettingButton` readout — one typeface for every tile.
struct CaptureBarReadout: View {
    let label: String
    let value: String
    let widest: String
    var isActive = false
    var valueIcon: OpcIcon? = nil
    /// Shown beside the label (EV Face Priority). Distinct from `valueIcon`, which replaces the value.
    var badgeIcon: OpcIcon? = nil

    var body: some View {
        MonitorReadout(label, active: isActive) {
            HStack(spacing: 3) {
                if let valueIcon { valueIcon.frame(width: 17, height: 17) }
                Text(value)
                if let badgeIcon { badgeIcon.frame(width: 11, height: 11) }
            }
        }
    }
}
