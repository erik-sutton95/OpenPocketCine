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
    @Environment(AppModel.self) private var model

    private var state: LiveRecordChromeState {
        if model.session.status.isRecording {
            return model.session.controlBusy ? .stopping : .recording
        }
        return .idle
    }

    @State private var confirmRecord = false

    var body: some View {
        Button {
            if model.recordConfirmationEnabled {
                confirmRecord = true
            } else {
                model.session.pressShutter()
            }
        } label: {
            RecordLamp(
                diameter: LiveChromeMetrics.recordButtonSize, recording: state.isRecordingLook)
        }
        .buttonStyle(.zcTapTarget)
        .disabled(model.session.controlBusy)
        .opacity(state == .stopping ? 0.72 : 1)
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
        .accessibilityIdentifier(
            model.session.currentShootingMode?.isPhoto == true
                ? "monitor.system.shutter" : "monitor.system.record"
        )
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
private struct RecordLamp: View {
    let diameter: CGFloat
    let recording: Bool

    @State private var pulse = false

    /// Physical Pocket face — matte charcoal, lifted off DJI Black chrome.
    private static let well = Color(red: 44 / 255, green: 43 / 255, blue: 43 / 255)
    /// Pocket shutter ring — coral, not cinema tally red.
    private static let pocketRing = Color(red: 227 / 255, green: 83 / 255, blue: 70 / 255)
    /// Hardware ring is ~half the face. Stroke stays thin like the Pocket button.
    private static let ringRatio: CGFloat = 0.50
    private static let ringLineRatio: CGFloat = 0.026

    var body: some View {
        let glow = recording ? (pulse ? 0.55 : 0.22) : 0
        let glowRadius: CGFloat = recording ? (pulse ? 10 : 4) : 0
        let ring = diameter * Self.ringRatio
        let ringLine = max(2.0, diameter * Self.ringLineRatio)

        return ZStack {
            Circle()
                .fill(Self.well)
            // Physical gap where the Pocket button sits in its housing.
            Circle()
                .strokeBorder(Color.black.opacity(0.55), lineWidth: 1.5)

            if recording {
                Circle()
                    .fill(Self.pocketRing)
                    .frame(width: ring, height: ring)
            } else {
                Circle()
                    .strokeBorder(Self.pocketRing, lineWidth: ringLine)
                    .frame(width: ring, height: ring)
            }
        }
        .frame(width: diameter, height: diameter)
        .shadow(color: Color.black.opacity(0.40), radius: 2, y: 1)
        .shadow(color: Self.pocketRing.opacity(glow), radius: glowRadius)
        .onAppear { syncPulse(recording) }
        .onChange(of: recording) { _, rec in
            syncPulse(rec)
        }
    }

    private func syncPulse(_ recording: Bool) {
        if recording {
            pulse = false
            withAnimation(.easeInOut(duration: 0.85).repeatForever(autoreverses: true)) {
                pulse = true
            }
        } else {
            withAnimation(.easeOut(duration: 0.16)) {
                pulse = false
            }
        }
    }
}

/// REC tally on the physical screen bezel — OpenZCine `RecordingBorderModule`.
struct LiveRecordingTally: View {
    var body: some View {
        RoundedRectangle(cornerRadius: Self.displayCornerRadius, style: .continuous)
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
