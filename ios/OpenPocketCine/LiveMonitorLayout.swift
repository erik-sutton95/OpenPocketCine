import OpenPocketViewCore
import SwiftUI
import UIKit

/// OpenZCine `MonitorLiveViewModuleLayout.fit` + `MonitorSideRailControlLayout.fit` for Pocket.
/// Chrome uses **fixed** insets (`MonitorChromeLayout.insets` with zero safe area): 14 / 16 / 12 / 18.
/// The feed is an explicit 16:9 **full-height** well, leading-shifted for the island — not a
/// `resizeAspect`-centered island that then hosts chrome.
struct LiveMonitorLayout: Equatable {
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

    /// 874×402 Dynamic Island leading 59: feed.maxX ≈ 773.7, rail.x ≈ 782.4, record center ≈ (823.8, 202).
    static func fit(
        viewportWidth: CGFloat,
        viewportHeight: CGFloat,
        safeLeading: CGFloat,
        safeTrailing: CGFloat,
        showsBottomBars: Bool,
        mirrored: Bool = false,
        feedAspect: CGFloat = LiveChromeMetrics.feedAspect,
        pictureAspect: CGFloat? = nil
    ) -> LiveMonitorLayout {
        let viewport = CGSize(width: max(0, viewportWidth), height: max(0, viewportHeight))
        let cinemaAspect = LiveChromeMetrics.feedAspect
        let constrained = isWidthConstrained(viewport: viewport, feedAspect: cinemaAspect)
        let chrome = chromeRect(in: viewport)
        let bottomBarHeight = showsBottomBars ? LiveDesign.controlHeight : 0
        let feed = feedFrame(
            viewport: viewport,
            safeLeading: safeLeading,
            safeTrailing: safeTrailing,
            feedAspect: cinemaAspect
        )
        let picture = pictureFrame(
            aspect: pictureAspect ?? feedAspect,
            in: feed,
            viewport: viewport,
            safeLeading: safeLeading,
            safeTrailing: safeTrailing
        )
        let lock = lockRect(chrome: chrome)
        let battery = batteryRect(chrome: chrome, lock: lock, constrained: constrained)
        let rail = rightRailRect(viewport: viewport, chrome: chrome, feed: feed)
        let slots =
            constrained
            ? constrainedSlots(viewport: viewport, chrome: chrome, lock: lock)
            : railSlots(rail: rail, bottomBarHeight: bottomBarHeight)
        let bars = bottomBand(viewport: viewport, chrome: chrome, constrained: constrained)
        var layout = LiveMonitorLayout(
            viewport: viewport,
            feed: feed,
            picture: picture,
            lock: lock,
            battery: battery,
            topDeck: .zero,
            assist: bars.assist,
            capture: bars.capture,
            rail: rail,
            settings: slots.settings,
            media: slots.media,
            record: slots.record,
            disp: slots.disp,
            isWidthConstrained: constrained,
            showsBottomBars: showsBottomBars
        )
        if mirrored {
            layout.mirrorHorizontally(in: viewport.width)
        }
        layout.topDeck = topDeckRect(
            feed: layout.feed,
            lock: layout.lock,
            battery: layout.battery,
            rail: layout.rail,
            constrained: constrained
        )
        layout.safeArea = EdgeInsets(
            top: 0, leading: safeLeading, bottom: 0, trailing: safeTrailing)
        return layout
    }

    static func fit(
        layoutSize: CGSize,
        safeArea: EdgeInsets,
        screenSize: CGSize?,
        showsBottomBars: Bool,
        feedAspect: CGFloat = LiveChromeMetrics.feedAspect,
        pictureAspect: CGFloat? = nil,
        orientation: MonitorDeviceOrientation? = nil
    ) -> LiveMonitorLayout {
        let viewport = canvasSize(
            layoutSize: layoutSize, safeArea: safeArea, screenSize: screenSize)
        var layout = fit(
            viewportWidth: viewport.width,
            viewportHeight: viewport.height,
            safeLeading: safeArea.leading,
            safeTrailing: safeArea.trailing,
            showsBottomBars: showsBottomBars,
            mirrored: shouldMirror(
                leading: safeArea.leading, trailing: safeArea.trailing,
                orientation: orientation),
            feedAspect: feedAspect,
            pictureAspect: pictureAspect ?? feedAspect
        )
        layout.safeArea = safeArea
        return layout
    }

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

    static var sceneSize: CGSize? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        let size = scene?.coordinateSpace.bounds.size ?? .zero
        return size.width > 0 ? size : nil
    }

    /// UIKit insets for full-screen panels. SwiftUI `GeometryReader.safeAreaInsets` is 0
    /// after a parent `ignoresSafeArea` — OpenZCine reads the window the same way.
    static var sceneSafeArea: EdgeInsets {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first { $0.activationState == .foregroundInactive }
            ?? scenes.first
        guard let insets = scene?.keyWindow?.safeAreaInsets else { return EdgeInsets() }
        return EdgeInsets(
            top: insets.top, leading: insets.left, bottom: insets.bottom, trailing: insets.right)
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
    @ObservationIgnored private var geometryObservation: NSKeyValueObservation?
    @ObservationIgnored private var deviceObserver: (any NSObjectProtocol)?

    func start() {
        refresh()
        guard geometryObservation == nil else { return }
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        let scene =
            scenes.first { $0.activationState == .foregroundActive }
            ?? scenes.first
        geometryObservation = scene?.observe(\.effectiveGeometry, options: [.new]) {
            [weak self] _, _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
        UIDevice.current.beginGeneratingDeviceOrientationNotifications()
        deviceObserver = NotificationCenter.default.addObserver(
            forName: UIDevice.orientationDidChangeNotification, object: nil, queue: .main
        ) { [weak self] _ in
            Task { @MainActor [weak self] in self?.refresh() }
        }
    }

    private func refresh() {
        let current = LiveMonitorLayout.monitorDeviceOrientation()
        guard current != orientation else { return }
        orientation = current
    }
}

extension LiveMonitorLayout {
    static func isWidthConstrained(
        viewport: CGSize, feedAspect: CGFloat = LiveChromeMetrics.feedAspect
    ) -> Bool {
        viewport.height <= viewport.width
            && viewport.height * feedAspect > viewport.width + 0.5
    }

    static func chromeRect(in viewport: CGSize) -> CGRect {
        CGRect(
            x: LiveChromeMetrics.chromeLeading,
            y: LiveChromeMetrics.chromeTop,
            width: max(
                0,
                viewport.width - LiveChromeMetrics.chromeLeading - LiveChromeMetrics.chromeTrailing),
            height: max(
                0, viewport.height - LiveChromeMetrics.chromeTop - LiveChromeMetrics.chromeBottom)
        )
    }

    static func feedFrame(
        viewport: CGSize,
        safeLeading: CGFloat,
        safeTrailing: CGFloat,
        feedAspect: CGFloat = LiveChromeMetrics.feedAspect
    ) -> CGRect {
        let aspect = feedAspect > 0.2 ? feedAspect : LiveChromeMetrics.feedAspect
        let vw = max(0, viewport.width)
        let vh = max(0, viewport.height)
        if vh > vw {
            return CGRect(x: 0, y: 0, width: vw, height: vw / aspect)
        }
        let width = vh * aspect
        if width > vw + 0.5 {
            let height = vw / aspect
            return CGRect(x: 0, y: (vh - height) / 2, width: vw, height: height)
        }
        let remaining = max(0, vw - width)
        let leadCut = safeLeading >= LiveChromeMetrics.cutoutMinimum ? safeLeading : 0
        let trailCut = safeTrailing >= LiveChromeMetrics.cutoutMinimum ? safeTrailing : 0
        let leadingInset = trailCut > leadCut ? 0 : leadCut
        let x: CGFloat
        if isClassicNotch(leading: safeLeading, trailing: safeTrailing) {
            let available = max(0, remaining - max(0, safeLeading) - max(0, safeTrailing))
            let shift = min(LiveChromeMetrics.classicNotchRailwardShift, available)
            x = min(remaining, safeLeading + shift)
        } else {
            x = min(remaining, leadingInset)
        }
        return CGRect(x: x, y: 0, width: width, height: vh)
    }

    /// Center the displayed raster in the cinema well. A 9:16 Pocket flip
    /// pillarboxes here so the rail — keyed off the 16:9 well — never moves.
    static func pictureFrame(
        aspect: CGFloat,
        in well: CGRect,
        viewport: CGSize,
        safeLeading: CGFloat,
        safeTrailing: CGFloat
    ) -> CGRect {
        let aspect = aspect > 0.2 ? aspect : LiveChromeMetrics.feedAspect
        if well.width < 1 || well.height < 1 { return well }
        if abs(aspect - LiveChromeMetrics.feedAspect) < 0.02 { return well }
        let vw = max(0, viewport.width)
        let vh = max(0, viewport.height)
        guard vh <= vw, vh > 0 else { return well }
        var width = vh * aspect
        var height = vh
        if width > vw + 0.5 {
            width = vw
            height = vw / aspect
        }
        let lead = safeLeading >= LiveChromeMetrics.cutoutMinimum ? safeLeading : 0
        let trail = safeTrailing >= LiveChromeMetrics.cutoutMinimum ? safeTrailing : 0
        let minX = lead
        let maxX = max(minX, vw - trail - width)
        let x = min(max((vw - width) / 2, minX), maxX)
        let y = (vh - height) / 2
        return CGRect(x: x, y: y, width: width, height: height)
    }

    static func isClassicNotch(leading: CGFloat, trailing: CGFloat) -> Bool {
        let minimum = min(max(0, leading), max(0, trailing))
        let maximum = max(max(0, leading), max(0, trailing))
        return minimum >= 40 && maximum <= 50 && abs(leading - trailing) < 4
    }

    private static func lockRect(chrome: CGRect) -> CGRect {
        let size = LiveChromeMetrics.lockButtonSize
        return CGRect(
            x: chrome.minX,
            y: chrome.minY + (LiveChromeMetrics.topInfoDeckHeight - size) / 2,
            width: size,
            height: size
        )
    }

    private static func batteryRect(chrome: CGRect, lock: CGRect, constrained: Bool) -> CGRect {
        if constrained {
            return CGRect(
                x: chrome.minX + LiveChromeMetrics.lockButtonSize
                    + LiveChromeMetrics.batteryInlineGap,
                y: lock.minY,
                width: LiveChromeMetrics.batteryInlineWidth,
                height: LiveChromeMetrics.lockButtonSize
            )
        }
        return CGRect(
            x: LiveChromeMetrics.batteryPillLeading,
            y: lock.maxY + LiveChromeMetrics.batteryPillGap,
            width: LiveChromeMetrics.batteryPillWidth,
            height: LiveChromeMetrics.batteryPillHeight
        )
    }

    private static func rightRailRect(
        viewport: CGSize,
        chrome: CGRect,
        feed: CGRect
    ) -> CGRect {
        let railWidth = min(chrome.width, LiveChromeMetrics.railWidth)
        let laneX = min(viewport.width, max(0, feed.maxX))
        let laneWidth = max(0, viewport.width - laneX)
        if laneWidth >= railWidth {
            return CGRect(
                x: laneX + (laneWidth - railWidth) / 2,
                y: chrome.minY,
                width: railWidth,
                height: chrome.height
            )
        }
        return CGRect(
            x: chrome.maxX - railWidth,
            y: chrome.minY,
            width: railWidth,
            height: chrome.height
        )
    }

    private struct RailSlots {
        var settings, media, record, disp, railClearance: CGRect
    }

    /// OpenZCine `MonitorSideRailControlLayout.fit` in rail-local space, then offset.
    private static func railSlots(rail: CGRect, bottomBarHeight: CGFloat) -> RailSlots {
        let aux = LiveChromeMetrics.auxiliaryButtonSize
        let rec = LiveChromeMetrics.recordButtonSize
        let dispW = LiveChromeMetrics.displayButtonWidth
        let dispH = LiveChromeMetrics.displayButtonHeight
        let recordCenterX = max(rec / 2, rail.width - rec / 2)
        let settingsCenterY = aux / 2
        let recordCenterY = rail.height / 2
        let mediaCenterY = (settingsCenterY + aux / 2 + recordCenterY - rec / 2) / 2
        let bottomBarTop = max(0, rail.height - max(0, bottomBarHeight))
        let dispHalf = dispH / 2
        let clearOfRecord = recordCenterY + rec / 2 + dispHalf
        let displayCenterY =
            bottomBarHeight > 0
            ? (recordCenterY + rec / 2 + bottomBarTop) / 2
            : max(clearOfRecord, rail.height - dispHalf)
        func slot(centerX: CGFloat, centerY: CGFloat, width: CGFloat, height: CGFloat) -> CGRect {
            CGRect(
                x: rail.minX + centerX - width / 2,
                y: rail.minY + centerY - height / 2,
                width: width,
                height: height
            )
        }
        return RailSlots(
            settings: slot(
                centerX: recordCenterX, centerY: settingsCenterY, width: aux, height: aux),
            media: slot(centerX: recordCenterX, centerY: mediaCenterY, width: aux, height: aux),
            record: slot(centerX: recordCenterX, centerY: recordCenterY, width: rec, height: rec),
            disp: slot(
                centerX: recordCenterX, centerY: displayCenterY, width: dispW, height: dispH),
            railClearance: rail
        )
    }

    private static func constrainedSlots(
        viewport: CGSize,
        chrome: CGRect,
        lock: CGRect
    ) -> RailSlots {
        let aux = LiveChromeMetrics.auxiliaryButtonSize
        let gap = LiveChromeMetrics.bottomModuleSpacing
        let bandCenterY = chrome.minY + LiveChromeMetrics.topInfoDeckHeight / 2
        let settings = CGRect(
            x: chrome.maxX - aux,
            y: bandCenterY - aux / 2,
            width: aux,
            height: aux
        )
        let media = CGRect(
            x: settings.minX - gap - aux,
            y: bandCenterY - aux / 2,
            width: aux,
            height: aux
        )
        let rec = LiveChromeMetrics.recordButtonSize
        let recordBottom = viewport.height - LiveChromeMetrics.bottomBarBottomInset
        let record = CGRect(
            x: chrome.maxX - rec,
            y: recordBottom - rec,
            width: rec,
            height: rec
        )
        let disp = CGRect(
            x: record.minX - gap - LiveChromeMetrics.displayButtonWidth,
            y: record.midY - LiveChromeMetrics.displayButtonHeight / 2,
            width: LiveChromeMetrics.displayButtonWidth,
            height: LiveChromeMetrics.displayButtonHeight
        )
        return RailSlots(
            settings: settings, media: media, record: record, disp: disp, railClearance: record)
    }

    private static func topDeckRect(
        feed: CGRect,
        lock: CGRect,
        battery: CGRect,
        rail: CGRect,
        constrained: Bool
    ) -> CGRect {
        let gap = LiveChromeMetrics.topInfoDeckControlGap
        let side = LiveChromeMetrics.topInfoDeckSideInset
        var left = feed.minX + side
        var right = feed.maxX - side
        let clusterRight = max(lock.maxX, battery.maxX)
        let clusterLeft = min(lock.minX, battery.minX)
        if clusterRight < feed.midX {
            left = max(left, clusterRight + gap)
        }
        if clusterLeft > feed.midX {
            right = min(right, clusterLeft - gap)
        }
        if constrained {
            let reserved =
                2 * LiveChromeMetrics.auxiliaryButtonSize + 2
                * LiveChromeMetrics.bottomModuleSpacing
            let inset = side + reserved + gap
            left = max(left, feed.minX + inset)
            right = min(right, feed.maxX - inset)
        } else if rail.midX > feed.midX {
            right = min(right, rail.minX - gap)
        } else {
            left = max(left, rail.maxX + gap)
        }
        return CGRect(
            x: left,
            y: LiveChromeMetrics.chromeTop,
            width: max(0, right - left),
            height: LiveChromeMetrics.topInfoDeckHeight
        )
    }

    /// Pocket split: assist 1/3, capture 2/3. OpenZCine is 50/50 — the only intentional width delta.
    private static func bottomBand(
        viewport: CGSize,
        chrome: CGRect,
        constrained: Bool
    ) -> (assist: CGRect, capture: CGRect) {
        let reserved =
            LiveChromeMetrics.recordButtonSize
            + LiveChromeMetrics.displayButtonWidth
            + 2 * LiveChromeMetrics.bottomModuleSpacing
        let barsWidth = constrained ? max(0, chrome.width - reserved) : chrome.width
        let gap = LiveChromeMetrics.bottomModuleSpacing
        let assistWidth = max(0, (barsWidth - gap) / 3)
        let captureWidth = max(0, barsWidth - gap - assistWidth)
        let y = viewport.height - LiveChromeMetrics.bottomBarBottomInset - LiveDesign.controlHeight
        let assist = CGRect(
            x: chrome.minX,
            y: y,
            width: assistWidth,
            height: LiveDesign.controlHeight
        )
        let capture = CGRect(
            x: assist.maxX + gap,
            y: y,
            width: captureWidth,
            height: LiveDesign.controlHeight
        )
        return (assist, capture)
    }

    /// Horizontal mirror of every module, feed included. The deck is recomputed after
    /// this so it stays on the picture rather than tracking the pre-mirror feed.
    private mutating func mirrorHorizontally(in viewportWidth: CGFloat) {
        func flip(_ rect: CGRect) -> CGRect {
            CGRect(
                x: viewportWidth - rect.maxX,
                y: rect.minY,
                width: rect.width,
                height: rect.height
            )
        }
        feed = flip(feed)
        picture = flip(picture)
        lock = flip(lock)
        battery = flip(battery)
        assist = flip(assist)
        capture = flip(capture)
        rail = flip(rail)
        settings = flip(settings)
        media = flip(media)
        record = flip(record)
        disp = flip(disp)
    }
}

extension LiveMonitorLayout {
    /// On-feed raster. Assists and the pinch well sit here.
    /// Zoom and the gimbal stick use the cinema `feed` well so a vertical
    /// Pocket picture does not drag them inward with the pillarbox.
    var onFeed: CGRect { picture.width > 1 ? picture : feed }

    var zoomButton: CGRect {
        let size = LiveChromeMetrics.zoomButtonSize
        let inset = LiveChromeMetrics.zoomChipInset
        let clear: CGFloat = 8
        let well = feed
        if record.midX >= well.midX {
            let trailing = min(well.maxX - inset, record.minX - clear)
            return CGRect(
                x: trailing - size,
                y: record.midY - size / 2,
                width: size,
                height: size
            )
        }
        let leading = max(well.minX + inset, record.maxX + clear)
        return CGRect(
            x: leading,
            y: record.midY - size / 2,
            width: size,
            height: size
        )
    }

    /// Analog stick in the feed's trailing-bottom corner. DISP 1 parks it
    /// above the capture strip; DISP 2 drops it into the free corner.
    var gimbalStick: CGRect {
        let size = LiveChromeMetrics.gimbalStickSize
        let inset = LiveChromeMetrics.gimbalStickInset
        let gap = LiveChromeMetrics.gimbalStickGap
        var barTop = CGFloat.greatestFiniteMagnitude
        if showsBottomBars {
            if assist.height > 1 { barTop = min(barTop, assist.minY) }
            if capture.height > 1 { barTop = min(barTop, capture.minY) }
        }
        let well = feed
        let floorY =
            barTop < CGFloat.greatestFiniteMagnitude
            ? min(well.maxY - inset, barTop - gap)
            : well.maxY - inset
        var x = well.maxX - inset - size
        var y = floorY - size
        x = min(max(x, well.minX + inset), max(well.minX, well.maxX - inset - size))
        y = min(max(y, well.minY + inset), max(well.minY, well.maxY - inset - size))
        var rect = CGRect(x: x, y: y, width: size, height: size)
        let zoom = zoomButton
        if zoom.width > 1, rect.intersects(zoom.insetBy(dx: -gap, dy: -gap)) {
            rect.origin.y = zoom.maxY + gap
        }
        if record.width > 1, rect.intersects(record.insetBy(dx: -gap, dy: -gap)) {
            rect.origin.x = record.minX - gap - size
        }
        return rect
    }

    /// OpenZCine recenter key. Landscape: just past the battery, toward the feed,
    /// above the assist bar. Portrait: bottom-right of the feed.
    var focusReset: CGRect {
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
    static let assistMargin: CGFloat = 12
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

    /// OpenZCine `topPickerBody`: 340-wide card, centred on the cell, 8pt under `cell.maxY`.
    static func topPicker(
        cell: CGRect,
        panelHeight: CGFloat,
        viewport: CGSize,
        safeArea: EdgeInsets,
        floorY: CGFloat? = nil,
        preferredWidth: CGFloat = LiveChromeMetrics.topPickerWidth,
        gap: CGFloat = LiveChromeMetrics.topPickerGap
    ) -> Box {
        let band = horizontalBand(
            preferredWidth: preferredWidth,
            viewportWidth: viewport.width,
            safeLeading: safeArea.leading,
            safeTrailing: safeArea.trailing,
            margin: edgeMargin
        )
        let hasCell = cell.width > 1 && cell.height > 1
        let x = leadingX(
            desired: hasCell ? cell.midX - band.width / 2 : band.minX,
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

    /// OpenZCine `bottomPickerBody`: 420 cap, 10pt above the capture bar, centred on the
    /// originating tile (or the bar when the tile frame is missing).
    static func capturePicker(
        tile: CGRect,
        bar: CGRect,
        panelHeight: CGFloat,
        viewport: CGSize,
        safeArea: EdgeInsets,
        ceilingY: CGFloat = 0,
        preferredWidth: CGFloat = LiveChromeMetrics.capturePickerMaxWidth,
        gap: CGFloat = LiveChromeMetrics.popupGap
    ) -> Box {
        let hasBar = bar.width > 1
        let widthPref = hasBar ? min(bar.width, preferredWidth) : preferredWidth
        let band = horizontalBand(
            preferredWidth: widthPref,
            viewportWidth: viewport.width,
            safeLeading: safeArea.leading,
            safeTrailing: safeArea.trailing,
            margin: edgeMargin
        )
        let midX: CGFloat
        if tile.width > 1 {
            midX = tile.midX
        } else if hasBar {
            midX = bar.midX
        } else {
            midX = viewport.width / 2
        }
        let x = leadingX(
            desired: midX - band.width / 2,
            width: band.width,
            minX: band.minX,
            maxX: band.maxX
        )
        let minY = max(edgeMargin, safeArea.top + assistTopInset, ceilingY)
        let boxBottom =
            (hasBar ? bar.minY : viewport.height - max(edgeMargin, safeArea.bottom)) - gap
        let maxHeight = max(0, boxBottom - minY)
        let height = min(max(0, panelHeight), maxHeight)
        let y = max(minY, boxBottom - height)
        return Box(x: x, y: y, width: band.width, maxHeight: maxHeight)
    }

    /// OpenZCine `AssistOptionsPopupAnchor` (box above the toolbar, island clearance) plus
    /// Android trailing-align to the pressed icon.
    static func assistOptions(
        icon: CGRect,
        toolbar: CGRect,
        preferredWidth: CGFloat,
        panelHeight: CGFloat,
        viewport: CGSize,
        safeArea: EdgeInsets,
        ceilingY: CGFloat = 0,
        gap: CGFloat = LiveChromeMetrics.popupGap
    ) -> Box {
        let minX = max(
            LiveChromeMetrics.chromeLeading,
            safeArea.leading + cutoutClearance,
            assistMargin
        )
        let maxX =
            viewport.width
            - max(
                LiveChromeMetrics.chromeTrailing, safeArea.trailing + cutoutClearance, assistMargin)
        let width = max(0, min(preferredWidth, maxX - minX))
        let hasIcon = icon.width > 1 && icon.height > 1
        let hasToolbar = toolbar.width > 1 && toolbar.height > 1
        let desiredX: CGFloat
        if hasIcon {
            desiredX = icon.maxX - width
        } else if hasToolbar {
            desiredX = toolbar.maxX - width
        } else {
            desiredX = minX
        }
        let x = leadingX(desired: desiredX, width: width, minX: minX, maxX: maxX)
        let barTop: CGFloat
        if hasToolbar {
            barTop = toolbar.minY
        } else if hasIcon {
            barTop = icon.minY
        } else {
            barTop = viewport.height - max(edgeMargin, safeArea.bottom)
        }
        let minY = max(assistMargin, safeArea.top + assistTopInset, ceilingY)
        let boxBottom = barTop - gap
        let maxHeight = max(0, boxBottom - minY)
        let height = min(max(0, panelHeight), maxHeight)
        let y = max(minY, boxBottom - height)
        return Box(x: x, y: y, width: width, maxHeight: maxHeight)
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
