import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Presentation of the existing camera/clip level and peak measurements.
enum AudioAssist {
    static let longPressPanelWidth: CGFloat = 400
    static let panelSize = CGSize(width: 84, height: 184)
    static let helpCopy = "Meters the camera's audio. Available while live view is up."
    static let playbackHelpCopy = "Meters the playing clip."

    static func displayedSensitivity(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed.uppercased()
    }

    static func longPressMenu(assist _: LiveAssistState, compact: Bool = false)
        -> AudioLongPressMenu
    {
        AudioLongPressMenu(compact: compact)
    }

    static func longPressMenu(compact: Bool = false) -> AudioLongPressMenu {
        AudioLongPressMenu(compact: compact)
    }

    static func meter(levels: AudioMeterLevels, sensitivity: String?) -> AudioMetersPanelMini {
        AudioMetersPanelMini(levels: levels, sensitivity: sensitivity)
    }
}

struct AudioLongPressMenu: View {
    @Environment(AppModel.self) private var model
    @Bindable private var store = AudioAssist.store
    var compact = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            Text("Orientation").font(MonitorTheme.font(11, weight: .semibold))
            MonitorSegmentedControl(
                options: AudioAssist.Orientation.allCases,
                selection: Binding(
                    get: { store.options.orientation },
                    set: {
                        store.options.orientation = $0
                        store.persist()
                    }),
                stacked: true, title: { $0.rawValue },
                onSelectionFeedback: {
                    OperatorSettingsHaptics.selection(enabled: model.hapticsEnabled)
                }
            )
            .buttonStyle(MonitorButtonStyle())
            Toggle(
                "Show dB values",
                isOn: Binding(
                    get: { store.options.showsDB },
                    set: {
                        store.options.showsDB = $0
                        store.persist()
                    })
            )
            .font(MonitorTheme.font(12)).tint(MonitorTheme.accent)
            Text(model.assist.gradesClip ? AudioAssist.playbackHelpCopy : AudioAssist.helpCopy)
                .font(MonitorTheme.font(compact ? 11 : 12))
                .foregroundStyle(MonitorTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

/// Draw-only body; movement and options gestures belong to AudioMeterOverlay.
struct AudioMetersPanelMini: View {
    let levels: AudioMeterLevels
    let sensitivity: String?
    var orientation: AudioAssist.Orientation = .vertical
    var showsDB = false

    var body: some View {
        VStack(spacing: 7) {
            HStack {
                Text("AUDIO").font(MonitorTheme.font(9, weight: .semibold))
                if orientation == .horizontal { Spacer(minLength: 0) }
                if showsDB { Text("dBFS").font(MonitorTheme.font(8)) }
            }
            .foregroundStyle(MonitorTheme.muted)
            if orientation == .vertical {
                HStack(spacing: 10) {
                    verticalChannel("L", levels.left)
                    verticalChannel("R", levels.right)
                }
            } else {
                VStack(spacing: 9) {
                    horizontalChannel("L", levels.left)
                    horizontalChannel("R", levels.right)
                }
            }
        }
        .padding(10)
        .frame(
            width: AudioAssist.panelSize(orientation: orientation).width,
            height: AudioAssist.panelSize(orientation: orientation).height
        )
        .monitorGlass(in: RoundedRectangle(cornerRadius: 12), density: .compact)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio Levels")
        .accessibilityValue(
            "Left \(AudioAssist.dbText(levels.left.levelDB)) dBFS, right \(AudioAssist.dbText(levels.right.levelDB)) dBFS, sensitivity \(AudioAssist.displayedSensitivity(sensitivity))"
        )
    }

    private func verticalChannel(_ name: String, _ channel: AudioMeterChannel) -> some View {
        VStack(spacing: 4) {
            Self.meter(channel, orientation: orientation).frame(
                maxWidth: .infinity, maxHeight: .infinity)
            HStack(spacing: 3) {
                Text(name)
                if showsDB { Text(AudioAssist.dbText(channel.levelDB)).monospacedDigit() }
            }
            .font(MonitorTheme.font(9, weight: .medium)).foregroundStyle(MonitorTheme.secondary)
            .lineLimit(1).minimumScaleFactor(0.8)
        }
    }

    private func horizontalChannel(_ name: String, _ channel: AudioMeterChannel) -> some View {
        HStack(spacing: 7) {
            Text(name).font(MonitorTheme.font(9, weight: .medium))
                .foregroundStyle(MonitorTheme.secondary)
            Self.meter(channel, orientation: orientation).frame(maxWidth: .infinity).frame(
                height: 12)
            if showsDB {
                Text(AudioAssist.dbText(channel.levelDB))
                    .font(MonitorTheme.font(10, weight: .medium)).monospacedDigit()
                    .foregroundStyle(MonitorTheme.secondary).frame(width: 27, alignment: .trailing)
            }
        }
    }

    private nonisolated static func meter(
        _ channel: AudioMeterChannel, orientation: AudioAssist.Orientation
    ) -> some View {
        Canvas { context, size in
            let rect = CGRect(origin: .zero, size: size)
            context.fill(
                Path(roundedRect: rect, cornerRadius: 2), with: .color(.white.opacity(0.08)))
            let level = AudioAssist.levelFraction(channel.levelDB)
            let bands: [(Double, Double, Color)] = [
                (AudioMeterBallistics.floorDB, -18, Color(red: 0.34, green: 0.92, blue: 0.52)),
                (-18, -6, Color(red: 0.96, green: 0.82, blue: 0.32)),
                (-6, 0, Color(red: 1, green: 0.36, blue: 0.32)),
            ]
            for (low, high, color) in bands {
                let start = AudioAssist.levelFraction(low)
                let end = min(level, AudioAssist.levelFraction(high))
                guard end > start else { continue }
                let band =
                    orientation == .vertical
                    ? CGRect(
                        x: 0, y: (1 - end) * size.height, width: size.width,
                        height: (end - start) * size.height)
                    : CGRect(
                        x: start * size.width, y: 0, width: (end - start) * size.width,
                        height: size.height)
                context.fill(Path(band), with: .color(color))
            }
            let peak = AudioAssist.levelFraction(channel.peakDB)
            if peak > 0 {
                let tick =
                    orientation == .vertical
                    ? CGRect(
                        x: 0, y: max(0, (1 - peak) * size.height - 1), width: size.width, height: 2)
                    : CGRect(
                        x: min(size.width - 2, peak * size.width), y: 0, width: 2,
                        height: size.height)
                context.fill(Path(tick), with: .color(.white.opacity(0.9)))
            }
        }
    }
}
