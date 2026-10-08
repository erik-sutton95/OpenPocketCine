import Foundation
import MonitorPresentation
import OpenCineAppKitApple
import OpenCineApple
import OpenCineMedia
import OpenPocketViewCore

typealias MonitorBackdropRenderer = OpenCineAppKitApple.MonitorBackdropRenderer
typealias MonitorVideoBackdropRenderer = OpenCineAppKitApple.MonitorVideoBackdropRenderer
typealias MonitorVideoBackdropSource = OpenCineAppKitApple.MonitorVideoBackdropSource
typealias MonitorVideoBackdropConfiguration = OpenCineAppKitApple.MonitorVideoBackdropConfiguration

extension OpenCineAppKitApple.MonitorVideoBackdropRenderer {
    convenience init(clock: @escaping @Sendable () -> UInt64 = { DispatchTime.now().uptimeNanoseconds },
        minimumInterval: @escaping @Sendable () -> Double = { MonitorBackdropPolicy.minimumInterval },
        operation: Operation? = nil) {
        self.init(lookCurves: DJIMonitorColorProfile.value.rec709LookCurves,
            cacheEligibility: { !FeedWorkingRaster.isReusableOutput($0) },
            externalLookState: { effects in
                let maps = effects.falseColor ? PocketFalseColorMap.overlayPairData(
                    scale: effects.falseColorScale, mode: effects.colorMode,
                    rec709: effects.falseColorRec709, clipByte: effects.resolvedClipByte)?.clipByte : 0
                return .init(clipByte: effects.resolvedClipByte, mapClipByte: maps)
            },
            clock: clock, minimumInterval: minimumInterval, operation: operation)
    }
}
