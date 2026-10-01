import Foundation

/// Copied from OpenZCine `Sources/OpenZCineCore/CameraLinkHealth.swift`.
/// Pocket has no PTP RTT and no SoftAP RSSI — leave `ptpRoundTripMilliseconds` nil and score
/// from measured live-view FPS + frame freshness + decoder / datalink failures.
public enum CameraLinkPhase: Equatable, Sendable {
    case disconnected, connecting, connectedIdle, streaming, recovering, demo
}

public struct CameraLinkHealthInputs: Equatable, Sendable {
    public var phase: CameraLinkPhase
    public var ptpRoundTripMilliseconds: Double?
    public var liveViewFPS: Double?
    public var targetLiveViewFPS: Double
    public var secondsSinceLastGoodFrame: Double?
    public var consecutiveBadFrames: Int
    public var recentCommandFailures: Int
    public var isRecoveringStream: Bool
    public init(
        phase: CameraLinkPhase = .disconnected, ptpRoundTripMilliseconds: Double? = nil,
        liveViewFPS: Double? = nil, targetLiveViewFPS: Double = 30,
        secondsSinceLastGoodFrame: Double? = nil, consecutiveBadFrames: Int = 0,
        recentCommandFailures: Int = 0, isRecoveringStream: Bool = false
    ) {
        self.phase = phase
        self.ptpRoundTripMilliseconds = ptpRoundTripMilliseconds
        self.liveViewFPS = liveViewFPS
        self.targetLiveViewFPS = max(1, targetLiveViewFPS)
        self.secondsSinceLastGoodFrame = secondsSinceLastGoodFrame
        self.consecutiveBadFrames = max(0, consecutiveBadFrames)
        self.recentCommandFailures = max(0, recentCommandFailures)
        self.isRecoveringStream = isRecoveringStream
    }
}

public struct CameraLinkHealthSnapshot: Equatable, Sendable {
    public var linkHealthScore: Int
    public var detailCaption: String
    public init(linkHealthScore: Int, detailCaption: String) {
        self.linkHealthScore = min(100, max(0, linkHealthScore))
        self.detailCaption = detailCaption
    }
}

public enum CameraLinkHealthScorer {
    public static func latencyScore(milliseconds: Double) -> Double {
        switch milliseconds {
        case ..<30: return 100
        case 30..<60: return 92
        case 60..<100: return 82
        case 100..<150: return 68
        case 150..<250: return 48
        case 250..<500: return 28
        default: return 10
        }
    }
    public static func frameDeliveryScore(actualFPS: Double, targetFPS: Double) -> Double {
        guard actualFPS > 0, targetFPS > 0 else { return 0 }
        return min(1, actualFPS / targetFPS) * 100
    }
    public static func frameFreshnessPenalty(secondsSinceLastGoodFrame: Double?) -> Double {
        guard let s = secondsSinceLastGoodFrame else { return 0 }
        switch s {
        case ..<0.5: return 0
        case 0.5..<1.5: return 8
        case 1.5..<3: return 20
        case 3..<5: return 35
        default: return 55
        }
    }
    public static func badFramePenalty(consecutiveBadFrames: Int) -> Double {
        switch consecutiveBadFrames {
        case 0: return 0
        case 1...2: return 6
        case 3...5: return 18
        case 6...8: return 32
        default: return 50
        }
    }
    public static func commandFailurePenalty(recentFailures: Int) -> Double {
        switch recentFailures {
        case 0: return 0
        case 1: return 15
        case 2: return 30
        default: return 50
        }
    }
    public static func score(_ inputs: CameraLinkHealthInputs) -> CameraLinkHealthSnapshot {
        switch inputs.phase {
        case .disconnected:
            return .init(linkHealthScore: 0, detailCaption: "Not connected")
        case .demo:
            return .init(linkHealthScore: 85, detailCaption: "Demo session")
        case .connecting:
            return .init(linkHealthScore: 20, detailCaption: "Connecting…")
        case .connectedIdle, .streaming, .recovering: break
        }
        let latency = inputs.ptpRoundTripMilliseconds.map(latencyScore) ?? 0
        let latencyDetail = inputs.ptpRoundTripMilliseconds.map {
            String(format: "%.0f ms RTT", $0)
        }
        let frameScore: Double
        let frameDetail: String?
        if let fps = inputs.liveViewFPS, inputs.phase == .streaming || inputs.phase == .recovering {
            frameScore = frameDeliveryScore(actualFPS: fps, targetFPS: inputs.targetLiveViewFPS)
            frameDetail = String(format: "%.1f / %.0f FPS", fps, inputs.targetLiveViewFPS)
        } else {
            frameScore = 0
            frameDetail = nil
        }
        let linkHealthRaw: Double
        if inputs.phase == .streaming || inputs.phase == .recovering {
            let lc = latency > 0 ? latency : 70
            linkHealthRaw =
                frameScore * 0.55 + lc * 0.25 + 20
                - frameFreshnessPenalty(secondsSinceLastGoodFrame: inputs.secondsSinceLastGoodFrame)
                - badFramePenalty(consecutiveBadFrames: inputs.consecutiveBadFrames)
                - commandFailurePenalty(recentFailures: inputs.recentCommandFailures)
                - (inputs.isRecoveringStream ? 25 : 0)
        } else {
            let lc = latency > 0 ? latency : 60
            linkHealthRaw =
                lc * 0.75 + 25
                - commandFailurePenalty(recentFailures: inputs.recentCommandFailures)
                - (inputs.isRecoveringStream ? 25 : 0)
        }
        let detail = [frameDetail, latencyDetail].compactMap { $0 }.joined(separator: " · ")
        return .init(
            linkHealthScore: Int(linkHealthRaw.rounded()),
            detailCaption: detail.isEmpty ? "Command channel warm" : detail)
    }
}

/// Pocket mapping onto OpenZCine's FPS chip labels + `CameraLinkHealthScorer` phase.
///
/// SoftAP HEVC live view is 1280×720 at ~25 fps (`docs/protocol-notes.md`). That is the
/// delivery target for bars — not `CameraStatus.fps`, which is the recording format already
/// shown on the Rec chip. There is no SoftAP RSSI on the bus (and iOS cannot read it).
public enum LiveViewLink {
    public static let targetFPS: Double = 25

    public static func cameraLinkPhase(
        connection: ConnectionPhase,
        recovering: Bool,
        measuredFPS: Double
    ) -> CameraLinkPhase {
        if case .failed = connection { return .disconnected }
        if measuredFPS > 0 { return recovering ? .recovering : .streaming }
        switch connection {
        case .idle: return .disconnected
        case .live: return .connectedIdle
        default: return .connecting
        }
    }

    public static func fpsChipLabel(
        connection: ConnectionPhase,
        recovering: Bool,
        formattedFPS: String,
        measuredFPS: Double
    ) -> String {
        if case .failed = connection { return "FAIL" }
        if recovering { return "RECOV" }
        if measuredFPS > 0 { return formattedFPS }
        switch connection {
        case .idle: return "—"
        default: return "LINK"
        }
    }
}

/// Cover the feed well until a **rolling** picture exists.
/// After that, a stall, AF-C hunt, or in-flight recover keeps the last frame —
/// putting the waiting plate back is the mid-session “Waiting for live-view” hang.
public enum LiveFeedWarmup {
    /// ~⅓ s at 25 fps. Two leftover GOP frames must not lift the plate.
    public static let minimumRollingIntervals = 8

    public static func isWarming(
        hasPresentedPicture: Bool,
        measuredFPS: Double = 0,
        rollingIntervals: Int = 0,
        recovering: Bool = false,
        secondsSinceLastPresented: TimeInterval? = nil,
        stall: TimeInterval = FeedPresentPolicy.freezeThreshold
    ) -> Bool {
        _ = recovering
        _ = secondsSinceLastPresented
        _ = stall
        if !hasPresentedPicture { return true }
        if measuredFPS <= 0 { return true }
        if rollingIntervals < minimumRollingIntervals { return true }
        return false
    }
}
