import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// On-feed analog stick. Streams `0x04/0x01` while held, center on lift.
/// Resting ink is white on a dark picture and black on a bright one; a held
/// stick uses the accent.
struct LiveGimbalStick: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Environment(\.monitorHDRChromeGain) private var hdrGain
    var enabled: Bool
    /// Stick and picture in the same coordinate space, for the luma sample.
    var frame: CGRect
    var feed: CGRect
    @State private var darkInk = false
    @State private var knobOffset: CGSize = .zero
    @State private var dragging = false
    @State private var contact = false
    @State private var taps = GimbalStick.TapSequence()
    @State private var pendingDouble: Task<Void, Never>?
    @State private var pressTick = 0
    @State private var recenterTick = 0
    @State private var flipTick = 0

    // The layout sizes the stick (operator Small / Medium / Large); the knob scales with it.
    private var size: CGFloat { frame.width > 1 ? frame.width : LiveChromeMetrics.gimbalStickSize }
    private var knob: CGFloat {
        size * LiveChromeMetrics.gimbalKnobSize / LiveChromeMetrics.gimbalStickSize
    }
    private var opacity: CGFloat { contact ? 0.8 : LiveChromeMetrics.gimbalStickOpacity }
    private var interactive: Bool { enabled && !interfaceLocked }
    private var ink: Color {
        contact
            ? LiveDesign.accent
            : darkInk ? Color(white: 0.2) : MonitorTheme.edrText(gain: hdrGain)
    }

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
        .animation(.easeInOut(duration: 0.2), value: darkInk)
        .frame(width: size, height: size)
        // A compositor blend cannot adapt: iOS shows live video on its own
        // display plane. Sample the decoded source under the stick instead.
        // ponytail: 4 Hz loop of 64 CPU reads; MIRROR / 180 flips are not mapped
        // into the sample region (the stick sits near a corner either way).
        .task(id: "\(Int(frame.minX))x\(Int(frame.minY))x\(Int(feed.width))x\(Int(feed.height))") {
            while !Task.isCancelled {
                refreshInk()
                try? await Task.sleep(for: .milliseconds(250))
            }
        }
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
                let mapped = GimbalStick.mapTouch(
                    dx: Double(value.translation.width),
                    dy: Double(value.translation.height),
                    stickSize: Double(size),
                    knobSize: Double(knob),
                    engaged: dragging)
                if mapped.emit {
                    cancelTaps()
                    dragging = true
                    // Per drag sample; AppRoot observes gimbalAnalogHeld.
                    if !model.gimbalScreenHeld { model.gimbalScreenHeld = true }
                    knobOffset = CGSize(width: mapped.visualX, height: mapped.visualY)
                    model.session.updateGimbalStick(
                        x: mapped.commandX, y: mapped.commandY,
                        sensitivity: model.gimbalStickSensitivity,
                        assistMirror: model.assist.mirrorsHorizontally,
                        mapping: model.virtualJoystickMapping)
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
                    model.session.performGimbalDoubleTap()
                }
            }
        case .third:
            pendingDouble?.cancel()
            pendingDouble = nil
            hapticFlip()
            model.session.flipGimbal()
        }
    }

    private func refreshInk() {
        guard !contact else { return }
        guard
            let region = GimbalStick.chromeSampleRegion(
                stick: .init(
                    x: frame.minX, y: frame.minY, width: frame.width, height: frame.height),
                feed: .init(x: feed.minX, y: feed.minY, width: feed.width, height: feed.height))
        else {
            if darkInk { darkInk = false }
            return
        }
        let luma = model.frameSamples.sourcePixelBuffer.flatMap {
            GimbalStickLuma.mean($0, region: region)
        }
        let dark = GimbalStick.prefersDarkChrome(luma: luma, previous: darkInk)
        if dark != darkInk { darkInk = dark }
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
}
