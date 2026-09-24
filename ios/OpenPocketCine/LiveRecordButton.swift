import MonitorUI
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

    var canConfirm: Bool {
        !locked && !busy && phase == .live && ShootingMode.fromStatus(mode)?.isPhoto != true
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
    @State private var pendingRecord: RecordConfirmationContext?

    private var isPhoto: Bool { model.session.status.isPhoto }
    private var confirmationContext: RecordConfirmationContext {
        RecordConfirmationContext(
            mode: model.session.status.shootingMode,
            recording: model.session.status.isRecording,
            locked: locked || model.session.isLocked,
            busy: model.session.controlBusy, phase: model.session.phase)
    }

    var body: some View {
        MonitorRecordLamp(
            diameter: diameter, recording: state.isRecordingLook,
            photo: isPhoto
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
                guard pendingRecord == confirmationContext, confirmationContext.canConfirm else {
                    return
                }
                pendingRecord = nil
                model.session.pressShutter()
            }
            Button("Cancel", role: .cancel) {}
        }
        .onChange(of: confirmationContext) { _, _ in
            confirmRecord = false
            pendingRecord = nil
        }
        .accessibilityLabel(accessibility)
        .accessibilityHidden(false)
        .accessibilityAddTraits(.isButton)
        .accessibilityAction { pressShutter() }
        .accessibilityAction(named: "Shooting mode") { if !locked { model.captureSheet = .mode } }
        .accessibilityIdentifier(
            isPhoto ? "monitor.system.shutter" : "monitor.system.record"
        )
    }

    private func pressShutter() {
        guard !model.session.controlBusy, !locked, !model.session.isLocked else { return }
        if model.recordConfirmationEnabled, !isPhoto {
            pendingRecord = confirmationContext
            confirmRecord = true
        } else {
            model.session.pressShutter()
        }
    }

    private var accessibility: String {
        if isPhoto {
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
    @Environment(\.monitorPresentationIsVisible) private var isVisible
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.scenePhase) private var scenePhase

    var body: some View {
        // Core Animation owns the pulse: the render server animates opacity with
        // no per-step app or SwiftUI work for the whole take (a SwiftUI timeline
        // here cost about a third of the app's CPU while recording).
        LiveRecordingTallyLayer(
            cornerRadius: cornerRadius, color: UIColor(LiveDesign.rec),
            pulsing: isVisible && scenePhase == .active && !reduceMotion
        )
        .allowsHitTesting(false)
        .accessibilityHidden(true)
    }

    static let lineWidth: CGFloat = 4
    /// Approximate display corner. No public API; decorative, tuned to modern iPhones.
    static let displayCornerRadius: CGFloat = 52

    static func borderRect(in layout: LiveMonitorLayout) -> CGRect {
        CGRect(origin: .zero, size: layout.viewport)
    }
}

/// Full-screen REC border: stroke plus glow on a precomputed shadow path, with a
/// render-server opacity pulse (same period and floor as `monitorPulse`).
private struct LiveRecordingTallyLayer: UIViewRepresentable {
    let cornerRadius: CGFloat
    let color: UIColor
    let pulsing: Bool

    func makeUIView(context: Context) -> TallyView { TallyView() }

    func updateUIView(_ view: TallyView, context: Context) {
        view.configure(cornerRadius: cornerRadius, color: color, pulsing: pulsing)
    }

    final class TallyView: UIView {
        private let border = CAShapeLayer()
        private var cornerRadius: CGFloat = 0
        private var pulsing = false
        private static let pulseKey = "rec-pulse"

        override init(frame: CGRect) {
            super.init(frame: frame)
            backgroundColor = .clear
            isUserInteractionEnabled = false
            border.fillColor = nil
            border.lineWidth = LiveRecordingTally.lineWidth
            border.shadowOpacity = 0.55
            border.shadowRadius = 14
            border.shadowOffset = .zero
            layer.addSublayer(border)
        }

        required init?(coder: NSCoder) { nil }

        func configure(cornerRadius: CGFloat, color: UIColor, pulsing: Bool) {
            self.cornerRadius = cornerRadius
            border.strokeColor = color.cgColor
            border.shadowColor = color.cgColor
            self.pulsing = pulsing
            applyPulse()
            setNeedsLayout()
        }

        override func layoutSubviews() {
            super.layoutSubviews()
            CATransaction.begin()
            CATransaction.setDisableActions(true)
            border.frame = bounds
            // strokeBorder: the stroke sits inside the bounds.
            let inset = LiveRecordingTally.lineWidth / 2
            let path = UIBezierPath(
                roundedRect: bounds.insetBy(dx: inset, dy: inset),
                cornerRadius: max(0, cornerRadius - inset)
            ).cgPath
            border.path = path
            border.shadowPath = path.copy(
                strokingWithWidth: LiveRecordingTally.lineWidth, lineCap: .butt,
                lineJoin: .miter, miterLimit: 10)
            CATransaction.commit()
        }

        override func didMoveToWindow() {
            super.didMoveToWindow()
            // Core Animation drops animations when a layer leaves the window.
            applyPulse()
        }

        private func applyPulse() {
            let active = pulsing && window != nil
            guard active != (border.animation(forKey: Self.pulseKey) != nil) else { return }
            guard active else {
                border.removeAnimation(forKey: Self.pulseKey)
                return
            }
            let pulse = CABasicAnimation(keyPath: "opacity")
            pulse.fromValue = 1
            pulse.toValue = MonitorMotion.recPulseFloor
            pulse.duration = MonitorMotion.recPulseDuration / 2
            pulse.autoreverses = true
            pulse.repeatCount = .infinity
            pulse.timingFunction = CAMediaTimingFunction(name: .easeInEaseOut)
            pulse.preferredFrameRateRange = CAFrameRateRange(minimum: 15, maximum: 30, preferred: 30)
            pulse.isRemovedOnCompletion = false
            border.add(pulse, forKey: Self.pulseKey)
        }
    }
}
