#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Shared native monitor composition. A brand app supplies its native feed,
    /// assist renderer and capability-driven chrome slots. The feed's structural
    /// identity never changes with orientation, framing, a drawer, or DISP mode.
    public struct MonitorCanvas<Picture: View, Assists: View, Chrome: View>: View {
        private let layout: FieldMonitorLayout
        private let sourceAspect: Double
        private let picture: @MainActor () -> Picture
        private let assists: @MainActor () -> Assists
        private let chrome: @MainActor () -> Chrome

        public init(
            layout: FieldMonitorLayout, sourceAspect: Double,
            @ViewBuilder picture: @escaping @MainActor () -> Picture,
            @ViewBuilder assists: @escaping @MainActor () -> Assists,
            @ViewBuilder chrome: @escaping @MainActor () -> Chrome
        ) {
            self.layout = layout
            self.sourceAspect = sourceAspect
            self.picture = picture
            self.assists = assists
            self.chrome = chrome
        }

        public var body: some View {
            let region = layout.picture
            let contentWidth =
                layout.portrait && layout.fillsPicture && sourceAspect >= 1
                ? region.height * sourceAspect : region.width
            ZStack(alignment: .topLeading) {
                MonitorTheme.canvas
                MonitorCanvasSlot(content: picture)
                    .frame(width: contentWidth, height: region.height)
                    .frame(width: region.width, height: region.height).clipped()
                    .position(x: region.midX, y: region.midY)
                MonitorCanvasSlot(content: assists)
                    .frame(width: contentWidth, height: region.height)
                    .frame(width: region.width, height: region.height).clipped()
                    .position(x: region.midX, y: region.midY)
                    .allowsHitTesting(false)
                MonitorCanvasSlot(content: chrome)
            }
            .frame(width: layout.viewport.width, height: layout.viewport.height)
            .clipped()
            .environment(\.colorScheme, .dark)
        }
    }

    /// Execute each builder in its own SwiftUI observation scope. Calling it in
    /// the canvas initializer or body would subscribe the geometry owner to
    /// telemetry read by that slot. Keep these children at fixed structural
    /// positions so new layout values update, rather than replace, native hosts.
    private struct MonitorCanvasSlot<Content: View>: View {
        let content: @MainActor () -> Content

        var body: some View {
            content()
        }
    }
#endif
