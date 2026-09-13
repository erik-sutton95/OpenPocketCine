import MonitorUI
import OpenPocketViewCore
import SwiftUI

/// Presentation of the existing camera/clip level and peak measurements.
enum AudioAssist {
    static let longPressPanelWidth: CGFloat = 400
    static let panelSize = CGSize(width: 28, height: 168)
    static let barCrossAxis: CGFloat = 10
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

    private static let yellowFromDB = -18.0
    private static let redFromDB = -6.0
    private static let guideMarks: [Double] = [0, -6, -18, -36]
    private static let gap: CGFloat = 2
    private static let inset: CGFloat = 1
    private static let green = Color(red: 86 / 255, green: 235 / 255, blue: 132 / 255).opacity(0.9)
    private static let yellow = Color(red: 245 / 255, green: 208 / 255, blue: 82 / 255).opacity(
        0.95)
    private static let red = Color(red: 1, green: 92 / 255, blue: 82 / 255).opacity(0.95)

    var body: some View {
        let size = AudioAssist.panelSize(orientation: orientation)
        Self.meters(
            left: levels.left, right: levels.right, orientation: orientation, showsDB: showsDB
        )
        .frame(width: size.width, height: size.height)
        .monitorGlass(in: RoundedRectangle(cornerRadius: 10), density: .scope)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio Levels")
        .accessibilityValue(
            "Left \(AudioAssist.dbText(levels.left.levelDB)) dBFS, right \(AudioAssist.dbText(levels.right.levelDB)) dBFS, sensitivity \(AudioAssist.displayedSensitivity(sensitivity))"
        )
    }

    private nonisolated static func meters(
        left: AudioMeterChannel, right: AudioMeterChannel,
        orientation: AudioAssist.Orientation, showsDB: Bool
    ) -> some View {
        Canvas { context, size in
            let vertical = orientation == .vertical
            let labelReserve: CGFloat = vertical ? 10 : 0
            let barsRect =
                vertical
                ? CGRect(x: 0, y: 2, width: size.width, height: size.height - labelReserve - 2)
                : CGRect(
                    x: 9, y: inset, width: size.width - 9 - (showsDB ? 22 : 1),
                    height: size.height - inset * 2)
            func fraction(_ db: Double) -> CGFloat {
                CGFloat(AudioAssist.levelFraction(db))
            }
            func along(_ db: Double) -> CGFloat {
                let t = fraction(db)
                return vertical
                    ? barsRect.maxY - t * barsRect.height : barsRect.minX + t * barsRect.width
            }
            if vertical {
                for mark in guideMarks {
                    let y = along(mark)
                    var line = Path()
                    line.move(to: CGPoint(x: barsRect.minX, y: y))
                    line.addLine(to: CGPoint(x: barsRect.maxX, y: y))
                    context.stroke(
                        line, with: .color(Color.white.opacity(0.10)), lineWidth: 1)
                }
            }
            let barThickness = AudioAssist.barCrossAxis
            let pairSpan = barThickness * 2 + gap
            for (index, pair) in [("L", left), ("R", right)].enumerated() {
                let track: CGRect
                if vertical {
                    let x =
                        barsRect.midX - pairSpan / 2 + CGFloat(index) * (barThickness + gap)
                    track = CGRect(
                        x: x, y: barsRect.minY, width: barThickness, height: barsRect.height)
                } else {
                    let y =
                        barsRect.midY - pairSpan / 2 + CGFloat(index) * (barThickness + gap)
                    track = CGRect(
                        x: barsRect.minX, y: y, width: barsRect.width, height: barThickness)
                }
                context.fill(
                    Path(roundedRect: track, cornerRadius: 2),
                    with: .color(Color.white.opacity(0.08)))
                let level = pair.1.levelDB
                let filled =
                    vertical
                    ? CGRect(
                        x: track.minX, y: along(level), width: track.width,
                        height: max(0, track.maxY - along(level)))
                    : CGRect(
                        x: track.minX, y: track.minY,
                        width: max(0, along(level) - track.minX), height: track.height)
                if filled.height > 0.5 && filled.width > 0.5 {
                    var zones = context
                    zones.clip(to: Path(roundedRect: filled, cornerRadius: 2))
                    let bands: [(Double, Double, Color)] = [
                        (AudioMeterBallistics.floorDB, yellowFromDB, green),
                        (yellowFromDB, redFromDB, yellow),
                        (redFromDB, 0, red),
                    ]
                    for band in bands {
                        let start = along(band.0)
                        let end = along(band.1)
                        let slice =
                            vertical
                            ? CGRect(
                                x: track.minX, y: min(start, end), width: track.width,
                                height: abs(end - start))
                            : CGRect(
                                x: min(start, end), y: track.minY, width: abs(end - start),
                                height: track.height)
                        zones.fill(Path(slice), with: .color(band.2))
                    }
                }
                if pair.1.peakDB > AudioMeterBallistics.floorDB + 0.5 {
                    let peak = along(pair.1.peakDB)
                    var tick = Path()
                    if vertical {
                        tick.move(to: CGPoint(x: track.minX, y: peak))
                        tick.addLine(to: CGPoint(x: track.maxX, y: peak))
                    } else {
                        tick.move(to: CGPoint(x: peak, y: track.minY))
                        tick.addLine(to: CGPoint(x: peak, y: track.maxY))
                    }
                    context.stroke(tick, with: .color(zoneColor(pair.1.peakDB)), lineWidth: 1.5)
                }
                context.draw(
                    Text(pair.0)
                        .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                        .foregroundStyle(Color.white.opacity(0.58)),
                    at: vertical
                        ? CGPoint(x: track.midX, y: size.height - labelReserve / 2)
                        : CGPoint(x: 5, y: track.midY))
                if showsDB {
                    context.draw(
                        Text(AudioAssist.dbText(pair.1.levelDB))
                            .font(.system(size: 6, weight: .medium, design: .monospaced))
                            .foregroundStyle(Color.white.opacity(0.72)),
                        at: vertical
                            ? CGPoint(x: track.midX, y: track.minY + 7)
                            : CGPoint(x: size.width - 11, y: track.midY))
                }
            }
        }
    }

    private nonisolated static func zoneColor(_ db: Double) -> Color {
        if db >= redFromDB { return red }
        if db >= yellowFromDB { return yellow }
        return green
    }
}
