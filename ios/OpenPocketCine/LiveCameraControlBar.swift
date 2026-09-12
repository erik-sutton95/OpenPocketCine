import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorCaptureStrip` + `CaptureSettingButton` for Pocket:
/// ISO — SHUTTER — MODE — WB — FOCUS — AUDIO. Parent already sizes this to ~2/3 width.
struct LiveCameraControlBar: View {
    var columns = 6
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked

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
    }

    private var tilesLocked: Bool {
        interfaceLocked || model.session.isLocked
    }

    private var tileStrip: some View {
        MonitorControlGrid(columns: columns, spacing: columns == 3 ? 6 : 10) {
            tile(.iso, label: "ISO", value: isoValue, widest: "25600")
            if model.session.status.expoMode == .auto {
                tile(
                    .shutter, label: "EV", value: evValue, widest: "+3.0",
                    badgeIcon: model.facePriorityExposureEnabled
                        ? CaptureLists.facePriorityBadgeIcon : nil)
            } else {
                tile(
                    .shutter, label: "SHUTTER", value: shutterValue,
                    widest: OperatorPrefs.shutterUsesAngle ? "346°" : "1/16000")
            }
            tile(.exposure, label: "EXPOSURE", value: expoValue, widest: "Manual")
            tile(.wb, label: "WB", value: wbValue, widest: "10000K", valueIcon: wbIcon)
            if model.session.supportsFocusMode {
                tile(.focus, label: "FOCUS", value: focusValue, widest: "Showcase")
            }
            tile(.audio, label: "AUDIO", value: audioValue, widest: "Spatial")
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
        return CaptureBarReadout(
            label: label,
            value: value,
            widest: widest,
            isActive: isActive,
            valueIcon: valueIcon,
            badgeIcon: badgeIcon
        )
        .modifier(CaptureReadoutGesture(sheet: sheet, locked: tilesLocked) { open(sheet) })
        .disabled(tilesLocked)
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
        guard !tilesLocked else { return }
        model.captureDrum = nil
        if model.captureSheet == nil {
            model.captureSheet = sheet
        } else if model.captureSheet == sheet {
            model.captureSheet = nil
        } else {
            model.captureSheet = sheet
        }
    }

    private var isoValue: String {
        if model.session.status.isoIndex == .auto { return "Auto" }
        let iso = model.session.status.iso
        return iso > 0 ? "\(iso)" : (model.session.status.isoIndex?.label ?? "—")
    }

    private var shutterValue: String {
        if OperatorPrefs.shutterUsesAngle {
            return ShutterAngle.label(OperatorPrefs.shutterAngleDegrees)
        }
        let d = model.session.status.shutterDenom
        return d > 0 ? "1/\(d)" : "—"
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
