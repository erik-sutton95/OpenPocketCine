import Testing

@testable import OpenPocketViewCore

@Suite struct MonitorLayoutPolicyTests {
    // 44pt side insets are corner padding, not a cutout; 59pt is a hardware cutout.
    static let cornerPadding = MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 44)
    static let leadingCutout = MonitorEdgeInsets(top: 0, leading: 59, bottom: 21, trailing: 44)
    static let trailingCutout = MonitorEdgeInsets(top: 0, leading: 44, bottom: 21, trailing: 59)

    /// Device orientation wins; `nil` orientation exercises the safe-area-only resolver.
    @Test(arguments: [
        (
            MonitorDeviceOrientation?.some(.landscapeLeft), cornerPadding,
            MonitorHorizontalLayoutDirection.standard
        ),
        (.landscapeRight, cornerPadding, .mirrored),
        (.unknown, trailingCutout, .mirrored),
        (.unknown, leadingCutout, .standard),
        (.portrait, trailingCutout, .standard),
        (.portraitUpsideDown, trailingCutout, .standard),
        (.landscapeLeft, trailingCutout, .standard),
        (nil, leadingCutout, .standard),
        (nil, trailingCutout, .mirrored),
        (nil, cornerPadding, .standard),
    ])
    func horizontalLayoutDirection(
        orientation: MonitorDeviceOrientation?,
        safeArea: MonitorEdgeInsets,
        expected: MonitorHorizontalLayoutDirection
    ) {
        let resolved =
            orientation.map {
                MonitorHorizontalLayoutDirection.resolve(deviceOrientation: $0, safeArea: safeArea)
            } ?? MonitorHorizontalLayoutDirection.resolve(for: safeArea)
        #expect(resolved == expected)
    }
}
