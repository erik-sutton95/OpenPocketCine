import Foundation

/// Zoom capability, measured position and bounded lens dispatch for one take.
/// The transport owns this value on the same serial queue as the gimbal program.
public struct GimbalProgramZoom: Sendable {
    public static let interval: TimeInterval = 0.05
    private let program: GimbalProgram
    private let model: CameraModel?
    private var status: CameraStatus
    private var sampledAt: TimeInterval = -.infinity
    public private(set) var hasSentTarget = false
    private var lastLens: UInt16?
    private var zoomReceivedAt: TimeInterval?
    private var pausedAt: TimeInterval?
    private var stableSince: TimeInterval?
    private var stableLens: UInt16?
    private var lastNativeCommand: NativeProgramZoomCommand?
    private var nativeWakeAt: TimeInterval = .infinity
    private var preparationZoom: Double?
    private var preparationSentAt: TimeInterval?

    public init(program: GimbalProgram, model: CameraModel?, status: CameraStatus) {
        self.program = program
        self.model = model
        self.status = status
    }

    public var liveZoom: Double? { status.zoomFactor }
    /// The 50 Hz target path is measured on Pocket 4 Pro. Other bodies retain 20 Hz.
    public var usesHighRateTargets: Bool { model?.isPocket4Pro == true }
    private var maximumZoom: Double {
        model?.activeZoomStops(resolution: status.videoResolution,
            shootingMode: status.shootingMode).last ?? 1
    }

    public var failureReason: String? {
        guard program.changesZoom else { return nil }
        guard let color = status.colorMode else { return "Wait for camera color mode before a zoom move" }
        guard color != .dLog2 else { return "Zoom moves are unavailable in D-Log2" }
        let maximum = maximumZoom
        guard [program.a, program.b, program.c].compactMap({ $0 }).allSatisfy({
            $0.zoom.isFinite && $0.zoom >= 1 && $0.zoom <= maximum
        }) else { return "Saved zoom exceeds the current FORMAT limit" }
        guard let liveZoom, liveZoom.isFinite, (1...maximum).contains(liveZoom)
        else { return "Wait for camera zoom feedback" }
        return nil
    }

    /// Bounded transport cache keys, so preflight uses received camera values
    /// instead of optimistic UI pins that may precede a color or FORMAT reply.
    public static func feedbackKey(_ frame: Duml.Frame) -> String? {
        if frame.cmdSet == 0x02, frame.cmdId == 0x80 { return "status" }
        guard frame.cmdSet == 0, frame.cmdId == 0x99,
            let item = SubscribePush.parse(frame.payload),
            ["cam_image_effect", "cam_lens_state", "cam_fov", "cam_video_param_v2"].contains(item.name)
        else { return nil }
        return item.name
    }

    public mutating func observe(_ frame: Duml.Frame, at now: TimeInterval) {
        CameraStatusDecoder.apply(frame, to: &status, model: model)
        guard now.isFinite, frame.cmdSet == 0, frame.cmdId == 0x99,
            let item = SubscribePush.parse(frame.payload) else { return }
        let measuresZoom = item.name == "cam_lens_state" && CamFov.lensAt14(item.value) != nil
            || item.name == "cam_fov" && status.zoomLens == nil && CamFov.rawAt0(item.value) != nil
        guard measuresZoom, let liveZoom else { return }
        let lens = CamFov.pinchLens(for: liveZoom)
        if let previous = zoomReceivedAt, now <= previous { return }
        if let previous = zoomReceivedAt, now - previous > (usesHighRateTargets ? 0.85 : 0.3) {
            stableLens = nil
            stableSince = nil
        }
        if stableLens.map({ abs(Int($0) - Int(lens)) > 1 }) ?? true,
            pausedAt.map({ now > $0 }) ?? true {
            stableLens = lens
            stableSince = now
        }
        zoomReceivedAt = now
    }

    public mutating func notePause(at now: TimeInterval) {
        pausedAt = now
        stableSince = nil
        stableLens = nil
    }

    public func canResume(at now: TimeInterval) -> Bool {
        guard failureReason == nil, let pausedAt, let zoomReceivedAt,
            let stableSince, zoomReceivedAt > pausedAt, stableSince > pausedAt,
            now - zoomReceivedAt >= 0, now - zoomReceivedAt <= 0.3,
            zoomReceivedAt - stableSince >= 0.2 - 1e-9 else { return false }
        return true
    }

    public mutating func resetDispatch() {
        sampledAt = -.infinity
        lastLens = nil
        lastNativeCommand = nil
        nativeWakeAt = .infinity
        preparationZoom = nil
        preparationSentAt = nil
    }

    public func nextWakeInterval(at now: TimeInterval) -> TimeInterval {
        usesHighRateTargets ? max(0.000_001, nativeWakeAt - now)
            : max(0.000_001, sampledAt + Self.interval - now)
    }

    public func canSample(at now: TimeInterval) -> Bool {
        now.isFinite && now - sampledAt >= Self.interval - 1e-9
    }

    public func canSampleNativeTarget(at now: TimeInterval) -> Bool {
        now.isFinite && now - sampledAt >= NativeProgramZoom.interval - 1e-9
    }

    public mutating func lensTarget(for factor: Double, at now: TimeInterval) -> UInt16? {
        guard failureReason == nil, factor.isFinite, now.isFinite,
            canSample(at: now) else { return nil }
        sampledAt = now
        guard (1...maximumZoom).contains(factor) else { return nil }
        let lens = CamFov.pinchLens(for: factor)
        guard lens != lastLens else { return nil }
        lastLens = lens
        hasSentTarget = true
        return lens
    }

    public func nativeFailure(at now: TimeInterval) -> String? {
        if let failureReason { return failureReason }
        guard usesHighRateTargets else { return nil }
        // Lens reports arrive at 2.5 Hz. Angular reports cannot refresh them.
        guard let zoomReceivedAt, now.isFinite, now >= zoomReceivedAt,
            now - zoomReceivedAt <= 0.85 else { return "Move interrupted — camera zoom feedback lost" }
        return nil
    }

    public func nativeFailure(for demand: NativeProgramZoomDemand, at now: TimeInterval) -> String? {
        if let reason = nativeFailure(at: now) { return reason }
        if let reason = demand.failureReason { return reason }
        if case .position = demand.command { return nil }
        if let expected = preparationZoom, let sentAt = preparationSentAt {
            guard let measured = liveZoom, let receivedAt = zoomReceivedAt, receivedAt > sentAt,
                abs(measured - expected) <= 2.0 / 217.0 + 1e-9
            else { return "Move interrupted — camera did not reach the starting zoom" }
        }
        return nil
    }

    public mutating func nativeCommand(for demand: NativeProgramZoomDemand, at now: TimeInterval)
        -> NativeProgramZoomCommand?
    {
        guard nativeFailure(for: demand, at: now) == nil,
            demand.destination.isFinite, (1...maximumZoom).contains(demand.destination) else { return nil }
        nativeWakeAt = now + demand.nextChange
        let command = demand.command
        switch command {
        case .position(let factor):
            guard factor.isFinite, (1...maximumZoom).contains(factor), command != lastNativeCommand else { return nil }
            preparationZoom = factor
            preparationSentAt = now
            sampledAt = now
            lastLens = CamFov.pinchLens(for: factor)
        case .track(let factor):
            guard factor.isFinite, (1...maximumZoom).contains(factor) else { return nil }
            let due = sampledAt + NativeProgramZoom.interval
            guard now >= due - 1e-9 else {
                nativeWakeAt = due
                return nil
            }
            sampledAt = now
            nativeWakeAt = now + NativeProgramZoom.interval
            preparationZoom = nil
            preparationSentAt = nil
            let lens = CamFov.pinchLens(for: factor)
            // A duplicate still consumes its sample slot and any retained endpoint.
            guard lens != lastLens else { return nil }
            lastLens = lens
        case .stop:
            // STOP is immediate, including short idle gaps between native legs.
            guard hasSentTarget, command != lastNativeCommand else { return nil }
        }
        lastNativeCommand = command
        hasSentTarget = true
        return command
    }
}
