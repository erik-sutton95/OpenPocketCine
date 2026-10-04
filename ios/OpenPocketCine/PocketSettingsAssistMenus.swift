import MonitorPresentation
import MonitorUI
import OpenCineMedia
import OpenPocketViewCore
import SwiftUI

/// Settings supplies local values and actions to the common tool menus.
/// Stored option identities and the monitor source's calibration stay app-owned.
@MainActor enum PocketSettingsAssistMenus {
    static func feedback() {
        OperatorSettingsHaptics.selection(enabled: OperatorPrefs.hapticsEnabled)
    }

    static func doubleFeedback() {
        feedback()
        feedback()
    }

    static func falseColor(
        assist: LiveAssistState, compact: Bool, transfer: MonitorTransfer, clipByte: Int
    ) -> MonitorFalseColorMenu<FalseColorScaleKind> {
        MonitorFalseColorMenu(
            scales: FalseColorAssist.scaleOptions.map { FalseColorAssist.scale(forMenuLabel: $0) },
            scale: Binding(
                get: { assist.falseColorScale },
                set: {
                    assist.falseColorScale = $0
                    assist.persist()
                }),
            referenceEnabled: Binding(
                get: { assist.falseColorReference },
                set: {
                    assist.falseColorReference = $0
                    assist.persist()
                }),
            read709: Binding(
                get: { assist.falseColorRec709 },
                set: {
                    assist.falseColorRec709 = $0
                    assist.persist()
                }),
            reference: referenceValues(
                scale: assist.falseColorScale, transfer: transfer,
                rec709: assist.falseColorRec709, clipByte: clipByte),
            title: { FalseColorAssist.menuLabel(for: $0) },
            scaleHelp: FalseColorAssist.scaleHelp, readHelp: FalseColorAssist.readHelp,
            referenceHelp: FalseColorAssist.referenceHelp, compact: compact,
            selectionFeedback: feedback, readFeedback: doubleFeedback,
            referenceFeedback: doubleFeedback, onReferenceEnabled: { assist.falseColor = true })
    }

    private static func referenceValues(
        scale: FalseColorScaleKind, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> MonitorFalseColorReferenceValues {
        let segments = FalseColorReference.segments(
            scale: scale, transfer: transfer, rec709: rec709, clipByte: clipByte)
        let markers =
            scale == .sceneStops
            ? FalseColorReference.sceneStopMarkers(
                transfer: transfer, rec709: rec709, clipByte: clipByte) : []
        return MonitorFalseColorReferenceValues(
            subtitle: scale.referenceScaleLabel + " · "
                + FalseColorReference.curveKeyLabel(
                    DJILook.readsThroughLook(transfer: transfer, rec709: rec709)
                        ? .rec709 : transfer),
            segments: segments.map {
                .init(
                    id: $0.id, lowerFraction: $0.lowerFraction, upperFraction: $0.upperFraction,
                    red: $0.band.red, green: $0.band.green, blue: $0.band.blue)
            },
            markers: markers.map { .init(id: $0.id, label: $0.label, fraction: $0.fraction) },
            axisLabels: FalseColorReference.axisLabels(scale: scale))
    }

    static func common(_ value: PeakingAssist.Color) -> MonitorPeakingColor {
        switch value {
        case .white: .white
        case .blue: .blue
        case .red: .red
        case .green: .green
        }
    }

    static func local(_ value: MonitorPeakingColor) -> PeakingAssist.Color {
        switch value {
        case .white: .white
        case .blue: .blue
        case .red: .red
        case .green: .green
        }
    }

    static func common(_ value: PeakingAssist.Sensitivity) -> MonitorPeakingSense {
        switch value {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }

    static func local(_ value: MonitorPeakingSense) -> PeakingAssist.Sensitivity {
        switch value {
        case .low: .low
        case .medium: .medium
        case .high: .high
        }
    }

    static func common(_ value: VectorscopeAssist.Zoom) -> MonitorVectorscopeZoom {
        switch value {
        case .x1: .x1
        case .x2: .x2
        case .x4: .x4
        }
    }

    static func local(_ value: MonitorVectorscopeZoom) -> VectorscopeAssist.Zoom {
        switch value {
        case .x1: .x1
        case .x2: .x2
        case .x4: .x4
        }
    }

    static func common(_ value: HistogramAssist.CrushClipCompensation)
        -> MonitorCrushClipCompensation
    {
        switch value {
        case .zero: .zero
        case .quarter: .quarter
        case .half: .half
        case .threeQuarter: .threeQuarter
        case .one: .one
        }
    }

    static func histogram(_ value: MonitorCrushClipCompensation)
        -> HistogramAssist.CrushClipCompensation
    {
        switch value {
        case .zero: .zero
        case .quarter: .quarter
        case .half: .half
        case .threeQuarter: .threeQuarter
        case .one: .one
        }
    }

    static func commonTraffic(_ value: TrafficLightsAssist.CrushClipCompensation)
        -> MonitorCrushClipCompensation
    {
        switch value {
        case .zero: .zero
        case .quarter: .quarter
        case .half: .half
        case .threeQuarter: .threeQuarter
        case .one: .one
        }
    }

    static func trafficLights(_ value: MonitorCrushClipCompensation)
        -> TrafficLightsAssist.CrushClipCompensation
    {
        switch value {
        case .zero: .zero
        case .quarter: .quarter
        case .half: .half
        case .threeQuarter: .threeQuarter
        case .one: .one
        }
    }
}

extension ZebraLongPressMenu {
    @MainActor func commonMenu(transfer: MonitorTransfer, clipByte: Int)
        -> MonitorZebraMenu<ZebraAssist.Unit, ZebraAssist.StripeColor>
    {
        func zone(
            enabled: Binding<Bool>, threshold: Binding<Double>,
            paint: Binding<ZebraAssist.StripeColor>,
            palette: [ZebraAssist.StripeColor]
        ) -> MonitorZebraZone<ZebraAssist.StripeColor> {
            .init(
                enabled: enabled,
                threshold: Binding(
                    get: { threshold.wrappedValue },
                    set: {
                        threshold.wrappedValue = min(100, max(0, $0))
                    }),
                displayValue: options.displayValue(
                    for: threshold.wrappedValue, transfer: transfer, clipByte: clipByte),
                colors: palette.map { .init(value: $0, title: $0.rawValue, color: $0.swatch) },
                paint: paint)
        }
        return MonitorZebraMenu(
            units: ZebraAssist.Unit.allCases, unit: $options.unit, title: { $0.editorLabel },
            unitsTitle: ZebraAssist.unitsTitle, unitsHelp: ZebraAssist.unitsHelp,
            highlightHelp: ZebraAssist.highlightHelp, midtoneHelp: ZebraAssist.midtoneHelp,
            highlight: zone(
                enabled: $options.highlightEnabled, threshold: $options.highlightIRE,
                paint: $options.highlightColor, palette: ZebraAssist.highlightPalette),
            midtone: zone(
                enabled: $options.midtoneEnabled, threshold: $options.midtoneIRE,
                paint: $options.midtoneColor, palette: ZebraAssist.midtonePalette),
            compact: compact, selectionFeedback: PocketSettingsAssistMenus.feedback,
            toggleFeedback: PocketSettingsAssistMenus.doubleFeedback)
    }
}

extension WaveformLongPressMenu {
    @MainActor var commonMenu: MonitorScopeTraceMenu<WaveformAssist.Mode> {
        MonitorScopeTraceMenu(
            modes: WaveformAssist.Mode.allCases, mode: $options.mode,
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = WaveformAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    PocketSettingsAssistMenus.feedback()
                    options.brightness = next
                }),
            guides: Binding(
                get: {
                    .init(
                        clip: options.guides.clip, crush: options.guides.crush,
                        middle: options.guides.middle)
                },
                set: {
                    PocketSettingsAssistMenus.feedback()
                    options.guides = .init(clip: $0.clip, crush: $0.crush, middle: $0.middle)
                }),
            title: { $0.rawValue }, brightnessHelp: WaveformAssist.brightnessHelp,
            brightnessRange: WaveformAssist.brightnessRange, compact: compact,
            modeFeedback: PocketSettingsAssistMenus.feedback,
            guideFeedback: PocketSettingsAssistMenus.feedback)
    }
}

extension ParadeLongPressMenu {
    @MainActor var commonMenu: MonitorScopeTraceMenu<ParadeAssist.Mode> {
        MonitorScopeTraceMenu(
            modes: ParadeAssist.Mode.allCases, mode: $options.mode,
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = ParadeAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    PocketSettingsAssistMenus.feedback()
                    options.brightness = next
                }),
            guides: Binding(
                get: {
                    .init(
                        clip: options.guides.clip, crush: options.guides.crush,
                        middle: options.guides.middle)
                },
                set: {
                    PocketSettingsAssistMenus.feedback()
                    options.guides = .init(clip: $0.clip, crush: $0.crush, middle: $0.middle)
                }),
            title: { $0.rawValue }, brightnessHelp: ParadeAssist.brightnessHelp,
            brightnessRange: ParadeAssist.brightnessRange, compact: compact,
            modeFeedback: PocketSettingsAssistMenus.feedback,
            guideFeedback: PocketSettingsAssistMenus.feedback)
    }
}

extension HistogramLongPressMenu {
    @MainActor var commonMenu: MonitorHistogramMenu {
        MonitorHistogramMenu(
            trafficLights: $options.trafficLights,
            compensation: Binding(
                get: {
                    PocketSettingsAssistMenus.common(options.crushClipCompensation)
                },
                set: {
                    let next = PocketSettingsAssistMenus.histogram($0)
                    guard next != options.crushClipCompensation else { return }
                    PocketSettingsAssistMenus.feedback()
                    options.crushClipCompensation = next
                }),
            trafficHelp: HistogramAssist.trafficLightsHelp,
            compensationHelp: HistogramAssist.compensationHelp, compact: compact,
            trafficFeedback: PocketSettingsAssistMenus.doubleFeedback)
    }
}

extension VectorscopeLongPressMenu {
    @MainActor var commonMenu: MonitorVectorscopeMenu {
        MonitorVectorscopeMenu(
            zoom: Binding(
                get: { PocketSettingsAssistMenus.common(options.zoom) },
                set: {
                    let next = PocketSettingsAssistMenus.local($0)
                    guard next != options.zoom else { return }
                    PocketSettingsAssistMenus.feedback()
                    options.zoom = next
                }),
            brightness: Binding(
                get: { options.brightness },
                set: {
                    let next = VectorscopeAssist.Options.clampedBrightness($0)
                    guard next != options.brightness else { return }
                    PocketSettingsAssistMenus.feedback()
                    options.brightness = next
                }),
            zoomHelp:
                "Magnifies only the chroma trace; the graticule stays at unity. The vectorscope reads the monitor image (your active LUT, or the built-in display tone map), where chroma is meaningful.",
            brightnessHelp: "Raise trace intensity when the chroma plot is hard to read.",
            brightnessRange: VectorscopeAssist.brightnessRange, compact: compact,
            zoomFeedback: PocketSettingsAssistMenus.feedback)
    }
}

extension PeakingLongPressMenu {
    @MainActor var commonMenu: MonitorPeakingMenu {
        MonitorPeakingMenu(
            options: Binding(
                get: {
                    .init(
                        color: PocketSettingsAssistMenus.common(options.color),
                        sensitivity: PocketSettingsAssistMenus.common(options.sensitivity))
                },
                set: {
                    options = .init(
                        color: PocketSettingsAssistMenus.local($0.color),
                        sensitivity: PocketSettingsAssistMenus.local($0.sensitivity))
                }),
            colors: PeakingAssist.palette.map {
                .init(
                    value: PocketSettingsAssistMenus.common($0), title: $0.rawValue,
                    color: $0.swatch)
            },
            sensitivityHelp: PeakingAssist.sensitivityHelp, colorHelp: PeakingAssist.colorHelp,
            compact: compact, feedback: PocketSettingsAssistMenus.feedback)
    }
}

extension TrafficLightsLongPressMenu {
    @MainActor var commonMenu: MonitorCrushClipMenu {
        MonitorCrushClipMenu(
            compensation: Binding(
                get: {
                    PocketSettingsAssistMenus.commonTraffic(TrafficLightsAssist.sharedCompensation())
                },
                set: {
                    let next = PocketSettingsAssistMenus.trafficLights($0)
                    guard next != TrafficLightsAssist.sharedCompensation() else { return }
                    PocketSettingsAssistMenus.feedback()
                    TrafficLightsAssist.setSharedCompensation(next)
                    assist.crushClipCompensation = next
                    assist.persist()
                    TrafficLightsAssist.store.persist()
                }),
            help: TrafficLightsAssist.compensationHelp, compact: compact, showTopDivider: false)
    }
}
