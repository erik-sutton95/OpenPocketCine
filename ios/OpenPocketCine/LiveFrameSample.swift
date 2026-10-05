import CoreImage
import CoreVideo
import Foundation
import OpenCineApple
import OpenCineMedia
import OpenPocketViewCore

extension MonitorTransfer {
    /// Wire ColorMode that selected this transfer (`3F` / `3C` / `17` / `41`).
    var colorMode: ColorMode {
        switch self {
        case .rec709: .normal
        case .hdr: .hdr
        case .dlog: .dLog
        case .dlogm: .dLogM
        case .dlog2: .dLog2
        // ponytail: no DJI wire mode carries I-Log; Pocket never selects it.
        case .ilog: .normal
        }
    }

    /// `CameraStatus.monitorTransfer`, else ColorMode, else the last known
    /// curve. Rec.709 only when nothing has been seen yet — falling back on a
    /// missing `@2` is the WAVE black shelf (D-Log2 paper black at ~8 IRE).
    static func resolved(
        _ status: MonitorTransfer?, colorMode: ColorMode?, previous: MonitorTransfer? = nil
    ) -> MonitorTransfer {
        status ?? colorMode.map(MonitorTransfer.init) ?? previous ?? .rec709
    }
}

/// DJI source calibration supplied to neutral native owners; it is not a camera observation.
enum PocketMonitorCalibration {
    static let clipProfile = ScopeClipProfile(
        calibrations: [
            .dlog2: .init(
                referenceISO: OpenCineDJI.ScopeExposureCeiling.referenceEI,
                referenceByte: OpenCineDJI.ScopeExposureCeiling.dlog2LiveTapByteAt1600,
                refinementMaximumByte: OpenCineDJI.ScopeExposureCeiling.dlog2LiveTapByteAt1600High),
            .dlog: .init(
                referenceISO: OpenCineDJI.ScopeExposureCeiling.dlogReferenceEI,
                referenceByte: OpenCineDJI.ScopeExposureCeiling.dlogLiveTapByteAtNative,
                refinementMaximumByte: OpenCineDJI.ScopeExposureCeiling.dlogLiveTapByteAtNativeHigh,
                refinementAtOrAboveReference: true),
        ], defaultISO: OpenCineDJI.ScopeExposureCeiling.referenceEI)
}

// Source adapters select measured calibration and interpretation for the shared native owner.
typealias ScopeAssistBundle = OpenCineMedia.ScopeAssistBundle
typealias PocketScopeSampler = OpenCineMedia.ScopeSampler

extension ScopeSampler {
    static func minInterval(
        activeScopeCount: Int,
        thermalState: ProcessInfo.ThermalState = ProcessInfo.processInfo.thermalState
    ) -> CFAbsoluteTime {
        OpenCineApple.MonitorAssistEngine.minInterval(
            activeScopeCount: activeScopeCount,
            thermalState: thermalState)
    }
    static func thermalMultiplier(_ state: ProcessInfo.ThermalState) -> Double {
        OpenCineApple.MonitorAssistEngine.thermalMultiplier(state)
    }
    static func copyBGRA(_ buffer: CVPixelBuffer, maxWidth: Int) -> (
        bytes: [UInt8], width: Int, height: Int, bytesPerRow: Int
    )? {
        LiveFrameTap.copyBGRA8(buffer, maxWidth: maxWidth)
    }

    /// Display cube for VECTOR when no operator LUT is armed.
    static func monitorCube(for transfer: MonitorTransfer, effects: LiveImageEffects) -> CubeLUT? {
        if let armed = ScopeMonitorLook.cube(from: effects) { return armed }
        switch transfer {
        case .dlog: return BundledOfficialDJILUT.cube(.pocketDLog)
        case .dlog2: return BundledOfficialDJILUT.cube(.pocketDLog2)
        case .rec709, .hdr, .dlogm, .ilog: return nil
        }
    }

}

/// Operator LUT (armed in effects) as a scope-side cube.
enum ScopeMonitorLook {
    static func cube(from effects: LiveImageEffects) -> CubeLUT? {
        OpenCineApple.MonitorAssistEngine.armedCube(effects.nativeImagePlan)
    }
}

typealias LiveFrameSampleBus = OpenCineApple.LiveFrameSampleBus

extension LiveFrameSampleBus {
    convenience init() { self.init(profile: PocketMonitorCalibration.clipProfile) }
    var colorMode: ColorMode? { reportedTransfer.map(\.colorMode) }

}

/// Source adaptation supplies measured saturation, look tables and transfer inference.
final class LiveAssistEngine: Sendable {
    private let native: OpenCineApple.MonitorAssistEngine
    static var configuration: OpenCineApple.MonitorAssistConfiguration {
        let curves = Dictionary(
            uniqueKeysWithValues: [MonitorTransfer.rec709, .hdr, .dlog, .dlogm, .dlog2, .ilog]
                .compactMap { transfer in
                    DJILook.rec709LookCurve(transfer).map { (transfer, $0) }
                })
        return .init(
            clipProfile: PocketMonitorCalibration.clipProfile, lookCurves: curves,
            defaultScopeLook: { transfer in
                switch transfer {
                case .dlog: return BundledOfficialDJILUT.cube(.pocketDLog)
                case .dlog2: return BundledOfficialDJILUT.cube(.pocketDLog2)
                case .rec709, .hdr, .dlogm, .ilog: return nil
                }
            },
            inferTransfer: { MonitorTransfer.inferred(minByte: $0, maxByte: $1, fallback: $2) },
            logSubsystem: "com.opencapture.openpocketcine", journal: { ControlLiveLog.line($0) })
    }
    init() { native = OpenCineApple.MonitorAssistEngine(configuration: Self.configuration) }
    func adopt(exposureCeiling: OpenCineMedia.ScopeExposureCeiling) {
        native.adopt(exposureCeiling: exposureCeiling)
    }
    func updatePolicy(effects: LiveImageEffects, transfer: MonitorTransfer) {
        native.updatePolicy(effects: effects.nativeAssistPolicy, transfer: transfer)
    }
    func submit(
        _ buffer: CVPixelBuffer, effects: LiveImageEffects? = nil,
        transfer: MonitorTransfer? = nil, timeNs: Int64 = 0,
        completion: @escaping @Sendable (OpenCineApple.MonitorAssistEngine.Result) -> Void
    ) {
        native.submit(
            buffer, effects: effects?.nativeAssistPolicy, transfer: transfer,
            timeNs: timeNs == 0 ? nil : timeNs, completion: completion)
    }
    func reset() { native.reset() }
}
extension OpenCineApple.MonitorAssistEngine.Result {
    var colorMode: ColorMode { transfer.colorMode }
}
