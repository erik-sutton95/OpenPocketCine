import Foundation
import OpenCineCore
import OpenPocketViewCore

/// Wire progress of one camera SET, reported by `CameraSession.fireCamera` so the
/// OpenCineCore seam can tell an ACK from a camera-reported value (CORE-02).
enum ControlWireEvent: Equatable {
    /// Refused locally, or replaced by a newer request before it reached the wire.
    case notSent
    case sent
    /// The camera ACKed. Its status may not show the value yet.
    case acknowledged
    /// The camera's own status shows the requested value.
    case confirmed
    /// NACK, and the camera's status does not show the value.
    case refused
    /// The settle window closed with no ACK and no matching status.
    case unconfirmed
}

/// `OpenCineCore.CameraSession` over the Pocket session for the CORE-02 slice: ISO, white
/// balance and record start/stop. DUML, raw modes and ACK rules stay here and in
/// `CameraSession`; callers get common values and receipts that never claim more than the
/// camera reported.
///
/// One adapter per app `CameraSession` object (`session.control`). The control epoch advances
/// whenever the datalink is replaced (connect, repair, another camera), so a command built
/// against one link can never reach the next, and work in flight on the old link ends as
/// `.outcomeUnknown` or `.failed(.notSent)`.
@MainActor
final class DJICameraSessionAdapter: OpenCineCore.CameraSession {
    static let integration = IntegrationID("org.opencapture.openpocketcine.dji")

    nonisolated let id: CameraSessionID
    /// ACK to camera-reported value. Record telemetry trails its ACK by about 1 s.
    // ponytail: hand-picked; tune against Pocket 3 / Pocket 4 record telemetry on hardware.
    var readbackTimeout: Duration = .seconds(3)
    /// Admission to ACK or settle: the coalesce hold plus `CameraSession`'s 2 s settle window.
    /// A request the session dropped without a word ends here instead of hanging.
    var wireTimeout: Duration = .seconds(4)

    private unowned let session: CameraSession
    private var snapshot: CameraSnapshot
    private var epoch = ControlEpoch(1)
    private var attempt = ConnectionAttemptID()
    private var closed = false
    // ponytail: receipts live as long as the session (Core contract); prune finished ones if
    // a long shoot ever makes this measurable.
    private var receipts: [OperationID: CommandReceipt] = [:]
    private var open: [OperationID: Expectation] = [:]
    private var subscribers: [UUID: AsyncStream<CameraSnapshot>.Continuation] = [:]
    private var waiters: [OperationID: [UUID: CheckedContinuation<CommandReceipt?, Never>]] = [:]

    private struct Expectation {
        var deadline: MonotonicInstant
        /// The camera-reported status shows the request.
        let shows: (CameraStatus) -> Bool
    }

    private static let clockReference = ContinuousClock.now
    static func now() -> MonotonicInstant { MonotonicInstant(ContinuousClock.now - clockReference) }

    init(session: CameraSession) {
        let id = CameraSessionID()
        self.id = id
        self.session = session
        snapshot = CameraSnapshot(session: id, epoch: ControlEpoch(1))
    }

    /// A snapshot rebuilt from the session right now.
    var current: CameraSnapshot {
        rebuild()
        return snapshot
    }

    // MARK: UI entry points

    /// One intent against a fresh snapshot: what every control in the app submits.
    @discardableResult
    func request(_ intent: CameraCommandIntent) -> CommandReceipt {
        send(CameraCommand(intent, preconditions: CommandPreconditions(current)))
    }

    /// Record lamp, gamepad, Watch and watcher toggles. Photo fires a still; video resolves to
    /// an explicit start or stop from a fresh snapshot, never a blind toggle (plan 5.4).
    @discardableResult
    func shutter() -> CommandReceipt? {
        if session.currentShootingMode?.isPhoto == true {
            session.takePhoto()
            return nil
        }
        return request(current.recording.value == .recording ? .stopRecording : .startRecording)
    }

    // MARK: Session hooks

    /// Status or phase changed. Cheap unless someone listens or a request awaits readback.
    func sessionDidChange() {
        guard !closed else { return }
        if !subscribers.isEmpty { rebuild() }
        guard !open.isEmpty else { return }
        let status = session.status
        for (operation, expectation) in open
        where receipts[operation]?.stage == .awaitingObservation && expectation.shows(status) {
            finish(operation, .confirmed)
        }
    }

    /// The datalink was replaced or dropped. Requests on the old link cannot be followed.
    func linkDidChange() {
        guard !closed else { return }
        epoch = epoch.next()
        for operation in open.keys { abandon(operation) }
        if !subscribers.isEmpty { rebuild() }
    }

    // MARK: OpenCineCore.CameraSession

    func snapshots() -> AsyncStream<CameraSnapshot> {
        let (stream, continuation) = AsyncStream.makeStream(
            of: CameraSnapshot.self, bufferingPolicy: .bufferingNewest(1))
        continuation.yield(current)
        if closed {
            continuation.finish()
        } else {
            subscribers[UUID()] = continuation
        }
        return stream
    }

    func submit(_ command: CameraCommand) -> CommandReceipt { send(command) }

    func receipt(of operation: OperationID) -> CommandReceipt? { receipts[operation] }

    func outcome(of operation: OperationID) async -> CommandReceipt? {
        guard let receipt = receipts[operation] else { return nil }
        if receipt.isFinished || Task.isCancelled { return receipt }
        let token = UUID()
        return await withTaskCancellationHandler {
            await withCheckedContinuation { continuation in
                waiters[operation, default: [:]][token] = continuation
            }
        } onCancel: {
            Task { @MainActor in self.stopWaiting(operation, token) }
        }
    }

    /// Ends this seam only. Never sends a camera command and never stops a recording.
    func close(_ reason: SessionCloseReason) {
        guard !closed else { return }
        for operation in open.keys { abandon(operation) }
        closed = true
        snapshot.connection = .disconnected(reason)
        snapshot.authority = .unavailable(.link)
        snapshot.revision = snapshot.revision.next()
        for continuation in subscribers.values {
            continuation.yield(snapshot)
            continuation.finish()
        }
        subscribers.removeAll()
    }

    // MARK: Commands

    @discardableResult
    func send(_ command: CameraCommand) -> CommandReceipt {
        let operation = command.operation
        if let known = receipts[operation] { return known }
        let snapshot = current
        receipts[operation] = CommandReceipt(
            operation: operation, session: id, intent: command.intent,
            confirmation: snapshot.capabilities[command.intent.key]?.semantics.confirmation
                ?? .readback)
        if let rejection = snapshot.rejection(of: command, at: Self.now())
            ?? Self.integrationRejection(command.intent, snapshot)
        {
            noteRejection(rejection)
            return advance(operation, .rejected(rejection))
        }
        advance(operation, .admitted)
        if Self.alreadyReported(command.intent, snapshot) {
            return advance(operation, .confirmed)
        }
        guard let plan = wirePlan(command.intent) else {
            return advance(operation, .rejected(.unsupported))
        }
        open[operation] = Expectation(deadline: Self.now() + wireTimeout, shows: plan.shows)
        expire(after: wireTimeout)
        plan.fire { [weak self] event in self?.handle(event, operation) }
        return receipts[operation]!
    }

    private struct WirePlan {
        let shows: (CameraStatus) -> Bool
        let fire: (@escaping @MainActor (ControlWireEvent) -> Void) -> Void
    }

    /// Common intent to the DUML call that carries it, plus what the camera's own status must
    /// show afterwards. Admission already checked the value against the declared domain. DJI
    /// sends white balance and tint in one frame, so each write fills the other half from the
    /// current (or pending) white balance.
    private func wirePlan(_ intent: CameraCommandIntent) -> WirePlan? {
        let session = session
        let display = session.whiteBalanceDisplayStatus
        switch intent {
        case .set(.iso(let value)):
            guard let index = Self.isoIndex(value) else { return nil }
            return WirePlan(
                shows: { $0.isoIndex == index },
                fire: { session.setISO(index, onStage: $0) })
        case .set(.whiteBalanceTint(let tint)):
            guard let wb = display.whiteBalance else { return nil }
            return whiteBalancePlan(Self.whiteBalance(wb), tint: Int(tint))
        case .set(.whiteBalance(let value)):
            return whiteBalancePlan(value, tint: display.whiteBalanceTint ?? 0)
        case .startRecording, .stopRecording:
            let start = intent == .startRecording
            return WirePlan(
                shows: { $0.recordingReported && $0.isRecording == start },
                fire: { session.setRecording(start, onStage: $0) })
        case .set, .focusPoint:
            return nil
        }
    }

    private func whiteBalancePlan(_ value: WhiteBalanceValue, tint: Int) -> WirePlan? {
        let session = session
        let t = min(max(tint, -100), 100)
        switch value {
        case .auto:
            let wb = WhiteBalance.auto(tint: t)
            return WirePlan(
                shows: { $0.whiteBalance == wb },
                fire: { session.setWhiteBalanceAuto(tint: t, onStage: $0) })
        case .kelvin(let kelvin):
            let wb = WhiteBalance.custom(kelvin: min(max(kelvin, 2_000), 10_000), tint: t)
            return WirePlan(
                shows: { $0.whiteBalance == wb },
                fire: { session.setWhiteBalanceCustom(kelvin: wb.kelvin, tint: t, onStage: $0) }
            )
        case .preset:
            return nil
        }
    }

    private func handle(_ event: ControlWireEvent, _ operation: OperationID) {
        // A finished receipt is final: a late ACK never rewrites an outcome.
        guard open[operation] != nil else { return }
        switch event {
        case .notSent:
            finish(operation, .failed(.notSent))
        case .sent:
            advance(operation, .sent)
        case .acknowledged:
            advance(operation, .accepted)
            if open[operation]?.shows(session.status) == true {
                finish(operation, .confirmed)
            } else {
                advance(operation, .awaitingObservation)
                open[operation]?.deadline = Self.now() + readbackTimeout
                expire(after: readbackTimeout)
            }
        case .confirmed:
            // The session's own match is looser for ISO (applied value); this one decides.
            let shown = open[operation]?.shows(session.status) == true
            finish(operation, shown ? .confirmed : .timedOut)
        case .refused:
            finish(operation, .rejected(.cameraRefused))
        case .unconfirmed:
            finish(operation, .timedOut)
        }
    }

    /// The DJI record frames are value-shaped (`0x02/0x02` 01/00) but the app has only ever
    /// sent them as a toggle of the reported state; how a body answers a start while it is
    /// already recording is not hardware-qualified. Unknown state is refused.
    private static func integrationRejection(
        _ intent: CameraCommandIntent, _ snapshot: CameraSnapshot
    ) -> CommandRejection? {
        switch intent {
        case .startRecording, .stopRecording:
            snapshot.recording.isKnown ? nil : .recordingStateUnknown
        case .set, .focusPoint:
            nil
        }
    }

    /// Idempotency: a start while the camera reports recording (or a stop while idle) finishes
    /// without touching the wire, so a retry can never undo the first success.
    private static func alreadyReported(_ intent: CameraCommandIntent, _ snapshot: CameraSnapshot)
        -> Bool
    {
        switch intent {
        case .startRecording: snapshot.recording.value == .recording
        case .stopRecording: snapshot.recording.value == .idle
        case .set, .focusPoint: false
        }
    }

    private func noteRejection(_ rejection: CommandRejection) {
        switch rejection {
        case .sessionClosed, .wrongSession, .notConnected, .staleEpoch, .noAuthority:
            session.controlNote = "not live"
        case .recordingStateUnknown:
            session.controlNote = "Waiting for the camera's record state"
        default:
            break
        }
    }

    private func expire(after delay: Duration) {
        Task { @MainActor [weak self] in
            try? await Task.sleep(for: delay)
            self?.expireOverdue()
        }
    }

    private func expireOverdue() {
        let now = Self.now()
        for (operation, expectation) in open where expectation.deadline <= now {
            if receipts[operation]?.stage == .awaitingObservation {
                finish(operation, .timedOut)
            } else {
                abandon(operation)
            }
        }
    }

    /// Unsent work fails; sent work may have reached the camera, so its outcome is unknown.
    private func abandon(_ operation: OperationID) {
        switch receipts[operation]?.stage {
        case .created?, .admitted?: finish(operation, .failed(.notSent))
        default: finish(operation, .outcomeUnknown)
        }
    }

    @discardableResult
    private func finish(_ operation: OperationID, _ stage: CommandStage) -> CommandReceipt {
        open[operation] = nil
        return advance(operation, stage)
    }

    @discardableResult
    private func advance(_ operation: OperationID, _ stage: CommandStage) -> CommandReceipt {
        receipts[operation]?.stage = stage
        let receipt = receipts[operation]!
        if receipt.isFinished, let waiting = waiters.removeValue(forKey: operation) {
            for continuation in waiting.values { continuation.resume(returning: receipt) }
        }
        return receipt
    }

    private func stopWaiting(_ operation: OperationID, _ token: UUID) {
        waiters[operation]?.removeValue(forKey: token)?.resume(returning: receipts[operation])
    }

    // MARK: Snapshot mapping (raw DJI status to common values)

    private func rebuild() {
        guard !closed else { return }
        let status = session.status
        var next = snapshot
        next.epoch = epoch
        next.device = session.connectedCamera.map {
            .durable($0.id.uuidString, integration: Self.integration)
        }
        next.connection = connection()
        next.authority =
            next.connection != .ready
            ? .unavailable(.link)
            : session.admitsMultiviewControl ? .owner : .unavailable(.authority)
        next.mode = Self.mode(status)
        next.settings = Self.settings(status)
        next.recording =
            status.recordingReported
            ? ObservedValue(status.isRecording ? .recording : .idle, origin: .cameraReported, at: nil)
            : .unknown
        next.power = Self.power(status)
        next.storage = Self.storage(status)
        let descriptors = descriptors(status)
        let revision = snapshot.capabilities.revision
        if CapabilitySnapshot(revision: revision, descriptors: descriptors) != snapshot.capabilities
        {
            next.capabilities = CapabilitySnapshot(
                revision: revision.next(), descriptors: descriptors)
        }
        guard next != snapshot else { return }
        next.revision = snapshot.revision.next()
        snapshot = next
        for (token, continuation) in subscribers {
            if case .terminated = continuation.yield(snapshot) { subscribers[token] = nil }
        }
    }

    private func connection() -> ConnectionState {
        if session.datalink != nil, session.datalink?.isRebuilding != true { return .ready }
        let continuing: Bool
        switch snapshot.connection {
        case .connecting, .recovering: continuing = true
        default: continuing = false
        }
        if !continuing { attempt = ConnectionAttemptID() }
        if session.datalink?.isRebuilding == true || session.sessionRecovery.isRecovering {
            return .recovering(attempt)
        }
        switch session.phase {
        case .scanning, .connectingGatt, .pairing, .readingWifiCreds:
            return .connecting(attempt, .link)
        case .awaitingApproval:
            return .connecting(attempt, .awaitingApproval)
        case .joiningWifi:
            return .connecting(attempt, .joiningNetwork)
        case .openingDatalink:
            return .connecting(attempt, .negotiating)
        case .idle, .live, .failed:
            // Core has no "open but not linked" state; this session object outlives links.
            return .discovered
        }
    }

    /// Declared support is exactly what `wirePlan` routes. A test holds the two together.
    private func descriptors(_ status: CameraStatus) -> [SettingDescriptor] {
        var iso = CaptureLists.isoIndices(from: status).map { SettingValue.iso(Self.iso($0)) }
        if CaptureLists.offersIsoAuto(from: status), !iso.contains(.iso(.auto)) {
            iso.insert(.iso(.auto), at: 0)
        }
        let recording: Availability =
            status.isPhoto
            ? .unavailable(.mode)
            : session.controlBusy || session.isBrowsingMedia ? .unavailable(.busy) : .available
        return [
            SettingDescriptor(.iso, domain: SettingDomain(choices: iso)),
            SettingDescriptor(
                .whiteBalance,
                domain: SettingDomain(
                    choices: [.whiteBalance(.auto)], range: 2_000...10_000, step: 100)),
            // Tint rides on the white balance frame, so it needs a known white balance.
            SettingDescriptor(
                .whiteBalanceTint, domain: SettingDomain(range: -100...100, step: 1),
                availability: status.whiteBalance == nil
                    ? .unavailable(.otherSetting(.whiteBalance)) : .available),
            SettingDescriptor(.recording, availability: recording),
        ]
    }

    static func iso(_ index: IsoIndex) -> ISOValue {
        index.isoValue.map(ISOValue.manual) ?? .auto
    }

    static func isoIndex(_ value: ISOValue) -> IsoIndex? {
        switch value {
        case .auto: .auto
        case .manual(let iso): IsoIndex.allCases.first { $0.isoValue == iso }
        case .autoLimited: nil
        }
    }

    static func whiteBalance(_ wb: WhiteBalance) -> WhiteBalanceValue {
        wb.mode == .auto ? .auto : .kelvin(wb.kelvin)
    }

    private static func mode(_ status: CameraStatus) -> ObservedValue<CaptureMode> {
        guard status.shootingMode >= 0 else { return .unknown }
        let raw = status.shootingMode
        let known = ShootingMode.fromStatus(raw)
        let mode = CaptureMode(
            role: known.map { $0.isPhoto ? .photo : .video } ?? .other,
            id: "\(integration.rawValue).mode.\(raw)", title: known?.label ?? "Mode \(raw)")
        return ObservedValue(mode, origin: .cameraReported, at: nil)
    }

    private static func settings(_ status: CameraStatus) -> [SettingKey: ObservedValue<SettingValue>]
    {
        var settings: [SettingKey: ObservedValue<SettingValue>] = [:]
        if let index = status.isoIndex {
            settings[.iso] = ObservedValue(.iso(iso(index)), origin: .cameraReported, at: nil)
        }
        if let wb = status.whiteBalance {
            settings[.whiteBalance] = ObservedValue(
                .whiteBalance(whiteBalance(wb)), origin: .cameraReported, at: nil)
            settings[.whiteBalanceTint] = ObservedValue(
                .whiteBalanceTint(Double(wb.tint)), origin: .cameraReported, at: nil)
        }
        return settings
    }

    private static func power(_ status: CameraStatus) -> PowerStatus {
        var power = PowerStatus.unknown
        if (0...100).contains(status.batteryPercent) {
            power.battery = ObservedValue(
                Double(status.batteryPercent) / 100, origin: .cameraReported, at: nil,
                precision: .quantized(step: 0.01))
        }
        return power
    }

    private static func storage(_ status: CameraStatus) -> StorageStatus {
        guard status.storageTotalMb > 0 else { return .unknown }
        let free = ObservedValue(
            UInt64(status.storageFreeMb) * 1_048_576, origin: .cameraReported, at: nil)
        return ObservedValue(
            [StorageVolume(id: "active", freeBytes: free)], origin: .cameraReported, at: nil)
    }
}

/// DJI-typed entry points for this app's own controls. They only translate the raw value;
/// admission, the wire call and the receipt are the seam's (`request`).
extension DJICameraSessionAdapter {
    @discardableResult
    func setISO(_ index: IsoIndex) -> CommandReceipt {
        request(.set(.iso(Self.iso(index))))
    }

    /// `nil` keeps the current (or pending) tint, as the Auto row always has.
    @discardableResult
    func setWhiteBalanceAuto(tint: Int? = nil) -> CommandReceipt {
        setWhiteBalance(.auto, tint: tint)
    }

    /// Kelvin snaps to the 100 K drum the camera stores (`K/100` on the wire).
    @discardableResult
    func setWhiteBalanceCustom(kelvin: Int, tint: Int) -> CommandReceipt {
        setWhiteBalance(
            .kelvin(WhiteBalance.snappedKelvin(min(max(kelvin, 2_000), 10_000))), tint: tint)
    }

    /// One Core write per setting that changes: white balance (keeping the pending tint), then
    /// tint (on the pending white balance). Returns the last receipt.
    private func setWhiteBalance(_ value: WhiteBalanceValue, tint: Int?) -> CommandReceipt {
        let pending = session.whiteBalanceDisplayStatus.whiteBalance
        guard let tint = tint.map({ min(max($0, -100), 100) }), tint != pending?.tint else {
            return request(.set(.whiteBalance(value)))
        }
        if pending.map(Self.whiteBalance) != value { request(.set(.whiteBalance(value))) }
        return request(.set(.whiteBalanceTint(Double(tint))))
    }

    /// A confirmed start or stop: the target the operator approved, not a recomputed toggle.
    @discardableResult
    func record(start: Bool) -> CommandReceipt {
        request(start ? .startRecording : .stopRecording)
    }
}

/// The camera control a remote surface (Apple Watch, watcher relay, a record confirmation) was
/// showing: one adapter's session and control epoch (STATE-01). A command aimed at a target is
/// refused (`.wrongSession` / `.staleEpoch`) once the app holds another camera session or another
/// link, instead of acting on whatever `AppModel.session` holds at that moment.
struct ControlTarget: Hashable {
    fileprivate let session: CameraSessionID
    fileprivate let epoch: ControlEpoch

    /// Same camera session, any link: what a long-lived relay is bound to.
    func isSameSession(as other: ControlTarget) -> Bool { session == other.session }
}

extension DJICameraSessionAdapter {
    var target: ControlTarget { ControlTarget(session: id, epoch: epoch) }

    /// `request` with the preconditions of what `target` showed, not of a fresh snapshot.
    @discardableResult
    func request(_ intent: CameraCommandIntent, aimedAt target: ControlTarget) -> CommandReceipt {
        let snapshot = current
        return send(
            CameraCommand(
                intent,
                preconditions: CommandPreconditions(
                    session: target.session, epoch: target.epoch,
                    capabilityRevision: snapshot.capabilities.revision,
                    lease: snapshot.authority.leaseID)))
    }

    /// `shutter()` aimed at `target`. A still fires only while `target` holds; otherwise the
    /// record request is refused at admission and nothing reaches the camera.
    @discardableResult
    func shutter(aimedAt target: ControlTarget) -> CommandReceipt? {
        if session.currentShootingMode?.isPhoto == true, self.target == target {
            session.takePhoto()
            return nil
        }
        let recording = current.recording.value == .recording
        return request(recording ? .stopRecording : .startRecording, aimedAt: target)
    }

    /// A confirmed start or stop, refused if the approval was given for another session or link.
    @discardableResult
    func record(start: Bool, aimedAt target: ControlTarget?) -> CommandReceipt {
        guard let target else { return record(start: start) }
        return request(start ? .startRecording : .stopRecording, aimedAt: target)
    }
}

extension CommandReceipt {
    /// Finished without the camera acting: refused at admission or by the camera, or not sent.
    var didNotAct: Bool {
        switch stage {
        case .rejected, .failed: true
        default: false
        }
    }

    /// Refused because the command was aimed at another session or an older link.
    var targetChanged: Bool {
        stage == .rejected(.wrongSession) || stage == .rejected(.staleEpoch)
    }
}
