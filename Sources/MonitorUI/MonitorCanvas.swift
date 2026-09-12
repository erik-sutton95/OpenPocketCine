#if os(iOS)
    import MonitorPresentation
    import SwiftUI

    /// Shared native monitor composition. A brand app supplies its native feed,
    /// assist renderer and capability-driven chrome slots. The feed's structural
    /// identity never changes with orientation, framing, a drawer, or DISP mode.
    public struct MonitorCanvas<Picture: View, Assists: View, Chrome: View>: View {
        private let layout: FieldMonitorLayout
        private let sourceAspect: Double
        private let picture: Picture
        private let assists: Assists
        private let chrome: Chrome

        public init(
            layout: FieldMonitorLayout, sourceAspect: Double,
            @ViewBuilder picture: () -> Picture, @ViewBuilder assists: () -> Assists,
            @ViewBuilder chrome: () -> Chrome
        ) {
            self.layout = layout
            self.sourceAspect = sourceAspect
            self.picture = picture()
            self.assists = assists()
            self.chrome = chrome()
        }

        public var body: some View {
            let region = layout.picture
            let contentWidth =
                layout.portrait && layout.fillsPicture && sourceAspect >= 1
                ? region.height * sourceAspect : region.width
            ZStack(alignment: .topLeading) {
                MonitorTheme.canvas
                picture
                    .frame(width: contentWidth, height: region.height)
                    .frame(width: region.width, height: region.height).clipped()
                    .position(x: region.midX, y: region.midY)
                assists
                    .frame(width: contentWidth, height: region.height)
                    .frame(width: region.width, height: region.height).clipped()
                    .position(x: region.midX, y: region.midY)
                    .allowsHitTesting(false)
                chrome
            }
            .frame(width: layout.viewport.width, height: layout.viewport.height)
            .clipped()
            .environment(\.colorScheme, .dark)
        }
    }
#endif
