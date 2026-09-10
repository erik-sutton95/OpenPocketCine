import OpenPocketViewCore
import SwiftUI

/// Live-picture ND meter. Suggestion only — the app cannot set a screw-on filter.
enum NDAssist {
    static let panelID = "nd-meter"
    static let baseSize = CGSize(width: 88, height: 92)
    static let meterTitle = "ND"
    static let accessibilityTitle = "ND Suggestion"
    static let helpCopy =
        "Meters the live picture against middle gray and suggests a screw-on ND — stops and ND number — to balance it. The app cannot set a filter."

    static func longPressMenu(assist _: LiveAssistState) -> some View {
        Text(helpCopy)
            .font(LiveType.ui(size: 13))
            .foregroundStyle(LiveDesign.muted)
            .fixedSize(horizontal: false, vertical: true)
    }

    static func defaultCenter(
        feed: CGRect, size: CGSize, bounds: CGRect, chromeClearance: EdgeInsets, gap: CGFloat = 10
    ) -> CGPoint {
        let halfWidth = size.width / 2
        let halfHeight = size.height / 2
        let x = feed.maxX - halfWidth
        let outside = feed.maxY + gap + halfHeight
        let y: CGFloat
        if outside + halfHeight <= bounds.maxY {
            y = outside
        } else {
            y = min(feed.maxY, bounds.maxY - chromeClearance.bottom) - gap - halfHeight
        }
        return TrafficLightsAssist.clamp(CGPoint(x: x, y: y), size: size, in: bounds)
    }

    static func reading(from bundle: ScopeAssistBundle) -> NDFilterSuggestion? {
        NDFilterRecommendation.reading(
            lumaHistogram: bundle.samples.histogramLuma, transfer: bundle.transfer)
    }
}

struct NDMeterOverlay: View {
    @Environment(AppModel.self) private var model
    var bounds: CGRect
    var feed: CGRect
    var chromeClearance: EdgeInsets

    var body: some View {
        let size = NDAssist.baseSize
        let center = NDAssist.defaultCenter(
            feed: feed, size: size, bounds: bounds, chromeClearance: chromeClearance)
        NDMeterPlate(reading: NDAssist.reading(from: model.frameSamples.displayBundle))
            .frame(width: size.width, height: size.height)
            .position(center)
            .allowsHitTesting(false)
    }
}

struct NDMeterPlate: View {
    var reading: NDFilterSuggestion?

    var body: some View {
        VStack(spacing: 4) {
            Text(NDAssist.meterTitle)
                .font(.system(size: 8.5, weight: .bold, design: .monospaced))
                .foregroundStyle(LiveDesign.text.opacity(0.58))
            Text(reading?.ndLabel ?? "—")
                .font(LiveType.ui(size: 20, weight: .heavy, design: .default))
                .foregroundStyle(LiveDesign.text)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(reading?.stopsLabel ?? "—")
                .font(.system(size: 13, weight: .semibold, design: .monospaced))
                .foregroundStyle(reading?.needsGlass == true ? LiveDesign.accent : LiveDesign.muted)
                .lineLimit(1)
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(ScopePalette.panelFill)
        .clipShape(RoundedRectangle(cornerRadius: LiveDesign.cornerRadius, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                .stroke(LiveDesign.hairline, lineWidth: 1)
        )
        .shadow(color: .black.opacity(0.34), radius: 16, x: 0, y: 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(NDAssist.accessibilityTitle)
        .accessibilityValue(accessibilityValue)
    }

    private var accessibilityValue: String {
        guard let reading else { return "waiting for picture" }
        if reading.needsGlass {
            return "\(reading.ndLabel), \(reading.stopsLabel) stops over middle gray"
        }
        return "\(reading.stopsLabel) stops, no ND"
    }
}
