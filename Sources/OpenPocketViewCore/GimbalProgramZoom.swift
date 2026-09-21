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

    public init(program: GimbalProgram, model: CameraModel?, status: CameraStatus) {
        self.program = program
        self.model = model
        self.status = status
    }

    public var liveZoom: Double? { status.zoomFactor }
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
        if let previous = zoomReceivedAt, now - previous > 0.3 {
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
    }

    public func nextWakeInterval(at now: TimeInterval) -> TimeInterval {
        max(0.000_001, sampledAt + Self.interval - now)
    }

    public func canSample(at now: TimeInterval) -> Bool {
        now.isFinite && now - sampledAt >= Self.interval - 1e-9
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
}
