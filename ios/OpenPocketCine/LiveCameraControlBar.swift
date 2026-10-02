import MonitorPresentation
import MonitorUI
import OpenCineAppKit
import OpenCineCore
import OpenPocketViewCore
import SwiftUI

/// OpenZCine `MonitorCaptureStrip` + `CaptureSettingButton` for Pocket:
/// ISO — SHUTTER — MODE — WB — FOCUS (APERTURE on Action 6) — AUDIO. Parent already sizes this to ~2/3 width.
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
            .onChange(of: layout.focus) { _, on in
                if !on, model.captureSheet == .focus { model.captureSheet = nil }
            }
            .onChange(of: layout.iris) { _, on in
                if !on, model.captureSheet == .aperture { model.captureSheet = nil }
                if !on, model.captureDrum?.sheet == .aperture { model.captureDrum = nil }
            }
            .onChange(of: model.session.status.isPhoto) { _, photo in
                if photo, model.captureSheet == .audio { model.captureSheet = nil }
                if photo, model.captureDrum?.sheet == .audio { model.captureDrum = nil }
            }
    }

    private var tilesLocked: Bool {
        interfaceLocked || model.session.isLocked
    }

    private var layout: MonitorLayoutCapabilities {
        OsmoMonitorPresentation.capabilities(model.session)
    }

    private var showsAudio: Bool { layout.audio && !model.session.status.isPhoto }

    private var visibleTileCount: Int {
        4 + (layout.focus ? 1 : 0) + (layout.iris ? 1 : 0) + (showsAudio ? 1 : 0)
    }

    private var gridColumns: Int { columns == 3 ? 3 : max(visibleTileCount, 1) }

    private var tileStrip: some View {
        MonitorControlGrid(
            columns: gridColumns, spacing: columns == 3 ? 8 : 12, equalColumns: columns == 3
        ) {
            if model.session.status.isoIndex == .auto {
                tile(.iso, label: "ISO", value: isoValue, widest: "25600")
            } else {
                commonTile(.iso, key: .iso)
            }
            if model.session.status.expoMode == .auto {
                tile(
                    .shutter,
                    label: MonitorExposureReadout.autoEvCaption(
                        shutterDenom: model.session.status.shutterDenom),
                    value: evValue, widest: "+3.0",
                    badgeIcon: model.facePriorityExposureEnabled
                        ? CaptureLists.facePriorityBadgeIcon : nil)
            } else if OperatorPrefs.shutterUsesAngle && !model.session.status.isPhoto {
                tile(
                    .shutter, label: "SHUTTER", value: shutterValue,
                    widest: OperatorPrefs.shutterUsesAngle
                        && !model.session.status.isPhoto ? "346°" : "1/16000")
            } else {
                commonTile(.shutter, key: .shutter)
            }
            tile(.exposure, label: "EXPOSURE", value: expoValue, widest: "Manual")
            if model.session.status.whiteBalance?.mode == .custom,
                model.session.autoWhiteBalanceLock == nil {
                commonTile(.wb, key: .whiteBalance)
            } else {
                tile(.wb, label: "WB", value: wbValue, widest: "10000K", valueIcon: wbIcon)
            }
            if layout.focus {
                tile(.focus, label: "FOCUS", value: focusValue, widest: "Showcase")
            }
            if layout.iris {
                tile(.aperture, label: "APERTURE", value: apertureValue, widest: "Starburst f/4")
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

    @ViewBuilder private func commonTile(_ sheet: CaptureSheet, key: SettingKey) -> some View {
        if let field = model.control.captureField(key) {
            MonitorCaptureReadout(control: model.control, field: field,
                enabled: !tilesLocked && (model.captureDrum == nil || model.captureDrum?.sheet == sheet),
                active: model.captureSheet == sheet || model.captureDrum?.sheet == sheet,
                ownership: $readoutOwnership, presentationOwner: { model.captureDrum?.id },
                admission: { !tilesLocked && model.shell.cover == nil && model.captureSheet == nil }
            ) { event in
                switch event {
                case .open: open(sheet)
                case .preview(let preview):
                    guard !tilesLocked, model.shell.cover == nil,
                        readoutOwnership.owns(preview.id) else { return }
                    model.captureSheet = nil
                    model.captureDrum = CaptureDrumPresentation(id: preview.id, sheet: sheet,
                        snapshot: .common(preview.sourceIdentity), position: preview.position)
                case .commit(let release, _):
                    if model.captureDrum?.id == release.id { model.captureDrum = nil }
                case .cancel(let id):
                    if model.captureDrum?.id == id { model.captureDrum = nil }
                }
            }
            .background {
                GeometryReader { proxy in
                    Color.clear.preference(key: LiveCaptureTileFramesKey.self,
                        value: [sheet: proxy.frame(in: .named(LiveCanvasSpace.name))])
                }
            }
            .accessibilityIdentifier("monitor.capture.\(sheet.rawValue)")
        } else {
            MonitorReadout(MonitorCapturePresentation.title(key) ?? "") { Text("--") }
                .accessibilityValue("Not set")
        }
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
        model.session.whiteBalanceDisplayStatus.whiteBalance?.mode == .custom ? nil : .aperture
    }

    private var wbValue: String {
        if model.session.autoWhiteBalanceLock != nil { return CaptureLists.awbLockTile }
        let wb = model.session.whiteBalanceDisplayStatus
        switch wb.whiteBalance?.mode {
        case .custom:
            let k = wb.whiteBalanceKelvin
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

    /// Live mechanical iris first; the requested strategy until `cam_expo_param` lands.
    private var apertureValue: String {
        let status = model.session.status
        if let iris = status.irisHundredths {
            return ApertureStrategy.fNumberLabel(hundredths: iris)
        }
        return status.apertureStrategy?.label ?? "—"
    }

    private var expoValue: String {
        if model.session.autoExposureLock != nil { return CaptureLists.aeLock }
        return model.session.status.expoMode == .manual
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
