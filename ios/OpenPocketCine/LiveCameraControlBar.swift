import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorCaptureStrip` + `CaptureSettingButton` for Pocket:
/// ISO — SHUTTER — MODE — WB — FOCUS — AUDIO. Parent already sizes this to ~2/3 width.
struct LiveCameraControlBar: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked

    var body: some View {
        tileStrip
            .frame(maxWidth: .infinity, alignment: .trailing)
            .onChange(of: interfaceLocked) { _, locked in
                if locked { model.captureSheet = nil }
            }
            .onChange(of: model.session.isLocked) { _, locked in
                if locked { model.captureSheet = nil }
            }
            .onChange(of: model.session.supportsFocusMode) { _, on in
                if !on, model.captureSheet == .focus { model.captureSheet = nil }
            }
    }

    private var tilesLocked: Bool {
        interfaceLocked || model.session.isLocked
    }

    private var tileStrip: some View {
        HStack(spacing: 0) {
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
            tile(.exposure, label: "MODE", value: expoValue, widest: "Manual")
            tile(.wb, label: "WB", value: wbValue, widest: "10000K", valueIcon: wbIcon)
            if model.session.supportsFocusMode {
                tile(.focus, label: "FOCUS", value: focusValue, widest: "Showcase")
            }
            tile(.audio, label: "AUDIO", value: audioValue, widest: "Spatial")
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 4)
        .frame(maxWidth: .infinity)
        .frame(height: LiveDesign.controlHeight)
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
        )
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
        let isActive = model.captureSheet == sheet
        return Button {
            open(sheet)
        } label: {
            CaptureBarReadout(
                label: label,
                value: value,
                widest: widest,
                isActive: isActive,
                valueIcon: valueIcon,
                badgeIcon: badgeIcon
            )
        }
        .buttonStyle(.plain)
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
        .accessibilityLabel(label)
        .accessibilityValue(
            badgeIcon == nil ? value : "\(value), \(CaptureLists.facePriorityTitle)")
    }

    private func open(_ sheet: CaptureSheet) {
        guard !tilesLocked else { return }
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
        model.session.status.expoMode?.label ?? "—"
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
        VStack(spacing: 3) {
            HStack(spacing: 3) {
                Text(label)
                    .font(LiveType.ui(size: 9, weight: .semibold, design: .default))
                if let badgeIcon {
                    badgeIcon
                        .frame(width: 11, height: 11)
                }
            }
            .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.muted)
            Text(widest)
                .font(.system(size: 17, weight: .medium, design: .default))
                .hidden()
                .overlay {
                    if let valueIcon {
                        valueIcon
                            .frame(width: 18, height: 18)
                            .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.text)
                    } else {
                        Text(value)
                            .font(.system(size: 17, weight: .medium, design: .default))
                            .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.text)
                            .lineLimit(1)
                            .minimumScaleFactor(0.7)
                    }
                }
        }
        .frame(maxWidth: .infinity)
        .padding(.vertical, 5)
        .padding(.horizontal, 4)
        .background {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                .fill(isActive ? LiveDesign.accentDim : Color.clear)
        }
        .overlay {
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                .strokeBorder(isActive ? LiveDesign.accentDim : Color.clear, lineWidth: 1)
        }
    }
}
