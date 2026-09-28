import Foundation

/// AE lock without a camera-native lock. `0x02/0x68` (AE Lock Status Set) has
/// only the captured `08` hint and no captured clear, so the lock pins the
/// camera's applied Auto exposure as Manual and unlock returns to Auto.
public struct AutoExposureLock: Equatable, Sendable {
    public let isoIndex: IsoIndex
    public let shutterDenom: Int
    /// `-1` when the body had not reported a shooting mode yet.
    public let shootingMode: Int

    public init(isoIndex: IsoIndex, shutterDenom: Int, shootingMode: Int) {
        self.isoIndex = isoIndex
        self.shutterDenom = shutterDenom
        self.shootingMode = shootingMode
    }

    /// Applied Auto ISO (`@16`) and shutter (`@20–22`) as the nearest offered
    /// Manual values. Manual ISO is whole stops, so ISO can round by up to half
    /// a stop; the shutter keeps its motion cadence. nil unless Auto reports both.
    public static func capture(_ status: CameraStatus) -> AutoExposureLock? {
        guard status.expoMode == .auto, status.iso > 0, status.shutterDenom > 0 else { return nil }
        let isos =
            status.availableIsoIndices.isEmpty ? IsoIndex.allCases : status.availableIsoIndices
        guard let iso = IsoIndex.nearest(to: status.iso, available: isos) else { return nil }
        let live = status.shutterDenom
        let denom = status.availableShutterDenoms.min { abs($0 - live) < abs($1 - live) } ?? live
        return AutoExposureLock(
            isoIndex: iso, shutterDenom: denom, shootingMode: status.shootingMode)
    }

    /// An Auto report (operator, body, or a failed Manual SET) or another
    /// shooting mode ends the lock. Manual ISO / shutter changes keep it.
    public func holds(_ status: CameraStatus) -> Bool {
        status.expoMode != .auto && (shootingMode < 0 || status.shootingMode == shootingMode)
    }
}

/// AWB lock state: the Custom Kelvin that AWB Lock set. Another reported
/// mode or Kelvin (a body change, a failed SET) ends it; unknown WB keeps it.
public struct AutoWhiteBalanceLock: Equatable, Sendable {
    public let kelvin: Int

    public init(kelvin: Int) { self.kelvin = kelvin }

    public func holds(_ status: CameraStatus) -> Bool {
        guard let wb = status.whiteBalance else { return true }
        return wb.mode == .custom && wb.kelvin == kelvin
    }
}

extension WhiteBalance {
    /// Custom Kelvin drum on both shells (Android `CaptureLists.kelvinValues` mirrors it).
    /// One ladder for every model: Action 6 accepted single 100K steps (2000 → 2100K).
    public static let kelvinLadder = Array(stride(from: 2_000, through: 10_000, by: 100))

    /// Nearest drum value; a tie keeps the lower (warmer) value.
    public static func snappedKelvin(_ kelvin: Int) -> Int {
        kelvinLadder.min { abs($0 - kelvin) < abs($1 - kelvin) } ?? kelvin
    }

    /// AWB lock: Custom at the live Auto Kelvin snapped to the drum, keeping
    /// tint. nil unless Auto reports a Kelvin in the Custom range.
    public static func lockingAuto(_ status: CameraStatus) -> WhiteBalance? {
        guard status.whiteBalance?.mode == .auto, status.autoWhiteBalanceKelvin > 0 else {
            return nil
        }
        return .custom(
            kelvin: snappedKelvin(status.autoWhiteBalanceKelvin), tint: status.whiteBalanceTint ?? 0
        )
    }
}
