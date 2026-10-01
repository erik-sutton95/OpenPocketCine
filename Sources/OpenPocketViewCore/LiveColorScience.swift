import Foundation

// DJI integration side of the color science. Curve math, the scope axis, traffic lights
// and the false-colour scales live in OpenCineMedia (re-exported by this module). This file
// keeps what only the DJI integration knows: raw `ColorMode` → curve, the live-tap
// fingerprint, the measured live-tap ceilings (one ``ScopeExposureCeiling`` per picture
// source), the D-Gamut matrices and the official Rec.709 look curves.

/// Transfer the Pocket live HEVC *picture* is carrying.
///
/// `ColorMode` (`cam_image_effect` `@2`, body-mapped on Pocket 3) selects
/// Normal / HDR / D-Log / D-Log2 / D-Log M.
/// The camera writes **legal-range scaled** codes in a tv-range container:
/// `container10 = 64 + curve × 876`. ``LiveFrameTap`` expands that back, so
/// everything downstream speaks **curve fractions** (`byte/255` = the papers'
/// own encoded axis).
///
/// WAVE 100 is the **live-tap EI ceiling** of the source (``ScopeExposureCeiling``),
/// not code 255 and not the 10-bit recording top. Rec.709 / HLG use encoded 1.0.
/// D-Log M scopes use the unchanged 0…1 signal axis; its endpoints are not measured
/// sensor limits. Scene-stop estimates use an empirical Pocket 3 fit.
extension MonitorTransfer {
    public init(_ colorMode: ColorMode) {
        switch colorMode {
        case .normal, .normal10: self = .rec709
        case .hdr: self = .hdr
        case .dLog: self = .dlog
        case .dLogM: self = .dlogm
        case .dLog2: self = .dlog2
        }
    }

    /// Fingerprint the live tap when ColorMode `@2` has not arrived.
    ///
    /// D-Log2 paper black is byte 16 and the ISO 1600 preview ceiling is ~247.
    /// Plotting those codes on Rec.709 WAVE is the screenshot shelf (black at
    /// ~8, ceiling at ~75). An explicit ColorMode (`fallback` other than
    /// Rec.709) always wins.
    public static func inferred(
        minByte: UInt8, maxByte: UInt8, fallback: MonitorTransfer
    ) -> MonitorTransfer {
        guard fallback == .rec709 else { return fallback }
        // Expanded D-Log2: paper black 16, live-tap ceiling 247 (also 243–246).
        if (12...22).contains(minByte), (180...252).contains(maxByte) { return .dlog2 }
        // Expanded D-Log: paper black ~24, live-tap ceiling 223 (219–223).
        if (20...30).contains(minByte), (160...240).contains(maxByte) { return .dlog }
        return fallback
    }

    /// Curve for LUT exposure compensation and export bakes. D-Log M keeps the D-Log
    /// curve while its exposure model is uncalibrated, so the empirical scope estimate
    /// never silently changes baked images.
    public var lutExposureTransfer: MonitorTransfer {
        self == .dlogm ? .dlog : self
    }
}

// MARK: - Live-tap EI ceiling (not recording 1023, not code 255)

/// Preview clip model of **one** picture source. WAVE 100 / zebra highlight /
/// false-colour Maximum / traffic clip all sit on this ceiling. Each sample bus / feed
/// effects session owns its own instance, so two cameras (or a camera and a clip) never
/// share an ISO or a ratchet. Thread-safe.
///
/// Device evidence (SoftAP x420 1280×720 tap, `scope max:` journal):
/// D-Log2 ISO 1600 measures `max=247` (typical 243–247); D-Log measures
/// `max=223` (typical 219–223). 255 is a full-range leak and is ignored.
/// 188 was an under-read that made zebra / traffic-clip fire ~50 codes
/// early. DJI papers: below native EI the output cannot reach saturation;
/// at/above native an S-curve holds the code. D-Log2 native = 1600; D-Log
/// native = 400.
public final class ScopeExposureCeiling: @unchecked Sendable {
    public static let referenceEI = 1600
    /// Pocket D-Log native / base ISO. Hold the live-tap ceiling from here up.
    public static let dlogReferenceEI = 400
    /// Measured live-tap max at ISO 1600. Do not replace with recording ~847/1023.
    public static let dlog2LiveTapByteAt1600: UInt8 = 247
    /// Same blast also logged 248: treat as the same ceiling, not a new curve.
    public static let dlog2LiveTapByteAt1600High: UInt8 = 248
    /// Measured D-Log live-tap max (ISO 400–6400 hold). Independent of D-Log2.
    public static let dlogLiveTapByteAtNative: UInt8 = 223
    /// Same blast also logged 224: treat as the same ceiling, not a new curve.
    public static let dlogLiveTapByteAtNativeHigh: UInt8 = 224

    /// Clipped detail sits on a shelf under the ceiling, not on the ceiling byte
    /// itself, and white balance moves it: device journals show 242–247 on clipped
    /// highlights at D-Log2 ISO 1600 (a blown window read 242–244 on 2026-09-29) and
    /// 219–223 on D-Log. See ``ScopeAnchors/clipShelfCodes``.
    public static let clipShelfCodes = ScopeAnchors.clipShelfCodes

    private struct State {
        var iso = ScopeExposureCeiling.referenceEI
        var refined1600 = ScopeExposureCeiling.dlog2LiveTapByteAt1600
        var refinedDlog = ScopeExposureCeiling.dlogLiveTapByteAtNative
        var observedByEI: [Key: UInt8] = [:]
        var lastLoggedMax: UInt8 = 0
    }

    private struct Key: Hashable {
        var transfer: MonitorTransfer
        var ei: Int
    }

    private var state = State()
    private let lock = NSLock()

    public init() {}

    private func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&state)
    }

    /// Last `cam_expo_param` ISO. Unknown / 0 keeps the measured 1600 point.
    public func setISO(_ iso: Int) {
        guard (50...102_400).contains(iso) else { return }
        withLock { $0.iso = iso }
    }

    /// No-op when the session has not published an ISO yet.
    public func syncISO(_ iso: Int) {
        if iso > 0 { setISO(iso) }
    }

    public func resolvedISO() -> Int {
        withLock { $0.iso }
    }

    public func reset() {
        withLock { $0 = State() }
    }

    /// First byte of the clip shelf (D-Log2 ISO 1600 → 240).
    public func clipShelfByte(transfer: MonitorTransfer, iso: Int? = nil) -> Int {
        ScopeAnchors.clipShelfByte(clipByte: clipByte(transfer: transfer, iso: iso))
    }

    /// Encoded curve fraction of the live-tap clip (D-Log2 → 247/255, D-Log → 223/255).
    public func clipEncoded(transfer: MonitorTransfer, iso: Int? = nil) -> Double {
        Double(clipByte(transfer: transfer, iso: iso)) / 255.0
    }

    public func clipByte(transfer: MonitorTransfer, iso: Int? = nil) -> Int {
        withLock { s in
            let ei = iso ?? s.iso
            let table = Self.tableByte(
                transfer: transfer, iso: ei,
                refined1600: s.refined1600, refinedDlog: s.refinedDlog)
            let seen = s.observedByEI[Key(transfer: transfer, ei: ei)] ?? 0
            return Int(max(UInt8(table), seen))
        }
    }

    /// Scope anchors of `transfer` on this source's ceiling.
    public func anchors(transfer: MonitorTransfer, iso: Int? = nil) -> ScopeAnchors {
        ScopeAnchors.make(transfer: transfer, clipByte: clipByte(transfer: transfer, iso: iso))
    }

    /// Ratchet the live-tap ceiling from a scope-tap `max=`. Ignores 0 and 255
    /// (do not stretch a full-range leak onto the 100 line). Returns the clip
    /// byte now in force, and whether the rolling max rose (for the control log).
    @discardableResult
    public func observeTapMax(
        _ byte: UInt8, transfer: MonitorTransfer
    ) -> (clip: UInt8, maxRose: Bool) {
        guard transfer == .dlog || transfer == .dlog2, byte > 0, byte < 255 else {
            return (UInt8(clipByte(transfer: transfer)), false)
        }
        return withLock { s in
            if transfer == .dlog2, s.iso == Self.referenceEI, byte > s.refined1600,
                byte <= Self.dlog2LiveTapByteAt1600High
            {
                s.refined1600 = byte
            }
            if transfer == .dlog,
                s.iso == 0 || s.iso >= Self.dlogReferenceEI,
                byte > s.refinedDlog,
                byte <= Self.dlogLiveTapByteAtNativeHigh
            {
                s.refinedDlog = byte
            }
            let ei = s.iso
            let key = Key(transfer: transfer, ei: ei)
            let table = UInt8(
                Self.tableByte(
                    transfer: transfer, iso: ei,
                    refined1600: s.refined1600, refinedDlog: s.refinedDlog))
            let previous = s.observedByEI[key] ?? 0
            // Allow a couple of codes of preview noise; never 255 (full-range leak).
            let raised = min(max(previous, byte), UInt8(min(254, Int(table) + 2)))
            if raised > table { s.observedByEI[key] = raised }
            let clip = max(table, s.observedByEI[key] ?? 0)
            let maxRose = byte > s.lastLoggedMax
            if maxRose { s.lastLoggedMax = byte }
            return (clip, maxRose)
        }
    }

    /// Ceiling of a source with no ISO or tap history yet (reference EI, measured bytes).
    /// For values that were never stamped by a source, for example a default effects value.
    public static func referenceClipByte(transfer: MonitorTransfer) -> Int {
        tableByte(
            transfer: transfer, iso: referenceEI,
            refined1600: dlog2LiveTapByteAt1600, refinedDlog: dlogLiveTapByteAtNative)
    }

    /// Scene-linear live-tap ceiling at D-Log2 EI 1600. Rec.709 / HLG do not
    /// use this. D-Log has its own code-space ceiling (``dlogLiveTapByteAtNative``).
    public static var linearCeilingAt1600: Double {
        LiveColorScience.linearize(
            Double(dlog2LiveTapByteAt1600) / 255.0, transfer: .dlog2)
    }

    private static func tableByte(
        transfer: MonitorTransfer, iso: Int, refined1600: UInt8, refinedDlog: UInt8
    ) -> Int {
        switch transfer {
        case .rec709, .hdr, .dlogm, .ilog:
            return 255
        case .dlog2:
            let ei = iso > 0 ? iso : referenceEI
            let refLinear = LiveColorScience.linearize(
                Double(refined1600) / 255.0, transfer: .dlog2)
            // Paper: below 1600 the code cannot reach saturation (scale linear
            // by EI/1600). At/above 1600 the S-curve holds the preview at the
            // measured live-tap saturation, not encoded 1.0.
            let linear =
                ei >= referenceEI
                ? refLinear
                : refLinear * Double(ei) / Double(referenceEI)
            let encoded = LiveColorScience.encode(linear, transfer: .dlog2)
            return Int(min(254, max(1, (encoded * 255).rounded())))
        case .dlog:
            let ei = iso > 0 ? iso : dlogReferenceEI
            let refLinear = LiveColorScience.linearize(
                Double(refinedDlog) / 255.0, transfer: .dlog)
            // Pocket native EI is 400. Hold the measured *code* ceiling from
            // 400 up. Independent of the D-Log2 247 point.
            let linear =
                ei >= dlogReferenceEI
                ? refLinear
                : refLinear * Double(ei) / Double(dlogReferenceEI)
            let encoded = LiveColorScience.encode(linear, transfer: .dlog)
            return Int(min(254, max(1, (encoded * 255).rounded())))
        }
    }
}

// MARK: - D-Gamut2 (Gamut unofficial white paper, Rev 1.0, 2026-06-30)

/// Scene-linear D-Gamut2 interchange. Decode D-Log2 **before** applying these.
/// Display rendering, contrast, highlight roll-off, and gamut mapping stay
/// downstream. Scopes do **not** call this: they plot encoded codes.
public enum DGamut2 {
    /// Linear D-Gamut2 RGB → ITU-R BT.709 RGB.
    public static let rgbToRec709 = ColorMatrix3(
        1.8577, -0.7712, -0.0869,
        -0.2018, 1.4176, -0.2158,
        -0.0125, -0.1621, 1.1746)

    /// ITU-R BT.709 RGB → linear D-Gamut2 RGB.
    public static let rec709ToRGB = ColorMatrix3(
        0.5742, 0.3240, 0.1020,
        0.0844, 0.7682, 0.1474,
        0.0177, 0.1094, 0.8728)
}

// MARK: - D-Gamut (DJI 2017 white paper)

/// Scene-linear D-Gamut (v1) interchange, for D-Log footage. Same 2017 white
/// paper as the D-Log curve. Decode D-Log **before** applying.
public enum DGamut {
    /// Linear D-Gamut RGB → ITU-R BT.709 RGB.
    public static let rgbToRec709 = ColorMatrix3(
        1.6746, -0.5797, -0.0949,
        -0.0981, 1.3340, -0.2359,
        -0.0410, -0.2430, 1.2840)

    /// ITU-R BT.709 RGB → linear D-Gamut RGB.
    public static let rec709ToRGB = ColorMatrix3(
        0.6163, 0.2857, 0.0980,
        0.0505, 0.7990, 0.1505,
        0.0292, 0.1604, 0.8104)
}

// MARK: - Official Rec.709 looks (DJI cubes) for the 709 false-colour reading

extension LiveColorScience {
    /// Luma of the grey axis (33 points) of DJI's official Rec.709 cubes: Pocket 4P D-Log2
    /// and D-Log, Nano D-Log M. Regenerate from the cubes if DJI updates them. Curves
    /// without an official look (Rec.709, HLG) return `nil` and stay on the signal.
    public static func rec709LookCurve(_ transfer: MonitorTransfer) -> [Double]? {
        switch transfer {
        case .dlog2:
            [
                0.0000, 0.0048, 0.0294, 0.0657, 0.1016, 0.1390, 0.1854, 0.2390, 0.2987, 0.3631,
                0.4300, 0.4976, 0.5651, 0.6306, 0.6930, 0.7508, 0.8024, 0.8471, 0.8847, 0.9152,
                0.9392, 0.9571, 0.9702, 0.9796, 0.9865, 0.9916, 0.9953, 0.9977, 0.9991, 0.9998,
                1.0000, 1.0000, 1.0000,
            ]
        case .dlog:
            [
                0.0000, 0.0162, 0.0253, 0.0379, 0.0519, 0.0697, 0.0938, 0.1231, 0.1583, 0.1974,
                0.2451, 0.2989, 0.3568, 0.4155, 0.4741, 0.5322, 0.5896, 0.6463, 0.7019, 0.7561,
                0.8081, 0.8543, 0.8922, 0.9224, 0.9459, 0.9636, 0.9762, 0.9849, 0.9905, 0.9939,
                0.9962, 0.9988, 1.0000,
            ]
        case .dlogm:
            [
                0.0000, 0.0029, 0.0115, 0.0275, 0.0535, 0.0849, 0.1192, 0.1552, 0.1925, 0.2303,
                0.2692, 0.3090, 0.3488, 0.3883, 0.4239, 0.4563, 0.4874, 0.5193, 0.5538, 0.5908,
                0.6299, 0.6685, 0.7057, 0.7404, 0.7743, 0.8073, 0.8402, 0.8727, 0.9040, 0.9332,
                0.9604, 0.9832, 1.0000,
            ]
        case .rec709, .hdr, .ilog:
            nil
        }
    }

    /// Video level (0…100 IRE) of an encoded neutral code through the official look.
    public static func rec709LookIRE(encoded: Double, transfer: MonitorTransfer) -> Double? {
        rec709LookIRE(encoded: encoded, lookCurve: rec709LookCurve(transfer))
    }

    /// True when the 709 reading applies: the operator picked 709 and this curve has an
    /// official Rec.709 look.
    public static func readsThroughLook(transfer: MonitorTransfer, rec709: Bool) -> Bool {
        readsThroughLook(lookCurve: rec709LookCurve(transfer), rec709: rec709)
    }

    /// ``falseColorReading(encoded:transfer:rec709:lookCurve:scale:)`` through the official look.
    public static func falseColorReading(
        encoded: Double, transfer: MonitorTransfer, rec709: Bool,
        scale: LiveFalseColorScale = .ire
    ) -> (encoded: Double, transfer: MonitorTransfer) {
        falseColorReading(
            encoded: encoded, transfer: transfer, rec709: rec709,
            lookCurve: rec709LookCurve(transfer), scale: scale)
    }

    /// ``falseColorClip(scale:transfer:rec709:lookCurve:clipEncoded:)`` for a source whose
    /// live ceiling for `transfer` is `clipByte` (see ``ScopeExposureCeiling``).
    public static func falseColorClip(
        scale: LiveFalseColorScale, transfer: MonitorTransfer, rec709: Bool, clipByte: Int
    ) -> (transfer: MonitorTransfer, ceiling: Double) {
        falseColorClip(
            scale: scale, transfer: transfer, rec709: rec709,
            lookCurve: rec709LookCurve(transfer), clipEncoded: Double(clipByte) / 255)
    }
}
