import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// The prototype stays in the gimbal popup so motion can be tuned against live picture.
struct LiveCinematicTrackingControls: View {
    @Environment(AppModel.self) private var model
    var canInteract: Bool
    @State private var advanced = false

    var body: some View {
        @Bindable var tracker = model.session.cinematicTracking
        VStack(alignment: .leading, spacing: 16) {
            VStack(alignment: .leading, spacing: 5) {
                Text("Cinematic Tracking").font(MonitorTheme.font(13, weight: .semibold))
                Text("Experimental · Runs on this phone")
                    .font(MonitorTheme.font(10)).foregroundStyle(MonitorTheme.muted)
                Text(tracker.message)
                    .font(MonitorTheme.font(11)).foregroundStyle(MonitorTheme.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            HStack(spacing: 8) {
                Button(tracker.isEngaged ? "Select again" : "Select subject") {
                    guard canInteract else { return }
                    model.headTrackingEnabled = false
                    tracker.select()
                    if tracker.state == .selecting { model.liveGimbalPanel = .none }
                }
                .accessibilityIdentifier("cinematicTracking.select")
                .disabled(!canInteract || !model.session.canStartCinematicTracking)
                Spacer(minLength: 0)
                if tracker.isEngaged {
                    Button("Stop") { tracker.stop() }
                        .accessibilityIdentifier("cinematicTracking.stop")
                }
            }
            .buttonStyle(.bordered)
            .tint(MonitorTheme.accent)

            VStack(alignment: .leading, spacing: 8) {
                Text("STARTING POINT").font(MonitorTheme.font(9, weight: .semibold))
                    .foregroundStyle(MonitorTheme.muted)
                HStack(spacing: 6) {
                    ForEach(CinematicTrackingSettings.Preset.allCases, id: \.self) { preset in
                        Button(preset.rawValue) {
                            guard canInteract else { return }
                            let x = tracker.settings.framingX
                            let y = tracker.settings.framingY
                            tracker.settings = .preset(preset)
                            tracker.settings.framingX = x
                            tracker.settings.framingY = y
                        }
                        .font(MonitorTheme.font(10))
                        .buttonStyle(.bordered)
                    }
                }
            }

            slider(
                "Sensitivity", value: $tracker.settings.sensitivity, range: 0.1...3,
                readout: String(format: "%.1f×", tracker.settings.sensitivity),
                help: "How strongly the camera follows a subject outside the quiet zone.")
            slider(
                "Smoothness", value: $tracker.settings.smoothness, range: 0...1,
                readout: percent(tracker.settings.smoothness),
                help: "Higher values give starts and direction changes a longer, softer ease.")
            slider(
                "Dead band", value: $tracker.settings.deadBand, range: 0...0.3,
                readout: "±\(percent(tracker.settings.deadBand))",
                help: "Small movements inside this area do not ask the camera to follow.")
            slider(
                "Lerp", value: $tracker.settings.lerp, range: 0...1.5,
                readout: tracker.settings.lerp < 0.005
                    ? "Off" : String(format: "%.2f s", tracker.settings.lerp),
                help:
                    "Time to blend halfway toward a new follow speed. More adds a subtle trailing feel."
            )
            slider(
                "Maximum speed", value: $tracker.settings.maxSpeed, range: 1...90,
                readout: String(format: "%.0f°/s", tracker.settings.maxSpeed),
                help: "Limits how quickly the camera is asked to pan or tilt.")

            VStack(alignment: .leading, spacing: 8) {
                Text("FRAMING").font(MonitorTheme.font(9, weight: .semibold))
                    .foregroundStyle(MonitorTheme.muted)
                HStack(spacing: 6) {
                    framingButton("Left third", x: 1.0 / 3)
                    framingButton("Center", x: 0.5)
                    framingButton("Right third", x: 2.0 / 3)
                }
                Toggle("Keep composition when selecting", isOn: $tracker.keepComposition)
                    .font(MonitorTheme.font(11))
                slider(
                    "Vertical framing", value: $tracker.settings.framingY, range: 0.1...0.9,
                    readout: percent(tracker.settings.framingY),
                    help: "Subject position measured from the top of the picture.")
                HStack {
                    Toggle("Pan", isOn: $tracker.settings.panEnabled)
                    Toggle("Tilt", isOn: $tracker.settings.tiltEnabled)
                }.font(MonitorTheme.font(11))
                Toggle("Show framing guides", isOn: $tracker.showGuides)
                    .font(MonitorTheme.font(11))
            }

            DisclosureGroup("Fine tuning", isExpanded: $advanced) {
                VStack(spacing: 16) {
                    slider(
                        "Acceleration", value: $tracker.settings.maxAcceleration, range: 5...180,
                        readout: String(format: "%.0f°/s²", tracker.settings.maxAcceleration),
                        help: "How quickly follow speed can change.")
                    slider(
                        "Jerk limit", value: $tracker.settings.maxJerk, range: 10...900,
                        readout: String(format: "%.0f°/s³", tracker.settings.maxJerk),
                        help:
                            "Lower values soften changes in acceleration. Very low values add lag.")
                    slider(
                        "Minimum confidence", value: $tracker.settings.confidence,
                        range: 0.3...0.95,
                        readout: percent(tracker.settings.confidence),
                        help: "Stop when the tracker is less certain. Higher values stop sooner.")
                    Text(
                        "Confidence \(percent(tracker.confidence)) · Analysis \(Int(tracker.inferenceMilliseconds)) ms"
                    )
                    .font(MonitorTheme.font(10)).foregroundStyle(MonitorTheme.muted)
                }.padding(.top, 12)
            }
            .font(MonitorTheme.font(11))

            Text(
                "Manual gimbal control stops tracking. If the subject is lost, select it again. Settings last for this session."
            )
            .font(MonitorTheme.font(10)).foregroundStyle(MonitorTheme.muted)
            .fixedSize(horizontal: false, vertical: true)
        }
        .foregroundStyle(MonitorTheme.text)
        .tint(MonitorTheme.accent)
        .disabled(!canInteract)
    }

    private func framingButton(_ title: String, x: Double) -> some View {
        Button(title) {
            guard canInteract else { return }
            let tracker = model.session.cinematicTracking
            tracker.keepComposition = false
            tracker.settings.framingX = model.livePictureViewFlip ? 1 - x : x
        }
        .font(MonitorTheme.font(10)).buttonStyle(.bordered)
    }

    private func percent(_ value: Double) -> String { "\(Int((value * 100).rounded()))%" }

    private func slider(
        _ title: String, value: Binding<Double>, range: ClosedRange<Double>, readout: String,
        help: String
    ) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(title)
                Spacer()
                Text(readout).monospacedDigit().foregroundStyle(MonitorTheme.accent)
            }.font(MonitorTheme.font(11, weight: .medium))
            Slider(value: value, in: range)
                .accessibilityIdentifier("cinematicTracking.slider.\(title)")
                .accessibilityLabel(title)
                .accessibilityValue(readout)
                .accessibilityHint(help)
            Text(help).font(MonitorTheme.font(9)).foregroundStyle(MonitorTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Independent observed leaf: tracker readouts are published at the 5 Hz HUD budget.
struct LiveCinematicTrackingOverlay: View {
    @Environment(AppModel.self) private var model
    var feed: CGRect

    var body: some View {
        let tracker = model.session.cinematicTracking
        if tracker.state != .idle {
            ZStack(alignment: .top) {
                if tracker.isEngaged, tracker.showGuides {
                    let settings = tracker.settings
                    let x = model.livePictureViewFlip ? 1 - settings.framingX : settings.framingX
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(
                            MonitorTheme.accent.opacity(0.55),
                            style: StrokeStyle(lineWidth: 1, dash: [5, 5])
                        )
                        .frame(
                            width: max(4, feed.width * settings.deadBand * 2),
                            height: max(4, feed.height * settings.deadBand * 2)
                        )
                        .position(x: feed.width * x, y: feed.height * settings.framingY)
                        .allowsHitTesting(false)
                }
                if let box = tracker.box {
                    let x = model.livePictureViewFlip ? 1 - box.centerX : box.centerX
                    LiveTrackingChrome.bracketPath(
                        in: CGSize(width: feed.width * box.width, height: feed.height * box.height)
                    )
                    .stroke(MonitorTheme.accent, lineWidth: 2)
                    .frame(width: feed.width * box.width, height: feed.height * box.height)
                    .position(x: feed.width * x, y: feed.height * box.centerY)
                    .allowsHitTesting(false)
                }
                HStack(spacing: 10) {
                    Text(tracker.message)
                        .font(MonitorTheme.font(10, weight: .medium))
                        .fixedSize(horizontal: false, vertical: true)
                    Button(tracker.isEngaged ? "Stop" : "Dismiss") { tracker.stop() }
                        .font(MonitorTheme.font(11, weight: .semibold))
                        .frame(minWidth: 44, minHeight: 44)
                        .accessibilityIdentifier("cinematicTracking.liveStop")
                }
                .foregroundStyle(.white)
                .padding(.horizontal, 12)
                .background(.black.opacity(0.8), in: RoundedRectangle(cornerRadius: 12))
                .frame(maxWidth: min(360, max(80, feed.width - 24)))
                .padding(.top, 46)
            }
            .frame(width: feed.width, height: feed.height)
            .position(x: feed.midX, y: feed.midY)
        }
    }
}
