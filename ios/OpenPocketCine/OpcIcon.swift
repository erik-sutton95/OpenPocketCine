import SwiftUI

/// Shared Lucide HUD catalog. Names match `Resources/Icons/lucide/*.svg`.
///
/// Drop another official Lucide SVG in that folder, add a case, and both shells
/// can resolve it. Do not add a JS runtime.
enum OpcIcon: String, CaseIterable, View {
    case aperture
    case audioLines = "audio-lines"
    case audioWaveform = "audio-waveform"
    case blend
    case camera
    case chartColumn = "chart-column"
    case check
    case chevronDown = "chevron-down"
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case chevronUp = "chevron-up"
    case chevronsUpDown = "chevrons-up-down"
    case circle
    case circleCheck = "circle-check"
    case circlePlay = "circle-play"
    case circlePlus = "circle-plus"
    case contrast
    case copy
    case crosshair
    case download
    case ellipsis
    case eye
    case eyeOff = "eye-off"
    case film
    case flipHorizontal2 = "flip-horizontal-2"
    case folder
    case focus
    case funnel
    case grid3x3 = "grid-3x3"
    case image
    case info
    case layers
    case layoutGrid = "layout-grid"
    case layoutList = "layout-list"
    case listFilter = "list-filter"
    case lock
    case maximize
    case minimize
    case monitor
    case mountain
    case palette
    case pause
    case pencil
    case play
    case plus
    case radio
    case refreshCw = "refresh-cw"
    case rotateCw = "rotate-cw"
    case scan
    case settings
    case share
    case signal
    case skipBack = "skip-back"
    case skipForward = "skip-forward"
    case slidersHorizontal = "sliders-horizontal"
    case slidersVertical = "sliders-vertical"
    case smartphone
    case square
    case squareDashed = "square-dashed"
    case star
    case sun
    case thermometer
    case timer
    case trash
    case unplug
    case upload
    case video
    case volume2 = "volume-2"
    case volumeX = "volume-x"
    case wifi
    case wifiOff = "wifi-off"
    case x
    case zap
    case zoomIn = "zoom-in"

    /// Lucide file stem (`lock.svg` → `"lock"`).
    var lucideName: String { rawValue }

    var body: some View {
        LucideIconView(name: rawValue)
    }

    func view(filled: Bool = false) -> LucideIconView {
        LucideIconView(name: rawValue, filled: filled)
    }
}

/// Stroke (and optional fill) renderer for a bundled Lucide SVG.
struct LucideIconView: View {
    var name: String
    var filled: Bool = false

    var body: some View {
        Canvas { context, size in
            guard let document = LucideSVGCache.document(named: name) else { return }
            document.draw(in: &context, size: size, filled: filled)
        }
        .aspectRatio(1, contentMode: .fit)
        .accessibilityHidden(true)
    }
}
