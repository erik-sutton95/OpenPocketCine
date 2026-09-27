import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Formats only received telemetry. The stage has no clock, polling or inferred
/// timecode; the session's existing status publication remains its cadence owner.
struct MultiviewTelemetryPresentation {
    let settings: CameraStatus

    var iso: String { settings.iso > 0 ? "\(settings.iso)" : "—" }
    var shutter: String { settings.shutterDenom > 0 ? "1/\(settings.shutterDenom)" : "—" }
    var whiteBalance: String {
        settings.whiteBalance.map { $0.mode == .auto ? "Auto" : "\($0.kelvin)K" } ?? "—"
    }
    var focus: String {
        switch settings.focusMode {
        case .single: "AF-S"
        case .continuous: "AF-C"
        case nil: "—"
        }
    }
    var battery: String {
        (0...100).contains(settings.batteryPercent) ? "\(settings.batteryPercent)%" : "—"
    }
    var storage: String {
        guard settings.storageTotalMb > 0, settings.storageFreeMb >= 0 else { return "—" }
        return String(format: "%.0f GB", Double(settings.storageFreeMb) / 1024)
    }
    var format: String {
        let resolution = settings.videoResolution?.label ?? "—"
        let rate = settings.fps > 0 ? "\(settings.fps)p" : "—"
        return "\(resolution) \(rate) · \(settings.colorMode?.label ?? "—")"
    }
    static func letter(_ index: Int) -> String { ["A", "B", "C", "D"][min(3, max(0, index))] }

    @MainActor static func recordingStatus(_ tile: MultiviewSession.Tile) -> String {
        if tile.recordingBusy { return "WAIT" }
        if tile.recovering { return "HOLD" }
        if tile.failureMessage != nil { return "CHECK" }
        guard let active = tile.recordingActive else { return "—" }
        guard active else { return "STBY" }
        let elapsed = max(0, tile.settings.recordElapsedSec)
        return String(format: "REC %02d:%02d", elapsed / 60, elapsed % 60)
    }

    @MainActor static func sessionSummary(_ session: MultiviewSession) -> String {
        if let note = session.groupRecordingNote,
            session.groupRecordingBusy || note.contains("confirmed")
        {
            return note
        }
        let assigned = session.tiles.filter { $0.camera != nil }
        guard !assigned.isEmpty else { return "Ready for your first camera" }
        let recovering = assigned.filter { $0.recovering }.count
        let live = assigned.filter { $0.hasPicture && !$0.recovering }.count
        if recovering > 0 { return "\(live) live · \(recovering) reconnecting" }
        if live != assigned.count { return "\(live) live · \(assigned.count) cameras" }
        let recording = assigned.filter { $0.recordingActive == true }.count
        if recording > 0 { return "\(recording) of \(assigned.count) recording" }
        return "\(assigned.count) cameras connected"
    }
}

struct MultiviewTileChrome: View {
    let tile: MultiviewSession.Tile
    let index: Int
    let selected: Bool
    let compact: Bool
    let condensed: Bool
    var reservedBottom: CGFloat = 0
    /// The floating View Assist palette covers the main tile's lower left.
    var reservedLeading: CGFloat = 0
    /// Grid's selected tile shows its camera values between the footer columns.
    var inlineValues = false
    let openOptions: () -> Void

    private var values: MultiviewTelemetryPresentation { .init(settings: tile.settings) }

    var body: some View {
        ZStack {
            if condensed {
                condensedChrome
            } else {
                regularChrome
                    .padding(.bottom, reservedBottom)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var condensedChrome: some View {
        HStack(spacing: 5) {
            VStack(alignment: .leading, spacing: 3) {
                Text(
                    MultiviewTelemetryPresentation.letter(index) + " · "
                        + (tile.camera?.name ?? "Camera")
                )
                .font(MonitorTheme.font(9, weight: .semibold)).lineLimit(1)
                HStack(spacing: 6) {
                    battery
                    Text(MultiviewTelemetryPresentation.recordingStatus(tile))
                        .font(MonitorTheme.font(7)).lineLimit(1)
                }
            }.frame(maxWidth: .infinity, alignment: .leading).allowsHitTesting(false)
            Button(action: openOptions) {
                OpcIcon.ellipsis.frame(width: 18, height: 18)
                    .frame(width: 44, height: 44).contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Camera \(MultiviewTelemetryPresentation.letter(index)) options")
            .accessibilityIdentifier("multiview.options.\(index)")
        }
        .padding(.leading, 8).padding(.trailing, 2)
        .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
    }

    private var regularChrome: some View {
        VStack(spacing: 0) {
            HStack(spacing: compact ? 5 : 8) {
                Text(MultiviewTelemetryPresentation.letter(index))
                    .font(MonitorTheme.font(compact ? 9 : 11, weight: .semibold))
                    .frame(width: compact ? 21 : 27, height: compact ? 21 : 27)
                    .background(
                        selected ? MonitorTheme.accent.opacity(0.24) : .black.opacity(0.35),
                        in: RoundedRectangle(cornerRadius: 6)
                    )
                    .foregroundStyle(selected ? MonitorTheme.accent : .white)
                VStack(alignment: .leading, spacing: 2) {
                    Text(tile.camera?.name ?? "Camera")
                        .font(MonitorTheme.font(compact ? 9 : 12, weight: .semibold))
                    Text(tile.camera?.model.name ?? "")
                        .font(MonitorTheme.font(compact ? 6 : 8))
                        .foregroundStyle(.white.opacity(0.7))
                }.lineLimit(1).frame(maxWidth: .infinity, alignment: .leading)
                if !compact, let timecode = tile.timecodeReadout {
                    Text(timecode)
                        .font(MonitorTheme.font(11, weight: .medium)).monospacedDigit()
                        .lineLimit(1).fixedSize()
                        .accessibilityLabel("Timecode " + timecode)
                }
                Button(action: openOptions) {
                    OpcIcon.ellipsis.frame(width: 18, height: 18)
                        .frame(width: 44, height: 44).contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(
                    "Camera \(MultiviewTelemetryPresentation.letter(index)) options"
                )
                .accessibilityIdentifier("multiview.options.\(index)")
            }
            .padding(.leading, compact ? 7 : 11)
            .padding(.trailing, 2)
            .allowsHitTesting(true)
            Spacer(minLength: 0)
            // Two bottom-aligned columns so the left block ends on the same line as
            // the right block (and the stage's camera-values row).
            HStack(alignment: .bottom, spacing: 6) {
                VStack(alignment: .leading, spacing: compact ? 2 : 4) {
                    if !compact {
                        Text(values.format)
                            .font(MonitorTheme.font(9, weight: .semibold)).lineLimit(1)
                    }
                    HStack(spacing: 6) {
                        battery
                        Text(values.storage)
                    }
                    .font(MonitorTheme.font(compact ? 7.5 : 9, weight: .medium))
                    if compact, let timecode = tile.timecodeReadout {
                        Text(timecode).monospacedDigit()
                            .font(MonitorTheme.font(8, weight: .medium))
                            .accessibilityLabel("Timecode " + timecode)
                    }
                }
                .layoutPriority(1)
                if inlineValues {
                    // Inline with both columns; the values take what is left over.
                    HStack(alignment: .bottom, spacing: 4) {
                        inlineValue("ISO", values.iso)
                        inlineValue("SHUTTER", values.shutter)
                        inlineValue("WB", values.whiteBalance)
                        inlineValue("FOCUS", values.focus)
                    }
                    .frame(maxWidth: 220)
                    .frame(maxWidth: .infinity)
                } else {
                    Spacer(minLength: 0)
                }
                VStack(alignment: .trailing, spacing: compact ? 2 : 4) {
                    Text(MultiviewTelemetryPresentation.recordingStatus(tile))
                        .foregroundStyle(tile.recordingActive == true ? .red : .white)
                        .font(MonitorTheme.font(compact ? 7.5 : 9, weight: .medium))
                    HStack(spacing: 6) {
                        if tile.lutEnabled { Text("LUT").foregroundStyle(MonitorTheme.accent) }
                        if let note = tile.recordingNote,
                            note != "Recording", note != "Recording stopped"
                        {
                            Text(note).foregroundStyle(.orange).lineLimit(1)
                        } else if selected && !compact {
                            Text("SELECTED").foregroundStyle(MonitorTheme.accent)
                        }
                    }
                    .font(MonitorTheme.font(compact ? 8 : 10, weight: .medium))
                }
                .layoutPriority(1)
            }
            .monospacedDigit()
            .padding(.horizontal, compact ? 8 : 11)
            .padding(.leading, reservedLeading)
            .padding(.bottom, compact ? 5 : 9)
            .allowsHitTesting(false)
        }
        .shadow(color: .black.opacity(0.9), radius: 2, y: 1)
    }

    private func inlineValue(_ title: String, _ value: String) -> some View {
        VStack(spacing: 1) {
            Text(value).font(MonitorTheme.font(11, weight: .medium))
                .lineLimit(1).minimumScaleFactor(0.6)
            Text(title).font(MonitorTheme.font(6, weight: .semibold))
                .tracking(0.5).foregroundStyle(MonitorTheme.muted).lineLimit(1)
                .minimumScaleFactor(0.6)
        }
        .frame(maxWidth: .infinity)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(title + " " + value)
    }

    private var battery: some View {
        FieldMonitorGauges.cameraBattery(tile.settings.batteryPercent)
    }

}

struct MultiviewCameraOptions: View {
    @Environment(AppModel.self) private var model
    let session: MultiviewSession
    let tile: MultiviewSession.Tile
    let maximumHeight: CGFloat
    let close: () -> Void
    let openLiveView: () -> Void

    var body: some View {
        let values = MultiviewTelemetryPresentation(settings: tile.settings)
        MonitorCapturePanel(
            title: tile.camera?.name ?? "Camera options",
            subtitle: tile.camera?.model.name ?? "Camera",
            maximumHeight: maximumHeight, bottomCornerRadius: 16, edge: .top, close: close
        ) {
            VStack(alignment: .leading, spacing: 8) {
                HStack {
                    Text(values.format)
                    Spacer()
                    LiveBatteryRow(
                        percent: tile.settings.batteryPercent, deviceIcon: .camera,
                        isCharging: tile.settings.charging, isCamera: true)
                    Text(values.storage)
                }.font(MonitorTheme.font(11))
                if let timecode = tile.timecodeReadout {
                    Text(timecode).font(MonitorTheme.font(12)).monospacedDigit()
                }
                Text(tile.status).foregroundStyle(MonitorTheme.muted)
                if let error = tile.failureMessage { Text(error).foregroundStyle(.orange) }
                if let note = tile.recordingNote { Text(note) }
                Divider()
                action("Live View", action: openLiveView)
                    .disabled(tile.controlHost == nil || tile.recovering)
                MultiviewRecordAction(
                    session: session, tile: tile,
                    confirmationEnabled: model.recordConfirmationEnabled
                ) {
                    actionLabel(tile.recordingActive == true ? "Stop recording" : "Start recording")
                }
                .disabled(
                    !tile.recordingAvailable || tile.recordingBusy
                        || session.groupRecordingBusy || session.closing)
                action(tile.lutEnabled ? "Disable Auto LUT" : "Enable Auto LUT") {
                    tile.toggleLUT()
                    session.persistStage()
                }.disabled(tile.camera?.hasMultiviewPreview != true)
                if tile.camera?.hasMultiviewPreview == true || tile.failureMessage != nil {
                    action("Reconnect") {
                        close()
                        Task { await session.reconnect(tile) }
                    }
                    .disabled(session.busy || tile.connecting || tile.recovering)
                }
                if tile.failureMessage != nil, !tile.experimentalNetwork, tile.identity == nil {
                    action("Try experimental shared Wi-Fi") {
                        close()
                        Task { await session.tryExperimentalNetwork(tile) }
                    }.disabled(session.busy || tile.connecting || tile.recovering)
                }
                Button(role: .destructive) {
                    Task { if await session.remove(tile) { close() } }
                } label: {
                    actionLabel("Remove camera")
                }
                .disabled(
                    session.busy || tile.connecting || session.groupRecordingBusy
                        || tile.recordingBusy || session.closing)
                if tile.networkVerified && tile.camera?.hasMultiviewPreview == false {
                    Text("Remove this camera to enable group recording for your other cameras.")
                        .foregroundStyle(MonitorTheme.muted)
                }
            }
            .font(MonitorTheme.font(11))
            .buttonStyle(MonitorButtonStyle())
        }
        .tint(MonitorTheme.accent)
        .accessibilityElement(children: .contain)
        .accessibilityIdentifier("multiview.cameraOptions")
    }

    private func action(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) { actionLabel(title) }
    }

    private func actionLabel(_ title: String) -> some View {
        Text(title).font(MonitorTheme.font(12, weight: .medium))
            .frame(maxWidth: .infinity, minHeight: 44, alignment: .leading)
            .padding(.horizontal, 12)
            .background(Color.white.opacity(0.05), in: RoundedRectangle(cornerRadius: 9))
            .contentShape(Rectangle())
    }
}
