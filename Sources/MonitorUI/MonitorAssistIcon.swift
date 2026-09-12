#if os(iOS)
    import SwiftUI

    /// Exact view-assist artwork from the approved Field Monitor prototype. These
    /// deliberately form a separate catalog from the surrounding Lucide UI.
    public enum MonitorAssistIcon: String, CaseIterable, View {
        case lut
        case peaking
        case falseColor = "false-color"
        case zebra
        case waveform
        case rgbParade = "rgb-parade"
        case histogram
        case vectorscope
        case trafficLights = "traffic-lights"
        case frameGuide = "frame-guide"
        case grid
        case crosshair
        case mirror
        case audioMeters = "audio-meters"

        public var body: some View {
            Canvas { context, size in
                Self.documents[self]?.draw(in: &context, size: size, filled: false)
            }
            .aspectRatio(1, contentMode: .fit)
            .accessibilityHidden(true)
        }

        // All 14 authoritative glyphs are single paths, fill="none", opacity 1,
        // stroke="currentColor", stroke-width="2", round caps and joins. Loading
        // the SVG retains the prototype's exact geometry and stroke treatment.
        // Parsing occurs once per catalog, never during an animation or feed tick.
        @MainActor static let documents: [Self: LucideSVGDocument] = Dictionary(
            uniqueKeysWithValues: allCases.compactMap { icon in
                let stem = "monitor-assist-" + icon.rawValue
                guard
                    let url = Bundle.module.url(
                        forResource: stem, withExtension: "svg", subdirectory: "Icons/assist"),
                    let xml = try? String(contentsOf: url, encoding: .utf8),
                    let document = LucideSVGDocument(xml: xml)
                else { return nil }
                return (icon, document)
            })
    }
#endif
