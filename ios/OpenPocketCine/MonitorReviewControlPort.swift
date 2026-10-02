#if DEBUG && targetEnvironment(simulator)
    import OpenCineAppKit
    import OpenCineCore
    import OpenPocketViewCore

    /// SIMULATED review only. Declared reports exercise the real public DJI/common contracts;
    /// this port has no native session, datalink, driver, saved approval or camera connection.
    @MainActor
    final class MonitorReviewControlPort: DJIControlPort {
        var status: CameraStatus
        let connectedModel: CameraModel?
        let connectedCameraID: String? = "simulated-common-input"
        var whiteBalanceDisplayStatus: CameraStatus { status }
        var currentShootingMode: ShootingMode? { ShootingMode.fromStatus(status.shootingMode) }
        let admitsMultiviewControl = true
        let isBusy = false
        let link = DJILinkState.ready
        var controlNote: String?
        var captureControlState: DJICaptureControlState? {
            .init(reported: status, model: connectedModel)
        }
        private(set) var writes: [String] = []
        private let render: @MainActor (CameraStatus) -> Void
        lazy var control = DJICameraSessionAdapter(session: self)

        init(status: CameraStatus, body: CameraModel, render: @escaping @MainActor (CameraStatus) -> Void = { _ in }) {
            self.status = status
            self.status.recordingReported = true
            self.status.focusTrack = .default
            self.status.zoomLens = status.zoomLens ?? CamFov.lens1x
            connectedModel = body
            self.render = render
        }

        private func report(_ name: String, onStage: (@MainActor (ControlWireEvent) -> Void)?, change: (inout CameraStatus) -> Void) {
            writes.append(name)
            onStage?(.sent)
            onStage?(.acknowledged)
            change(&status)
            render(status)
            control.sessionDidChange()
            onStage?(.confirmed)
        }

        func takePhoto() { writes.append("SIMULATED photo") }
        func setISO(_ index: IsoIndex, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
            report("SIMULATED ISO", onStage: onStage) { $0.isoIndex = index; $0.iso = index.isoValue ?? -1 }
        }
        func setRecording(_ start: Bool, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
            report("SIMULATED record", onStage: onStage) { $0.isRecording = start }
        }
        func setWhiteBalanceAuto(tint: Int?, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
            report("SIMULATED WB auto", onStage: onStage) { $0.whiteBalance = .auto(tint: tint ?? 0); $0.whiteBalanceTint = tint }
        }
        func setWhiteBalanceCustom(kelvin: Int, tint: Int, onStage: (@MainActor (ControlWireEvent) -> Void)?) {
            report("SIMULATED WB custom", onStage: onStage) {
                $0.whiteBalance = .custom(kelvin: kelvin, tint: tint)
                $0.whiteBalanceKelvin = kelvin
                $0.whiteBalanceTint = tint
            }
        }
        func writeShutter(_ denominator: Int, onStage: @escaping @MainActor (ControlWireEvent) -> Void) {
            report("SIMULATED shutter", onStage: onStage) { $0.shutterDenom = denominator }
        }
        func writeExposureCompensation(_ value: EvComp, onStage: @escaping @MainActor (ControlWireEvent) -> Void) {
            report("SIMULATED EV", onStage: onStage) { $0.evComp = value }
        }
        func writeFocusMode(_ value: OpenPocketViewCore.FocusMode, onStage: @escaping @MainActor (ControlWireEvent) -> Void) {
            report("SIMULATED focus", onStage: onStage) { $0.focusMode = value }
        }
        func writeZoom(_ ratio: Double, onStage: @escaping @MainActor (ControlWireEvent) -> Void) {
            report("SIMULATED zoom", onStage: onStage) { $0.zoomLens = CamFov.pinchLens(for: ratio) }
        }
    }

    extension AppModel {
        /// Explicit writable fixture, separate from the ordinary unknown/read-only clip preview.
        func presentSimulatedControls(status: CameraStatus, body: CameraModel) {
            let port = MonitorReviewControlPort(status: status, body: body) { [weak self] status in
                guard let self else { return }
                var presentation = status
                // Native recording reads its own report flag; a fixture's report is never one.
                presentation.recordingReported = session.status.recordingReported
                presentation.isRecording = session.status.isRecording
                session.status = presentation
            }
            let saved = OpenCineCore.SavedCamera(id: "simulated-common-input",
                integration: DJICameraSessionAdapter.integration,
                advertisedName: "SIMULATED common input", model: "SIMULATED")
            shell.present(ConnectedCamera(saved: saved, session: port.control))
            simulatedControlReview = port
        }
    }
#endif
