import Foundation

/// Transfer the Pocket live HEVC *picture* is carrying.
///
/// `ColorMode` (`cam_image_effect` `@2`) selects Normal / HDR / D-Log / D-Log2.
/// The camera writes **legal-range scaled** codes in a tv-range container:
/// `container10 = 64 + curve × 876`. ``LiveFrameTap`` expands that back, so
/// everything downstream speaks **curve fractions** (`byte/255` = the papers'
/// own encoded axis).
///
    /// Shared IRE mapping for HISTO / PARADE / ZEBRA / FALSE / LIGHTS / WAVE
    /// (``ScopeDisplayScale``). WAVE draws 0 / 100 on the plot edges and
    /// keeps 18% gray at paper IRE (not remapped to 50):
    /// * 0 line = paper / legal black (`encode(0)`)
    /// * 18% grey = published paper IRE (`encode(0.18) × 100`; D-Log2 = 30.50)
    /// * 100 line = **live-tap EI ceiling**, not code 255 and not the 10-bit
    ///   recording top. SoftAP x420 at ISO 1600 measures D-Log2 `max=247`
    ///   (typical 243–247) and D-Log `max=223` (typical 219–223). 255 is a
    ///   full-range leak and is ignored. An earlier 188 calibration sat ~50
    ///   codes below that shelf, so zebra / traffic-clip / FALSE Maximum
    ///   fired while the LUT-off log still had highlight detail. Below each
    ///   curve's native EI the DJI paper scales the code; at/above native an
    ///   S-curve holds the preview at the measured ceiling (D-Log2 native
    ///   1600, D-Log native 400). Rec.709 / HLG still clip at encoded 1.0.
public enum MonitorTransfer: String, CaseIterable, Sendable, Identifiable {
    /// `ColorMode.normal` `0x3F`. ITU-R BT.709-6 inverse OETF.
    case rec709
    /// `ColorMode.hdr` `0x3C`. Pocket HDR is HLG (ITU-R BT.2100 / BT.2408), not PQ.
    case hdr
    /// `ColorMode.dLog` `0x17`. DJI D-Log (2017 Cinema Color System white paper).
    case dlog
    /// `ColorMode.dLog2` `0x41`. DJI D-Log2 (Gamut white paper Rev 1.0, 2026-06-30).
    case dlog2

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .rec709: "Rec.709"
        case .hdr: "HLG"
        case .dlog: "D-Log"
        case .dlog2: "D-Log2"
        }
    }

    public init(_ colorMode: ColorMode) {
        switch colorMode {
        case .normal, .normal10: self = .rec709
        case .hdr: self = .hdr
        case .dLog, .dLogM: self = .dlog
        case .dLog2: self = .dlog2
        }
    }

    /// Scene reflectance at encoded 1.0. D-Log white paper: 4200% = 42. D-Log2 paper: 47500% = 475.
    public var peakLinear: Double {
        switch self {
        case .rec709: 1
        case .hdr: HLG.decode(1)
        case .dlog: DLog.peakLinear
        case .dlog2: DLog2.peakLinear
        }
    }

    /// Anchor codes on the tap's byte axis at the current live-tap ISO.
    public var scopeAnchors: ScopeAnchors {
        ScopeAnchors.make(transfer: self)
    }

    /// Encoded curve fraction of 18% grey (D-Log2 0.304985, D-Log 0.398765, …).
    public var middleGrayEncoded: Double {
        scopeAnchors.mid
    }

    /// Published paper IRE of 18% grey (`encoded × 100`). D-Log2 = 30.50.
    public var middleGrayPaperIRE: Double {
        LiveColorScience.paperIRE(middleGrayEncoded)
    }

    /// 18% grey on the shared IRE scale (paper IRE). WAVE draws this as the
    /// solid middle-gray guide — not remapped to 50.
    public var scopeGreyScaleIRE: Double {
        (scopeAnchors.midLevel - ScopeDisplayScale.crushLevel)
            / (ScopeDisplayScale.clipLevel - ScopeDisplayScale.crushLevel) * 100
    }

    public func encodeLinear(_ linear: Double) -> Double {
        LiveColorScience.encode(linear, transfer: self)
    }

    public func linearize(_ encoded: Double) -> Double {
        LiveColorScience.linearize(encoded, transfer: self)
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
}

// MARK: - Live-tap EI ceiling (not recording 1023, not code 255)

/// Preview clip model. WAVE 100 / zebra highlight / false-colour Maximum /
/// traffic clip all sit on this ceiling.
///
/// Device evidence (SoftAP x420 1280×720 tap, `scope max:` journal):
/// D-Log2 ISO 1600 measures `max=247` (typical 243–247); D-Log measures
/// `max=223` (typical 219–223). 255 is a full-range leak and is ignored.
/// 188 was an under-read that made zebra / traffic-clip fire ~50 codes
/// early. DJI papers: below native EI the output cannot reach saturation;
/// at/above native an S-curve holds the code. D-Log2 native = 1600; D-Log
/// native = 400.
public enum ScopeExposureCeiling: Sendable {
    public static let referenceEI = 1600
    /// Pocket D-Log native / base ISO. Hold the live-tap ceiling from here up.
    public static let dlogReferenceEI = 400
    /// Measured live-tap max at ISO 1600. Do not replace with recording ~847/1023.
    public static let dlog2LiveTapByteAt1600: UInt8 = 247
    /// Same blast also logged 248 — treat as the same ceiling, not a new curve.
    public static let dlog2LiveTapByteAt1600High: UInt8 = 248
    /// Measured D-Log live-tap max (ISO 400–6400 hold). Independent of D-Log2.
    public static let dlogLiveTapByteAtNative: UInt8 = 223
    /// Same blast also logged 224 — treat as the same ceiling, not a new curve.
    public static let dlogLiveTapByteAtNativeHigh: UInt8 = 224

    private static let store = ExposureCeilingStore()

    /// Last `cam_expo_param` ISO. Unknown / 0 keeps the measured 1600 point.
    public static func setISO(_ iso: Int) {
        guard (50...102_400).contains(iso) else { return }
        store.withLock { $0.iso = iso }
    }

    /// No-op when the session has not published an ISO yet.
    public static func syncISO(_ iso: Int) {
        if iso > 0 { setISO(iso) }
    }

    public static func resolvedISO() -> Int {
        store.withLock { $0.iso }
    }

    public static func reset() {
        store.withLock { $0 = ExposureCeilingStore.State() }
    }

    /// Encoded curve fraction of the live-tap clip (D-Log2 → 247/255, D-Log → 223/255).
    public static func clipEncoded(transfer: MonitorTransfer, iso: Int? = nil) -> Double {
        Double(clipByte(transfer: transfer, iso: iso)) / 255.0
    }

    public static func clipByte(transfer: MonitorTransfer, iso: Int? = nil) -> Int {
        store.withLock { s in
            let ei = iso ?? s.iso
            let table = tableByte(
                transfer: transfer, iso: ei,
                refined1600: s.refined1600, refinedDlog: s.refinedDlog)
            let seen = s.observedByEI[ExposureCeilingStore.Key(transfer: transfer, ei: ei)] ?? 0
            return Int(max(UInt8(table), seen))
        }
    }

    /// Ratchet the live-tap ceiling from a scope-tap `max=`. Ignores 0 and 255
    /// (do not stretch a full-range leak onto the 100 line). Returns the clip
    /// byte now in force, and whether the rolling max rose (for the control log).
    @discardableResult
    public static func observeTapMax(
        _ byte: UInt8, transfer: MonitorTransfer
    ) -> (clip: UInt8, maxRose: Bool) {
        guard transfer == .dlog || transfer == .dlog2, byte > 0, byte < 255 else {
            return (UInt8(clipByte(transfer: transfer)), false)
        }
        return store.withLock { s in
            if transfer == .dlog2, s.iso == referenceEI, byte > s.refined1600,
                byte <= dlog2LiveTapByteAt1600High
            {
                s.refined1600 = byte
            }
            if transfer == .dlog,
                (s.iso == 0 || s.iso >= dlogReferenceEI),
                byte > s.refinedDlog,
                byte <= dlogLiveTapByteAtNativeHigh
            {
                s.refinedDlog = byte
            }
            let ei = s.iso
            let key = ExposureCeilingStore.Key(transfer: transfer, ei: ei)
            let table = UInt8(tableByte(
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

    /// Scene-linear live-tap ceiling at D-Log2 EI 1600. Rec.709 / HLG do not
    /// use this. D-Log has its own code-space ceiling (``dlogLiveTapByteAtNative``).
    public static var linearCeilingAt1600: Double {
        LiveColorScience.linearize(
            Double(dlog2LiveTapByteAt1600) / 255.0, transfer: .dlog2)
    }

    fileprivate static func tableByte(
        transfer: MonitorTransfer, iso: Int, refined1600: UInt8, refinedDlog: UInt8
    ) -> Int {
        switch transfer {
        case .rec709, .hdr:
            return 255
        case .dlog2:
            let ei = iso > 0 ? iso : referenceEI
            let refLinear = LiveColorScience.linearize(
                Double(refined1600) / 255.0, transfer: .dlog2)
            // Paper: below 1600 the code cannot reach saturation (scale linear
            // by EI/1600). At/above 1600 the S-curve holds the preview at the
            // measured live-tap saturation — not encoded 1.0.
            let linear = ei >= referenceEI
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
            let linear = ei >= dlogReferenceEI
                ? refLinear
                : refLinear * Double(ei) / Double(dlogReferenceEI)
            let encoded = LiveColorScience.encode(linear, transfer: .dlog)
            return Int(min(254, max(1, (encoded * 255).rounded())))
        }
    }
}

private final class ExposureCeilingStore: @unchecked Sendable {
    struct State {
        var iso = ScopeExposureCeiling.referenceEI
        var refined1600 = ScopeExposureCeiling.dlog2LiveTapByteAt1600
        var refinedDlog = ScopeExposureCeiling.dlogLiveTapByteAtNative
        var observedByEI: [Key: UInt8] = [:]
        var lastLoggedMax: UInt8 = 0
    }

    struct Key: Hashable {
        var transfer: MonitorTransfer
        var ei: Int
    }

    private var value = State()
    private let lock = NSLock()

    func withLock<T>(_ body: (inout State) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&value)
    }
}

// MARK: - Anchored scope axis

/// Per-transfer anchors on the tap's curve-fraction axis (`byte / 255`).
///
/// `black = encode(0)`, `mid = encode(0.18)`, `clip` = live-tap EI ceiling
/// (D-Log2 → 247/255, D-Log → 223/255), **not** the curve top.
public struct ScopeAnchors: Equatable, Sendable {
    /// Encode-of-zero-light (D-Log2 0.062561 → byte ≈ 16, D-Log 0.0929 → ≈ 24, others 0).
    public let black: Double
    /// Encode-of-18%-grey (D-Log2 0.304985 → byte ≈ 78).
    public let mid: Double
    /// Live-tap EI ceiling (D-Log2 → 247/255, D-Log → 223/255). Rec.709 / HLG → 1.0.
    public let clip: Double
    /// Plot level of 18% grey, pinned at paper IRE (`encoded × 100`).
    public let midLevel: Double

    /// Traffic-light band edges on the 0…255 byte axis.
    /// `clipFloorByte…255` is the clip *zone* (WAVE IRE 95, matching HISTO
    /// and zebra's highlight start). `clipEdgeByte` is the 100-line ceiling.
    public let clipEdgeByte: Int
    public let clipFloorByte: Int
    public let crushFloorByte: Int
    public let crushEdgeByte: Int

    public static func make(
        transfer: MonitorTransfer, iso: Int? = nil
    ) -> ScopeAnchors {
        let black = LiveColorScience.encode(0, transfer: transfer)
        let mid = LiveColorScience.encode(0.18, transfer: transfer)
        let clip = ScopeExposureCeiling.clipEncoded(transfer: transfer, iso: iso)
        let midLevel = ScopeDisplayScale.crushLevel
            + LiveColorScience.paperIRE(mid) / 100.0
            * (ScopeDisplayScale.clipLevel - ScopeDisplayScale.crushLevel)
        let clipEdge = ScopeExposureCeiling.clipByte(transfer: transfer, iso: iso)
        let span = max(0, clip - black) * 255
        let crushFloor = Int((black * 255).rounded(.down))
        let crushEdge = Int((black * 255 + 0.02 * span).rounded(.up))
        // WAVE IRE 95 — same mark HISTO already draws, and just below
        // zebra's soft highlight start (threshold − 1/40). Journal shelf
        // 243–246 has luma a few codes under maxRGB; 2% (byte 242) missed
        // it. 188 is ~76 IRE and stays out. Computed here (not via
        // signalNative) so make() cannot recurse.
        let target95 = ScopeDisplayScale.crushLevel
            + 0.95 * (ScopeDisplayScale.clipLevel - ScopeDisplayScale.crushLevel)
        let encoded95: Double
        if clip <= mid || mid <= black {
            encoded95 = black + 0.95 * (clip - black)
        } else if target95 <= midLevel {
            let t = (target95 - ScopeDisplayScale.crushLevel)
                / max(midLevel - ScopeDisplayScale.crushLevel, 1e-9)
            encoded95 = black + t * (mid - black)
        } else {
            let t = (target95 - midLevel)
                / max(ScopeDisplayScale.clipLevel - midLevel, 1e-9)
            encoded95 = mid + t * (clip - mid)
        }
        let clipFloor = min(clipEdge, max(0, Int((encoded95 * 255).rounded(.down))))
        return ScopeAnchors(
            black: black, mid: mid, clip: clip, midLevel: midLevel,
            clipEdgeByte: clipEdge,
            clipFloorByte: clipFloor,
            crushFloorByte: crushFloor,
            crushEdgeByte: crushEdge)
    }

    fileprivate init(
        black: Double, mid: Double, clip: Double, midLevel: Double,
        clipEdgeByte: Int, clipFloorByte: Int,
        crushFloorByte: Int, crushEdgeByte: Int
    ) {
        self.black = black
        self.mid = mid
        self.clip = clip
        self.midLevel = midLevel
        self.clipEdgeByte = clipEdgeByte
        self.clipFloorByte = clipFloorByte
        self.crushFloorByte = crushFloorByte
        self.crushEdgeByte = crushEdgeByte
    }
}

/// HISTO / PARADE / ZEBRA / FALSE / LIGHTS axis. WAVE uses the same IRE
/// numbers on a full-height plot (0 / 100 on the edges, gray at paper IRE).
///
/// 0 and 100 scale lines sit at 5% / 95% of plot height. Paper black lands on
/// the 0 line, the live-tap EI ceiling on the 100 line, 18% grey is pinned at
/// its published paper IRE. Sub-black noise and codes above the EI ceiling
/// (including 255) draw in the margins — 255 is **not** stretched onto 100.
public enum ScopeDisplayScale {
    public static let crushLevel = 0.05
    public static let clipLevel = 0.95

    /// Plot level (0…1 of plot height) of a normalized tap byte.
    public static func waveformLevel(
        _ c: Double, transfer: MonitorTransfer, iso: Int? = nil
    ) -> Double {
        let a = ScopeAnchors.make(transfer: transfer, iso: iso)
        let v = min(1, max(0, c))
        if v < a.black {
            return a.black <= 0 ? crushLevel : v / a.black * crushLevel
        }
        if a.clip <= a.mid || a.mid <= a.black {
            if v <= a.clip {
                return crushLevel
                    + (v - a.black) / max(a.clip - a.black, 1e-9)
                    * (clipLevel - crushLevel)
            }
            return overshoot(v, clip: a.clip)
        }
        if v <= a.mid {
            return crushLevel + (v - a.black) / (a.mid - a.black) * (a.midLevel - crushLevel)
        }
        if v <= a.clip {
            return a.midLevel + (v - a.mid) / (a.clip - a.mid) * (clipLevel - a.midLevel)
        }
        return overshoot(v, clip: a.clip)
    }

    /// Level of a 0…100 scale value (0 → crush line, 100 → clip line).
    public static func level(scaleIRE: Double) -> Double {
        crushLevel + scaleIRE / 100.0 * (clipLevel - crushLevel)
    }

    /// WAVE IRE: 0 = paper black, 18% grey = paper IRE (D-Log2 30.50,
    /// D-Log 39.88), 100 = live-tap EI ceiling. Codes above the ceiling
    /// clamp to 100 (zebra / FALSE clip).
    public static func monitorPercent(
        _ c: Double, transfer: MonitorTransfer, iso: Int? = nil
    ) -> Double {
        let level = waveformLevel(c, transfer: transfer, iso: iso)
        return min(100, max(0, (level - crushLevel) / (clipLevel - crushLevel) * 100))
    }

    /// Normalized tap code whose ``monitorPercent(_:transfer:iso:)`` equals `percent`.
    public static func signalNative(
        monitorPercent percent: Double, transfer: MonitorTransfer, iso: Int? = nil
    ) -> Double {
        let a = ScopeAnchors.make(transfer: transfer, iso: iso)
        let p = min(100, max(0, percent))
        if p <= 0 { return a.black }
        if p >= 100 { return a.clip }
        let target = crushLevel + p / 100.0 * (clipLevel - crushLevel)
        if a.clip <= a.mid || a.mid <= a.black {
            return a.black + p / 100.0 * (a.clip - a.black)
        }
        if target <= a.midLevel {
            let t = (target - crushLevel) / max(a.midLevel - crushLevel, 1e-9)
            return a.black + t * (a.mid - a.black)
        }
        let t = (target - a.midLevel) / max(clipLevel - a.midLevel, 1e-9)
        return a.mid + t * (a.clip - a.mid)
    }

    /// 256-entry `waveformLevel` lookup for the hot sampling/vertex paths.
    public static func levelTable(for transfer: MonitorTransfer, iso: Int? = nil) -> [Float] {
        let ei = iso ?? ScopeExposureCeiling.resolvedISO()
        let clip = ScopeExposureCeiling.clipByte(transfer: transfer, iso: ei)
        return tables.withLock { cache in
            let key = ScopeLevelTableKey(transfer: transfer, clipByte: clip)
            if let hit = cache[key] { return hit }
            let built = (0...255).map {
                Float(waveformLevel(Double($0) / 255.0, transfer: transfer, iso: ei))
            }
            cache[key] = built
            return built
        }
    }

    /// Move native-code histogram counts into display buckets on the waveform
    /// axis (`round(level × 255)`), so histogram x and waveform y agree
    /// column-for-column. Conserves total count.
    public static func remapHistogram(_ bins: [Int], transfer: MonitorTransfer) -> [Int] {
        var out = [Int](repeating: 0, count: 256)
        let table = levelTable(for: transfer)
        for code in 0..<min(bins.count, 256) where bins[code] != 0 {
            let bucket = Int((table[code] * 255).rounded())
            out[min(255, max(0, bucket))] += bins[code]
        }
        return out
    }

    private static func overshoot(_ v: Double, clip: Double) -> Double {
        let headroom = 1.0 - clip
        guard headroom > 0 else { return clipLevel }
        return clipLevel + (v - clip) / headroom * (1.0 - clipLevel)
    }

    private static let tables = TableCache()
}

private struct ScopeLevelTableKey: Hashable {
    var transfer: MonitorTransfer
    var clipByte: Int
}

private final class TableCache: @unchecked Sendable {
    private var cache: [ScopeLevelTableKey: [Float]] = [:]
    private let lock = NSLock()
    func withLock<T>(_ body: (inout [ScopeLevelTableKey: [Float]]) -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body(&cache)
    }
}

// MARK: - Traffic lights (OpenZCine ScopeSampler / TrafficLightsMeter port)

/// One channel of the goal-post meter. `level` is the histogram median on the
/// waveform axis, re-centred so 18% grey reads exactly 0.5.
public struct ScopeChannelLight: Equatable, Sendable {
    public var clip: Bool
    public var crush: Bool
    public var level: Double

    public init(clip: Bool, crush: Bool, level: Double) {
        self.clip = clip
        self.crush = crush
        self.level = level
    }

    /// Within ±0.03 of centre the bar reads neutral (OpenZCine balanceDeadZone).
    public var isNeutral: Bool { abs(level - 0.5) <= 0.03 }
}

public struct ScopeTrafficLightsReading: Equatable, Sendable {
    public var red: ScopeChannelLight
    public var green: ScopeChannelLight
    public var blue: ScopeChannelLight

    public init(red: ScopeChannelLight, green: ScopeChannelLight, blue: ScopeChannelLight) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    public static let none = ScopeTrafficLightsReading(
        red: ScopeChannelLight(clip: false, crush: false, level: 0.5),
        green: ScopeChannelLight(clip: false, crush: false, level: 0.5),
        blue: ScopeChannelLight(clip: false, crush: false, level: 0.5))

    public var anyClip: Bool { red.clip || green.clip || blue.clip }
    public var anyCrush: Bool { red.crush || green.crush || blue.crush }
}

public enum ScopeTrafficLights {
    /// Default pixel-fraction threshold = 0 stop compensation (stops / 10).
    public static let defaultThreshold = 0.0
    /// Stay lit until energy falls to half the fire threshold (stops blink).
    public static let holdRatio = 0.5

    /// Meter from the 256-bin native histograms — never from the point array.
    public static func reading(
        red: [Int], green: [Int], blue: [Int],
        transfer: MonitorTransfer,
        threshold: Double = defaultThreshold,
        previous: ScopeTrafficLightsReading? = nil
    ) -> ScopeTrafficLightsReading {
        reading(
            red: red, green: green, blue: blue, luma: nil,
            transfer: transfer, threshold: threshold, previous: previous)
    }

    public static func reading(
        red: [Int], green: [Int], blue: [Int],
        luma: [Int]? = nil,
        transfer: MonitorTransfer,
        threshold: Double = defaultThreshold,
        previous: ScopeTrafficLightsReading? = nil
    ) -> ScopeTrafficLightsReading {
        let a = transfer.scopeAnchors
        let redClip = edgeEnergy(red, from: a.clipFloorByte, to: 255)
        let greenClip = edgeEnergy(green, from: a.clipFloorByte, to: 255)
        let blueClip = edgeEnergy(blue, from: a.clipFloorByte, to: 255)
        let lumaClip = luma.map { edgeEnergy($0, from: a.clipFloorByte, to: 255) } ?? 0
        // Zebra is luma. A blown door can clip Y while reconstructed R/B sit
        // a few codes lower — and the frame median is still the subject, not
        // the door. If luma (or any channel) is clipped, light every lamp.
        let pictureClip =
            lumaClip > threshold || redClip > threshold
            || greenClip > threshold || blueClip > threshold
        let pictureEnergy = max(lumaClip, redClip, greenClip, blueClip)
        return ScopeTrafficLightsReading(
            red: channel(
                red, transfer: transfer, threshold: threshold,
                ownClipEnergy: redClip, pictureEnergy: pictureEnergy,
                pictureClip: pictureClip, previous: previous?.red),
            green: channel(
                green, transfer: transfer, threshold: threshold,
                ownClipEnergy: greenClip, pictureEnergy: pictureEnergy,
                pictureClip: pictureClip, previous: previous?.green),
            blue: channel(
                blue, transfer: transfer, threshold: threshold,
                ownClipEnergy: blueClip, pictureEnergy: pictureEnergy,
                pictureClip: pictureClip, previous: previous?.blue))
    }

    private static func channel(
        _ bins: [Int], transfer: MonitorTransfer, threshold: Double,
        ownClipEnergy: Double, pictureEnergy: Double,
        pictureClip: Bool,
        previous: ScopeChannelLight?
    ) -> ScopeChannelLight {
        let a = transfer.scopeAnchors
        guard bins.count >= 256 else {
            return ScopeChannelLight(clip: false, crush: false, level: 0.5)
        }
        var total = 0
        for count in bins { total += count }
        guard total > 0 else {
            return ScopeChannelLight(clip: false, crush: false, level: 0.5)
        }

        var crushed = 0
        for code in a.crushFloorByte...a.crushEdgeByte { crushed += bins[code] }
        let crushEnergy = Double(crushed) / Double(total)

        var seen = 0
        var median = 0
        let half = (total + 1) / 2
        for code in 0..<256 {
            seen += bins[code]
            if seen >= half {
                median = code
                break
            }
        }
        let rawClip = ownClipEnergy > threshold || pictureClip
        let clip = latched(
            now: rawClip, was: previous?.clip ?? false,
            energy: max(ownClipEnergy, pictureEnergy), threshold: threshold)
        let crush = latched(
            now: crushEnergy > threshold, was: previous?.crush ?? false,
            energy: crushEnergy, threshold: threshold)
        let level = balance(
            ScopeDisplayScale.waveformLevel(Double(median) / 255.0, transfer: transfer),
            midLevel: a.midLevel)
        return ScopeChannelLight(clip: clip, crush: crush, level: level)
    }

    /// Fraction of counts in `from...to`, or 0 if the histogram is unusable.
    static func edgeEnergy(_ bins: [Int], from: Int, to: Int) -> Double {
        guard bins.count >= 256, from <= to, from >= 0, to <= 255 else { return 0 }
        var total = 0
        var band = 0
        for code in 0..<256 {
            total += bins[code]
            if code >= from, code <= to { band += bins[code] }
        }
        guard total > 0 else { return 0 }
        return Double(band) / Double(total)
    }

    static func latched(
        now: Bool, was: Bool, energy: Double, threshold: Double
    ) -> Bool {
        if now { return true }
        guard was else { return false }
        return energy > threshold * holdRatio
    }

    /// Re-centre the anchored level so the transfer's grey lands at exactly 0.5.
    static func balance(_ level: Double, midLevel: Double) -> Double {
        if level <= midLevel {
            guard midLevel > 0 else { return 0.5 }
            return 0.5 * level / midLevel
        }
        let span = 1.0 - midLevel
        guard span > 0 else { return 0.5 }
        return 0.5 + 0.5 * (level - midLevel) / span
    }
}

// MARK: - Zebra / false colour supporting types

/// False-colour / limits zone. Bounds are stops or WAVE IRE depending on the scale.
public struct LiveFalseColorBand: Equatable, Sendable {
    public var lowerBound: Double
    public var upperBound: Double
    public var red: Double
    public var green: Double
    public var blue: Double
    public var label: String

    public init(
        lowerBound: Double, upperBound: Double,
        red: Double, green: Double, blue: Double,
        label: String
    ) {
        self.lowerBound = lowerBound
        self.upperBound = upperBound
        self.red = red
        self.green = green
        self.blue = blue
        self.label = label
    }

    public func contains(_ value: Double) -> Bool {
        value >= lowerBound && value < upperBound
    }
}

/// OpenZCine `FalseColorScale` names. IRE / Limits use WAVE IRE; Stops use scene EV.
public enum LiveFalseColorScale: String, CaseIterable, Sendable {
    case stops = "Stops"
    case ire = "IRE"
    case limits = "Limits"
}

/// OpenZCine zebra defaults (`AssistConfiguration.Zebra`: highlight 100, midtone 55).
/// Thresholds are on the ``ScopeDisplayScale/monitorPercent(_:transfer:)`` axis.
public enum LiveZebra {
    public static let highlightIRE = 100.0
    public static let midtoneIRE = 55.0
    /// Half-width of the midtone stripe, in monitor IRE.
    public static let midtoneHalfWidthIRE = 5.0
}

// MARK: - Color science entry points

/// Linearize Pocket live codes and map them for the display-referred assists
/// (false colour, zebra, LUT generation). Scopes do NOT linearize pixel data —
/// they ride ``ScopeDisplayScale`` on encoded codes.
public enum LiveColorScience {
    /// Scene-linear reflectance from a normalized encoded channel (`0…1`).
    /// Values below a log toe clamp to 0 so downstream math never sees NaN / negatives.
    public static func linearize(_ encoded: Double, transfer: MonitorTransfer) -> Double {
        let code = clamp01(encoded)
        let linear = decode(code, transfer: transfer)
        guard linear.isFinite else { return 0 }
        return max(0, linear)
    }

    /// Normalized encoded code from scene-linear reflectance. Clamped to `0…1`.
    public static func encode(_ linear: Double, transfer: MonitorTransfer) -> Double {
        let y = max(0, linear)
        let encoded = encodeRaw(y, transfer: transfer)
        guard encoded.isFinite else { return 0 }
        return clamp01(encoded)
    }

    /// Linearize one encoded RGB pixel (normalized `0…1`).
    public static func linearizeRGB(
        red: Double, green: Double, blue: Double, transfer: MonitorTransfer
    ) -> (red: Double, green: Double, blue: Double) {
        (
            linearize(red, transfer: transfer),
            linearize(green, transfer: transfer),
            linearize(blue, transfer: transfer)
        )
    }

    /// Scene-linear luminance. Channels are decoded first, then weighted.
    /// Rec.709 / D-Log use BT.709 Y; HDR (HLG) and D-Log2 use BT.2020 Y (BT.2100).
    public static func linearLuminance(
        red: Double, green: Double, blue: Double, transfer: MonitorTransfer
    ) -> Double {
        let rgb = linearizeRGB(red: red, green: green, blue: blue, transfer: transfer)
        let w = lumaWeights(transfer)
        return w.red * rgb.red + w.green * rgb.green + w.blue * rgb.blue
    }

    /// Encoded-domain luma weights for the scope sampler (same per-transfer choice).
    public static func lumaWeights(_ transfer: MonitorTransfer) -> (
        red: Double, green: Double, blue: Double
    ) {
        switch transfer {
        case .rec709, .dlog:
            (0.2126, 0.7152, 0.0722)
        case .hdr, .dlog2:
            (0.2627, 0.6780, 0.0593)
        }
    }

    /// Published paper IRE: encoded curve fraction × 100.
    /// D-Log2 18% = 30.4985; D-Log 18% = 39.88; Rec.709 18% ≈ 40.9.
    public static func paperIRE(_ encoded: Double) -> Double {
        encoded * 100
    }

    /// Shared HISTO / PARADE / ZEBRA / FALSE / WAVE IRE. 0 = paper black,
    /// 18% grey = paper IRE (D-Log2 30.50, D-Log 39.88), 100 = live-tap EI ceiling.
    public static func monitorIRE(linear: Double, transfer: MonitorTransfer) -> Double {
        monitorIRE(encoded: encode(linear, transfer: transfer), transfer: transfer)
    }

    public static func monitorIRE(encoded: Double, transfer: MonitorTransfer) -> Double {
        finiteIRE(ScopeDisplayScale.monitorPercent(encoded, transfer: transfer))
    }

    /// Stops relative to 18% grey. Zero light is `−∞`, never NaN.
    public static func stops(linear: Double) -> Double {
        let y = max(0, linear)
        guard y > 0, y.isFinite else { return -.infinity }
        return log2(y / 0.18)
    }

    public static func stops(encoded: Double, transfer: MonitorTransfer) -> Double {
        stops(linear: linearize(encoded, transfer: transfer))
    }

    public static func zebraHighlight(_ monitorPercent: Double, threshold: Double = LiveZebra.highlightIRE) -> Bool {
        monitorPercent >= threshold
    }

    public static func zebraMidtone(
        _ monitorPercent: Double,
        centre: Double = LiveZebra.midtoneIRE,
        halfWidth: Double = LiveZebra.midtoneHalfWidthIRE
    ) -> Bool {
        abs(monitorPercent - centre) <= halfWidth
    }

    /// IRE / Limits ride the WAVE axis. Stops are scene EV; clip-relative
    /// bands use the live-tap EI ceiling, not D-Log2's paper peak (+11.4).
    public static func falseColorBands(
        _ scale: LiveFalseColorScale, transfer: MonitorTransfer
    ) -> [LiveFalseColorBand] {
        switch scale {
        case .stops: stopBands(transfer: transfer)
        case .ire: ireBands
        case .limits: limitBands
        }
    }

    public static func falseColorBand(
        value: Double, scale: LiveFalseColorScale, transfer: MonitorTransfer
    ) -> LiveFalseColorBand? {
        let candidate = scale == .stops ? value : clamp(value, 0, 100)
        return falseColorBands(scale, transfer: transfer).first { $0.contains(candidate) }
    }

    // MARK: - Private transfers

    private static func decode(_ encoded: Double, transfer: MonitorTransfer) -> Double {
        switch transfer {
        case .rec709: Rec709.decode(encoded)
        case .hdr: HLG.decode(encoded)
        case .dlog: DLog.decode(encoded)
        case .dlog2: DLog2.decode(encoded)
        }
    }

    private static func encodeRaw(_ linear: Double, transfer: MonitorTransfer) -> Double {
        switch transfer {
        case .rec709: Rec709.encode(linear)
        case .hdr: HLG.encode(linear)
        case .dlog: DLog.encode(linear)
        case .dlog2: DLog2.encode(linear)
        }
    }

    private static func clamp01(_ x: Double) -> Double { clamp(x, 0, 1) }

    private static func clamp(_ x: Double, _ lo: Double, _ hi: Double) -> Double {
        min(hi, max(lo, x))
    }

    private static func finiteIRE(_ ire: Double) -> Double {
        guard ire.isFinite else { return 0 }
        return clamp(ire, 0, 100)
    }
}

// MARK: - BT.709 (ITU-R BT.709-6)

/// ITU-R BT.709-6 §1.2 inverse OETF / OETF. Live Normal is Rec.709-looking on the wire.
private enum Rec709 {
    static func decode(_ encoded: Double) -> Double {
        let e = encoded
        return e < 0.081 ? e / 4.5 : pow((e + 0.099) / 1.099, 1 / 0.45)
    }

    static func encode(_ linear: Double) -> Double {
        let l = min(1, linear)
        return l < 0.018 ? 4.5 * l : 1.099 * pow(l, 0.45) - 0.099
    }
}

// MARK: - HLG (ITU-R BT.2100 / BT.2408)

/// ITU-R BT.2100 HLG OETF (ARIB STD-B67). `linear` is scene reflectance with
/// 1.0 = diffuse white, scaled per BT.2408 (75% signal).
private enum HLG {
    private static let a = 0.178_832_77
    private static let b = 0.284_668_92
    private static let c = 0.559_910_73
    /// Inverse OETF of the BT.2408 75% reference-white signal.
    private static let diffuseWhite = inverseOETF(0.75)

    static func decode(_ encoded: Double) -> Double {
        inverseOETF(min(1, max(0, encoded))) / diffuseWhite
    }

    static func encode(_ linear: Double) -> Double {
        oetf(min(1, max(0, linear * diffuseWhite)))
    }

    private static func oetf(_ scene: Double) -> Double {
        scene <= 1.0 / 12.0 ? sqrt(3 * scene) : a * log(12 * scene - b) + c
    }

    private static func inverseOETF(_ e: Double) -> Double {
        e <= 0.5 ? e * e / 3 : (exp((e - c) / a) + b) / 12
    }
}

// MARK: - D-Log (DJI 2017 white paper)

/// DJI, *White Paper on D-Log and D-Gamut of DJI Cinema Color System* (2017-09-29),
/// https://dl.djicdn.com/downloads/zenmuse+x7/20171010/D-Log_D-Gamut_Whitepaper.pdf
///
/// Curve fractions: 0% → 95/1023 (0.0929); 18% → 408/1023; 90% → 586/1023;
/// peak 4200% (7.8 stops above 18% grey) → 1.0. On the Pocket wire these ride
/// the legal-range container (0% → 10-bit ≈ 145, measured floor 142).
private enum DLog {
    static let peakLinear = 42.0

    static func decode(_ encoded: Double) -> Double {
        if encoded <= 0.14 {
            return (encoded - 0.0929) / 6.025
        }
        return (pow(10, 3.89616 * encoded - 2.27752) - 0.0108) / 0.9892
    }

    static func encode(_ linear: Double) -> Double {
        if linear <= 0.0078 {
            return 6.025 * linear + 0.0929
        }
        return log10(linear * 0.9892 + 0.0108) * 0.256663 + 0.584555
    }
}

// MARK: - D-Log2 (Gamut unofficial white paper, Rev 1.0, 2026-06-30)

/// D-Log2 transfer from *White Paper on D-Log2 and D-Gamut2 of DJI Cinema Color
/// System* (Gamut, Revision 1.0, June 30, 2026). Constants match that paper
/// bit-for-bit (and the Pocket 4P DCTL). Peak 475 linear, +11.37 EV above 18%.
///
/// Curve fractions: 0 → 0.062561; 18% → 0.304985; 1.0 → 0.454539; 475 → 1.0.
/// On the Pocket wire these ride the legal-range container
/// (0 → 10-bit ≈ 118.8, measured floor 112; 475 → 940).
private enum DLog2 {
    static let peakLinear = 475.0
    private static let a = 16.285_770_761_945_304
    private static let k1 = 0.059_439_938_321_493
    private static let b1 = 0.304_985_337_243_402
    private static let k2 = 2.960_935_245_492_250
    private static let b2 = 0.148_314_799_066_323
    private static let inLimit1 = 0.18
    private static let inLimit2 = 0.028_961_695_254_132

    static func decode(_ encoded: Double) -> Double {
        if encoded >= b1 {
            return (peakLinear / (pow(2, a) - 1)) * (pow(2, a * encoded) - 1)
        }
        if encoded >= b2 {
            return pow(2, (encoded - b1) / k1 + log2(inLimit1))
        }
        return (encoded - b2) / k2 + inLimit2
    }

    static func encode(_ linear: Double) -> Double {
        if linear >= inLimit1 {
            return (1 / a) * log2(linear * (pow(2, a) - 1) / peakLinear + 1)
        }
        if linear >= inLimit2 {
            return k1 * (log2(max(linear, 1e-15)) - log2(inLimit1)) + b1
        }
        return k2 * (linear - inLimit2) + b2
    }
}

// MARK: - D-Gamut2 (Gamut unofficial white paper, Rev 1.0, 2026-06-30)

/// Scene-linear D-Gamut2 interchange. Decode D-Log2 **before** applying these.
/// Display rendering, contrast, highlight roll-off, and gamut mapping stay
/// downstream. Scopes do **not** call this — they plot encoded codes.
public enum DGamut2 {
    /// CIE 1931 xy. Blue y is negative (below the spectral locus). White is D65.
    public static let redPrimary = (x: 0.7347, y: 0.2653)
    public static let greenPrimary = (x: 0.1600, y: 0.8400)
    public static let bluePrimary = (x: 0.0900, y: -0.0800)
    public static let whiteD65 = (x: 0.3127, y: 0.3290)

    /// Linear D-Gamut2 RGB → CIE 1931 XYZ.
    public static let rgbToXYZ = ColorMatrix3(
        0.6917, 0.1596, 0.0990,
        0.2498, 0.8381, -0.0880,
        0.0000, 0.0000, 1.0891)

    /// CIE 1931 XYZ → linear D-Gamut2 RGB.
    public static let xyzToRGB = ColorMatrix3(
        1.5525, -0.2956, -0.1650,
        -0.4627, 1.2813, 0.1456,
        0.0000, 0.0000, 0.9182)

    /// Linear D-Gamut2 RGB → DaVinci Wide Gamut RGB (`DJI DLog2 to DWG.dctl`).
    public static let rgbToDWG = ColorMatrix3(
        0.9790, 0.0062, 0.0149,
        -0.0090, 0.9747, 0.0343,
        0.0721, 0.1018, 0.8260)

    /// DaVinci Wide Gamut RGB → linear D-Gamut2 RGB.
    public static let dwgToRGB = ColorMatrix3(
        1.0228, -0.0046, -0.0182,
        0.0126, 1.0304, -0.0430,
        -0.0909, -0.1266, 1.2175)

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

/// Row-major 3×3 for paper D-Gamut / D-Gamut2 / Rec.709 / DWG interchange.
public struct ColorMatrix3: Equatable, Sendable {
    public var m00: Double, m01: Double, m02: Double
    public var m10: Double, m11: Double, m12: Double
    public var m20: Double, m21: Double, m22: Double

    public init(
        _ m00: Double, _ m01: Double, _ m02: Double,
        _ m10: Double, _ m11: Double, _ m12: Double,
        _ m20: Double, _ m21: Double, _ m22: Double
    ) {
        self.m00 = m00; self.m01 = m01; self.m02 = m02
        self.m10 = m10; self.m11 = m11; self.m12 = m12
        self.m20 = m20; self.m21 = m21; self.m22 = m22
    }

    public func apply(r: Double, g: Double, b: Double) -> (r: Double, g: Double, b: Double) {
        (
            m00 * r + m01 * g + m02 * b,
            m10 * r + m11 * g + m12 * b,
            m20 * r + m21 * g + m22 * b
        )
    }
}

// MARK: - False-colour tables (WAVE IRE / EI-relative stops)

extension LiveColorScience {
    /// OpenZCine ZC Stops landmarks (minimum / −3 / 18% / skin +1 / +2) with
    /// clip-relative warnings from *this* transfer's peak, not RED 180 / N-Log 940.
    fileprivate static func stopBands(transfer: MonitorTransfer) -> [LiveFalseColorBand] {
        let clipLinear = linearize(
            ScopeExposureCeiling.clipEncoded(transfer: transfer), transfer: transfer)
        let maximum = max(3, log2(max(clipLinear, 0.18 * 8) / 0.18))
        // OpenZCine ZCStopsPalette (original muted RGB; RED published meanings, not RGB).
        return [
            band(-.infinity, -35.0 / 6, 78, 11, 82, "Minimum"),
            band(-19.0 / 6, -17.0 / 6, 17, 149, 141, "−3"),
            band(-1.0 / 6, 1.0 / 6, 8, 203, 24, "18%"),
            band(5.0 / 6, 7.0 / 6, 245, 143, 148, "Skin +1"),
            band(11.0 / 6, 13.0 / 6, 212, 208, 13, "+2"),
            band(maximum - 5.0 / 6, maximum - 0.5, 255, 244, 0, "⅔ below max"),
            band(maximum - 0.5, maximum - 1.0 / 6, 255, 126, 18, "⅓ below max"),
            band(maximum - 1.0 / 6, .infinity, 250, 60, 36, "Maximum"),
        ]
    }

    /// WAVE IRE bands. 18% (D-Log2 paper 30.50) is the green band; 99–100 is
    /// the live-tap EI ceiling, not Reinhard-mapped curve peak.
    fileprivate static let ireBands: [LiveFalseColorBand] = [
        ire(0, 5, 0.44, 0.22, 0.76, "0–4"),
        ire(5, 6, 0.28, 0.37, 0.85, "5"),
        ire(10, 13, 0.18, 0.58, 0.64, "10–12"),
        ire(28, 34, 0.38, 0.63, 0.35, "18%"),
        ire(52, 62, 0.83, 0.53, 0.71, "55–61"),
        ire(92, 94, 0.83, 0.77, 0.45, "92–93"),
        ire(94, 96, 0.89, 0.72, 0.29, "94–95"),
        ire(96, 99, 0.85, 0.55, 0.22, "96–98"),
        ire(99, .infinity, 0.78, 0.28, 0.18, "99–100"),
    ]

    fileprivate static let limitBands: [LiveFalseColorBand] = [
        ire(0, 5, 0.44, 0.22, 0.76, "0–4"),
        ire(5, 10, 0.28, 0.37, 0.85, "5–9"),
        ire(94, 99, 0.89, 0.72, 0.29, "94–98"),
        ire(99, .infinity, 0.78, 0.28, 0.18, "99–100"),
    ]

    private static func band(
        _ lo: Double, _ hi: Double,
        _ r: Double, _ g: Double, _ b: Double,
        _ label: String
    ) -> LiveFalseColorBand {
        LiveFalseColorBand(
            lowerBound: lo, upperBound: hi,
            red: r / 255, green: g / 255, blue: b / 255,
            label: label)
    }

    private static func ire(
        _ lo: Double, _ hi: Double,
        _ r: Double, _ g: Double, _ b: Double,
        _ label: String
    ) -> LiveFalseColorBand {
        LiveFalseColorBand(
            lowerBound: lo, upperBound: hi,
            red: r, green: g, blue: b,
            label: label)
    }
}
