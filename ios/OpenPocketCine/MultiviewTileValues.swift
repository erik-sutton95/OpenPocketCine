import MonitorUI
import OpenCineAppKit
import OpenCineCore
import OpenCineCameraControls
import OpenCineMedia
import OpenCineMulticam
import OpenPocketViewCore
import SwiftUI

/// Formats only received telemetry. The stage has no clock, polling or inferred
/// timecode; the session's existing status publication remains its cadence owner.
struct MultiviewTelemetryPresentation {
    let settings: CameraStatus
    private let power: PowerStatus
    let storageObservation: StorageStatus?

    init(settings: CameraStatus, power: PowerStatus, storageObservation: StorageStatus? = nil) {
        self.settings = settings; self.power = power; self.storageObservation = storageObservation
    }

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
        MonitorOperatorPowerReading.readoutLabel(power.batteryReading) ?? "\u{2014}"
    }
    var storage: String {
        let readout = storageObservation.map { $0.storageReadout } ?? settings.storageReadout
        return readout?.free ?? StorageReadout.unavailable
    }
    var format: String {
        let resolution = settings.videoResolution?.label ?? "—"
        let rate = settings.fps > 0 ? "\(settings.fps)p" : "—"
        return "\(resolution) \(rate) · \(settings.colorMode?.label ?? "—")"
    }
    static func letter(_ index: Int) -> String { MultiviewTile.letter(min(3, index)) }

    /// The stage's program readouts and Grid's in-tile row.
    var readouts: [MultiviewReadout] {
        [
            .init(title: "ISO", value: iso), .init(title: "SHUTTER", value: shutter),
            .init(title: "WB", value: whiteBalance), .init(title: "FOCUS", value: focus),
        ]
    }

    @MainActor static func recordingStatus(_ tile: MultiviewSession.Tile) -> String {
        MultiviewTally.text(
            recording: tile.recordingActive, seconds: tile.settings.recordElapsedSec,
            waiting: tile.recordingBusy, holding: tile.recovering,
            failed: tile.failureMessage != nil)
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

extension MultiviewSession {
    /// The shared stage's values for one slot, `nil` while it is empty: Pocket's camera readings
    /// with the tally, notes, status and options the stage owns.
    func stageTile(_ index: Int) -> MultiviewTile? {
        let tile = tiles[index]
        guard let camera = tile.camera else { return nil }
        let power = tile.control.current.power
        let values = MultiviewTelemetryPresentation(
            settings: tile.settings, power: power, storageObservation: tile.control.current.storage)
        return coordinator.tile(
            index,
            MultiviewTileReadings(
                name: camera.name, model: camera.model.name, format: values.format,
                storage: values.storage, timecode: tile.timecodeReadout, readouts: values.readouts,
                recordingSeconds: tile.settings.recordElapsedSec, power: power,
                hasPicture: tile.hasPicture, accessibilityValue: tile.previewAccessibilityValue))
    }

    /// The record plan for every camera (`nil`) or one slot, with what blocks it now.
    func recordContext(slot: Int?) -> MultiviewRecordContext {
        coordinator.recordContext(slot: slot)
    }
}

extension MultiviewRecordContext {
    @MainActor init(session: MultiviewSession, tile: MultiviewSession.Tile? = nil) {
        self = session.recordContext(
            slot: tile.flatMap { tile in session.tiles.firstIndex { $0 === tile } })
    }
}
