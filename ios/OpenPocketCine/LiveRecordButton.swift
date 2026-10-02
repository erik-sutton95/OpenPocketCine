import MonitorUI
import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI

/// Idle = Pocket well + thin coral ring. Recording fills that ring. Stopping dims the face.
enum LiveRecordChromeState: Equatable {
    case idle
    case recording
    case stopping

    var isRecordingLook: Bool {
        self == .recording || self == .stopping
    }
}

/// A confirmation authorizes the capture state visible when it was opened.
struct RecordConfirmationContext: Equatable {
    let mode: Int
    let recording: Bool
    let locked: Bool
    let busy: Bool
    let phase: ConnectionPhase
    /// The session and link the prompt was raised for; another one dismisses it (STATE-01).
    var target: ControlTarget? = nil

    var canConfirm: Bool {
        !locked && !busy && phase == .live && ShootingMode.fromStatus(mode)?.isPhoto != true
    }
}

/// Record / shutter on the right rail. Hit target stays `LiveChromeMetrics.recordButtonSize`.
struct LiveRecordButton: View {
    var diameter: CGFloat = LiveChromeMetrics.recordButtonSize
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var locked

    var body: some View {
        MonitorCaptureButton(control: model.control, diameter: diameter,
            enabled: !locked && !model.session.isLocked && !model.session.controlBusy,
            photo: model.session.status.isPhoto,
            confirm: model.recordConfirmationEnabled, haptics: model.hapticsEnabled,
            takePhoto: { model.session.control.shutter() },
            openMode: { model.captureSheet = .mode })
    }
}

/// Existing multiview call sites use the common render-server recording border.
struct LiveRecordingTally: View {
    var cornerRadius: CGFloat = LiveRecordingTally.displayCornerRadius
    static let displayCornerRadius: CGFloat = 52
    var body: some View { MonitorRecordingBorder(cornerRadius: cornerRadius) }
}
