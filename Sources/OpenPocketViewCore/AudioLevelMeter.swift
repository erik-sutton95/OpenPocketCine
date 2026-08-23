import Foundation

/// One channel of a broadcast-style dBFS bar meter: the decaying level bar plus its peak-hold
/// marker. Values are dBFS clamped to `AudioMeterBallistics.floorDB`…0.
/// Ported from OpenZCine `AudioLevelMeter`.
public struct AudioMeterChannel: Equatable, Sendable {
    /// Bar level in dBFS.
    public var levelDB: Double
    /// Peak-hold marker in dBFS (never reads below `levelDB`).
    public var peakDB: Double
    /// Seconds the current peak marker has been held — drives the hold-then-decay release.
    public var peakAge: Double

    public init(
        levelDB: Double = AudioMeterBallistics.floorDB,
        peakDB: Double = AudioMeterBallistics.floorDB,
        peakAge: Double = 0
    ) {
        self.levelDB = levelDB
        self.peakDB = peakDB
        self.peakAge = peakAge
    }

    public static let silent = AudioMeterChannel()
}

/// Stereo readout published to the live audio-levels panel.
public struct AudioMeterLevels: Equatable, Sendable {
    public var left: AudioMeterChannel
    public var right: AudioMeterChannel

    public init(left: AudioMeterChannel, right: AudioMeterChannel) {
        self.left = left
        self.right = right
    }

    public static let silent = AudioMeterLevels(left: .silent, right: .silent)
}

extension AudioMeterLevels {
    /// Maps a 15-segment camera indicator onto the meter's dBFS scale. Segment 0 sits at the
    /// meter floor (silence), segment 14 at 0 dBFS, spaced evenly in dB between. Same mapping
    /// OpenZCine uses for the Nikon LiveViewObject sound bytes.
    public init(segments currentLeft: Int, currentRight: Int, peakLeft: Int, peakRight: Int) {
        func decibels(_ segment: Int) -> Double {
            let fraction =
                Double(min(max(segment, 0), CamAudioStatus.maxSegment))
                / Double(CamAudioStatus.maxSegment)
            return AudioMeterBallistics.floorDB * (1 - fraction)
        }
        self.init(
            left: AudioMeterChannel(levelDB: decibels(currentLeft), peakDB: decibels(peakLeft)),
            right: AudioMeterChannel(levelDB: decibels(currentRight), peakDB: decibels(peakRight)))
    }
}

/// dBFS conversion and meter ballistics (instant attack, timed decay, peak hold). Pure — a
/// tap or subscribe snapshot supplies linear frame peaks and a wall-clock `dt`.
public enum AudioMeterBallistics {
    /// Meter floor — anything quieter renders as silence.
    public static let floorDB = -60.0
    /// Bar fall rate once the signal drops (dB per second) — fast but readable, PPM-style.
    public static let levelDecayPerSecond = 26.0
    /// How long a peak marker holds before it starts to fall.
    public static let peakHoldSeconds = 1.8
    /// Peak-marker fall rate once the hold expires (dB per second).
    public static let peakDecayPerSecond = 12.0

    /// Linear amplitude (0…1) → dBFS, clamped to `floorDB`…0.
    public static func decibels(fromLinear amplitude: Double) -> Double {
        guard amplitude > 0 else { return floorDB }
        return max(floorDB, min(0, 20 * log10(amplitude)))
    }

    /// Advances one channel by `dt` seconds, given the loudest linear sample amplitude observed
    /// since the previous step. The bar attacks instantly and decays at `levelDecayPerSecond`; the
    /// peak marker grabs new maxima, holds `peakHoldSeconds`, then falls at `peakDecayPerSecond`.
    public static func step(
        _ channel: AudioMeterChannel, peakLinear: Double, dt: Double
    ) -> AudioMeterChannel {
        let dt = max(0, dt)
        let incoming = decibels(fromLinear: peakLinear)
        var next = channel
        let decayed = max(floorDB, channel.levelDB - levelDecayPerSecond * dt)
        next.levelDB = max(incoming, decayed)
        if incoming >= channel.peakDB {
            next.peakDB = incoming
            next.peakAge = 0
        } else {
            next.peakAge = channel.peakAge + dt
            if next.peakAge > peakHoldSeconds {
                next.peakDB = max(floorDB, channel.peakDB - peakDecayPerSecond * dt)
            }
        }
        next.peakDB = max(next.peakDB, next.levelDB)
        return next
    }
}

/// Pocket `cam_audio_status_v2` subscribe value → stereo dBFS.
///
/// 114 B in `live1.pcap` (487×) and `/tmp/mimo-audio.pcapng` (134×). u16-BE:
///
/// * `@2` left current (captured 2…8)
/// * `@4` constant `3` — not a meter
/// * `@6` left peak (equals `@2` in every captured frame)
/// * `@8` right current (captured 2…9, independent of left)
/// * `@10` / `@12` scale `100`
///
/// Values sit on OpenZCine's 0…14 segment scale while they stay ≤ 14; if the body
/// ever reports 15…100 they map as percent of `@10`. Camera-held — no local decay.
public enum CamAudioStatus {
    /// OpenZCine `PTPLiveViewSoundIndicator.maxSegment`.
    public static let maxSegment = 14
    public static let subscribeKey = "cam_audio_status_v2"
    public static let capturedSize = 114

    public static func parse(_ value: [UInt8]) -> AudioMeterLevels? {
        guard !value.isEmpty else { return nil }
        if let pocket = parsePocketV2(value) { return pocket }
        if value.count >= 4, let window = bestU8Window(value), window.contains(where: { $0 > 0 }) {
            return fromU8Window(window)
        }
        if let levels = parseInt16Pairs(value), levels != .silent { return levels }
        if value.count >= 4 { return .silent }
        if value.count >= 2, value[0] <= 100, value[1] <= 100 {
            return AudioMeterLevels(
                segments: scaledSegment(value[0]),
                currentRight: scaledSegment(value[1]),
                peakLeft: scaledSegment(value[0]),
                peakRight: scaledSegment(value[1]))
        }
        return nil
    }

    /// Captured Pocket 4 layout. `nil` when the blob is not this struct.
    public static func parsePocketV2(_ value: [UInt8]) -> AudioMeterLevels? {
        guard value.count >= 14 else { return nil }
        let scale = u16be(value, 10)
        let scaleRight = u16be(value, 12)
        guard scale == 100, scaleRight == 100 else { return nil }
        let left = Int(u16be(value, 2))
        let leftPeak = Int(u16be(value, 6))
        let right = Int(u16be(value, 8))
        let peakLeft = max(left, leftPeak)
        if max(left, peakLeft, right) <= maxSegment {
            return AudioMeterLevels(
                segments: left, currentRight: right, peakLeft: peakLeft, peakRight: right)
        }
        return AudioMeterLevels(
            left: AudioMeterChannel(
                levelDB: decibels(percent: left), peakDB: decibels(percent: peakLeft)),
            right: AudioMeterChannel(
                levelDB: decibels(percent: right), peakDB: decibels(percent: right)))
    }

    public static func u16be(_ value: [UInt8], _ offset: Int) -> UInt16 {
        (UInt16(value[offset]) << 8) | UInt16(value[offset + 1])
    }

    /// Highest-energy 4-byte run whose bytes all sit on a meter scale (0…100).
    public static func bestU8Window(_ value: [UInt8]) -> [UInt8]? {
        guard value.count >= 4 else { return nil }
        var best: (score: Int, bytes: [UInt8])?
        for index in 0...(value.count - 4) {
            let window = Array(value[index..<(index + 4)])
            guard window.allSatisfy({ $0 <= 100 }) else { continue }
            let score = window.reduce(0) { $0 + Int($1) }
            if score > (best?.score ?? -1) { best = (score, window) }
        }
        return best?.bytes
    }

    public static func fromU8Window(_ bytes: [UInt8]) -> AudioMeterLevels {
        precondition(bytes.count >= 4)
        let a = Int(bytes[0])
        let b = Int(bytes[1])
        let c = Int(bytes[2])
        let d = Int(bytes[3])
        let currentFirst = (c >= a && d >= b) || !(a >= c && b >= d)
        let currentLeft = currentFirst ? a : c
        let currentRight = currentFirst ? b : d
        let peakLeft = currentFirst ? c : a
        let peakRight = currentFirst ? d : b
        let ceiling = max(a, b, c, d)
        if ceiling <= maxSegment {
            return AudioMeterLevels(
                segments: currentLeft, currentRight: currentRight,
                peakLeft: peakLeft, peakRight: peakRight)
        }
        return AudioMeterLevels(
            left: AudioMeterChannel(
                levelDB: decibels(percent: currentLeft), peakDB: decibels(percent: peakLeft)),
            right: AudioMeterChannel(
                levelDB: decibels(percent: currentRight), peakDB: decibels(percent: peakRight)))
    }

    public static func parseInt16Pairs(_ value: [UInt8]) -> AudioMeterLevels? {
        guard value.count >= 4 else { return nil }
        func i16(_ offset: Int) -> Int {
            Int(Int16(bitPattern: UInt16(value[offset]) | (UInt16(value[offset + 1]) << 8)))
        }
        let count = value.count / 2
        guard count >= 2 else { return nil }
        let samples = (0..<min(count, 4)).map { i16($0 * 2) }
        let currentLeft = samples[0]
        let currentRight = samples[1]
        let peakLeft = samples.count > 2 ? samples[2] : currentLeft
        let peakRight = samples.count > 3 ? samples[3] : currentRight
        let all = [currentLeft, currentRight, peakLeft, peakRight]
        // All-zero is idle silence, not four channels sitting at 0 dBFS.
        if all.allSatisfy({ $0 == 0 }) { return .silent }
        if all.allSatisfy({ (-600...50).contains($0) }) {
            let scale = all.allSatisfy({ (-60...0).contains($0) || $0 == 0 }) ? 1.0 : 10.0
            func db(_ raw: Int) -> Double {
                max(AudioMeterBallistics.floorDB, min(0, Double(raw) / scale))
            }
            return AudioMeterLevels(
                left: AudioMeterChannel(levelDB: db(currentLeft), peakDB: db(peakLeft)),
                right: AudioMeterChannel(levelDB: db(currentRight), peakDB: db(peakRight)))
        }
        if all.allSatisfy({ (0...32_767).contains($0) }) {
            func linear(_ raw: Int) -> Double {
                AudioMeterBallistics.decibels(fromLinear: Double(raw) / 32_767.0)
            }
            return AudioMeterLevels(
                left: AudioMeterChannel(levelDB: linear(currentLeft), peakDB: linear(peakLeft)),
                right: AudioMeterChannel(levelDB: linear(currentRight), peakDB: linear(peakRight)))
        }
        return nil
    }

    private static func scaledSegment(_ byte: UInt8) -> Int {
        if byte <= maxSegment { return Int(byte) }
        return Int((Double(byte) / 100.0) * Double(maxSegment) + 0.5)
    }

    private static func decibels(percent: Int) -> Double {
        let fraction = Double(min(max(percent, 0), 100)) / 100.0
        return AudioMeterBallistics.floorDB * (1 - fraction)
    }
}
