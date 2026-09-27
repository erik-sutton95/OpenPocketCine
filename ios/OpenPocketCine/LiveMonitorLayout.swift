import MonitorPresentation
import OpenPocketViewCore
import SwiftUI
import UIKit

/// Live chrome frames in CGRect space, built from the core `FieldMonitorLayout`
/// by ``fieldMonitor(size:safeArea:sourceAspect:fill:showsValues:showsBottomBars:topControlInset:)``.
struct LiveMonitorLayout: Equatable {
    var presentation: FieldMonitorLayout? = nil
    var viewport: CGSize
    /// Cinema 16:9 well — lock, deck, rail, and bottom bars stay on this even
    /// when the Pocket screen is flipped to a 9:16 picture.
    var feed: CGRect
    /// Displayed raster. Matches `feed` for 16:9; a centered pillarbox when the
    /// camera is vertical. Assists sit here. Zoom and the gimbal stick stay on
    /// `feed` so a Pocket screen flip does not walk them with the picture.
    var picture: CGRect
    var lock: CGRect
    var battery: CGRect
    var topDeck: CGRect
    var assist: CGRect
    var capture: CGRect
    var rail: CGRect
    var settings: CGRect
    var media: CGRect
    var record: CGRect
    var disp: CGRect
    var isWidthConstrained: Bool
    /// False in DISP 2 when the tool / capture strips are off — on-feed chrome
    /// can sit in that corner.
    var showsBottomBars: Bool
    /// Device insets in canvas space (island / home indicator). Used to clamp popups.
    var safeArea: EdgeInsets = EdgeInsets()

    /// Physical canvas for chrome. A portrait `GeometryReader` inside the safe
    /// area matches the screen *width*, so a width-only full-bleed test used to
    /// keep the short height and leave a dead band under the system bar.
    static func canvasSize(
        layoutSize: CGSize,
        safeArea: EdgeInsets,
        screenSize: CGSize?
    ) -> CGSize {
        let restored = CGSize(
            width: layoutSize.width + safeArea.leading + safeArea.trailing,
            height: layoutSize.height + safeArea.top + safeArea.bottom
        )
        guard let screen = screenSize, screen.width > 1, screen.height > 1 else {
            return restored
        }
        let matchesScreen =
            abs(layoutSize.width - screen.width) < 1
            && abs(layoutSize.height - screen.height) < 1
        if matchesScreen { return layoutSize }
        return CGSize(
            width: max(restored.width, screen.width),
            height: max(restored.height, screen.height)
        )
    }

    /// Prefer the larger of SwiftUI's report and the window insets. A parent
    /// `ignoresSafeArea` (or a GeometryReader that is already inset) can report 0.
    static func resolvedSafeArea(_ reported: EdgeInsets, scene: EdgeInsets) -> EdgeInsets {
        EdgeInsets(
            top: max(reported.top, scene.top),
            leading: max(reported.leading, scene.leading),
            bottom: max(reported.bottom, scene.bottom),
            trailing: max(reported.trailing, scene.trailing)
        )
    }

    static func shouldMirror(
        leading: CGFloat, trailing: CGFloat,
        orientation: MonitorDeviceOrientation? = nil
    ) -> Bool {
        let safe = MonitorEdgeInsets(
            top: 0, leading: Double(leading), bottom: 0, trailing: Double(trailing))
        return MonitorHorizontalLayoutDirection.resolve(
            deviceOrientation: orientation ?? monitorDeviceOrientation(),
            safeArea: safe) == .mirrored
    }

    /// UIKit interface landscape values are opposite the physical device orientation.
    static func monitorDeviceOrientation() -> MonitorDeviceOrientation {
        switch deviceOrientation() {
        case .portrait: .portrait
        case .portraitUpsideDown: .portraitUpsideDown
        case .landscapeLeft: .landscapeRight
        case .landscapeRight: .landscapeLeft
        case .unknown: .unknown
        @unknown default: .unknown
        }
    }

    private static func deviceOrientation() -> UIInterfaceOrientation {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        return scene?.interfaceOrientation ?? .unknown
    }
}

/// Rebuilds the live shell when the phone rolls landscape-left ↔ landscape-right.
/// Those two orientations share a size, so GeometryReader does not invalidate.
@MainActor
@Observable
final class InterfaceOrientationObserver {
    private(set) var orientation = LiveMonitorLayout.monitorDeviceOrientation()
    @ObservationIgnored private let notificationCenter: NotificationCenter
    @ObservationIgnored private var geometryObservation: NSKeyValueObservation?
    @ObservationIgnored private var deviceObserver: (any NSObjectProtocol)?
    @ObservationIgnored private var isObserving = false

    init(notificationCenter: NotificationCenter = .default) {
        self.notificationCenter = notificationCenter
    }

    deinit {
        geometryObservation?.invalidate()
        if let deviceObserver { notificationCenter.removeObserver(deviceObserver) }
        if isObserving {
            Task { @MainActor in UIDevice.current.endGeneratingDeviceOrientationNotifications() }
        }
    }

    func start() {
        refresh()
        // A scene is not guaranteed during launch or an app transition. The
        // notification subscription is still live when there is no KVO token.
        guard !isObserving else { return }
        isObserving = true
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        geometryObservation = scene?.observe(\.effectiveGeometry, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        deviceObserver = notificationCenter.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    func stop() {
        guard isObserving else { return }
        isObserving = false
        geometryObservation?.invalidate()
        geometryObservation = nil
        if let deviceObserver { notificationCenter.removeObserver(deviceObserver) }
        deviceObserver = nil
        UIDevice.current.endGeneratingDeviceOrientationNotifications()
    }

    private func refresh() {
        let current = LiveMonitorLayout.monitorDeviceOrientation()
        guard current != orientation else { return }
        orientation = current
    }
}

extension LiveMonitorLayout {
    /// On-feed raster. Assists and the pinch well sit here.
    /// The gimbal cluster (zoom + stick) uses the cinema `feed` well so a
    /// vertical Pocket picture does not drag it inward with the pillarbox.
    var onFeed: CGRect { picture.width > 1 ? picture : feed }

    /// Stick + zoom (+ gimbal-controls button beside zoom). Trailing-bottom of
    /// the cinema well — not glued to record. Same cluster in every orientation.
    func gimbalCluster(showGimbalButton: Bool = false) -> GimbalCluster {
        if let presentation {
            var cluster = GimbalCluster.inTrailingBottom(
                well: MonitorLayoutRegion(
                    x: 0, y: 0, width: viewport.width, height: viewport.height),
                floorY: viewport.height, canvasMaxY: viewport.height)
            cluster.stick = presentation.stick.coreRegion
            cluster.zoom = presentation.zoom.coreRegion
            cluster.controls =
                showGimbalButton
                ? presentation.gimbal.coreRegion
                : MonitorLayoutRegion(x: 0, y: 0, width: 0, height: 0)
            return cluster
        }
        let inset = Double(LiveChromeMetrics.gimbalStickInset)
        let gap = Double(LiveChromeMetrics.gimbalStickGap)
        var barTop = Double.greatestFiniteMagnitude
        if showsBottomBars {
            if assist.height > 1 { barTop = min(barTop, Double(assist.minY)) }
            if capture.height > 1 { barTop = min(barTop, Double(capture.minY)) }
        }
        let well = MonitorLayoutRegion(
            x: Double(feed.minX), y: Double(feed.minY),
            width: Double(feed.width), height: Double(feed.height))
        let floorY =
            barTop < Double.greatestFiniteMagnitude
            ? min(Double(feed.maxY) - inset, barTop - gap)
            : Double(feed.maxY) - inset
        let avoid =
            record.width > 1
            ? MonitorLayoutRegion(
                x: Double(record.minX), y: Double(record.minY),
                width: Double(record.width), height: Double(record.height))
            : nil
        return GimbalCluster.inTrailingBottom(
            well: well,
            floorY: floorY,
            canvasMaxY: Double(viewport.height - max(0, safeArea.bottom)),
            avoid: avoid,
            stickSize: Double(LiveChromeMetrics.gimbalStickSize),
            zoomSize: Double(LiveChromeMetrics.zoomButtonSize),
            gap: gap,
            inset: inset,
            showGimbalButton: showGimbalButton
        )
    }

    var zoomButton: CGRect { Self.cgRect(gimbalCluster().zoom) }

    var gimbalStick: CGRect { Self.cgRect(gimbalCluster().stick) }

    func gimbalButton(showGimbalButton: Bool) -> CGRect {
        Self.cgRect(gimbalCluster(showGimbalButton: showGimbalButton).controls)
    }

    /// Compass Head Lock, trailing-aligned above the stick/zoom cluster.
    var gimbalCalibrate: CGRect {
        if let presentation { return presentation.headTrack.cgRect }
        return Self.cgRect(gimbalCluster().headTrack)
    }

    private static func cgRect(_ region: MonitorLayoutRegion) -> CGRect {
        CGRect(x: region.x, y: region.y, width: region.width, height: region.height)
    }

    /// OpenZCine recenter key. Landscape: just past the battery, toward the feed,
    /// above the assist bar. Portrait: bottom-right of the feed.
    var focusReset: CGRect {
        if let presentation { return presentation.focusReset.cgRect }
        let size = LiveChromeMetrics.focusResetSize
        if viewport.height > viewport.width {
            let well = onFeed
            return CGRect(
                x: well.maxX - size - 10,
                y: well.maxY - size - 10,
                width: size,
                height: size
            )
        }
        let towardFeed =
            battery.midX < feed.midX
            ? battery.maxX + LiveChromeMetrics.focusResetGap
            : battery.minX - LiveChromeMetrics.focusResetGap
        let baseY = (assist.height > 1 ? assist.minY : viewport.height) - 30
        return CGRect(
            x: towardFeed - size / 2,
            y: baseY - size / 2,
            width: size,
            height: size
        )
    }

    /// WAVE/HISTO/VECTOR well: feed top down to just above the assist strip.
    /// This rectangle covers `zoomButton`. It must not steal hits.
    var assistOverlay: CGRect {
        let well = onFeed
        let height = max(0, assist.minY - well.minY - 8)
        return CGRect(x: well.minX, y: well.minY, width: well.width, height: height)
    }
}

/// OpenZCine live-view popup geometry (`PanelHost.topPickerBody` / `bottomPickerBody` /
/// `AssistOptionsPopupAnchor`): a glass card 8pt below a top chip or 10pt above a bottom
/// bar, clamped into the safe viewport — never a full-bleed or centred sheet.
///
/// Height is the measured `GlassPanel` / `PickerPanel` / `AssistPanel` (header +
/// drum or rows + optional mode bar + padding). `Box.maxHeight` is only the
/// remaining well above the bar — not a shared card size.
enum LivePopupPlacement {
    struct Box: Equatable {
        var x: CGFloat
        var y: CGFloat
        var width: CGFloat
        var maxHeight: CGFloat

        var origin: CGPoint { CGPoint(x: x, y: y) }
    }

    static let edgeMargin: CGFloat = 8
    static let cutoutClearance: CGFloat = 4
    static let assistTopInset: CGFloat = 4

    static func horizontalBand(
        preferredWidth: CGFloat,
        viewportWidth: CGFloat,
        safeLeading: CGFloat,
        safeTrailing: CGFloat,
        margin: CGFloat
    ) -> (minX: CGFloat, maxX: CGFloat, width: CGFloat) {
        let minX = max(margin, safeLeading + cutoutClearance)
        let maxX = viewportWidth - max(margin, safeTrailing + cutoutClearance)
        let width = max(0, min(preferredWidth, maxX - minX))
        return (minX, maxX, width)
    }

    static func leadingX(desired: CGFloat, width: CGFloat, minX: CGFloat, maxX: CGFloat) -> CGFloat
    {
        min(max(desired, minX), max(minX, maxX - width))
    }

    /// Field Monitor top category drum. A missing cell uses the viewport center;
    /// the physical safe-area band always wins over the preferred card width.
    static func topPicker(
        cell: CGRect,
        panelHeight: CGFloat,
        viewport: CGSize,
        safeArea: EdgeInsets,
        floorY: CGFloat? = nil,
        preferredWidth: CGFloat? = nil,
        gap: CGFloat = LiveChromeMetrics.topPickerGap
    ) -> Box {
        let band = horizontalBand(
            preferredWidth: preferredWidth
                ?? (min(viewport.width, viewport.height) >= 600 ? 620 : 480),
            viewportWidth: viewport.width,
            safeLeading: safeArea.leading,
            safeTrailing: safeArea.trailing,
            margin: edgeMargin
        )
        let hasCell = cell.width > 1 && cell.height > 1
        let x = leadingX(
            desired: hasCell ? cell.midX - band.width / 2 : (viewport.width - band.width) / 2,
            width: band.width,
            minX: band.minX,
            maxX: band.maxX
        )
        let minY = max(
            edgeMargin,
            safeArea.top + LiveChromeMetrics.chromeTop + edgeMargin
        )
        let floor = floorY ?? (viewport.height - max(edgeMargin, safeArea.bottom))
        let desiredTop = hasCell ? cell.maxY + gap : minY
        let height = min(max(0, panelHeight), max(0, floor - minY))
        let y = max(minY, min(desiredTop, floor - height))
        return Box(x: x, y: y, width: band.width, maxHeight: max(0, floor - y))
    }
}

extension View {
    /// OpenZCine `monitorModuleFrame` — viewport-absolute placement.
    func liveModuleFrame(_ rect: CGRect, alignment: Alignment = .center) -> some View {
        self
            .frame(width: rect.width, height: rect.height, alignment: alignment)
            .position(x: rect.midX, y: rect.midY)
    }
}

// The compatibility layout keeps existing scope/popup interfaces stable while
// live chrome consumes the brand-neutral engine geometry.
extension LiveMonitorLayout {
    static func fieldMonitor(
        size: CGSize, safeArea: EdgeInsets, sourceAspect: CGFloat,
        fill: Bool, showsValues: Bool, showsBottomBars: Bool,
        topControlInset: CGFloat = 0, joystick: MonitorJoystickSize = .medium
    ) -> Self {
        let p = FieldMonitorLayout(
            width: size.width, height: size.height,
            safeArea: MonitorSafeArea(
                top: safeArea.top, leading: safeArea.leading,
                bottom: safeArea.bottom, trailing: safeArea.trailing),
            sourceAspect: sourceAspect, fill: fill, showsValues: showsValues,
            topControlInset: topControlInset, joystick: joystick)
        return Self(
            presentation: p, viewport: size, feed: p.picture.cgRect, picture: p.picture.cgRect,
            lock: p.lock.cgRect, battery: p.gauges.cgRect, topDeck: p.status.cgRect,
            assist: p.assists.cgRect, capture: p.values.cgRect,
            rail: p.system.cgRect, settings: p.settings.cgRect, media: p.media.cgRect,
            record: p.record.cgRect, disp: p.display.cgRect,
            isWidthConstrained: !p.tablet && size.width < 740,
            showsBottomBars: showsBottomBars, safeArea: safeArea)
    }
}

extension MonitorRect {
    var cgRect: CGRect { CGRect(x: x, y: y, width: width, height: height) }
    var coreRegion: MonitorLayoutRegion {
        MonitorLayoutRegion(x: x, y: y, width: width, height: height)
    }
}
