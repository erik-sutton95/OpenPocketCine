import OpenPocketViewCore
import SwiftUI

/// OpenZCine `AudioMetersPanelMini` + tap-only AUDIO assist.
///
/// Live source is Pocket `cam_audio_status_v2` (decoded onto `CameraStatus.audioMeters`).
/// OpenZCine live reads the Nikon LiveViewObject header instead; both feed the same
/// green→yellow→red stereo bars with a camera-held peak tick. There is no operator
/// menu: `MonitorAssistTool.hasConfiguration` is false — no channel picker, no local
/// peak-hold toggle. Peak hold is the body's.
enum AudioAssist {
    /// Popup width OpenZCine uses for tap-only tools (`assistPanelWidth` — 400).
    static let longPressPanelWidth: CGFloat = 400
    static let panelSize = CGSize(width: 28, height: 168)

    /// OpenZCine live copy. Playback uses `playbackHelpCopy`.
    static let helpCopy = "Meters the camera's audio. Available while live view is up."
    static let playbackHelpCopy = "Meters the playing clip."

    static func displayedSensitivity(_ value: String?) -> String {
        let trimmed = value?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        return trimmed.isEmpty ? "—" : trimmed.uppercased()
    }

    /// OpenZCine `AssistPanel` `.audioMeters` — help copy only.
    static func longPressMenu(
        assist _: LiveAssistState,
        compact: Bool = false
    ) -> AudioLongPressMenu {
        AudioLongPressMenu(compact: compact)
    }

    static func longPressMenu(compact: Bool = false) -> AudioLongPressMenu {
        AudioLongPressMenu(compact: compact)
    }

    static func meter(
        levels: AudioMeterLevels,
        sensitivity: String?
    ) -> AudioMetersPanelMini {
        AudioMetersPanelMini(levels: levels, sensitivity: sensitivity)
    }
}

/// OpenZCine `AssistPanel` AUDIO copy: 13pt muted. Android `OptionCopy` is 11pt.
struct AudioLongPressMenu: View {
    var compact: Bool = false

    var body: some View {
        Text(AudioAssist.helpCopy)
            .font(LiveType.ui(size: compact ? 11 : 13))
            .foregroundStyle(LiveDesign.muted)
            .frame(maxWidth: .infinity, alignment: .leading)
    }
}

/// OpenZCine `AudioMetersPanelMini` — 28×168, zones at −18 / −6 dBFS, peak-hold tick, SENS.
struct AudioMetersPanelMini: View {
    let levels: AudioMeterLevels
    let sensitivity: String?

    private static let yellowFromDB = -18.0
    private static let redFromDB = -6.0
    private static let guideMarks: [Double] = [0, -6, -18, -36]

    var body: some View {
        VStack(spacing: 2) {
            Text("AUDIO")
                .font(.system(size: 6, weight: .bold, design: .monospaced))
                .foregroundStyle(LiveDesign.text.opacity(0.58))
            Canvas { context, size in
                drawMeters(in: context, size: size)
            }
            VStack(spacing: 0) {
                Text("SENS")
                    .font(.system(size: 5, weight: .semibold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.42))
                Text(AudioAssist.displayedSensitivity(sensitivity))
                    .font(.system(size: 8, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.72))
                    .lineLimit(1)
                    .minimumScaleFactor(0.65)
            }
            .frame(maxWidth: .infinity)
        }
        .padding(.horizontal, 3)
        .padding(.vertical, 7)
        .frame(width: AudioAssist.panelSize.width, height: AudioAssist.panelSize.height)
        .background(Color(red: 0.025, green: 0.036, blue: 0.03).opacity(0.72))
        .clipShape(RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 12)
        .allowsHitTesting(false)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Audio Levels")
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        func channel(_ name: String, _ ch: AudioMeterChannel) -> String {
            ch.levelDB <= AudioMeterBallistics.floorDB + 0.5
                ? "\(name) silent"
                : String(format: "%@ %.0f dB, peak %.0f", name, ch.levelDB, ch.peakDB)
        }
        return
            "\(channel("left", levels.left)), \(channel("right", levels.right)), sensitivity \(AudioAssist.displayedSensitivity(sensitivity))"
    }

    private func zoneColor(_ db: Double) -> Color {
        if db >= Self.redFromDB {
            return Color(red: 1, green: 92 / 255, blue: 82 / 255).opacity(0.95)
        }
        if db >= Self.yellowFromDB {
            return Color(red: 245 / 255, green: 208 / 255, blue: 82 / 255).opacity(0.95)
        }
        return Color(red: 86 / 255, green: 235 / 255, blue: 132 / 255).opacity(0.9)
    }

    private func drawMeters(in context: GraphicsContext, size: CGSize) {
        let floor = AudioMeterBallistics.floorDB
        let labelReserve: CGFloat = 10
        let barsRect = CGRect(x: 0, y: 2, width: size.width, height: size.height - labelReserve - 2)
        func y(_ db: Double) -> CGFloat {
            let fraction = max(0, min(1, (db - floor) / -floor))
            return barsRect.maxY - CGFloat(fraction) * barsRect.height
        }

        for mark in Self.guideMarks {
            let tickY = y(mark)
            var line = Path()
            line.move(to: CGPoint(x: barsRect.minX, y: tickY))
            line.addLine(to: CGPoint(x: barsRect.maxX, y: tickY))
            context.stroke(
                line,
                with: .color(
                    Color(red: 220 / 255, green: 235 / 255, blue: 225 / 255).opacity(0.10)),
                lineWidth: 1)
        }

        let gap: CGFloat = 2
        let inset: CGFloat = 1
        let barWidth = (barsRect.width - gap - inset * 2) / 2
        for (index, pair) in [("L", levels.left), ("R", levels.right)].enumerated() {
            let x = barsRect.minX + inset + CGFloat(index) * (barWidth + gap)
            let track = CGRect(x: x, y: barsRect.minY, width: barWidth, height: barsRect.height)
            context.fill(
                Path(roundedRect: track, cornerRadius: 2),
                with: .color(LiveDesign.text.opacity(0.08)))

            let levelY = y(pair.1.levelDB)
            if levelY < track.maxY - 0.5 {
                var zones = context
                zones.clip(
                    to: Path(
                        roundedRect: CGRect(
                            x: track.minX, y: levelY, width: track.width,
                            height: track.maxY - levelY),
                        cornerRadius: 2))
                let bands: [(from: Double, to: Double)] = [
                    (floor, Self.yellowFromDB), (Self.yellowFromDB, Self.redFromDB),
                    (Self.redFromDB, 0),
                ]
                for band in bands {
                    let top = y(band.to)
                    let bottom = y(band.from)
                    zones.fill(
                        Path(
                            CGRect(x: track.minX, y: top, width: track.width, height: bottom - top)),
                        with: .color(zoneColor(band.from)))
                }
            }

            if pair.1.peakDB > floor + 0.5 {
                let peakY = y(pair.1.peakDB)
                var tick = Path()
                tick.move(to: CGPoint(x: track.minX, y: peakY))
                tick.addLine(to: CGPoint(x: track.maxX, y: peakY))
                context.stroke(tick, with: .color(zoneColor(pair.1.peakDB)), lineWidth: 1.5)
            }

            context.draw(
                Text(pair.0)
                    .font(.system(size: 7.5, weight: .bold, design: .monospaced))
                    .foregroundStyle(LiveDesign.text.opacity(0.58)),
                at: CGPoint(x: track.midX, y: size.height - labelReserve / 2))
        }
    }
}
