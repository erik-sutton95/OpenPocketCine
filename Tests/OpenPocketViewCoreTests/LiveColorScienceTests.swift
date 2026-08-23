import Testing

@testable import OpenPocketViewCore

@Suite(.serialized)
struct LiveColorScienceTests {
    private let transfers = MonitorTransfer.allCases

    init() {
        ScopeExposureCeiling.reset()
    }

    // MARK: - Protocol contract

    @Test func colorModeMapsToMonitorTransfer() {
        #expect(MonitorTransfer(.normal) == .rec709)
        #expect(MonitorTransfer(.hdr) == .hdr)
        #expect(MonitorTransfer(.dLog) == .dlog)
        #expect(MonitorTransfer(.dLog2) == .dlog2)
        #expect(ColorMode.normal.rawValue == 0x3F)
        #expect(ColorMode.hdr.rawValue == 0x3C)
        #expect(ColorMode.dLog.rawValue == 0x17)
        #expect(ColorMode.dLog2.rawValue == 0x41)

        var status = CameraStatus()
        #expect(status.monitorTransfer == nil)
        status.colorMode = .dLog2
        #expect(status.monitorTransfer == .dlog2)
    }

    @Test func tapSignatureInfersDLog2FromPaperBlackAndLiveCeiling() {
        #expect(MonitorTransfer.inferred(minByte: 16, maxByte: 188, fallback: .rec709) == .dlog2)
        #expect(MonitorTransfer.inferred(minByte: 16, maxByte: 247, fallback: .rec709) == .dlog2)
        #expect(MonitorTransfer.inferred(minByte: 16, maxByte: 189, fallback: .rec709) == .dlog2)
        #expect(MonitorTransfer.inferred(minByte: 0, maxByte: 255, fallback: .rec709) == .rec709)
        #expect(
            MonitorTransfer.inferred(minByte: 16, maxByte: 188, fallback: .dlog) == .dlog,
            "explicit ColorMode wins")
        #expect(MonitorTransfer.inferred(minByte: 24, maxByte: 200, fallback: .rec709) == .dlog)
    }

    // MARK: - Transfer functions (paper anchors)

    @Test func roundTripGreyBlackPeak() {
        // D-Log's published constants are rounded (3.89616 ≈ 1/0.256663), so the
        // curve inverts to ~1e-5 relative, not machine precision.
        for transfer in transfers {
            for linear in [0.0, 0.18, transfer.peakLinear] {
                let encoded = LiveColorScience.encode(linear, transfer: transfer)
                let back = LiveColorScience.linearize(encoded, transfer: transfer)
                #expect(
                    abs(back - linear) <= max(1e-6, linear * 1e-4),
                    "\(transfer) round trip at \(linear)")
            }
        }
    }

    @Test func dLog2PaperAnchors() {
        // Gamut white paper Rev 1.0 (2026-06-30) curve table, 1e-6 or table precision.
        let e = { LiveColorScience.encode($0, transfer: .dlog2) }
        #expect(abs(e(0) - 0.062561) < 1e-6)
        #expect(abs(e(0.0289617) - 0.148315) < 1e-5)
        #expect(abs(e(0.18) - 0.304985337243402) < 1e-12)
        #expect(abs(e(0.9) - 0.445264) < 1e-6)
        #expect(abs(e(1.0) - 0.454539) < 1e-6)
        #expect(abs(e(18) - 0.710090) < 1e-6)
        #expect(abs(e(475) - 1.0) < 1e-9)
        // 10-bit full-range code table from the paper.
        for (linear, code) in [
            (0.0, 64.0), (0.18, 312.0), (1.0, 465.0), (18.0, 726.0), (475.0, 1023.0),
        ] {
            #expect(abs(e(linear) * 1023 - code) < 0.5, "code for linear \(linear)")
        }
        #expect(MonitorTransfer.dlog2.peakLinear == 475.0)
    }

    @Test func dLogWhitePaperAnchors() {
        // DJI 2017 white paper: 0% → 95, 18% → 408, 90% → 586 (of 1023); peak 4200%.
        let e = { LiveColorScience.encode($0, transfer: .dlog) }
        #expect(abs(e(0) * 1023 - 95.0) < 0.5)
        #expect(abs(e(0.18) * 1023 - 408.0) < 0.5)
        #expect(abs(e(0.9) * 1023 - 586.0) < 0.5)
        #expect(abs(e(42.0) - 1.0) < 1e-5)
        #expect(MonitorTransfer.dlog.peakLinear == 42.0)
    }

    @Test func hlgFollowsBT2408() {
        #expect(abs(LiveColorScience.encode(1.0, transfer: .hdr) - 0.75) < 1e-6)
        #expect(abs(LiveColorScience.encode(0.18, transfer: .hdr) - 0.378) < 1e-3)
    }

    @Test func rec709EighteenPercent() {
        #expect(abs(LiveColorScience.encode(0.18, transfer: .rec709) - 0.409) < 1e-3)
        #expect(LiveColorScience.encode(0, transfer: .rec709) == 0)
        #expect(abs(LiveColorScience.encode(1, transfer: .rec709) - 1) < 1e-9)
    }

    // MARK: - Anchors (curve-fraction axis; the tap expands the legal-range wire)

    @Test func anchorsAreCurveFractions() {
        // The tap expands container codes back to curve fractions
        // (container10 = 64 + curve × 876, measured on Pocket 4P recordings),
        // so the anchors are the papers' own values.
        let cases: [(MonitorTransfer, Double, Double)] = [
            (.dlog2, 15.95, 77.77),
            (.dlog, 23.69, 101.68),
            (.rec709, 0.00, 104.30),
            (.hdr, 0.00, 96.46),
        ]
        for (transfer, black8, mid8) in cases {
            let a = ScopeAnchors.make(transfer: transfer, iso: 1600)
            #expect(abs(a.black * 255 - black8) < 0.05, "\(transfer) black")
            #expect(abs(a.mid * 255 - mid8) < 0.05, "\(transfer) mid")
            if transfer == .rec709 || transfer == .hdr {
                #expect(a.clip == 1.0, "\(transfer) preview peak is encoded 1.0")
            } else {
                #expect(
                    a.clipEdgeByte == ScopeExposureCeiling.clipByte(transfer: transfer, iso: 1600),
                    "\(transfer) clip is the live-tap EI ceiling, not 255")
                #expect(a.clip < 1.0, "\(transfer) must not stretch 255 to 100")
            }
        }
        #expect(abs(MonitorTransfer.dlog2.middleGrayEncoded - 0.304985337243402) < 1e-12)
        #expect(abs(MonitorTransfer.dlog2.middleGrayPaperIRE - 30.50) < 0.01)
    }

    // MARK: - Anchored scope axis (OpenZCine ScopeDisplayScale semantics)

    @Test func waveformLevelPinsAnchors() {
        for transfer in transfers {
            let a = transfer.scopeAnchors
            #expect(
                abs(ScopeDisplayScale.waveformLevel(a.black, transfer: transfer) - 0.05) < 1e-12,
                "\(transfer) black on the 0 line")
            #expect(
                abs(ScopeDisplayScale.waveformLevel(a.clip, transfer: transfer) - 0.95) < 1e-12,
                "\(transfer) clip on the 100 line")
            #expect(
                abs(ScopeDisplayScale.waveformLevel(a.mid, transfer: transfer) - a.midLevel)
                    < 1e-12,
                "\(transfer) grey pinned")
            // Log toes keep a live sub-black margin; zero-black transfers sit on the line.
            let zero = ScopeDisplayScale.waveformLevel(0, transfer: transfer)
            #expect(a.black > 0 ? zero == 0 : zero == 0.05, "\(transfer) at code 0")
        }
    }

    @Test func waveformLevelStrictlyIncreasing() {
        for transfer in transfers {
            var previous = -1.0
            for code in 0...255 {
                let level = ScopeDisplayScale.waveformLevel(Double(code) / 255, transfer: transfer)
                #expect(level > previous, "\(transfer) flat/reversed at code \(code)")
                previous = level
            }
        }
    }

    @Test func midLevelsMatchPaperIRE() {
        // 18% is pinned at published paper IRE (encoded × 100), not
        // (mid−black)/(clip−black) which would move with the EI ceiling.
        let expected: [(MonitorTransfer, Double)] = [
            (.dlog2, 30.50),
            (.dlog, 39.88),
            (.rec709, 40.90),
            (.hdr, 37.83),
        ]
        for (transfer, greyIRE) in expected {
            let a = ScopeAnchors.make(transfer: transfer, iso: 1600)
            #expect(
                abs(a.midLevel - ScopeDisplayScale.level(scaleIRE: greyIRE)) < 1e-3,
                "\(transfer) midLevel")
            #expect(abs(transfer.scopeGreyScaleIRE - greyIRE) < 0.05, "\(transfer) grey scale IRE")
            #expect(abs(LiveColorScience.paperIRE(a.mid) - greyIRE) < 0.05)
        }
    }

    @Test func fullDynamicRangeSceneSpansZeroToHundred() {
        // The user-facing contract: log black → the 0 line, clip → the 100 line.
        for transfer in [MonitorTransfer.dlog, .dlog2] {
            let a = transfer.scopeAnchors
            let blackIRE =
                (ScopeDisplayScale.waveformLevel(a.black, transfer: transfer)
                    - ScopeDisplayScale.crushLevel) / 0.9 * 100
            let clipIRE =
                (ScopeDisplayScale.waveformLevel(a.clip, transfer: transfer)
                    - ScopeDisplayScale.crushLevel) / 0.9 * 100
            #expect(abs(blackIRE - 0) < 1e-9)
            #expect(abs(clipIRE - 100) < 1e-9)
        }
    }

    @Test func monitorPercentContract() {
        for transfer in transfers {
            let a = transfer.scopeAnchors
            #expect(ScopeDisplayScale.monitorPercent(a.black, transfer: transfer) == 0)
            #expect(abs(ScopeDisplayScale.monitorPercent(a.clip, transfer: transfer) - 100) < 1e-9)
            #expect(ScopeDisplayScale.monitorPercent(0, transfer: transfer) == 0, "clamps below")
            #expect(ScopeDisplayScale.monitorPercent(1, transfer: transfer) == 100, "clamps above")
            let mid = ScopeDisplayScale.monitorPercent(a.mid, transfer: transfer)
            #expect(abs(mid - transfer.scopeGreyScaleIRE) < 1e-9, "grey agrees across axes")
            // signalNative inverts it.
            for percent in [0.0, 2, 55, 100] {
                let native = ScopeDisplayScale.signalNative(
                    monitorPercent: percent, transfer: transfer)
                #expect(
                    abs(ScopeDisplayScale.monitorPercent(native, transfer: transfer) - percent)
                        < 1e-9)
            }
        }
    }

    @Test func levelTableMatchesReference() {
        for transfer in transfers {
            let table = ScopeDisplayScale.levelTable(for: transfer)
            #expect(table.count == 256)
            for code in stride(from: 0, through: 255, by: 5) {
                let reference = ScopeDisplayScale.waveformLevel(
                    Double(code) / 255, transfer: transfer)
                #expect(abs(Double(table[code]) - reference) < 1e-6)
            }
        }
    }

    @Test func histogramRemapConservesAndAnchors() {
        var bins = [Int](repeating: 0, count: 256)
        bins[5] = 15  // sub-black noise
        bins[16] = 100  // D-Log2 paper black
        bins[78] = 50  // 18% grey
        bins[247] = 25  // live-tap EI ceiling
        bins[255] = 10  // above the ceiling — margin, not the 100 line
        let out = ScopeDisplayScale.remapHistogram(bins, transfer: .dlog2)
        #expect(out.reduce(0, +) == 200, "conserves total count")
        // Paper black lands on the scale-0 bucket (level 0.05 → 12/13).
        #expect(out[12] + out[13] >= 100)
        // Live-tap ceiling lands on the scale-100 bucket (level 0.95 → 242).
        #expect(out[242] == 25)
        // Code 255 is overshoot, not stretched onto 100.
        #expect(out[255] == 10)
        let subBlack = out[0...11].reduce(0, +)
        #expect(subBlack == 15)

        var dlogBins = [Int](repeating: 0, count: 256)
        dlogBins[18] = 15  // sub-black
        dlogBins[24] = 100  // D-Log paper black
        dlogBins[102] = 50  // 18% grey
        dlogBins[223] = 25  // live-tap ceiling
        dlogBins[255] = 10  // leak — margin, not the 100 line
        let dlogOut = ScopeDisplayScale.remapHistogram(dlogBins, transfer: .dlog)
        #expect(dlogOut.reduce(0, +) == 200)
        #expect(dlogOut[242] == 25, "D-Log 223 is the 100 line")
        #expect(dlogOut[255] == 10, "D-Log code 255 is overshoot")
    }

    // MARK: - Traffic lights

    @Test func trafficEdgesFollowTheAnchors() {
        for transfer in transfers {
            let a = ScopeAnchors.make(transfer: transfer, iso: 1600)
            #expect(
                a.clipEdgeByte == ScopeExposureCeiling.clipByte(transfer: transfer, iso: 1600),
                "\(transfer) clip edge")
            #expect(
                a.crushFloorByte == Int((a.black * 255).rounded(.down)), "\(transfer) crush floor")
            #expect(a.crushEdgeByte >= a.crushFloorByte, "\(transfer) crush edge")
        }
        let dlog2 = ScopeAnchors.make(transfer: .dlog2, iso: 1600)
        #expect(dlog2.clipEdgeByte == 247)
        #expect(dlog2.clipFloorByte <= 237, "IRE 95 must include journal shelf luma (~240)")
        #expect(dlog2.clipFloorByte > 188, "188 stays recoverable, not a clip lamp")
        #expect(ScopeAnchors.make(transfer: .dlog, iso: 1600).clipEdgeByte == 223)
        #expect(ScopeAnchors.make(transfer: .dlog, iso: 400).clipEdgeByte == 223)
        let dlog = ScopeAnchors.make(transfer: .dlog, iso: 1600)
        #expect(dlog.clipFloorByte <= 219)
        #expect(dlog.clipFloorByte < dlog.clipEdgeByte)
    }

    private func histogram(spikeAt code: Int, count: Int = 1000) -> [Int] {
        var bins = [Int](repeating: 0, count: 256)
        bins[code] = count
        return bins
    }

    @Test func subBlackNoiseDoesNotCrush() {
        // Below the toe floor is sensor noise under true black, not crushed picture.
        let cases: [(MonitorTransfer, Int)] = [(.dlog2, 10), (.dlog, 18)]
        for (transfer, code) in cases {
            let bins = histogram(spikeAt: code)
            let reading = ScopeTrafficLights.reading(
                red: bins, green: bins, blue: bins, transfer: transfer)
            #expect(!reading.anyCrush, "\(transfer) sub-black")
            #expect(!reading.anyClip)
        }
    }

    @Test func toePileUpCrushes() {
        for transfer in transfers {
            let floor = transfer.scopeAnchors.crushFloorByte
            let bins = histogram(spikeAt: floor + 1)
            let reading = ScopeTrafficLights.reading(
                red: bins, green: bins, blue: bins, transfer: transfer)
            #expect(reading.anyCrush, "\(transfer) toe pile-up")
            #expect(!reading.anyClip)
        }
    }

    @Test func curveTopClips() {
        for transfer in transfers {
            let bins = histogram(spikeAt: 255)
            let reading = ScopeTrafficLights.reading(
                red: bins, green: bins, blue: bins, transfer: transfer)
            #expect(reading.anyClip, "\(transfer) clip at the curve top")
            #expect(!reading.anyCrush)
        }
    }

    @Test func recoverableDLog2HighlightDoesNotClipLights() {
        let bins = histogram(spikeAt: 188)
        let reading = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2)
        #expect(!reading.anyClip, "byte 188 is below the measured 247 ceiling")
        let shelf = histogram(spikeAt: 243)
        let shelfReading = ScopeTrafficLights.reading(
            red: shelf, green: shelf, blue: shelf, transfer: .dlog2)
        #expect(shelfReading.anyClip, "live-tap shelf 243–247 must light the clip lamps")
        // Journal maxRGB is 243–246; BT.2020 luma of that shelf sits ~240.
        let lumaShelf = histogram(spikeAt: 240)
        let lumaReading = ScopeTrafficLights.reading(
            red: lumaShelf, green: lumaShelf, blue: lumaShelf,
            luma: lumaShelf, transfer: .dlog2)
        #expect(lumaReading.anyClip, "luma 240 of a 244-max door must light the lamps")
        let atCeiling = histogram(spikeAt: 247)
        let clipped = ScopeTrafficLights.reading(
            red: atCeiling, green: atCeiling, blue: atCeiling, transfer: .dlog2)
        #expect(clipped.anyClip)
    }

    @Test func blownHighlightLightsEveryChannelNotJustGreen() {
        // 4:2:0 reconstruction: G tracks Y at the ceiling, R/B sit a few codes
        // lower. The picture is still clipped — all three lamps must come on.
        var red = [Int](repeating: 0, count: 256)
        var green = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        var luma = [Int](repeating: 0, count: 256)
        red[230] = 1000
        green[247] = 1000
        blue[228] = 1000
        luma[242] = 1000
        let reading = ScopeTrafficLights.reading(
            red: red, green: green, blue: blue, luma: luma, transfer: .dlog2)
        #expect(reading.red.clip && reading.green.clip && reading.blue.clip)
        #expect(reading.anyClip)
    }

    @Test func mixedSceneDoorClipLightsLampsWhileSubjectMedianIsMid() {
        // Screenshot case: most of the frame is a person (midtones), the door
        // is blown (zebra). Median stays on the shirt — lamps must still fire.
        var red = [Int](repeating: 0, count: 256)
        var green = [Int](repeating: 0, count: 256)
        var blue = [Int](repeating: 0, count: 256)
        var luma = [Int](repeating: 0, count: 256)
        red[90] = 800
        green[90] = 800
        blue[90] = 800
        luma[90] = 800
        red[230] = 200
        green[247] = 200
        blue[228] = 200
        luma[247] = 200
        let reading = ScopeTrafficLights.reading(
            red: red, green: green, blue: blue, luma: luma, transfer: .dlog2)
        #expect(reading.red.clip && reading.green.clip && reading.blue.clip)
        #expect(
            abs(reading.green.level - 0.5) < 0.25, "bars still follow the subject, not the door")
    }

    @Test func clipLampsHoldThroughThresholdChatter() {
        let quarter = 0.025
        var bins = [Int](repeating: 0, count: 256)
        bins[128] = 970
        bins[247] = 30
        let on = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: quarter)
        #expect(on.anyClip)
        bins[247] = 20
        bins[128] = 980
        let held = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: quarter,
            previous: on)
        #expect(held.anyClip, "2.0% after 3.0% must stay lit (half of 2.5%)")
        bins[247] = 10
        bins[128] = 990
        let off = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: quarter,
            previous: held)
        #expect(!off.anyClip, "1.0% drops the latch")
    }

    @Test func greyBalancesToCentre() {
        for transfer in transfers {
            let grey = Int((transfer.scopeAnchors.mid * 255).rounded())
            let bins = histogram(spikeAt: grey)
            let reading = ScopeTrafficLights.reading(
                red: bins, green: bins, blue: bins, transfer: transfer)
            #expect(abs(reading.green.level - 0.5) < 0.02, "\(transfer) grey at centre")
            #expect(reading.green.isNeutral)
        }
    }

    @Test func thresholdLadderIsStopsOverTen() {
        #expect(ScopeTrafficLights.defaultThreshold == 0)
        // 2.6% clipped fires a 0.25-stop (2.5%) threshold; 2.4% does not.
        let quarter = 0.025
        var bins = [Int](repeating: 0, count: 256)
        bins[128] = 974
        bins[255] = 26
        var reading = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: quarter)
        #expect(reading.anyClip)
        bins[255] = 24
        bins[128] = 976
        reading = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: quarter)
        #expect(!reading.anyClip)
        // One-stop compensation (10%): 9% does not fire.
        bins[255] = 90
        bins[128] = 910
        reading = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2, threshold: 0.10)
        #expect(!reading.anyClip)
    }

    @Test func emptyHistogramReadsNeutral() {
        let bins = [Int](repeating: 0, count: 256)
        let reading = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2)
        #expect(reading == .none)
    }

    // MARK: - Zebra (monitor-percent axis, no bisection)

    @Test func zebraThresholdsRideMonitorPercent() {
        #expect(LiveZebra.highlightIRE == 100.0)
        #expect(LiveZebra.midtoneIRE == 55.0)
        for transfer in transfers {
            let clip = ScopeDisplayScale.signalNative(monitorPercent: 100, transfer: transfer)
            let expected = ScopeExposureCeiling.clipEncoded(transfer: transfer, iso: 1600)
            #expect(
                abs(clip - expected) < 1e-12, "\(transfer) highlight zebra at the live-tap ceiling")
            let black = ScopeDisplayScale.signalNative(monitorPercent: 0, transfer: transfer)
            #expect(abs(black - transfer.scopeAnchors.black) < 1e-12)
        }
        #expect(LiveColorScience.zebraHighlight(100))
        #expect(!LiveColorScience.zebraHighlight(99.4))
        #expect(LiveColorScience.zebraMidtone(58))
        #expect(!LiveColorScience.zebraMidtone(61))
    }

    // MARK: - False colour

    @Test func falseColorIREBandsMatchOpenZCine() {
        let labels = LiveColorScience.falseColorBands(.ire, transfer: .dlog2).map(\.label)
        #expect(
            labels == ["0–4", "5", "10–12", "18%", "55–61", "92–93", "94–95", "96–98", "99–100"])
        let limits = LiveColorScience.falseColorBands(.limits, transfer: .dlog2).map(\.label)
        #expect(limits == ["0–4", "5–9", "94–98", "99–100"])
    }

    @Test func dLog2StopScaleUsesDJIClipNotRED() {
        let labels = LiveColorScience.falseColorBands(.stops, transfer: .dlog2).map(\.label)
        #expect(labels.contains("18%"))
        #expect(labels.contains("Maximum"))
        #expect(abs(LiveColorScience.stops(linear: 475) - 11.366) < 0.01)
        #expect(abs(LiveColorScience.stops(linear: 42) - 7.867) < 0.01)
        #expect(LiveColorScience.stops(linear: 0) == -.infinity)
    }

    @Test func monitorIREIsTheWaveAxis() {
        for transfer in transfers {
            let paper = LiveColorScience.paperIRE(
                LiveColorScience.encode(0.18, transfer: transfer))
            #expect(
                abs(LiveColorScience.monitorIRE(linear: 0.18, transfer: transfer) - paper) < 0.5,
                "\(transfer) 18% is paper IRE on the WAVE axis, not Reinhard 42")
            let clip = ScopeExposureCeiling.clipEncoded(transfer: transfer, iso: 1600)
            #expect(
                abs(LiveColorScience.monitorIRE(encoded: clip, transfer: transfer) - 100) < 0.05)
        }
        #expect(abs(LiveColorScience.monitorIRE(linear: 0.18, transfer: .dlog2) - 30.50) < 0.5)
        #expect(abs(LiveColorScience.monitorIRE(linear: 0.18, transfer: .dlog) - 39.88) < 0.5)
        #expect(
            abs(LiveColorScience.monitorIRE(encoded: 223.0 / 255, transfer: .dlog) - 100) < 0.05)
        // 188 is recoverable D-Log2 highlight, not clip (journal max is 247).
        let early = LiveColorScience.monitorIRE(encoded: 188.0 / 255, transfer: .dlog2)
        #expect(early < 90)
        #expect(!LiveColorScience.zebraHighlight(early))
    }

    @Test func liveTapCeilingUsesMeasuredPreviewMax() {
        ScopeExposureCeiling.reset()
        #expect(ScopeExposureCeiling.clipByte(transfer: .dlog2, iso: 1600) == 247)
        #expect(ScopeExposureCeiling.clipByte(transfer: .dlog, iso: 1600) == 223)
        #expect(ScopeExposureCeiling.clipByte(transfer: .dlog, iso: 400) == 223)
        #expect(ScopeExposureCeiling.clipByte(transfer: .rec709, iso: 1600) == 255)
        #expect(ScopeExposureCeiling.clipByte(transfer: .hdr, iso: 1600) == 255)
        // Below base EI the paper scales linear by EI/1600.
        let byte800 = ScopeExposureCeiling.clipByte(transfer: .dlog2, iso: 800)
        #expect(byte800 == 231)
        #expect(byte800 < 247)
        // At/above 1600 the S-curve holds the live preview at the measured ceiling.
        #expect(ScopeExposureCeiling.clipByte(transfer: .dlog2, iso: 3200) == 247)
        // D-Log holds the measured code-space ceiling from native 400 up.
        #expect(ScopeExposureCeiling.clipByte(transfer: .dlog, iso: 800) == 223)
        #expect(ScopeExposureCeiling.clipByte(transfer: .dlog, iso: 3200) == 223)
        // 255 is not the 100 line. 188 is below the 100 line (the early-zebra bug).
        let y255 = ScopeDisplayScale.waveformLevel(1, transfer: .dlog2, iso: 1600)
        #expect(y255 > ScopeDisplayScale.clipLevel + 0.01)
        #expect(
            abs(
                ScopeDisplayScale.waveformLevel(247.0 / 255, transfer: .dlog2, iso: 1600)
                    - ScopeDisplayScale.clipLevel) < 1e-9)
        #expect(
            abs(
                ScopeDisplayScale.waveformLevel(223.0 / 255, transfer: .dlog, iso: 1600)
                    - ScopeDisplayScale.clipLevel) < 1e-9)
        #expect(
            ScopeDisplayScale.waveformLevel(188.0 / 255, transfer: .dlog2, iso: 1600)
                < ScopeDisplayScale.clipLevel - 0.05)
        // observe ignores 255 and can refine 247 → 248.
        let ignored = ScopeExposureCeiling.observeTapMax(255, transfer: .dlog2)
        #expect(ignored.clip == 247)
        ScopeExposureCeiling.setISO(1600)
        let refined = ScopeExposureCeiling.observeTapMax(248, transfer: .dlog2)
        #expect(refined.clip == 248)
        ScopeExposureCeiling.reset()
        ScopeExposureCeiling.setISO(1600)
        let dlogIgnored = ScopeExposureCeiling.observeTapMax(255, transfer: .dlog)
        #expect(dlogIgnored.clip == 223)
        let dlogRefined = ScopeExposureCeiling.observeTapMax(224, transfer: .dlog)
        #expect(dlogRefined.clip == 224)
        ScopeExposureCeiling.reset()
    }

    @Test func paperBlackAndEighteenPercentOnWave() {
        let black = LiveColorScience.encode(0, transfer: .dlog2)
        #expect(abs(ScopeDisplayScale.monitorPercent(black, transfer: .dlog2, iso: 1600)) < 1e-9)
        let grey = LiveColorScience.encode(0.18, transfer: .dlog2)
        #expect(
            abs(ScopeDisplayScale.monitorPercent(grey, transfer: .dlog2, iso: 1600) - 30.50) < 0.5)
        let band = LiveColorScience.falseColorBand(
            value: 30.50, scale: .ire, transfer: .dlog2)
        #expect(band?.label == "18%")
        let clip = LiveColorScience.falseColorBand(
            value: 100, scale: .ire, transfer: .dlog2)
        #expect(clip?.label == "99–100")
        #expect(LiveColorScience.zebraHighlight(100))
        #expect(
            !LiveColorScience.zebraHighlight(
                ScopeDisplayScale.monitorPercent(grey, transfer: .dlog2, iso: 1600)))

        let dlogBlack = LiveColorScience.encode(0, transfer: .dlog)
        #expect(abs(ScopeDisplayScale.monitorPercent(dlogBlack, transfer: .dlog, iso: 400)) < 1e-9)
        let dlogGrey = LiveColorScience.encode(0.18, transfer: .dlog)
        #expect(
            abs(ScopeDisplayScale.monitorPercent(dlogGrey, transfer: .dlog, iso: 400) - 39.88) < 0.5
        )
        #expect(
            abs(ScopeDisplayScale.monitorPercent(223.0 / 255, transfer: .dlog, iso: 400) - 100)
                < 0.05)
        #expect(
            abs(ScopeDisplayScale.monitorPercent(223.0 / 255, transfer: .dlog, iso: 1600) - 100)
                < 0.05)
        let dlogClip = LiveColorScience.falseColorBand(
            value: 100, scale: .ire, transfer: .dlog)
        #expect(dlogClip?.label == "99–100")
        #expect(
            !LiveColorScience.zebraHighlight(
                ScopeDisplayScale.monitorPercent(dlogGrey, transfer: .dlog, iso: 400)))
    }

    // MARK: - Gamut matrices (papers)

    @Test func dGamut2PaperMatrices() {
        #expect(DGamut2.redPrimary == (x: 0.7347, y: 0.2653))
        #expect(DGamut2.bluePrimary == (x: 0.0900, y: -0.0800))
        #expect(DGamut2.whiteD65 == (x: 0.3127, y: 0.3290))
        // White preservation: rows of D-Gamut2 → Rec.709 sum to ≈ 1.
        for row in [
            DGamut2.rgbToRec709.m00 + DGamut2.rgbToRec709.m01 + DGamut2.rgbToRec709.m02,
            DGamut2.rgbToRec709.m10 + DGamut2.rgbToRec709.m11 + DGamut2.rgbToRec709.m12,
            DGamut2.rgbToRec709.m20 + DGamut2.rgbToRec709.m21 + DGamut2.rgbToRec709.m22,
        ] {
            #expect(abs(row - 1) < 1e-3)
        }
        let grey = DGamut2.rgbToRec709.apply(r: 0.18, g: 0.18, b: 0.18)
        #expect(abs(grey.r - 0.18) < 1e-3 && abs(grey.g - 0.18) < 1e-3 && abs(grey.b - 0.18) < 1e-3)
        // Round trip through DWG.
        let dwg = DGamut2.rgbToDWG.apply(r: 0.4, g: 0.3, b: 0.2)
        let back = DGamut2.dwgToRGB.apply(r: dwg.r, g: dwg.g, b: dwg.b)
        #expect(abs(back.r - 0.4) < 5e-3 && abs(back.g - 0.3) < 5e-3 && abs(back.b - 0.2) < 5e-3)
    }

    @Test func dGamutV1PaperMatrices() {
        // DJI 2017 white paper values; rows preserve white.
        #expect(DGamut.rgbToRec709.m00 == 1.6746)
        #expect(DGamut.rec709ToRGB.m22 == 0.8104)
        for row in [
            DGamut.rgbToRec709.m00 + DGamut.rgbToRec709.m01 + DGamut.rgbToRec709.m02,
            DGamut.rgbToRec709.m10 + DGamut.rgbToRec709.m11 + DGamut.rgbToRec709.m12,
            DGamut.rgbToRec709.m20 + DGamut.rgbToRec709.m21 + DGamut.rgbToRec709.m22,
        ] {
            #expect(abs(row - 1) < 1e-3)
        }
    }

    // MARK: - Safety

    @Test func noNaNsAcrossEncodedSweep() {
        for transfer in transfers {
            for step in 0...200 {
                let encoded = Double(step) / 200
                let level = ScopeDisplayScale.waveformLevel(encoded, transfer: transfer)
                let percent = ScopeDisplayScale.monitorPercent(encoded, transfer: transfer)
                let linear = LiveColorScience.linearize(encoded, transfer: transfer)
                let ire = LiveColorScience.monitorIRE(encoded: encoded, transfer: transfer)
                #expect(level.isFinite && level >= 0 && level <= 1)
                #expect(percent.isFinite && percent >= 0 && percent <= 100)
                #expect(linear.isFinite && linear >= 0)
                #expect(ire.isFinite && ire >= 0 && ire <= 100)
            }
        }
    }
}
