import MonitorPresentation
import MonitorUI
import OpenPocketViewCore
import SwiftUI
import UIKit

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

/// All persistent camera drawers share a bottom-center anchor. The host may
/// keep visible controls touchable; every other outside tap dismisses the drawer.
struct LiveCapturePickerHost: View {
    @Binding var sheet: CaptureSheet?
    var frames: [CaptureSheet: CGRect]
    var bar: CGRect
    var viewport: CGSize
    var safeArea: EdgeInsets = EdgeInsets()
    var ceilingY: CGFloat = 0
    var bottomY: CGFloat? = nil
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    private var reveal: Animation? {
        reduceMotion ? nil : .timingCurve(0.2, 0.9, 0.2, 1, duration: 0.26)
    }

    var body: some View {
        let place = MonitorCapturePopupLayout(
            viewportWidth: viewport.width, viewportHeight: viewport.height,
            tablet: UIDevice.current.userInterfaceIdiom == .pad,
            safeArea: MonitorSafeArea(
                top: safeArea.top, leading: safeArea.leading,
                bottom: safeArea.bottom, trailing: safeArea.trailing),
            bottomBoundary: bottomY.map(Double.init), ceiling: ceilingY)
        ZStack(alignment: .topLeading) {
            if sheet != nil {
                Color.clear
                    .contentShape(CapturePickerBackdrop(frames: frames), eoFill: true)
                    .onTapGesture(coordinateSpace: .named(LiveCanvasSpace.name)) { location in
                        handleBackdrop(at: location)
                    }
            }
            VStack(spacing: 0) {
                Spacer(minLength: 0)
                if let current = sheet {
                    CapturePickerPanel(
                        sheet: current, maximumHeight: place.maximumHeight,
                        bottomPadding: place.bottomPadding,
                        isPresented: { sheet == current },
                        onSelectRecordingCategory: [.resolution, .color, .mode].contains(current)
                            ? { sheet = $0 } : nil
                    ) { sheet = nil }
                    .id(current)
                    .accessibilityElement(children: .contain)
                    .accessibilityIdentifier("monitor.capture.panel")
                    .transition(.move(edge: .bottom).combined(with: .opacity))
                }
            }
            .frame(width: place.width, height: place.bottom, alignment: .bottom)
            .offset(x: place.centerX - place.width / 2)
        }
        .frame(width: viewport.width, height: viewport.height, alignment: .topLeading)
        .animation(reveal, value: sheet)
        .allowsHitTesting(sheet != nil)
    }

    private func handleBackdrop(at location: CGPoint) {
        if let hit = frames.first(where: { $0.value.insetBy(dx: -10, dy: -8).contains(location) })?
            .key
        {
            sheet = hit == sheet ? nil : hit
        } else {
            sheet = nil
        }
    }
}

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
    var maximumHeight: CGFloat = .infinity
    var bottomPadding: CGFloat = 12
    var isPresented: () -> Bool = { true }
    var onSelectRecordingCategory: ((CaptureSheet) -> Void)? = nil
    var onClose: () -> Void
    @Environment(AppModel.self) private var model
    @Environment(\.interfaceLocked) private var interfaceLocked
    @Environment(\.scenePhase) private var scenePhase
    @Environment(\.monitorWindowGeometry) private var windowGeometry
    @State private var selectedMode = 0
    @State private var selectedAspect: VideoAspect = .sixteenNine
    @State private var drumSelection = ""
    @State private var lastApplied = ""
    @State private var tintDraft: Double?
    @State private var drumSendTask: Task<Void, Never>?
    @State private var deferredDrum = MonitorDeferredSelection<DrumContext>()
    @State private var appeared = false
    @State private var drumInteractionRevision: UInt64 = 0

    private struct DrumContext: Hashable {
        let cameraID: UUID?
        let phase: String
        let sheet: CaptureSheet
        let mode: Int
        let color: ColorMode?
        let fps: Int
        let shutterDenoms: [Int]
        let snapshot: CaptureQuickSnapshot?
        let focusTrack: FocusTrackMode?
        let options: [String]
    }

    private struct DrumIdentity: Hashable {
        let context: DrumContext
        let revision: UInt64
        let presented: Bool
    }

    private var drumOptions: [String] {
        switch sheet {
        case .iso: isIsoAutoTab ? isoAutoDrumLabels : isoDrumLabels
        case .shutter: isEvSheet ? evLabels : (isAngleSheet ? shutterAngleLabels : shutterLabels)
        default: []
        }
    }

    private var drumContext: DrumContext {
        DrumContext(
            cameraID: model.session.connectedCamera?.id, phase: model.session.phase.label,
            sheet: sheet, mode: selectedMode, color: model.session.status.colorMode,
            fps: model.session.status.fps, shutterDenoms: shutterDenoms,
            snapshot: CaptureQuickSnapshot.primary(sheet, model: model),
            focusTrack: sheet == .focus ? model.session.status.focusTrack : nil,
            options: drumOptions)
    }

    private var canApplyDrum: Bool {
        appeared && isPresented() && scenePhase == .active
            && !interfaceLocked && !model.session.isLocked
    }

    var body: some View {
        MonitorCapturePanel(
            title: headerTitle, subtitle: headerSubtitle,
            maximumHeight: maximumHeight, bottomPadding: bottomPadding, close: onClose
        ) {
            VStack(alignment: .leading, spacing: 8) {
                content
                if sheet == .resolution, formatAspects.count > 1 { aspectBar }
                if !modeTabs.isEmpty { modeBar }
                if let onSelectRecordingCategory {
                    MonitorCaptureTabs(
                        options: [CaptureSheet.resolution, .color, .mode], selection: sheet,
                        title: { $0 == .resolution ? "Format" : $0 == .color ? "Color" : "Mode" }
                    ) { category in
                        cancelDrumSend()
                        onSelectRecordingCategory(category)
                    }
                }
                if sheet == .iso { nativeIsoHopToggle }
                if isEvSheet { facePriorityToggle }
            }
        }
        .environment(
            \.captureDrumInteractionIdentity,
            {
                AnyHashable(
                    DrumIdentity(
                        context: drumContext, revision: drumInteractionRevision,
                        presented: canApplyDrum))
            }
        )
        .contentShape(Rectangle())
        .simultaneousGesture(TapGesture().onEnded {})
        .onAppear {
            appeared = true
            seed()
        }
        .onDisappear {
            appeared = false
            cancelDrumSend()
        }
        .onChange(of: canApplyDrum) { _, active in
            if !active { cancelDrumSend(reseat: true) }
        }
        .onChange(of: drumContext) { _, _ in cancelDrumSend(reseat: true) }
        .onChange(of: windowGeometry) { _, _ in cancelDrumSend(reseat: true) }
        .onReceive(
            NotificationCenter.default.publisher(for: UIDevice.orientationDidChangeNotification)
        ) { _ in cancelDrumSend(reseat: true) }
        .onReceive(
            NotificationCenter.default.publisher(for: UIApplication.willResignActiveNotification)
        ) { _ in cancelDrumSend(reseat: true) }
        .onChange(of: sheet) { _, _ in
            cancelDrumSend()
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
            cancelDrumSend()
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
        .onChange(of: pickerVideoFormats) { _, _ in
            guard sheet == .resolution else { return }
            guard !model.session.isFormatPinActive else { return }
            seed()
        }
        .onChange(of: model.session.status.videoFormat) { _, _ in
            guard sheet == .resolution else { return }
            guard !model.session.isFormatPinActive else { return }
            seed()
        }
        .onChange(of: drumSelection) { _, newValue in
            applyDrum(newValue)
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
            }
        case .shutter:
            if isEvSheet {
                VStack(alignment: .leading, spacing: 12) {
                    CaptureDrumWheel(
                        options: evLabels, selection: $drumSelection,
                        isInteractive: !model.facePriorityExposureEnabled
                    )
                    .id(evLabels)
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
                choiceDrum(
                    WhiteBalanceMode.allCases.map(\.label),
                    selected: model.session.status.whiteBalance?.mode.label
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
            choiceDrum(
                ExpoMode.allCases.map(\.label), selected: model.session.status.expoMode?.label
            ) { label in
                if let mode = ExpoMode.allCases.first(where: { $0.label == label }) {
                    model.session.setExpoMode(mode)
                }
            }
        case .audio:
            audioBody
        case .mode:
            choiceDrum(
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
        let selected = CaptureLists.focusOption(from: model.session.status)
        return VStack(alignment: .leading, spacing: 8) {
            choiceDrum(FocusOption.allCases.map(\.chip), selected: selected?.chip) { value in
                guard let option = FocusOption.allCases.first(where: { $0.chip == value }) else {
                    return
                }
                model.session.setFocusOption(option)
            }
            VStack(alignment: .leading, spacing: 2) {
                Text(CaptureLists.focusTitle(selected))
                    .font(MonitorTheme.font(11.5, weight: .semibold)).foregroundStyle(
                        MonitorTheme.text)
                Text(CaptureLists.focusHelp(selected))
                    .font(MonitorTheme.font(9.5)).lineSpacing(2).foregroundStyle(MonitorTheme.faint)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.top, 9)
            .overlay(alignment: .top) { Color.white.opacity(0.08).frame(height: 1) }
        }
    }

    @ViewBuilder private var audioBody: some View {
        switch selectedMode {
        case 0:
            choiceDrum(
                AudioChannel.allCases.map(\.label),
                selected: model.session.status.audioChannel?.label
            ) { label in
                if let ch = AudioChannel.allCases.first(where: { $0.label == label }) {
                    model.session.setAudioChannel(ch)
                }
            }
        case 1:
            choiceDrum(
                WindNoiseReduction.allCases.map(\.label),
                selected: model.session.status.windNR?.label
            ) { label in
                if let value = WindNoiseReduction.allCases.first(where: { $0.label == label }) {
                    model.session.setWindNR(value)
                }
            }
        case 2:
            choiceDrum(
                DirectionalAudio.allCases.map(\.label),
                selected: model.session.status.directionalAudio?.label
            ) { label in
                if let value = DirectionalAudio.allCases.first(where: { $0.label == label }) {
                    model.session.setDirectionalAudio(value)
                }
            }
        default:
            choiceDrum(
                VocalBoost.allCases.map(\.label), selected: model.session.status.vocalBoost?.label
            ) { label in
                if let value = VocalBoost.allCases.first(where: { $0.label == label }) {
                    model.session.setVocalBoost(value)
                }
            }
        }
    }

    private var tintPad: some View {
        CaptureDrumWheel(
            options: (-100...100).map(String.init),
            selection: Binding(
                get: { tintDraft.map { String(Int($0.rounded())) } ?? "" },
                set: { value in
                    guard let tint = Int(value), (-100...100).contains(tint) else { return }
                    tintDraft = Double(tint)
                    applyTint(tint)
                })
        )
        .onAppear { tintDraft = model.session.status.whiteBalanceTint.map(Double.init) }
        .onChange(of: model.session.status.whiteBalanceTint) { _, _ in
            tintDraft = model.session.status.whiteBalanceTint.map(Double.init)
        }
    }

    private var facePriorityToggle: some View {
        MonitorCaptureToggle(
            "Face priority",
            help: "EV follows faces to middle gray. Several faces use the median.",
            isOn: Binding(
                get: { model.facePriorityExposureEnabled },
                set: { model.facePriorityExposureEnabled = $0 }))
    }

    private var nativeIsoHopToggle: some View {
        MonitorCaptureToggle(
            "Auto native ISO",
            help: "Hop to the curve's native ISO when the color mode changes.",
            isOn: Binding(
                get: { model.nativeISOHopEnabled },
                set: { model.nativeISOHopEnabled = $0 }))
    }

    private var aspectBar: some View {
        MonitorCaptureTabs(
            options: formatAspects, selection: selectedAspect,
            title: { $0.label }, select: handleAspectChange)
    }

    private var modeBar: some View {
        MonitorCaptureTabs(
            options: Array(modeTabs.indices), selection: selectedMode,
            title: { modeTabs[$0] },
            select: { index in
                selectedMode = index
                handleModeChange(index)
            })
    }

    private func choiceDrum(
        _ options: [String], selected: String?, action: @escaping (String) -> Void
    ) -> some View {
        CaptureDrumWheel(
            options: options,
            selection: Binding(
                get: { selected ?? "" }, set: action))
    }

    private var headerTitle: String {
        if isEvSheet { return "EXPOSURE" }
        return sheet.headerLabel
    }

    private var headerSubtitle: String {
        if isEvSheet {
            return "Compensation"
        }
        if sheet == .shutter { return "Angle · speed" }
        return sheet.subtitle
    }

    private var modeTabs: [String] {
        switch sheet {
        case .iso where offersIsoAuto: ["Auto", "Manual"]
        case .shutter where !isEvSheet: ["Speed", "Angle"]
        case .wb: ["Mode", "Kelvin", "Tint"]
        case .audio: ["Channel", "Wind", "Direction", "Vocal"]
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

    private var connectedBody: CameraModel? { model.session.connectedCamera?.model }

    private var isoAutoDrumLabels: [String] {
        CaptureLists.isoAutoLabels(from: model.session.status, model: connectedBody)
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
            drumSelection =
                (2_000...10_000).contains(model.session.status.whiteBalanceKelvin) ? k : ""
            lastApplied = drumSelection
            tintDraft = model.session.status.whiteBalanceTint.map(Double.init)
        case .audio:
            selectedMode = 0
            Task { await model.session.refreshAudioState() }
        case .resolution:
            let format = currentVideoFormat
            selectedAspect = format.resolution.aspect ?? .sixteenNine
            let tabs = formatResolutions
            selectedMode = tabs.firstIndex(of: format.resolution) ?? 0
            drumSelection = format.frameRate.drumLabel
            lastApplied = drumSelection
        case .color:
            selectedMode = 0
            let family = model.session.bodyFamily
            let live =
                model.session.status.colorMode?.label(for: family)
                ?? ""
            drumSelection = colorWheelLabels.contains(live) ? live : ""
            lastApplied = drumSelection
        default:
            selectedMode = 0
        }
    }

    private func handleModeChange(_ index: Int) {
        cancelDrumSend()
        switch sheet {
        case .iso where offersIsoAuto:
            if index == 0 {
                model.session.setISO(.auto)
                reseatIsoAutoDrum()
            } else {
                reseatIsoDiscrete()
                // Choosing Manual is an explicit mode action. Preserve its
                // existing first-legal-ISO fallback when camera ISO is unknown.
                if drumSelection.isEmpty, let first = isoDrumLabels.first {
                    lastApplied = first
                    drumSelection = first
                }
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
                available: pickerVideoFormats,
                resolution: res,
                current: currentVideoFormat.frameRate)
            let rate =
                VideoFrameRate(drumLabel: drumSelection).flatMap { rates.contains($0) ? $0 : nil }
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
                guard
                    let limit = CaptureLists.isoLimit(
                        from: value, status: model.session.status, model: connectedBody)
                else { return }
                enqueueDrumSend(value) { model.session.setIsoLimit(limit) }
                return
            }
            guard let idx = IsoIndex.allCases.first(where: { $0.label == value }),
                isoIndices.contains(idx)
            else { return }
            enqueueDrumSend(value) { model.session.setISO(idx) }
        case .shutter:
            if isEvSheet {
                guard !model.facePriorityExposureEnabled else { return }
                guard let ev = EvComp(label: value) else { return }
                enqueueDrumSend(value) { model.session.setEv(ev) }
                return
            }
            if isAngleSheet {
                guard let degrees = ShutterAngle.parse(value) else { return }
                let denom = ShutterAngle.denom(
                    degrees: degrees,
                    fps: model.session.status.fps,
                    available: shutterDenoms)
                enqueueDrumSend(value) {
                    OperatorPrefs.shutterAngleDegrees = degrees
                    model.session.setShutterDenom(denom)
                }
                return
            }
            guard let denom = CamCapShutter.denom(from: value),
                shutterDenoms.contains(denom)
            else { return }
            enqueueDrumSend(value) { model.session.setShutterDenom(denom) }
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
    private func enqueueDrumSend(_ value: String, _ send: @escaping () -> Void) {
        drumSendTask?.cancel()
        guard canApplyDrum else {
            cancelDrumSend(reseat: true)
            return
        }
        let request = deferredDrum.schedule(value, context: drumContext)
        drumSendTask = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(80))
            guard !Task.isCancelled, deferredDrum.pending == request else { return }
            let accepted = deferredDrum.consume(
                request, context: drumContext, options: drumOptions, isActive: canApplyDrum)
            drumSendTask = nil
            guard accepted != nil else {
                reseatDrum()
                return
            }
            send()
        }
    }

    private func cancelDrumSend(reseat: Bool = false) {
        drumInteractionRevision &+= 1
        let hadPending = deferredDrum.pending != nil
        drumSendTask?.cancel()
        drumSendTask = nil
        deferredDrum.cancel()
        if reseat, hadPending { reseatDrum() }
    }

    private func reseatDrum() {
        switch sheet {
        case .iso: reseatIso()
        case .shutter: reseatShutterOrEv()
        default: break
        }
    }

    private var currentVideoFormat: VideoFormat {
        if let format = model.session.status.videoFormat { return format }
        let res = model.session.status.videoResolution ?? .p1080
        let rate = VideoFrameRate.fromFps(model.session.status.fps) ?? .fps24
        return VideoFormat(resolution: res, frameRate: rate)
    }

    private var pickerVideoFormats: [VideoFormat] {
        CamCapVideoFormat.pickerFormats(
            available: model.session.status.availableVideoFormats,
            model: connectedBody, shootingMode: model.session.status.shootingMode)
    }

    private var formatAspects: [VideoAspect] {
        CamCapVideoFormat.aspects(
            available: pickerVideoFormats,
            current: currentVideoFormat.resolution.aspect)
    }

    private var formatResolutions: [VideoResolution] {
        let aspect = formatAspects.count > 1 ? selectedAspect : nil
        return CamCapVideoFormat.resolutions(
            available: pickerVideoFormats,
            aspect: aspect,
            current: currentVideoFormat.resolution)
    }

    private var formatRates: [VideoFrameRate] {
        CamCapVideoFormat.frameRates(
            available: pickerVideoFormats,
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

    private func handleAspectChange(_ aspect: VideoAspect) {
        guard aspect != selectedAspect else { return }
        selectedAspect = aspect
        let sizes = formatResolutions
        let match =
            sizes.first { $0.sizeTitle == currentVideoFormat.resolution.sizeTitle }
            ?? sizes.first
            ?? currentVideoFormat.resolution
        selectedMode = sizes.firstIndex(of: match) ?? 0
        let rates = CamCapVideoFormat.frameRates(
            available: pickerVideoFormats,
            resolution: match,
            current: currentVideoFormat.frameRate)
        let rate =
            rates.contains(currentVideoFormat.frameRate)
            ? currentVideoFormat.frameRate : (rates.first ?? currentVideoFormat.frameRate)
        drumSelection = rate.drumLabel
        lastApplied = drumSelection
        applyVideoFormat(resolution: match, frameRate: rate)
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
        let live = CaptureLists.isoAutoLabel(from: model.session.status, model: connectedBody)
        let next = labels.contains(live) ? live : ""
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
            live = ""
        }
        let next = isoDrumLabels.contains(live) ? live : ""
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
        let live = model.session.status.evComp?.label ?? ""
        let next = labels.contains(live) ? live : ""
        lastApplied = next
        drumSelection = next
    }

    private func reseatShutter() {
        if isAngleSheet {
            reseatShutterAngle()
            return
        }
        let labels = shutterLabels
        guard model.session.status.shutterDenom > 0 else {
            lastApplied = ""
            drumSelection = ""
            return
        }
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
        lastApplied = ""
        drumSelection = ""
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
    var markedValues: Set<String> = []
    var isInteractive: Bool = true
    @Environment(AppModel.self) private var model
    @Environment(\.captureDrumInteractionIdentity) private var interactionIdentity

    var body: some View {
        MonitorValueDrum(
            options: options, selection: $selection, markedValues: markedValues,
            isInteractive: isInteractive, haptics: model.hapticsEnabled,
            interactionIdentity: interactionIdentity
        )
    }
}

private struct CaptureDrumInteractionIdentityKey: EnvironmentKey {
    static let defaultValue: () -> AnyHashable = { AnyHashable(0) }
}

extension EnvironmentValues {
    fileprivate var captureDrumInteractionIdentity: () -> AnyHashable {
        get { self[CaptureDrumInteractionIdentityKey.self] }
        set { self[CaptureDrumInteractionIdentityKey.self] = newValue }
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

    static func isoAutoLabels(from status: CameraStatus, model: CameraModel? = nil) -> [String] {
        (status.colorMode ?? .normal).isoAutoLabels(for: model)
    }

    static func isoAutoLabel(from status: CameraStatus, model: CameraModel? = nil) -> String {
        guard let base = (status.colorMode ?? .normal).isoAutoBase(for: model),
            let limit = status.isoLimit
        else { return "" }
        return limit.label(base: base)
    }

    static func isoLimit(from label: String, status: CameraStatus, model: CameraModel? = nil)
        -> IsoLimit?
    {
        let color = status.colorMode ?? .normal
        guard let base = color.isoAutoBase(for: model) else { return nil }
        return color.isoAutoLimits.first { $0.label(base: base) == label }
    }

    static let evLabels = EvComp.allCases.map(\.label)

    /// Star markers only. List stays `camcap_iso`; transfer is `status.monitorTransfer`.
    static func isoMarkedLabels(from status: CameraStatus) -> Set<String> {
        CamCapIso.markedLabels(transfer: status.monitorTransfer)
    }

    static func focusOption(from status: CameraStatus) -> FocusOption? {
        FocusOption.resolve(mode: status.focusMode, track: status.focusTrack)
    }

    static func focusTitle(_ option: FocusOption?) -> String {
        switch option {
        case .single: "Single autofocus"
        case .continuousDefault: "Continuous autofocus"
        case .productShowcase: "Product showcase"
        case .subjectLock: "Subject lock tracking"
        case .registeredPriority: "Registered subject priority"
        case nil: "Focus tracking"
        }
    }

    static func focusHelp(_ option: FocusOption?) -> String {
        switch option {
        case .single: "Set focus once. Tap the picture to choose the focus point."
        case .continuousDefault: "Keep focus adjusting as the subject moves through frame."
        case .productShowcase: "Prioritize a product presented close to the camera."
        case .subjectLock: "Keep focus on the selected subject as it moves through frame."
        case .registeredPriority: "Give a subject registered on the camera priority when focusing."
        case nil: "Choose a focus mode supported by the connected camera."
        }
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
        case .wb: "WHITE BALANCE"
        case .focus: "FOCUS"
        case .exposure: "EXPOSURE MODE"
        case .audio: "AUDIO"
        case .mode: "SHOOTING MODE"
        case .resolution: "FORMAT"
        case .color: "COLOR"
        }
    }

    var subtitle: String {
        switch self {
        case .iso: "Sensitivity"
        case .shutter: "Angle · speed"
        case .wb: "Kelvin · auto · tint"
        case .focus: "AF-S · AF-C · tracking"
        case .exposure: "Exposure"
        case .audio: "Channel · wind · direction · vocal"
        case .mode: "Shooting mode"
        case .resolution: "Resolution · frame rate"
        case .color: "Color mode"
        }
    }
}

/// A noninteractive preview follows the readout's original touch. Closing this
/// view cannot end or replace the recognizer that owns the eventual commit.
struct LiveCaptureDrumHost: View {
    var frames: [CaptureSheet: CGRect]
    var bar: CGRect
    var viewport: CGSize
    var safeArea: EdgeInsets = EdgeInsets()
    @Environment(AppModel.self) private var model

    var body: some View {
        if let drum = model.captureDrum {
            let height: CGFloat = 127
            let place = LivePopupPlacement.capturePicker(
                tile: frames[drum.sheet] ?? .zero, bar: bar, panelHeight: height,
                viewport: viewport, safeArea: safeArea, ceilingY: safeArea.top + 10)
            VStack(alignment: .leading, spacing: 3) {
                Text(drum.snapshot.title).font(MonitorTheme.font(9, weight: .semibold))
                    .tracking(1.8).foregroundStyle(MonitorTheme.muted)
                MonitorValueDrum(
                    options: drum.snapshot.options,
                    selection: .constant(drum.snapshot.selection),
                    markedValues: drum.snapshot.marked,
                    haptics: model.hapticsEnabled, previewPosition: drum.position)
            }
            .padding(14)
            .frame(width: place.width, height: min(height, place.maxHeight))
            .monitorGlass(in: RoundedRectangle(cornerRadius: 14), density: .expanded)
            .position(x: place.x + place.width / 2, y: place.y + min(height, place.maxHeight) / 2)
            .allowsHitTesting(false)
            .accessibilityHidden(true)
            .onChange(of: viewport) { _, _ in model.captureDrum = nil }
        }
    }
}

/// Let the underlying readouts retain their recognizers while a persistent
/// picker is open. The rest of the picture remains a dismiss target.
private struct CapturePickerBackdrop: Shape {
    let frames: [CaptureSheet: CGRect]
    func path(in rect: CGRect) -> Path {
        var path = Path(rect)
        for frame in frames.values where frame.width > 0 && frame.height > 0 {
            path.addRect(frame)
        }
        return path
    }
}
