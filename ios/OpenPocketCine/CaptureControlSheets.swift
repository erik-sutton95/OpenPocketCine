import OpenPocketViewCore
import SwiftUI

enum CaptureSheet: String, Identifiable {
    case iso, shutter, wb, focus, exposure, audio
    case mode
    case resolution, color
    var id: String { rawValue }
}

struct LiveCaptureTileFramesKey: PreferenceKey {
    static var defaultValue: [CaptureSheet: CGRect] = [:]
    static func reduce(
        value: inout [CaptureSheet: CGRect],
        nextValue: () -> [CaptureSheet: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// OpenZCine `PanelHost.bottomPickerBody`: backdrop tap, slide-up from below the
/// capture bar, width capped at 420, parked 10pt above the bar and centred on
/// the tile. Card height is the hugged `PickerPanel`, not a shared well.
struct LiveCapturePickerHost: View {
    @Binding var sheet: CaptureSheet?
    var frames: [CaptureSheet: CGRect]
    var bar: CGRect
    var viewport: CGSize
    var safeArea: EdgeInsets = EdgeInsets()
    var ceilingY: CGFloat = 0

    @State private var revealed = false
    @State private var panelHeight: CGFloat = 280

    private static let revealCurve = Animation.timingCurve(0.16, 1, 0.3, 1, duration: 0.20)

    var body: some View {
        let current = sheet ?? .iso
        let place = LivePopupPlacement.capturePicker(
            tile: frames[current] ?? .zero,
            bar: bar,
            panelHeight: panelHeight,
            viewport: viewport,
            safeArea: safeArea,
            ceilingY: ceilingY
        )
        let slide = place.maxHeight + 20

        ZStack(alignment: .topLeading) {
            Color.clear
                .contentShape(Rectangle())
                .onTapGesture(coordinateSpace: .named(LiveCanvasSpace.name)) { location in
                    handleBackdrop(at: location)
                }

            CapturePickerPanel(
                sheet: current,
                showsGrabber: false
            ) {
                sheet = nil
            }
            .id(current)
            .transition(.opacity)
            .frame(width: place.width)
            .background(panelHeightReader)
            // Overflow clip only — height is the hugged glass, never the shared well.
            .frame(
                height: min(max(panelHeight, 1), place.maxHeight),
                alignment: .bottom
            )
            .clipped()
            .opacity(revealed ? 1 : 0)
            .offset(x: place.x, y: place.y + (revealed ? 0 : slide))
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
            if hit.key == sheet {
                sheet = nil
            } else {
                withAnimation(.easeInOut(duration: 0.14)) { sheet = hit.key }
            }
            return
        }
        sheet = nil
    }
}

/// OpenZCine `PickerPanel` chrome: glass card, grabber, heavy header, close, drum or checked rows.
struct CaptureControlSheet: View {
    let sheet: CaptureSheet
    var onClose: (() -> Void)? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        CapturePickerPanel(sheet: sheet) {
            if let onClose {
                onClose()
            } else {
                model.captureSheet = nil
            }
        }
        .padding(.horizontal, 8)
        .padding(.bottom, 10)
        .presentationDetents([.medium, .large])
        .presentationDragIndicator(.visible)
        .presentationBackground(LiveDesign.background)
        .preferredColorScheme(.dark)
    }
}

struct CapturePickerPanel: View {
    let sheet: CaptureSheet
    var showsGrabber: Bool = true
    var onClose: () -> Void
    @Environment(AppModel.self) private var model
    @State private var selectedMode = 0
    @State private var drumSelection = ""
    @State private var lastApplied = ""
    @State private var tintDraft: Double = 0
    @State private var drumSendTask: Task<Void, Never>?

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if showsGrabber { grabber }
            header
            content
            if !modeTabs.isEmpty {
                modeBar
            }
        }
        .padding(EdgeInsets(top: showsGrabber ? 10 : 16, leading: 20, bottom: 16, trailing: 20))
        // OpenZCine `GlassPanel`: hug header + drum + optional mode bar. Do not
        // stretch to the host well — that made every capture sheet the same height.
        .fixedSize(horizontal: false, vertical: true)
        // Picker cards float over the picture — pinned dark like the rest of the
        // HUD (`liveChromeGlass`), never adaptive `liquidGlass` that flips light
        // over a bright feed.
        .liveChromeGlass(
            in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
        .onAppear { seed() }
        .onChange(of: sheet) { _, _ in
            drumSendTask?.cancel()
            seed()
        }
        .onChange(of: model.session.status.availableShutterDenoms) { _, _ in
            guard sheet == .shutter, !isEvSheet else { return }
            reseatShutter()
        }
        .onChange(of: model.session.status.fps) { _, _ in
            guard sheet == .shutter, !isEvSheet else { return }
            reseatShutter()
        }
        .onChange(of: model.session.status.availableIsoIndices) { _, _ in
            guard sheet == .iso else { return }
            reseatIso()
        }
        .onChange(of: model.session.status.expoMode) { _, _ in
            guard sheet == .shutter else { return }
            drumSendTask?.cancel()
            if model.session.status.expoMode != .auto {
                selectedMode = OperatorPrefs.shutterUsesAngle ? 1 : 0
            }
            reseatShutterOrEv()
        }
        .onChange(of: model.session.status.evComp) { _, _ in
            guard isEvSheet else { return }
            reseatEv()
        }
        .onChange(of: model.facePriorityExposureEnabled) { _, _ in
            guard isEvSheet else { return }
            reseatEv()
        }
        .onChange(of: model.session.status.colorMode) { _, _ in
            guard sheet == .iso else { return }
            reseatIso()
        }
        .onChange(of: model.session.status.availableVideoFormats) { _, _ in
            guard sheet == .resolution else { return }
            seed()
        }
        .onChange(of: model.session.status.videoFormat) { _, _ in
            guard sheet == .resolution else { return }
            seed()
        }
        .onChange(of: drumSelection) { _, newValue in
            applyDrum(newValue)
        }
    }

    private var grabber: some View {
        Capsule()
            .fill(LiveDesign.hairlineStrong)
            .frame(width: 36, height: 4)
            .frame(maxWidth: .infinity)
    }

    private var header: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(headerTitle)
                    .font(LiveType.ui(size: 18, weight: .heavy, design: .default))
                    .kerning(2)
                    .foregroundStyle(LiveDesign.text)
                    .lineLimit(1)
                    .fixedSize(horizontal: true, vertical: false)
                Text(headerSubtitle)
                    .font(.system(size: 11, weight: .semibold, design: .monospaced))
                    .kerning(1.5)
                    .textCase(.uppercase)
                    .foregroundStyle(LiveDesign.faint)
            }
            Spacer(minLength: 8)
            CloseButton(action: onClose)
        }
    }

    @ViewBuilder private var content: some View {
        switch sheet {
        case .iso:
            VStack(alignment: .leading, spacing: 12) {
                if isIsoAutoTab {
                    CaptureDrumWheel(options: isoAutoDrumLabels, selection: $drumSelection)
                        .id(isoAutoDrumLabels)
                } else {
                    CaptureDrumWheel(
                        options: isoDrumLabels, selection: $drumSelection,
                        markedValues: isoMarkedLabels)
                }
                nativeIsoHopToggle
            }
        case .shutter:
            if isEvSheet {
                VStack(alignment: .leading, spacing: 12) {
                    CaptureDrumWheel(
                        options: evLabels, selection: $drumSelection,
                        isInteractive: !model.facePriorityExposureEnabled
                    )
                    .id(evLabels)
                    facePriorityToggle
                }
            } else if isAngleSheet {
                CaptureDrumWheel(options: shutterAngleLabels, selection: $drumSelection)
                    .id(shutterAngleLabels)
            } else {
                CaptureDrumWheel(options: shutterLabels, selection: $drumSelection)
                    .id(shutterLabels)
            }
        case .wb:
            if selectedMode == 0 {
                checkedRows(
                    WhiteBalanceMode.allCases.map(\.label),
                    selected: model.session.status.whiteBalance?.mode.label ?? "Auto"
                ) { label in
                    if label == WhiteBalanceMode.auto.label {
                        model.session.setWhiteBalanceAuto()
                    } else {
                        model.session.setWhiteBalanceCustom(
                            kelvin: currentKelvin, tint: currentTint)
                    }
                }
            } else if selectedMode == 1 {
                CaptureDrumWheel(options: CaptureLists.kelvinLabels, selection: $drumSelection)
            } else {
                tintPad
            }
        case .focus:
            if model.session.supportsFocusMode {
                focusRows
            }
        case .exposure:
            checkedRows(
                ExpoMode.allCases.map(\.label), selected: model.session.status.expoMode?.label
            ) { label in
                if let mode = ExpoMode.allCases.first(where: { $0.label == label }) {
                    model.session.setExpoMode(mode)
                }
            }
        case .audio:
            audioBody
        case .mode:
            checkedRows(
                ShootingMode.allCases.map(\.label),
                selected: model.session.currentShootingMode?.label
            ) { label in
                if let mode = ShootingMode.allCases.first(where: { $0.label == label }) {
                    model.session.setShootingMode(mode)
                }
            }
        case .resolution:
            CaptureDrumWheel(
                options: formatRates.map(\.drumLabel), selection: $drumSelection
            )
            .id(selectedMode)
        case .color:
            CaptureDrumWheel(options: colorWheelLabels, selection: $drumSelection)
        }
    }

    private var focusRows: some View {
        let continuous = model.session.status.focusMode == .continuous
        return VStack(alignment: .leading, spacing: 12) {
            HStack(spacing: 10) {
                focusTab("AF-S", active: !continuous) {
                    model.session.setFocusMode(.single)
                }
                focusTab("AF-C", active: continuous) {
                    model.session.setFocusMode(.continuous)
                }
            }
            if continuous {
                ScrollView(.horizontal, showsIndicators: false) {
                    HStack(spacing: 8) {
                        ForEach(FocusTrackMode.allCases, id: \.self) { track in
                            let on = (model.session.status.focusTrack ?? .default) == track
                            Button {
                                model.session.setFocusTrack(track)
                            } label: {
                                Text(track.label)
                                    .font(LiveType.ui(size: 13, weight: .bold, design: .default))
                                    .kerning(0.3)
                                    .foregroundStyle(on ? LiveDesign.accent : LiveDesign.muted)
                                    .lineLimit(1)
                                    .fixedSize(horizontal: true, vertical: false)
                                    .padding(.horizontal, 14)
                                    .padding(.vertical, 12)
                                    .background(
                                        on
                                            ? LiveDesign.accentDim
                                            : LiveDesign.background.opacity(0.28),
                                        in: Capsule()
                                    )
                                    .overlay {
                                        Capsule()
                                            .stroke(
                                                on ? LiveDesign.accent : LiveDesign.hairline,
                                                lineWidth: 1.5)
                                    }
                            }
                            .buttonStyle(.zcTapTarget)
                        }
                    }
                }
                .transition(.opacity)
            }
        }
        .animation(.easeInOut(duration: 0.16), value: continuous)
    }

    private func focusTab(_ title: String, active: Bool, action: @escaping () -> Void) -> some View
    {
        Button(action: action) {
            Text(title)
                .font(LiveType.ui(size: 13, weight: .bold, design: .default))
                .kerning(0.5)
                .textCase(.uppercase)
                .foregroundStyle(active ? LiveDesign.accent : LiveDesign.muted)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    active ? LiveDesign.accentDim : LiveDesign.background.opacity(0.28),
                    in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                )
                .overlay {
                    RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                        .stroke(active ? LiveDesign.accent : LiveDesign.hairline, lineWidth: 1.5)
                }
        }
        .buttonStyle(.zcTapTarget)
    }

    @ViewBuilder private var audioBody: some View {
        switch selectedMode {
        case 0:
            checkedRows(
                AudioChannel.allCases.map(\.label),
                selected: model.session.status.audioChannel?.label
            ) { label in
                if let ch = AudioChannel.allCases.first(where: { $0.label == label }) {
                    model.session.setAudioChannel(ch)
                }
            }
        case 1:
            checkedRows(
                WindNoiseReduction.allCases.map(\.label),
                selected: model.session.status.windNR?.label
            ) { label in
                if let value = WindNoiseReduction.allCases.first(where: { $0.label == label }) {
                    model.session.setWindNR(value)
                }
            }
        case 2:
            checkedRows(
                DirectionalAudio.allCases.map(\.label),
                selected: model.session.status.directionalAudio?.label
            ) { label in
                if let value = DirectionalAudio.allCases.first(where: { $0.label == label }) {
                    model.session.setDirectionalAudio(value)
                }
            }
        default:
            checkedRows(
                VocalBoost.allCases.map(\.label), selected: model.session.status.vocalBoost?.label
            ) { label in
                if let value = VocalBoost.allCases.first(where: { $0.label == label }) {
                    model.session.setVocalBoost(value)
                }
            }
        }
    }

    private var tintPad: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(tintLabel)
                .font(LiveType.ui(size: 17, weight: .semibold, design: .rounded))
                .foregroundStyle(
                    Int(tintDraft.rounded()) == 0 ? LiveDesign.muted : LiveDesign.accent)
            HStack(spacing: 12) {
                Button {
                    nudgeTint(-10)
                } label: {
                    Text("−10")
                        .font(LiveType.ui(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LiveDesign.accent)
                        .frame(width: 56, height: 40)
                        .background(
                            LiveDesign.accentDim,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.zcTapTarget)
                Slider(value: $tintDraft, in: -100...100, step: 1) { editing in
                    if !editing {
                        applyTint(Int(tintDraft.rounded()))
                    }
                }
                .tint(LiveDesign.accent)
                Button {
                    nudgeTint(10)
                } label: {
                    Text("+10")
                        .font(LiveType.ui(size: 14, weight: .bold, design: .rounded))
                        .foregroundStyle(LiveDesign.accent)
                        .frame(width: 56, height: 40)
                        .background(
                            LiveDesign.accentDim,
                            in: RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                .buttonStyle(.zcTapTarget)
            }
            Button("Apply tint \(Int(tintDraft.rounded()))") {
                applyTint(Int(tintDraft.rounded()))
            }
            .font(LiveType.ui(size: 13, weight: .semibold, design: .rounded))
            .foregroundStyle(LiveDesign.accent)
        }
        .onAppear { tintDraft = Double(currentTint) }
    }

    private var facePriorityToggle: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(CaptureLists.facePriorityTitle)
                .font(LiveType.ui(size: 13, weight: .bold, design: .default))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(LiveDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HelpBadge(text: CaptureLists.facePriorityHelp)
            Spacer(minLength: 8)
            Toggle(
                "",
                isOn: Binding(
                    get: { model.facePriorityExposureEnabled },
                    set: { model.facePriorityExposureEnabled = $0 }
                )
            )
            .labelsHidden()
            .tint(LiveDesign.accent)
            .accessibilityLabel(CaptureLists.facePriorityTitle)
            .accessibilityHint(CaptureLists.facePriorityHelp)
        }
    }

    private var nativeIsoHopToggle: some View {
        HStack(alignment: .center, spacing: 8) {
            Text(CaptureLists.nativeIsoHopTitle)
                .font(LiveType.ui(size: 13, weight: .bold, design: .default))
                .kerning(0.4)
                .textCase(.uppercase)
                .foregroundStyle(LiveDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            HelpBadge(text: CaptureLists.nativeIsoHopHelp)
            Spacer(minLength: 8)
            Toggle(
                "",
                isOn: Binding(
                    get: { model.nativeISOHopEnabled },
                    set: { model.nativeISOHopEnabled = $0 }
                )
            )
            .labelsHidden()
            .tint(LiveDesign.accent)
            .accessibilityLabel(CaptureLists.nativeIsoHopTitle)
            .accessibilityHint(CaptureLists.nativeIsoHopHelp)
        }
    }

    private var modeBar: some View {
        HStack(spacing: 10) {
            ForEach(Array(modeTabs.enumerated()), id: \.offset) { index, title in
                let active = index == selectedMode
                Button {
                    selectedMode = index
                    handleModeChange(index)
                } label: {
                    Text(title)
                        .font(LiveType.ui(size: 13, weight: .bold, design: .default))
                        .kerning(0.5)
                        .textCase(.uppercase)
                        .foregroundStyle(active ? LiveDesign.accent : LiveDesign.muted)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 12)
                        .background(
                            active ? LiveDesign.accentDim : LiveDesign.background.opacity(0.28),
                            in: RoundedRectangle(
                                cornerRadius: LiveDesign.cornerRadius, style: .continuous)
                        )
                        .overlay {
                            RoundedRectangle(
                                cornerRadius: LiveDesign.cornerRadius, style: .continuous
                            )
                            .stroke(
                                active ? LiveDesign.accent : LiveDesign.hairline, lineWidth: 1.5)
                        }
                }
                .buttonStyle(.zcTapTarget)
            }
        }
    }

    private func checkedRows(
        _ options: [String], selected: String?, action: @escaping (String) -> Void
    ) -> some View {
        VStack(spacing: 0) {
            ForEach(options, id: \.self) { option in
                let isOn = option == selected
                Button {
                    action(option)
                } label: {
                    HStack {
                        Text(option)
                            .font(LiveType.ui(size: 17, weight: .medium, design: .rounded))
                            .foregroundStyle(isOn ? LiveDesign.accent : LiveDesign.text)
                        Spacer()
                        if isOn {
                            OpcIcon.check
                                .foregroundStyle(LiveDesign.accent)
                                .frame(width: 14, height: 14)
                        }
                    }
                    .padding(.vertical, 10)
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                if option != options.last {
                    Rectangle().fill(LiveDesign.hairline).frame(height: 1)
                }
            }
        }
    }

    private var headerTitle: String {
        if isEvSheet { return "EV" }
        return sheet.headerLabel
    }

    private var headerSubtitle: String {
        if isEvSheet {
            return model.facePriorityExposureEnabled ? "Face priority" : "Compensation"
        }
        if sheet == .shutter { return isAngleSheet ? "Angle" : "Speed" }
        return sheet.subtitle
    }

    private var modeTabs: [String] {
        switch sheet {
        case .iso where offersIsoAuto: ["Auto", "Manual"]
        case .shutter where !isEvSheet: ["Speed", "Angle"]
        case .wb: ["Mode", "Kelvin", "Tint"]
        case .audio: ["Channel", "Wind", "Dir", "Vocal"]
        case .resolution: formatResolutions.map(\.tabTitle)
        default: []
        }
    }

    private var offersIsoAuto: Bool {
        CaptureLists.offersIsoAuto(from: model.session.status)
    }

    private var isIsoAutoTab: Bool {
        sheet == .iso && offersIsoAuto && selectedMode == 0
    }

    private var isEvSheet: Bool {
        sheet == .shutter && model.session.status.expoMode == .auto
    }

    private var isAngleSheet: Bool {
        sheet == .shutter && !isEvSheet && selectedMode == 1
    }

    private var isoIndices: [IsoIndex] {
        CaptureLists.isoIndices(from: model.session.status)
    }

    private var shutterDenoms: [Int] {
        CaptureLists.shutterDenoms(from: model.session.status)
    }

    private var shutterLabels: [String] {
        CaptureLists.shutterLabels(from: model.session.status)
    }

    private var shutterAngleLabels: [String] {
        ShutterAngle.labels
    }

    private var isoDrumLabels: [String] {
        CaptureLists.isoDrumLabels(from: model.session.status)
    }

    private var colorWheelLabels: [String] {
        let family = model.session.bodyFamily
        return model.session.colorModes.map { $0.label(for: family) }
    }

    private var isoAutoDrumLabels: [String] {
        CaptureLists.isoAutoLabels(from: model.session.status)
    }

    private var evLabels: [String] {
        CaptureLists.evLabels
    }

    /// OpenZCine `AccentDrumWheel.markedValues` — star after the native base only.
    private var isoMarkedLabels: Set<String> {
        CaptureLists.isoMarkedLabels(from: model.session.status)
    }

    private var currentKelvin: Int {
        let k = model.session.status.whiteBalanceKelvin
        return (2_000...10_000).contains(k) ? k : 5_600
    }

    private var currentTint: Int {
        min(max(model.session.status.whiteBalanceTint ?? 0, -100), 100)
    }

    private var tintLabel: String {
        let t = Int(tintDraft.rounded())
        if t == 0 { return "Neutral" }
        return t > 0 ? "+\(t)" : "\(t)"
    }

    private func seed() {
        switch sheet {
        case .iso:
            reseatIso()
            guard IsoLimit.shouldGet(colorMode: model.session.status.colorMode) else { return }
            Task {
                await model.session.refreshIsoLimit()
                reseatIso()
            }
        case .shutter:
            if !isEvSheet {
                selectedMode = OperatorPrefs.shutterUsesAngle ? 1 : 0
            }
            reseatShutterOrEv()
        case .wb:
            let mode = model.session.status.whiteBalance?.mode
            selectedMode = (mode == nil || mode == .auto) ? 0 : 1
            let k = "\(currentKelvin)K"
            drumSelection = CaptureLists.kelvinLabels.contains(k) ? k : "5600K"
            lastApplied = drumSelection
            tintDraft = Double(currentTint)
        case .audio:
            selectedMode = 0
            Task { await model.session.refreshAudioState() }
        case .resolution:
            let format = currentVideoFormat
            let tabs = formatResolutions
            selectedMode = tabs.firstIndex(of: format.resolution) ?? 0
            drumSelection = format.frameRate.drumLabel
            lastApplied = drumSelection
        case .color:
            selectedMode = 0
            let family = model.session.bodyFamily
            let live =
                model.session.status.colorMode?.label(for: family)
                ?? ColorMode.normal.label(for: family)
            drumSelection = colorWheelLabels.contains(live) ? live : colorWheelLabels[0]
            lastApplied = drumSelection
        default:
            selectedMode = 0
        }
    }

    private func handleModeChange(_ index: Int) {
        switch sheet {
        case .iso where offersIsoAuto:
            if index == 0 {
                model.session.setISO(.auto)
                reseatIsoAutoDrum()
            } else {
                reseatIsoDiscrete()
                if let idx = IsoIndex.allCases.first(where: { $0.label == drumSelection }),
                    isoIndices.contains(idx)
                {
                    model.session.setISO(idx)
                }
            }
        case .shutter:
            OperatorPrefs.shutterUsesAngle = index == 1
            reseatShutter()
        case .wb:
            if index == 0, model.session.status.whiteBalance?.mode != .auto {
                // Mode tab only; write happens on row tap.
            }
        case .resolution:
            let res = resolutionForTab(index)
            let rates = CamCapVideoFormat.frameRates(
                available: model.session.status.availableVideoFormats,
                resolution: res,
                current: currentVideoFormat.frameRate)
            let rate = VideoFrameRate(drumLabel: drumSelection).flatMap { rates.contains($0) ? $0 : nil }
                ?? rates.first
                ?? currentVideoFormat.frameRate
            let next = VideoFormat(resolution: res, frameRate: rate)
            guard next != currentVideoFormat else { return }
            applyVideoFormat(resolution: next.resolution, frameRate: next.frameRate)
        default:
            break
        }
    }

    private func applyDrum(_ value: String) {
        guard !value.isEmpty, value != lastApplied else { return }
        if sheet == .color, model.session.status.isRecording {
            if let mode = ColorMode(label: value) {
                model.session.setColorMode(mode)
            }
            return
        }
        lastApplied = value
        switch sheet {
        case .iso:
            if isIsoAutoTab {
                guard let limit = CaptureLists.isoLimit(from: value, status: model.session.status)
                else { return }
                enqueueDrumSend { model.session.setIsoLimit(limit) }
                return
            }
            guard let idx = IsoIndex.allCases.first(where: { $0.label == value }),
                isoIndices.contains(idx)
            else { return }
            enqueueDrumSend { model.session.setISO(idx) }
        case .shutter:
            if isEvSheet {
                guard !model.facePriorityExposureEnabled else { return }
                guard let ev = EvComp(label: value) else { return }
                enqueueDrumSend { model.session.setEv(ev) }
                return
            }
            if isAngleSheet {
                guard let degrees = ShutterAngle.parse(value) else { return }
                OperatorPrefs.shutterAngleDegrees = degrees
                let denom = ShutterAngle.denom(
                    degrees: degrees,
                    fps: model.session.status.fps,
                    available: shutterDenoms)
                enqueueDrumSend { model.session.setShutterDenom(denom) }
                return
            }
            guard let denom = CamCapShutter.denom(from: value),
                shutterDenoms.contains(denom)
            else { return }
            enqueueDrumSend { model.session.setShutterDenom(denom) }
        case .wb:
            guard selectedMode == 1, let kelvin = CaptureLists.kelvin(from: value) else { return }
            model.session.setWhiteBalanceCustom(kelvin: kelvin, tint: currentTint)
        case .resolution:
            guard let rate = VideoFrameRate(drumLabel: value),
                formatRates.contains(rate)
            else { return }
            applyVideoFormat(resolution: resolutionForTab(selectedMode), frameRate: rate)
        case .color:
            guard let mode = ColorMode(label: value) else { return }
            model.session.setColorMode(mode)
        default:
            break
        }
    }

    /// Latest-wins: scrubbing must not enqueue a SET per detent.
    private func enqueueDrumSend(_ send: @escaping () -> Void) {
        drumSendTask?.cancel()
        drumSendTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled else { return }
            send()
        }
    }

    private var currentVideoFormat: VideoFormat {
        if let format = model.session.status.videoFormat { return format }
        let res = model.session.status.videoResolution ?? .p1080
        let rate = VideoFrameRate.allCases.first { $0.fps == model.session.status.fps } ?? .fps24
        return VideoFormat(resolution: res, frameRate: rate)
    }

    private var formatResolutions: [VideoResolution] {
        CamCapVideoFormat.resolutions(
            available: model.session.status.availableVideoFormats,
            current: currentVideoFormat.resolution)
    }

    private var formatRates: [VideoFrameRate] {
        CamCapVideoFormat.frameRates(
            available: model.session.status.availableVideoFormats,
            resolution: resolutionForTab(selectedMode),
            current: currentVideoFormat.frameRate)
    }

    private func resolutionForTab(_ index: Int) -> VideoResolution {
        let tabs = formatResolutions
        guard tabs.indices.contains(index) else { return currentVideoFormat.resolution }
        return tabs[index]
    }

    private func applyVideoFormat(resolution: VideoResolution, frameRate: VideoFrameRate) {
        model.session.setVideoFormat(resolution: resolution, frameRate: frameRate)
    }

    private func nudgeTint(_ delta: Int) {
        tintDraft = min(max(tintDraft + Double(delta), -100), 100)
        applyTint(Int(tintDraft.rounded()))
    }

    /// Auto SET keeps tint (Mimo). Tint pad must not kick Auto into Custom.
    private func applyTint(_ tint: Int) {
        if model.session.status.whiteBalance?.mode == .custom {
            model.session.setWhiteBalanceCustom(kelvin: currentKelvin, tint: tint)
        } else {
            model.session.setWhiteBalanceAuto(tint: tint)
        }
    }

    private func reseatIso() {
        if offersIsoAuto {
            selectedMode = model.session.status.isoIndex == .auto ? 0 : 1
        } else {
            selectedMode = 0
        }
        if isIsoAutoTab {
            reseatIsoAutoDrum()
        } else {
            reseatIsoDiscrete()
        }
    }

    private func reseatIsoAutoDrum() {
        let labels = isoAutoDrumLabels
        let live = CaptureLists.isoAutoLabel(from: model.session.status)
        let next = labels.contains(live) ? live : (labels.first ?? "")
        lastApplied = next
        drumSelection = next
    }

    private func reseatIsoDiscrete() {
        let live: String
        if let idx = model.session.status.isoIndex, idx != .auto {
            live = idx.label
        } else if model.session.status.iso > 0 {
            live = "\(model.session.status.iso)"
        } else {
            live = isoDrumLabels.first ?? ""
        }
        let next = isoDrumLabels.contains(live) ? live : (isoDrumLabels.first ?? "")
        lastApplied = next
        drumSelection = next
    }

    private func reseatShutterOrEv() {
        if isEvSheet {
            reseatEv()
        } else {
            reseatShutter()
        }
    }

    private func reseatEv() {
        let labels = evLabels
        let live = model.session.status.evComp?.label ?? "0.0"
        let next = labels.contains(live) ? live : "0.0"
        lastApplied = next
        drumSelection = next
    }

    private func reseatShutter() {
        if isAngleSheet {
            reseatShutterAngle()
            return
        }
        let labels = shutterLabels
        let live =
            model.session.status.shutterDenom > 0
            ? CamCapShutter.label(model.session.status.shutterDenom) : labels.first ?? ""
        let next = labels.contains(live) ? live : nearestShutter(live)
        lastApplied = next
        drumSelection = next
    }

    private func reseatShutterAngle() {
        let fps = model.session.status.fps
        let liveDenom = model.session.status.shutterDenom
        let preferred = ShutterAngle.label(OperatorPrefs.shutterAngleDegrees)
        if liveDenom > 0 {
            let mapped = ShutterAngle.denom(
                degrees: OperatorPrefs.shutterAngleDegrees, fps: fps, available: shutterDenoms)
            if mapped == liveDenom, shutterAngleLabels.contains(preferred) {
                lastApplied = preferred
                drumSelection = preferred
                return
            }
            let next = ShutterAngle.nearestLabel(denom: liveDenom, fps: fps)
            OperatorPrefs.shutterAngleDegrees =
                ShutterAngle.parse(next) ?? ShutterAngle.defaultDegrees
            lastApplied = next
            drumSelection = next
            return
        }
        lastApplied = preferred
        drumSelection = preferred
    }

    private func nearestShutter(_ label: String) -> String {
        guard let denom = CamCapShutter.denom(from: label),
            let near = CamCapShutter.nearestDenom(denom, in: shutterDenoms)
        else {
            return shutterLabels.first ?? ""
        }
        return CamCapShutter.label(near)
    }
}

struct CaptureDrumWheel: View {
    let options: [String]
    @Binding var selection: String
    /// OpenZCine `AccentDrumWheel.markedValues` — native base ISO after the number.
    var markedValues: Set<String> = []
    var isInteractive: Bool = true

    private let rowHeight: CGFloat = 52
    private let wheelHeight: CGFloat = 176

    var body: some View {
        ScrollViewReader { proxy in
            ScrollView(.vertical, showsIndicators: false) {
                VStack(spacing: 0) {
                    ForEach(options, id: \.self) { option in
                        let centered = option == selection
                        HStack(spacing: 6) {
                            Text(option)
                                .font(
                                    .system(
                                        size: centered ? 30 : 23,
                                        weight: centered ? .semibold : .regular, design: .monospaced
                                    )
                                )
                                .lineLimit(1)
                                .minimumScaleFactor(0.5)
                            if markedValues.contains(option) {
                                LucideIconView(name: OpcIcon.star.lucideName, filled: true)
                                    .frame(width: centered ? 13 : 10, height: centered ? 13 : 10)
                                    .opacity(0.85)
                            }
                        }
                        .foregroundStyle(
                            centered ? LiveDesign.accent : LiveDesign.muted.opacity(0.7)
                        )
                        .frame(maxWidth: .infinity)
                        .frame(height: rowHeight)
                        .contentShape(Rectangle())
                        .id(option)
                        .onTapGesture {
                            guard isInteractive else { return }
                            selection = option
                        }
                    }
                }
                .scrollTargetLayout()
            }
            .scrollTargetBehavior(.viewAligned)
            .scrollPosition(
                id: Binding(
                    get: { selection },
                    set: { if let value = $0 { selection = value } }
                )
            )
            .scrollDisabled(!isInteractive)
            .opacity(isInteractive ? 1 : 0.55)
            .contentMargins(.vertical, (wheelHeight - rowHeight) / 2, for: .scrollContent)
            .frame(height: wheelHeight)
            .sensoryFeedback(.selection, trigger: selection)
            .mask {
                LinearGradient(
                    stops: [
                        .init(color: .clear, location: 0),
                        .init(color: .black, location: 0.22),
                        .init(color: .black, location: 0.78),
                        .init(color: .clear, location: 1),
                    ],
                    startPoint: .top,
                    endPoint: .bottom
                )
            }
            .overlay {
                Rectangle().fill(LiveDesign.hairlineStrong).frame(height: 1).offset(
                    y: -rowHeight / 2)
                Rectangle().fill(LiveDesign.hairlineStrong).frame(height: 1).offset(
                    y: rowHeight / 2)
            }
            .onAppear {
                DispatchQueue.main.async { proxy.scrollTo(selection, anchor: .center) }
            }
        }
    }
}

enum CaptureLists {
    static func shutterDenoms(from status: CameraStatus) -> [Int] {
        CamCapShutter.wheelDenoms(
            available: status.availableShutterDenoms, current: status.shutterDenom)
    }

    static func shutterLabels(from status: CameraStatus) -> [String] {
        shutterDenoms(from: status).map(CamCapShutter.label)
    }

    static func isoIndices(from status: CameraStatus) -> [IsoIndex] {
        CamCapIso.wheelIndices(
            available: status.availableIsoIndices,
            fallback: (status.colorMode ?? .normal).isoIndices
        )
    }

    static func isoDrumLabels(from status: CameraStatus) -> [String] {
        isoIndices(from: status).filter { $0 != .auto }.map(\.label)
    }

    static func offersIsoAuto(from status: CameraStatus) -> Bool {
        (status.colorMode ?? .normal).offersIsoAuto
    }

    static func isoAutoLabels(from status: CameraStatus) -> [String] {
        (status.colorMode ?? .normal).isoAutoLabels
    }

    static func isoAutoLabel(from status: CameraStatus) -> String {
        guard let base = (status.colorMode ?? .normal).isoAutoBase,
            let limit = status.isoLimit
        else { return "" }
        return limit.label(base: base)
    }

    static func isoLimit(from label: String, status: CameraStatus) -> IsoLimit? {
        let color = status.colorMode ?? .normal
        guard let base = color.isoAutoBase else { return nil }
        return color.isoAutoLimits.first { $0.label(base: base) == label }
    }

    static let evLabels = EvComp.allCases.map(\.label)

    /// Star markers only. List stays `camcap_iso`; transfer is `status.monitorTransfer`.
    static func isoMarkedLabels(from status: CameraStatus) -> Set<String> {
        CamCapIso.markedLabels(transfer: status.monitorTransfer)
    }

    static let facePriorityTitle = "Face Priority"
    static let facePriorityBadgeIcon = OpcIcon.scan
    static let facePriorityHelp =
        "On: EV follows faces to middle gray. Several faces use the median. First couple of seconds after a face appears are faster, then about 1 s. Off: put EV back to what it was, or 0.0."

    static let nativeIsoHopTitle = "Auto Native ISO"
    static let nativeIsoHopHelp =
        "On: switching D-Log ↔ D-Log2 hops ISO to that curve's starred native if you were still on native. Off: keep the ISO you set."

    static let kelvinValues = Array(stride(from: 2_000, through: 10_000, by: 100))
    static let kelvinLabels = kelvinValues.map { "\($0)K" }

    static func kelvin(from label: String) -> Int? {
        Int(label.replacingOccurrences(of: "K", with: ""))
    }
}

extension CaptureSheet {
    var headerLabel: String {
        switch self {
        case .iso: "ISO"
        case .shutter: "SHUTTER"
        case .wb: "WB"
        case .focus: "FOCUS"
        case .exposure: "MODE"
        case .audio: "AUDIO"
        case .mode: "MODE"
        case .resolution: "RESOLUTION"
        case .color: "COLOR"
        }
    }

    var subtitle: String {
        switch self {
        case .iso: "Sensitivity"
        case .shutter: "Angle / speed"
        case .wb: "Kelvin / auto / tint"
        case .focus: "AF-S / AF-C"
        case .exposure: "Exposure"
        case .audio: "Channel · wind · direction · vocal"
        case .mode: "Shooting mode"
        case .resolution: "Frame rate"
        case .color: "Color mode"
        }
    }
}
