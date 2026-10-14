import Foundation
import OpenCineMedia
import OpenCineCameraVocabulary
import OpenPocketViewCore

/// Compatibility facade for original callers. The packer is stateless; its caller owns caching.
public enum FeedEffectsWire {
    public static let falseColorCubeSize = MonitorFeedEffectsWire.falseColorCubeSize
    public static let assistScalarCount = MonitorFeedEffectsWire.assistScalarCount

    public static func monitorTransfer(colorModeCode: Int) -> MonitorTransfer {
        MonitorFeedEffectsWire.monitorTransfer(colorModeCode: colorModeCode)
    }
    public static func falseColorScale(_ ordinal: Int) -> LiveFalseColorScale? {
        MonitorFeedEffectsWire.falseColorScale(ordinal)
    }
    public static func readsRec709Look(_ ordinal: Int) -> Bool {
        MonitorFeedEffectsWire.readsRec709Look(ordinal)
    }
    public static func packedFalseColorPaint(scaleOrdinal: Int, colorModeCode: Int, iso: Int,
        sourceProfile: MonitorColorSourceProfile = DJIMonitorColorProfile.value) -> [UInt8]? {
        MonitorFeedEffectsWire.packedFalseColorPaint(scaleOrdinal: scaleOrdinal,
            colorModeCode: colorModeCode, iso: iso, sourceProfile: sourceProfile)
    }
    public static func packedFalseColorWeight(scaleOrdinal: Int, colorModeCode: Int, iso: Int,
        sourceProfile: MonitorColorSourceProfile = DJIMonitorColorProfile.value) -> [UInt8]? {
        MonitorFeedEffectsWire.packedFalseColorWeight(scaleOrdinal: scaleOrdinal,
            colorModeCode: colorModeCode, iso: iso, sourceProfile: sourceProfile)
    }
    public static func assistScalars(colorModeCode: Int, iso: Int, highlightIRE: Double,
        midtoneIRE: Double, sourceProfile: MonitorColorSourceProfile = DJIMonitorColorProfile.value) -> [Float] {
        MonitorFeedEffectsWire.assistScalars(colorModeCode: colorModeCode, iso: iso,
            highlightIRE: highlightIRE, midtoneIRE: midtoneIRE, sourceProfile: sourceProfile)
    }
    public static func peakingGateScale(for transfer: MonitorTransfer) -> Double {
        MonitorFeedEffectsWire.peakingGateScale(for: transfer)
    }
}
