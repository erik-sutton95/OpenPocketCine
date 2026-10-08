import Foundation
import OpenCineApple

extension CameraSession {
    /// Reads the native owner and raw camera pushes, never optimistic editor values.
    var nativeQualificationSnapshot: MonitorNativeQualificationSnapshot {
        #if targetEnvironment(simulator)
        let simulated = true
        #else
        let simulated = false
        #endif
        let source = decoder.sourceToken
        let reported = cameraReportedCapture
        return MonitorNativeQualificationSnapshot(
            simulated: simulated, sourceIdentity: source.map { String(describing: $0) },
            sourceActive: source.map { decoder.sourceToken == $0 },
            sourceFrameAt: decoder.lastSourceFrameAt?.timeIntervalSince1970,
            sourcePresentations: decoder.sourcePresentations,
            nativeDecodeOutputs: decoder.nativeOutputExpected ? decoder.nativeDecodeTotals.output : nil,
            cameraRecording: reported.recordingReported ? reported.isRecording : nil,
            cameraISO: reported.iso > 0 ? reported.iso : nil,
            cameraISOIsAuto: reported.isoIndex.map { $0 == .auto })
    }
}
