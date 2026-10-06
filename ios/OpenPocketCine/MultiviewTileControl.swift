import Foundation
import OpenCineCore
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
        let deadline = ContinuousClock.now + confirmationWindow
        tile.recordingBusy = true
        tile.recordingNote = "Waiting for camera confirmation"
        onStage?(.sent)
        Task { @MainActor [weak tile] in
            var event = ControlWireEvent.unconfirmed
            var acknowledged = false
            defer {
                tile?.recordingBusy = false
                onStage?(event)
            }
            while ContinuousClock.now < deadline {
                try? await Task.sleep(for: .milliseconds(100))
                guard let tile, tile.driver === driver else { return }
                if let reply = tile.responses[seq], reply.cmdSet == 2, reply.cmdId == 2 {
                    if reply.payload != [0] {
                        event = .refused
                        return
                    }
                    if !acknowledged {
                        acknowledged = true
                        onStage?(.acknowledged)
                    }
                }
                if let observation = tile.recordingObservation, observation.received > sent,
                    observation.active == start
                {
                    ControlLiveLog.line("multiview: station recording confirmed active=\(start)")
                    event = .confirmed
                    return
                }
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
    /// Pocket's qualified group record: every camera must be eligible, or nothing is sent.
    static let recordPolicy = TargetPolicy.strict

    /// Tiles with a camera, in slot order.
    var multicamGroup: MulticamGroup { multicamGroup(of: recordingTiles) }

    func multicamSnapshot() -> MulticamSnapshot { multicamSnapshot(of: recordingTiles) }

    /// The engine's view of only `tiles` (those with a camera). A one-tile plan or lease check
    /// reads only that tile, so a SwiftUI view showing it re-renders only for that camera; plans
    /// built this way equal plans built over every tile (non-requested entries never matter).
    func multicamGroup(of tiles: [Tile]) -> MulticamGroup {
        var group = MulticamGroup()
        for tile in tiles where tile.camera != nil { try? group.add(tile.entry) }
        return group
    }

    func multicamSnapshot(of tiles: [Tile]) -> MulticamSnapshot {
        let members = tiles.filter { $0.camera != nil }
        return MulticamSnapshot(
            cameras: members.map { $0.control.current },
            pictures: Dictionary(
                uniqueKeysWithValues: members.map { ($0.stream, $0.pictureHealth) }),
            busy: Set(
                members.filter { $0.recordingBusy || $0.connecting || $0.recovering }
                    .map(\.entryID)),
            now: .now())
    }

    var cameraSessions: [CameraSessionID: any OpenCineCore.CameraSession] {
        Dictionary(
            uniqueKeysWithValues: tiles.map {
                ($0.control.id, $0.control as any OpenCineCore.CameraSession)
            })
    }

    /// The operator's record button resolved to an explicit plan: stop when any requested camera
    /// reports recording, else start. `tile == nil` is Record all.
    func recordPlan(for tile: Tile? = nil) -> RecordPlan {
        let requested = tile.map { [$0] } ?? recordingTiles
        let stop = requested.contains { $0.recordingActive == true }
        return RecordPlan.make(
            stop ? .stop : .start, policy: Self.recordPolicy, entries: requested.map(\.entryID),
            in: multicamGroup(of: requested), at: multicamSnapshot(of: requested))
    }

    /// Sends an approved plan: one explicit start or stop per camera, revalidated first, each
    /// outcome on its own tile. A partial result is never compensated; stopping a camera that
    /// started is a separate operator action.
    func record(_ plan: RecordPlan, together: Bool) async {
        guard !busy, !closing, !groupRecordingBusy else { return }
        let start = plan.direction == .start
        if together {
            groupRecordingBusy = true
            groupRecordingNote = start ? "Starting cameras…" : "Stopping cameras…"
        }
        defer { if together { groupRecordingBusy = false } }
        let sessions = cameraSessions
        guard
            let submission = try? await plan.submit(
                in: multicamGroup, at: multicamSnapshot(), sessions: sessions)
        else {
            // Stale: a camera, link or mode changed after the operator approved.
            if together { groupRecordingNote = "Cameras changed · try again" }
            return
        }
        let result = await submission.finished(sessions: sessions)
        let group = multicamGroup
        for tile in tiles {
            guard let outcome = result.outcome(for: tile.entryID, in: group),
                let note = Self.recordingNote(outcome, start: start)
            else { continue }
            tile.recordingNote = note
        }
        guard together else { return }
        let allMatch = recordingTiles.allSatisfy {
            $0.recordingAvailable && $0.recordingActive == start
        }
        groupRecordingNote =
            result.confirmed == plan.targets.count && allMatch
            ? (start ? "Recording on \(result.confirmed) cameras" : "Recording stopped")
            : "\(result.confirmed) of \(plan.targets.count) confirmed · check camera tiles"
    }

    static func recordingNote(_ outcome: TargetOutcome, start: Bool) -> String? {
        switch outcome {
        case .confirmed: start ? "Recording" : "Recording stopped"
        case .rejected(.cameraRefused): "Recording command rejected · check camera"
        case .rejected, .failed: "Not sent · check camera"
        case .timedOut, .outcomeUnknown, .accepted, .pending: "No confirmation · check camera"
        case .superseded: nil
        }
    }
}
