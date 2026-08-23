import OpenPocketViewCore
import SwiftUI

enum LiveTopMenu: Equatable {
    case recFormat
    case color
}

struct LiveTopPickerFramesKey: PreferenceKey {
    static var defaultValue: [LiveTopMenu: CGRect] = [:]
    static func reduce(value: inout [LiveTopMenu: CGRect], nextValue: () -> [LiveTopMenu: CGRect]) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// OpenZCine `topPickerBody`: 340-wide card, centred on the cell, 8 pt under `cell.maxY`.
enum LiveTopPickerPlacement {
    static func leadingX(
        cellMidX: CGFloat,
        width: CGFloat,
        viewportWidth: CGFloat,
        safeArea: EdgeInsets = EdgeInsets()
    ) -> CGFloat {
        LivePopupPlacement.topPicker(
            cell: CGRect(x: cellMidX - 1, y: 0, width: 2, height: 2),
            panelHeight: 80,
            viewport: CGSize(width: viewportWidth, height: 400),
            safeArea: safeArea,
            preferredWidth: width
        ).x
    }

    static func topY(
        cellMaxY: CGFloat,
        panelHeight: CGFloat,
        viewportHeight: CGFloat,
        safeArea: EdgeInsets = EdgeInsets(),
        floorY: CGFloat? = nil
    ) -> CGFloat {
        LivePopupPlacement.topPicker(
            cell: CGRect(x: 0, y: cellMaxY - 2, width: 2, height: 2),
            panelHeight: panelHeight,
            viewport: CGSize(width: 400, height: viewportHeight),
            safeArea: safeArea,
            floorY: floorY
        ).y
    }
}

/// OpenZCine `TimecodeReadout`: last field in accent. Osmo has no frames, so seconds tick Sky Blue.
private struct LiveTimecodeLabel: View {
    let clock: String

    var body: some View {
        let head: String
        let seconds: String
        if let colon = clock.lastIndex(of: ":") {
            head = String(clock[...colon])
            seconds = String(clock[clock.index(after: colon)...])
        } else {
            head = clock
            seconds = ""
        }
        return
            (Text("TC \(head)").foregroundStyle(LiveDesign.text)
            + Text(seconds).foregroundStyle(LiveDesign.accent))
            .font(.system(size: 20, weight: .medium, design: .monospaced))
            .lineLimit(1)
            .fixedSize(horizontal: true, vertical: false)
            .layoutPriority(1)
            .accessibilityLabel("Timecode \(clock)")
    }
}

/// OpenZCine `FPSChip` (`MonitorControls.swift`). Bars are transport health
/// (`CameraSession.liveSignalBars`), not SoftAP RSSI.
struct FPSChip: View {
    let fps: String
    /// Live link quality (0–4 bars) from `CameraSession.liveSignalBars` — frame-delivery
    /// health, not radio RSSI (which iOS apps can't read without special entitlements).
    let signalBars: Int

    private var signalTint: Color {
        switch signalBars {
        case 3...: LiveDesign.good
        case 2: LiveDesign.accent
        case 1: LiveDesign.rec
        default: LiveDesign.faint
        }
    }

    var body: some View {
        HStack(spacing: 6) {
            OpcIcon.signal
                .foregroundStyle(signalTint)
                .frame(width: 14, height: 14)
                .opacity(max(0.35, Double(signalBars) / 4.0))
            Text("FPS")
                .font(.system(size: 8, weight: .bold, design: .monospaced))
                .foregroundStyle(LiveDesign.faint)
                .lineLimit(1)
            // `frameRate.formatted` is two decimals (e.g. "25.00") — without a hard
            // single-line policy the monospaced value wraps under deck squeeze as
            // "25.0" / "0". Never allow multi-line in the top bar.
            Text(fps)
                .font(.system(size: 12, weight: .medium, design: .monospaced))
                .foregroundStyle(LiveDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 11)
        .padding(.vertical, 7)
        .liveChromeCapsule()
        .accessibilityLabel("Live view \(fps) frames per second, \(signalBars) of 4 signal bars")
    }
}

/// OpenZCine `MonitorInfoBar.InfoPillContent` (`MonitorUnified.swift` ~25) with Pocket cells:
/// Timecode | Rec (res+fps) | Color | Storage | FPS + signal bars.
struct LiveTopChrome: View {
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Binding var menu: LiveTopMenu?
    @State private var showStorageDuration = false

    var body: some View {
        GlassDeck {
            HStack(spacing: 10) {
                cell(.recReadout) { recordChip }
                cell(.timecode) { LiveTimecodeCell() }
                cell(.format) { recFormatButton }
                cell(.color) { colorButton }
                cell(.storage) { storageCell }
                cell(.fps) { LiveFPSChip() }
            }
        }
        .fixedSize(horizontal: false, vertical: true)
        .onChange(of: model.assist.clean) { _, clean in
            if clean { menu = nil }
        }
    }

    @ViewBuilder
    private func cell<Content: View>(
        _ section: PocketDispChrome.Section,
        @ViewBuilder content: () -> Content
    ) -> some View {
        if model.chromeSectionMounts(section) {
            content()
                .chromeEditable(section, editing: model.chromeEditorMode)
        }
    }

    // MARK: - Cells (OpenZCine `RecordChip` / `TimecodeReadout` / `inlineReadout` / `FPSChip`)

    private var recordChip: some View {
        let rec = model.session.status.isRecording
        return HStack(spacing: 7) {
            Circle()
                .fill(rec ? LiveDesign.rec : LiveDesign.faint)
                .frame(width: 9, height: 9)
            Text(rec ? "REC" : "STBY")
                .font(LiveType.ui(size: 11, weight: .bold, design: .default))
                .foregroundStyle(rec ? LiveDesign.text : LiveDesign.muted)
                .lineLimit(1)
                .minimumScaleFactor(0.75)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .liveChromeCapsule()
        .accessibilityLabel(rec ? "Recording" : "Standby")
    }

    private var recFormatButton: some View {
        let active = menu == .recFormat
        return Button {
            guard !interfaceLocked else { return }
            menu = active ? nil : .recFormat
        } label: {
            inlineReadout(icon: .video, value: recFormatLabel, isActive: active)
        }
        .buttonStyle(.zcTapTarget)
        .geometryGroup()
        .background(pickerAnchor(.recFormat))
        .accessibilityLabel("Recording format")
        .accessibilityValue(recFormatLabel)
    }

    private var colorButton: some View {
        let active = menu == .color
        return Button {
            guard !interfaceLocked else { return }
            menu = active ? nil : .color
        } label: {
            inlineReadout(icon: .contrast, value: colorLabel, isActive: active)
        }
        .buttonStyle(.zcTapTarget)
        .geometryGroup()
        .background(pickerAnchor(.color))
        .accessibilityLabel("Color mode")
        .accessibilityValue(colorLabel)
    }

    private var storageCell: some View {
        Button {
            showStorageDuration.toggle()
        } label: {
            inlineReadout(icon: .folder, value: storageLabel)
                .contentShape(Rectangle())
        }
        .buttonStyle(.zcTapTarget)
        .geometryGroup()
        .accessibilityLabel("Storage remaining")
        .accessibilityValue(storageLabel)
    }

    private func pickerAnchor(_ item: LiveTopMenu) -> some View {
        GeometryReader { proxy in
            Color.clear.preference(
                key: LiveTopPickerFramesKey.self,
                value: [item: proxy.frame(in: .named(LiveCanvasSpace.name))]
            )
        }
    }
}

private struct LiveTimecodeCell: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        LiveTimecodeLabel(clock: model.session.status.timecodeClock)
    }
}

/// Hold a numeric FPS string until it moves by `step` so hundredths do not
/// tick the chip. Non-numeric labels (LINK / FAIL / RECOV / —) always win.
enum LiveChromeReadout {
    static func holdFPS(_ incoming: String, displayed: String, step: Double = 0.4) -> String {
        guard let next = Double(incoming), let current = Double(displayed) else {
            return incoming
        }
        return abs(next - current) >= step ? incoming : displayed
    }
}

private struct LiveFPSChip: View {
    @Environment(AppModel.self) private var model
    @State private var heldFPS = "—"

    var body: some View {
        FPSChip(fps: heldFPS, signalBars: model.session.liveSignalBars)
            .onAppear { heldFPS = model.session.liveFPS }
            .onChange(of: model.session.liveFPS) { _, next in
                heldFPS = LiveChromeReadout.holdFPS(next, displayed: heldFPS)
            }
    }
}

/// OpenZCine `MonitorOverlayHost.topPickerBody`: backdrop tap, slide-down from above the cell.
struct LiveTopPickerHost: View {
    @Binding var menu: LiveTopMenu?
    var frames: [LiveTopMenu: CGRect]
    var viewport: CGSize
    var topDeck: CGRect
    var safeArea: EdgeInsets = EdgeInsets()
    var floorY: CGFloat? = nil

    @State private var revealed = false
    @State private var panelHeight: CGFloat = 280

    private static let revealCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.20)

    var body: some View {
        let cell =
            frames[menu ?? .recFormat]
            ?? CGRect(x: topDeck.midX - 40, y: topDeck.minY, width: 80, height: topDeck.height)
        let place = LivePopupPlacement.topPicker(
            cell: cell,
            panelHeight: panelHeight,
            viewport: viewport,
            safeArea: safeArea,
            floorY: floorY
        )
        let slide = place.y + panelHeight + 40

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .named(LiveCanvasSpace.name)) { location in
                    handleBackdrop(at: location)
                }

            CapturePickerPanel(
                sheet: menu == .color ? .color : .resolution,
                showsGrabber: false
            ) {
                menu = nil
            }
            .id(menu)
            .transition(.opacity)
            .frame(width: place.width)
            .background(panelHeightReader)
            .opacity(revealed ? 1 : 0)
            .offset(x: place.x, y: place.y + (revealed ? 0 : -slide))
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .onAppear { scheduleReveal() }
    }

    private var panelHeightReader: some View {
        GeometryReader { proxy in
            Color.clear
                .onAppear { panelHeight = proxy.size.height }
                .onChange(of: proxy.size.height) { _, height in
                    panelHeight = height
                }
        }
    }

    private func scheduleReveal() {
        DispatchQueue.main.async {
            withAnimation(Self.revealCurve) { revealed = true }
        }
    }

    private func handleBackdrop(at location: CGPoint) {
        if let hit = frames.first(where: { $0.value.insetBy(dx: -10, dy: -8).contains(location) }) {
            if hit.key == menu {
                menu = nil
            } else {
                withAnimation(.easeInOut(duration: 0.14)) { menu = hit.key }
            }
            return
        }
        menu = nil
    }
}

/// HEAD `LiveViewScreen` still publishes midX through this key until that file is committed.
struct LiveTopPickerAnchorKey: PreferenceKey {
    static var defaultValue: CGFloat?
    static func reduce(value: inout CGFloat?, nextValue: () -> CGFloat?) {
        value = nextValue() ?? value
    }
}

/// Drum card without the host chrome — used if `LiveViewScreen` still mounts the old overlay.
struct LiveTopPickerCard: View {
    @Binding var menu: LiveTopMenu?

    var body: some View {
        CapturePickerPanel(
            sheet: menu == .color ? .color : .resolution,
            showsGrabber: false
        ) {
            menu = nil
        }
    }
}

extension LiveTopChrome {
    // MARK: - Values

    private var recFormatLabel: String {
        let s = model.session.status
        if let format = s.videoFormat {
            return format.chipLabel
        }
        let fpsText = s.fps > 0 ? "\(s.fps)p" : "—"
        if let res = s.videoResolution {
            return "\(res.label) · \(fpsText)"
        }
        return "— · \(fpsText)"
    }

    private var colorLabel: String {
        model.session.status.colorMode?.label ?? "—"
    }

    private var storageLabel: String {
        let s = model.session.status
        if showStorageDuration {
            if s.recordRemainingSec > 0 {
                return "\(s.recordRemainingSec / 60) Min"
            }
            return "— Min"
        }
        let free = s.storageFreeMb > 0 ? s.storageFreeMb : s.sdFreeMb
        let total = s.storageTotalMb > 0 ? s.storageTotalMb : s.sdTotalMb
        if total > 0 {
            let gb = max(0, free) / 1024
            let pct = Int((Double(max(0, free)) / Double(total) * 100).rounded())
            return "\(gb) GB · \(pct)%"
        }
        if free > 0 {
            return "\(free / 1024) GB"
        }
        return "—"
    }

    private func inlineReadout(icon: OpcIcon, value: String, isActive: Bool = false) -> some View {
        let content = HStack(spacing: 6) {
            icon
                .frame(width: 12, height: 12)
                .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.muted)
            Text(value.replacingOccurrences(of: " · ", with: "·"))
                .font(.system(size: 15, weight: .medium, design: .monospaced))
                .foregroundStyle(isActive ? LiveDesign.accent : LiveDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .fixedSize(horizontal: true, vertical: false)
        }
        .fixedSize(horizontal: true, vertical: false)
        .padding(.horizontal, 10)
        .padding(.vertical, 6)

        return Group {
            if isActive {
                content
                    .background(Capsule().fill(LiveDesign.accentDim))
                    .overlay(Capsule().strokeBorder(LiveDesign.accentDim, lineWidth: 1))
            } else {
                content.liveChromeCapsule()
            }
        }
    }
}

/// OpenZCine `GlassPanel` (`MonitorControls.swift` ~1420) with the info-pill insets.
private struct GlassDeck<Content: View>: View {
    @ViewBuilder var content: Content

    var body: some View {
        content
            .padding(EdgeInsets(top: 6, leading: 12, bottom: 6, trailing: 12))
            .liveChromeGlass(
                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
            )
    }
}
