import OpenPocketViewCore
import SwiftUI

/// On-feed analog stick. Streams `0x04/0x01` while held, center on lift.
/// UI 2.0 uses translucent white at rest and cyan while the operator holds it.
struct LiveGimbalStick: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    var enabled: Bool
    @State private var knobOffset: CGSize = .zero
    @State private var dragging = false
    @State private var contact = false
    @State private var taps = GimbalStick.TapSequence()
    @State private var pendingDouble: Task<Void, Never>?
    @State private var pressTick = 0
    @State private var recenterTick = 0
    @State private var flipTick = 0

    private var size: CGFloat { LiveChromeMetrics.gimbalStickSize }
    private var knob: CGFloat { LiveChromeMetrics.gimbalKnobSize }
    private var travel: CGFloat { (size - knob) / 2 }
    private var opacity: CGFloat { contact ? 0.8 : LiveChromeMetrics.gimbalStickOpacity }
    private var interactive: Bool { enabled && !interfaceLocked }
    private var ink: Color { contact ? LiveDesign.accent : LiveDesign.text }

    var body: some View {
        ZStack {
            Circle()
                .strokeBorder(ink.opacity(opacity), lineWidth: 2)
            Circle()
                .fill(ink.opacity(opacity))
                .frame(width: knob, height: knob)
                .offset(knobOffset)
                .animation(
                    contact ? nil : .spring(response: 0.3, dampingFraction: 0.72), value: knobOffset
                )
        }
        .animation(.easeOut(duration: 0.12), value: contact)
        .frame(width: size, height: size)
        .contentShape(Circle())
        .gesture(drag, including: interactive ? .gesture : .none)
        .allowsHitTesting(interactive)
        .sensoryFeedback(.impact(weight: .light), trigger: pressTick)
        .sensoryFeedback(.impact(weight: .medium), trigger: recenterTick)
        .sensoryFeedback(.impact(weight: .heavy), trigger: flipTick)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Gimbal stick")
        .accessibilityHint("Drag to move the gimbal. Double-tap to recenter. Triple-tap to flip.")
        .accessibilityIdentifier("monitor.system.gimbal")
        .onDisappear {
            cancelTaps()
            contact = false
            model.session.endGimbalStick()
        }
        .onChange(of: interfaceLocked) { _, locked in
            if locked {
                contact = false
                cancelTaps()
                release()
            }
        }
        .onChange(of: enabled) { _, on in
            if !on {
                contact = false
                cancelTaps()
                release()
            }
        }
    }

    private var drag: some Gesture {
        DragGesture(minimumDistance: 0)
            .onChanged { value in
                if !contact {
                    contact = true
                    hapticPress()
                }
                let limited = clamp(value.translation)
                let mag =
                    hypot(Double(limited.width), Double(limited.height))
                    / Double(max(travel, 1))
                if !GimbalStick.isTap(normalizedMagnitude: mag) {
                    cancelTaps()
                    dragging = true
                    model.gimbalScreenHeld = true
                    knobOffset = limited
                    let nx = Double(limited.width / max(travel, 1))
                    let ny = Double(-limited.height / max(travel, 1))
                    model.session.updateGimbalStick(
                        x: nx, y: ny, sensitivity: model.gimbalStickSensitivity,
                        assistMirror: model.assist.isVisible(.mirror))
                }
            }
            .onEnded { _ in
                contact = false
                if dragging {
                    cancelTaps()
                    release()
                    return
                }
                handleTap()
                knobOffset = .zero
            }
    }

    private func handleTap() {
        switch taps.tap(at: Date().timeIntervalSinceReferenceDate) {
        case .first:
            break
        case .second:
            pendingDouble?.cancel()
            pendingDouble = Task { @MainActor in
                let ns = UInt64(GimbalStick.doubleTapWindow * 1_000_000_000)
                try? await Task.sleep(nanoseconds: ns)
                guard !Task.isCancelled else { return }
                if taps.commitDouble() {
                    hapticRecenter()
                    model.session.recenterGimbal()
                }
            }
        case .third:
            pendingDouble?.cancel()
            pendingDouble = nil
            hapticFlip()
            model.session.flipGimbal()
        }
    }

    private func hapticPress() {
        guard model.hapticsEnabled else { return }
        pressTick += 1
    }

    private func hapticRecenter() {
        guard model.hapticsEnabled else { return }
        recenterTick += 1
    }

    private func hapticFlip() {
        guard model.hapticsEnabled else { return }
        flipTick += 1
    }

    private func cancelTaps() {
        pendingDouble?.cancel()
        pendingDouble = nil
        taps.reset()
    }

    private func release() {
        dragging = false
        model.gimbalScreenHeld = false
        knobOffset = .zero
        model.session.endGimbalStick()
    }

    private func clamp(_ raw: CGSize) -> CGSize {
        let mag = hypot(raw.width, raw.height)
        guard mag > travel, mag > 0 else { return raw }
        return CGSize(width: raw.width / mag * travel, height: raw.height / mag * travel)
    }
}
