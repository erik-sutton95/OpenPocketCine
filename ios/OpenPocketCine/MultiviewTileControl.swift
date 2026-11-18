import Foundation
import OpenCineCore
import OpenCineAppKit
import OpenCineMulticam
import OpenPocketViewCore
import OpenCineDJIApple

/// A Multiview tile's record path as `DJICameraSessionAdapter` (OpenCineDJI) drives it, so the
/// multicam engine sees each tile as a common camera session (MULTI-02). The tile keeps its
/// datalink, decoder and repair ownership; this reads the tile's reported state and sends the
/// explicit record frame on the tile's existing link. It never opens a link and never runs a
/// second command pump: settings still go through the editor's borrowed `CameraSession`.
@MainActor final class MultiviewTileControl: DJIControlPort {
    weak var tile: MultiviewSession.Tile?
    /// Puts a frame on the tile's link: its sequence, or `nil` when it never left the phone.
    /// Tests replace it; production uses the tile's own driver.
    var transmit: (DjiAppleDatalink, Duml.Frame) -> UInt16? = { driver, frame in
        let seq = driver.send(frame)
        return driver.lastWriteLanded == false ? nil : seq
    }
    /// Pocket's record confirmation window: a reply or a matching `0x02/0x80` report within 8 s.
    var confirmationWindow: Duration = .seconds(8)
    /// The window's clock and its 100 ms poll. Tests advance a manual clock instead of waiting.
    var clock: HostClock = .live

    var status: CameraStatus {
        guard let tile else { return CameraStatus() }
        var status = tile.settings
        // Pocket's qualification: the record state counts as reported only while the
        // `0x02/0x80` report is fresh (`recordingAvailable`, sampled each second).
        status.recordingReported = tile.recordingAvailable
        status.isRecording = tile.recordingActive == true
        return status
    }
    var whiteBalanceDisplayStatus: CameraStatus { status }
    var currentShootingMode: ShootingMode? {
        tile.flatMap { ShootingMode.fromStatus($0.settings.shootingMode) }
    }
    var connectedCameraID: String? { tile?.camera?.id.uuidString }
    var connectedModel: CameraModel? { tile?.camera?.model }
    /// The tile owns its link; Live View and the settings editor only borrow it.
    var admitsMultiviewControl: Bool { true }
    var isBusy: Bool { tile?.recordingBusy == true }
    var link: DJILinkState {
        guard let tile else { return .notLinked }
        if tile.recovering { return .recovering }
        if tile.connecting { return .connecting(.negotiating) }
        // A driver-internal rebuild stays `.ready`: the send itself reports it as not sent,
        // and the settings editor keeps its own rebuild check, as before.
        return tile.driver != nil && tile.controlHost != nil ? .ready : .notLinked
    }
    /// The session writes one note per tile from the record outcome (`record(_:together:)`).
    var controlNote: String? {
        get { tile?.recordingNote }
        set {}
    }

    func takePhoto() {}

    // ponytail: tiles route only record here; ISO and white balance belong to the settings
    // editor's mailbox, the one command pump for SETs. Route them here only if the editor
    // ever moves onto this seam.
    func setISO(_ index: IsoIndex, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        onStage?(.notSent)
    }
    func setWhiteBalanceAuto(tint: Int?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        onStage?(.notSent)
    }
    func setWhiteBalanceCustom(
        kelvin: Int, tint: Int, onStage: (@MainActor (ControlWireEvent) -> Void)?
    ) {
        onStage?(.notSent)
    }

    /// One explicit start or stop on the tile's link: NACK refuses, the camera's own newer
    /// report confirms, the window closing leaves it unconfirmed. A replaced link ends the wait;
    /// the adapter has already abandoned the request as outcome unknown.
    func setRecording(_ start: Bool, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
        guard let tile, let driver = tile.driver, tile.controlHost != nil, !tile.recordingBusy,
            let seq = transmit(driver, start ? Commands.recordStart() : Commands.recordStop())
        else {
            onStage?(.notSent)
            return
        }
        let sent = Date()
        let clock = clock
        let window = confirmationWindow
        tile.recordingBusy = true
        tile.recordingNote = RecordAll.waiting
        onStage?(.sent)
        Task { @MainActor [weak tile] in
            let outcome = await MultiviewRecordConfirmation.wait(
                start: start, sentAt: sent, window: window, clock: clock,
                current: { tile?.driver === driver },
                reply: {
                    guard let reply = tile?.responses[seq], reply.cmdSet == 2, reply.cmdId == 2
                    else { return nil }
                    return reply.payload == [0]
                },
                report: { tile?.recordReport },
                acknowledged: { onStage?(.acknowledged) })
            tile?.recordingBusy = false
            switch outcome {
            case .confirmed:
                ControlLiveLog.line("multiview: station recording confirmed active=\(start)")
                onStage?(.confirmed)
            case .refused: onStage?(.refused)
            case .unconfirmed: onStage?(.unconfirmed)
            }
        }
    }
}

extension MultiviewSession.Tile {
    /// Stable multicam slot: the tile's own identity, kept through layout, staging and rotation.
    var entryID: MonitorEntryID { MonitorEntryID(id) }

    var entry: MonitorEntryDescriptor {
        MonitorEntryDescriptor(
            id: entryID, name: camera?.name ?? "",
            picture: PictureSourceDescriptor(stream: stream, label: camera?.name ?? ""),
            cameraSession: control.id, telemetry: .cameraSession, controlAuthority: .owner)
    }

    var pictureHealth: PictureHealth {
        if failureMessage != nil { return .failed }
        if previewFresh { return .live }
        return hasPicture ? .stalled : .starting
    }
}

extension MultiviewSession {
    /// Tiles with a camera, in slot order.
    var multicamGroup: MulticamGroup { coordinator.multicamGroup() }

    func multicamSnapshot() -> MulticamSnapshot { coordinator.multicamSnapshot() }

    /// The engine's view of only `tiles` (those with a camera), in slot order.
    func multicamGroup(of tiles: [Tile]) -> MulticamGroup {
        coordinator.multicamGroup(of: slots(tiles))
    }

    func multicamSnapshot(of tiles: [Tile]) -> MulticamSnapshot {
        coordinator.multicamSnapshot(of: slots(tiles))
    }

    private func slots(_ chosen: [Tile]) -> [Int] {
        tiles.indices.filter { slot in chosen.contains { $0 === tiles[slot] } }
    }

    /// The operator's record button resolved to an explicit plan: stop when any requested camera
    /// reports recording, else start. `tile == nil` is Record all.
    func recordPlan(for tile: Tile? = nil) -> RecordPlan {
        coordinator.recordPlan(slot: tile.flatMap { tile in tiles.firstIndex { $0 === tile } })
    }

    /// Sends an approved plan: one explicit start or stop per camera, revalidated first, each
    /// outcome on its own tile. A partial result is never compensated; stopping a camera that
    /// started is a separate operator action.
    func record(_ plan: RecordPlan, together: Bool) async {
        await coordinator.record(plan, together: together)
    }
}
