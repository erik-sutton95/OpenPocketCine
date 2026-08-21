import SwiftUI

/// Shared Lucide HUD catalog. Names match `Resources/Icons/lucide/*.svg`.
///
/// Drop another official Lucide SVG in that folder, add a case, and both shells
/// can resolve it. Do not add a JS runtime.
enum OpcIcon: String, CaseIterable, View {
    case camera
    case chevronLeft = "chevron-left"
    case chevronRight = "chevron-right"
    case contrast
    case crosshair
    case grid3x3 = "grid-3x3"
    case layers
    case lock
    case pause
    case play
    case settings
    case share
    case star
    case trash
    case video
    case x
    case zap

    /// Lucide file stem (`lock.svg` → `"lock"`).
    var lucideName: String { rawValue }

    var body: some View {
        LucideIconView(name: rawValue)
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
