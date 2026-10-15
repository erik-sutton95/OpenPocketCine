import Foundation
import OpenCineMedia
import OpenPocketViewCore

extension CameraSession {
    var captureControlState: DJICaptureControlState? {
        DJICaptureControlState(
            reported: cameraReportedCapture, model: connectedModel,
            shutterPresentation: OperatorPrefs.shutterUsesAngle ? .emulatedAngle : .cameraValue)
    }

    func writeShutter(
        _ denominator: Int, onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        guard cameraReportedCapture.expoMode == .manual,
            cameraReportedCapture.availableShutterDenoms.contains(denominator)
        else {
            onStage(.notSent)
            return
        }
        setShutterDenom(denominator, onStage: onStage, ensureManual: false)
    }

    func writeHostShutterAngle(
        _ degrees: Double, denominator: Int, admission: DJICommandAdmission?,
        onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        guard OperatorPrefs.shutterUsesAngle, !cameraReportedCapture.isPhoto,
            admission?.admits(commandOwner) ?? true
        else {
            onStage(.notSent)
            return
        }
        let source = commandOwner.map { DJICommandAdmission(owner: $0, isCurrent: { true }) }
        let note: @MainActor (ControlWireEvent) -> Void = { [weak self] stage in
            if stage == .sent, let self, source?.admits(self.commandOwner) == true,
                admission?.isCurrent ?? true
            {
                OperatorPrefs.shutterAngleDegrees = degrees
            }
            onStage(stage)
        }
        if let admission {
            writeShutter(denominator, admission: admission, onStage: note)
        } else {
            writeShutter(denominator, onStage: note)
        }
    }

    func writeExposureCompensation(
        _ value: EvComp, onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        setEv(value, onStage: onStage)
    }

    func writeFocusMode(
        _ value: FocusMode, onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        setFocusMode(value, onStage: onStage)
    }

    func writeZoom(
        _ ratio: Double, onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        setZoom(ratio, onStage: onStage)
    }

    func writeShutter(
        _ denominator: Int, admission: DJICommandAdmission,
        onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        guard cameraReportedCapture.expoMode == .manual,
            cameraReportedCapture.availableShutterDenoms.contains(denominator)
        else {
            onStage(.notSent)
            return
        }
        setShutterDenom(denominator, admission: admission, onStage: onStage, ensureManual: false)
    }

    func writeExposureCompensation(
        _ value: EvComp, admission: DJICommandAdmission,
        onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        setEv(value, admission: admission, onStage: onStage)
    }

    func writeFocusMode(
        _ value: FocusMode, admission: DJICommandAdmission,
        onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        setFocusMode(value, admission: admission, onStage: onStage)
    }

    func writeZoom(
        _ ratio: Double, admission: DJICommandAdmission,
        onStage: @escaping @MainActor (ControlWireEvent) -> Void
    ) {
        setZoom(ratio, admission: admission, onStage: onStage)
    }
}
