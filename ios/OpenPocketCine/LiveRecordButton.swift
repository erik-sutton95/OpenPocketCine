import MonitorUI
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

/// Record / shutter on the right rail. Hit target stays `LiveChromeMetrics.recordButtonSize`.
struct LiveRecordButton: View {
    var diameter: CGFloat = LiveChromeMetrics.recordButtonSize
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var locked

    private var state: LiveRecordChromeState {
        if model.session.status.isRecording {
            return model.session.controlBusy ? .stopping : .recording
        }
        return .idle
    }

    @State private var confirmRecord = false

    var body: some View {
        MonitorRecordLamp(
            diameter: diameter, recording: state.isRecordingLook,
            photo: model.session.currentShootingMode?.isPhoto == true
        )
        .contentShape(Circle())
        .gesture(
            LongPressGesture(minimumDuration: 0.45)
                .exclusively(before: TapGesture())
                .onEnded { gesture in
                    guard !model.session.controlBusy, !locked else { return }
                    switch gesture {
                    case .first: model.captureSheet = .mode
                    case .second: pressShutter()
                    }
                }
        )
        .disabled(model.session.controlBusy || locked)
        .opacity(locked ? 0.4 : (state == .stopping ? 0.72 : 1))
        .sensoryFeedback(
            model.hapticsEnabled
                ? .impact(weight: .heavy) : .impact(flexibility: .solid, intensity: 0),
            trigger: model.session.status.isRecording
        )
        .confirmationDialog(
            state.isRecordingLook ? "Stop recording?" : "Start recording?",
            isPresented: $confirmRecord,
            titleVisibility: .visible
        ) {
            Button(
                state.isRecordingLook ? "Stop" : "Start",
                role: state.isRecordingLook ? .destructive : nil
            ) {
                model.session.pressShutter()
            }
            Button("Cancel", role: .cancel) {}
        }
        .accessibilityLabel(accessibility)
        .accessibilityHidden(false)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { pressShutter() }
        .accessibilityAction(named: "Shooting mode") { if !locked { model.captureSheet = .mode } }
        .accessibilityIdentifier(
            model.session.currentShootingMode?.isPhoto == true
                ? "monitor.system.shutter" : "monitor.system.record"
        )
    }

    private func pressShutter() {
        guard !model.session.controlBusy, !locked else { return }
        if model.recordConfirmationEnabled {
            confirmRecord = true
        } else {
            model.session.pressShutter()
        }
    }

    private var accessibility: String {
        if model.session.currentShootingMode?.isPhoto == true {
            return "Take photo"
        }
        switch state {
        case .idle: return "Start recording"
        case .recording: return "Stop recording"
        case .stopping: return "Stopping recording"
        }
    }
}

/// Osmo Pocket shutter: recessed charcoal well, thin coral ring. Recording fills the ring.
struct RecordLamp: View {
    let diameter: CGFloat
    let recording: Bool
    var body: some View { MonitorRecordLamp(diameter: diameter, recording: recording) }
}

/// REC tally on the physical screen bezel — OpenZCine `RecordingBorderModule`.
struct LiveRecordingTally: View {
    var cornerRadius: CGFloat = LiveRecordingTally.displayCornerRadius

    var body: some View {
        RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
            .strokeBorder(LiveDesign.rec, lineWidth: Self.lineWidth)
            .shadow(color: LiveDesign.rec.opacity(0.55), radius: 14)
            .allowsHitTesting(false)
    }

    static let lineWidth: CGFloat = 4
    /// Approximate display corner. No public API; decorative, tuned to modern iPhones.
    static let displayCornerRadius: CGFloat = 52

    static func borderRect(in layout: LiveMonitorLayout) -> CGRect {
        CGRect(origin: .zero, size: layout.viewport)
    }
}
