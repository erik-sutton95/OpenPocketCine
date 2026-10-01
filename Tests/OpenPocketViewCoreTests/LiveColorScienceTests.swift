import Testing

@testable import OpenPocketViewCore

/// DJI integration side of the color science: `ColorMode` → curve, the tap fingerprint, the
/// per-source live-tap ceiling (ISO + ratchet), the official Rec.709 look curves and the
/// D-Gamut matrices. The pure curve, scope and false-colour math moved to OpenCineMedia with
/// its tests. Each test gets a fresh suite value, so a fresh ceiling: no shared state.
@Suite struct LiveColorScienceTests {
    private let transfers = MonitorTransfer.allCases
    private let ceiling = ScopeExposureCeiling()

    private func percent(_ c: Double, _ transfer: MonitorTransfer, iso: Int? = nil) -> Double {
        ScopeDisplayScale.monitorPercent(
            c, transfer: transfer, clipByte: ceiling.clipByte(transfer: transfer, iso: iso))
    }

    private func lamps(_ bins: [Int], _ transfer: MonitorTransfer) -> ScopeTrafficLightsReading {
        ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, luma: bins, transfer: transfer,
            clipByte: ceiling.clipByte(transfer: transfer))
    }

    @Test func dLogMScopesPreserveSignalAndIgnoreDLogISOAnchors() {
        let transfer = MonitorTransfer(.dLogM)
        #expect(transfer != .dlog)
        for iso in [100, 400, 1600, 6400] {
            for byte in 0...255 {
                let signal = Double(byte) / 255
                #expect(abs(percent(signal, transfer, iso: iso) - signal * 100) < 1e-8)
            }
            #expect(ceiling.clipByte(transfer: transfer, iso: iso) == 255)
        }
        #expect(MonitorTransfer.inferred(minByte: 24, maxByte: 223, fallback: transfer) == transfer)
        #expect(CamCapIso.baseISO(transfer: transfer) == nil)
    }

    // MARK: - Protocol contract

    @Test func colorModeMapsToMonitorTransfer() {
        #expect(MonitorTransfer(.normal) == .rec709)
        #expect(MonitorTransfer(.hdr) == .hdr)
        #expect(MonitorTransfer(.dLog) == .dlog)
        #expect(MonitorTransfer(.dLog2) == .dlog2)

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

    /// D-Log M LUT exposure keeps the D-Log curve (the empirical scope estimate must not
    /// change baked images); every other curve compensates in its own light.
    @Test func lutExposureKeepsDLogForDLogM() {
        #expect(MonitorTransfer.dlogm.lutExposureTransfer == .dlog)
        for transfer in transfers where transfer != .dlogm {
            #expect(transfer.lutExposureTransfer == transfer)
        }
    }

    // MARK: - Live-tap ceiling (per source)

    @Test func anchorsFollowTheSourceCeiling() {
        for transfer in transfers {
            let a = ceiling.anchors(transfer: transfer, iso: 1600)
            #expect(
                a.clipEdgeByte == ceiling.clipByte(transfer: transfer, iso: 1600),
                "\(transfer) clip is the live-tap EI ceiling")
            if transfer == .rec709 || transfer == .hdr {
                #expect(a.clip == 1.0, "\(transfer) preview peak is encoded 1.0")
            }
        }
        let dlog2 = ceiling.anchors(transfer: .dlog2, iso: 1600)
        #expect(dlog2.clipEdgeByte == 247)
        #expect(dlog2.clipFloorByte == 240, "the clip shelf under the 247 ceiling, not WAVE 95")
        #expect(ceiling.anchors(transfer: .dlog, iso: 1600).clipEdgeByte == 223)
        #expect(ceiling.anchors(transfer: .dlog, iso: 400).clipEdgeByte == 223)
        for transfer in transfers {
            #expect(
                ScopeExposureCeiling.referenceClipByte(transfer: transfer)
                    == ScopeExposureCeiling().clipByte(transfer: transfer),
                "\(transfer) reference is a fresh source")
        }
    }

    @Test func liveTapCeilingUsesMeasuredPreviewMax() {
        #expect(ceiling.clipByte(transfer: .dlog2, iso: 1600) == 247)
        #expect(ceiling.clipByte(transfer: .dlog, iso: 1600) == 223)
        #expect(ceiling.clipByte(transfer: .dlog, iso: 400) == 223)
        #expect(ceiling.clipByte(transfer: .rec709, iso: 1600) == 255)
        #expect(ceiling.clipByte(transfer: .hdr, iso: 1600) == 255)
        // Below base EI the paper scales linear by EI/1600.
        let byte800 = ceiling.clipByte(transfer: .dlog2, iso: 800)
        #expect(byte800 == 231)
        #expect(byte800 < 247)
        // At/above 1600 the S-curve holds the live preview at the measured ceiling.
        #expect(ceiling.clipByte(transfer: .dlog2, iso: 3200) == 247)
        // D-Log holds the measured code-space ceiling from native 400 up.
        #expect(ceiling.clipByte(transfer: .dlog, iso: 800) == 223)
        #expect(ceiling.clipByte(transfer: .dlog, iso: 3200) == 223)
        // observe ignores 255 and can refine 247 → 248.
        let ignored = ceiling.observeTapMax(255, transfer: .dlog2)
        #expect(ignored.clip == 247)
        ceiling.setISO(1600)
        let refined = ceiling.observeTapMax(248, transfer: .dlog2)
        #expect(refined.clip == 248)
        ceiling.reset()
        ceiling.setISO(1600)
        let dlogIgnored = ceiling.observeTapMax(255, transfer: .dlog)
        #expect(dlogIgnored.clip == 223)
        let dlogRefined = ceiling.observeTapMax(224, transfer: .dlog)
        #expect(dlogRefined.clip == 224)
    }

    /// STATE-01: two cameras (or a camera and a clip) each own a ceiling. One source's ISO
    /// and tap ratchet must never move the other's WAVE 100, zebra or clip lamps.
    @Test func twoSourcesKeepIndependentCeilings() {
        let a = ScopeExposureCeiling()
        let b = ScopeExposureCeiling()
        a.setISO(800)
        a.observeTapMax(233, transfer: .dlog2)
        b.observeTapMax(224, transfer: .dlog)
        #expect(a.resolvedISO() == 800)
        #expect(b.resolvedISO() == ScopeExposureCeiling.referenceEI)
        #expect(a.clipByte(transfer: .dlog2) == 233, "a ratcheted its own ISO 800 point")
        #expect(b.clipByte(transfer: .dlog2) == 247, "b never saw a's ISO or ratchet")
        #expect(b.clipByte(transfer: .dlog) == 224)
        #expect(a.clipByte(transfer: .dlog) == 223, "a never saw b's D-Log ratchet")
        var bins = [Int](repeating: 0, count: 256)
        bins[230] = 1000
        let lampsA = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2,
            clipByte: a.clipByte(transfer: .dlog2))
        let lampsB = ScopeTrafficLights.reading(
            red: bins, green: bins, blue: bins, transfer: .dlog2,
            clipByte: b.clipByte(transfer: .dlog2))
        #expect(lampsA.anyClip && !lampsB.anyClip)
        a.reset()
        #expect(b.clipByte(transfer: .dlog) == 224, "resetting a leaves b alone")
    }

    @Test func sceneStopClipFollowsTheCameraCeiling() {
        let dlog2Clip = ceiling.clipEncoded(transfer: .dlog2, iso: 1600)
        let dlog2Stops = LiveColorScience.stops(encoded: dlog2Clip, transfer: .dlog2)
        #expect(dlog2Stops > 10.5)
        #expect(
            LiveColorScience.falseColorBand(
                value: dlog2Stops, scale: .sceneStops, transfer: .dlog2, clipEncoded: dlog2Clip)?
                .label == "clip")
        #expect(ceiling.clipEncoded(transfer: .rec709) == 1)
    }

    @Test func clipToolsAgreeOnTheClipShelf() {
        ceiling.setISO(1600)
        func histogram(atByte byte: Int, pixels: Int = 40) -> [Int] {
            var bins = [Int](repeating: 0, count: 256)
            bins[Int(MonitorTransfer.dlog2.middleGrayEncoded * 255)] = 5_000
            bins[byte] = pixels
            return bins
        }
        let clip = ceiling.clipByte(transfer: .dlog2)
        let underClip = Int(
            (ScopeDisplayScale.signalNative(monitorPercent: 93, transfer: .dlog2, clipByte: clip)
                * 255).rounded())
        #expect(underClip < 240)
        #expect(!lamps(histogram(atByte: underClip), .dlog2).anyClip, "93 IRE is under clip")
        #expect(lamps(histogram(atByte: 244), .dlog2).anyClip, "the clip shelf is clipped")
        #expect(lamps(histogram(atByte: 242), .dlog2).anyClip, "a blown window read 242 on device")

        #expect(ceiling.clipShelfByte(transfer: .dlog2) == 240)
        let zebra100 = ScopeDisplayScale.zebraHighlightNative(
            monitorPercent: 100, transfer: .dlog2, clipByte: clip)
        #expect(zebra100 * 255 <= 240.0001, "zebra 100% fires on the clip shelf")

        let shelfStops = LiveColorScience.stops(encoded: 244.0 / 255, transfer: .dlog2)
        #expect(
            LiveColorScience.falseColorBand(
                value: shelfStops, scale: .sceneStops, transfer: .dlog2,
                clipEncoded: ceiling.clipEncoded(transfer: .dlog2))?
                .label == "clip", "CineStop paints the clip shelf red")
    }

    @Test func monitorPercentFollowsTheSourceCeiling() {
        for transfer in transfers {
            let clip = ceiling.clipEncoded(transfer: transfer, iso: 1600)
            #expect(abs(percent(clip, transfer, iso: 1600) - 100) < 0.05)
        }
        #expect(abs(percent(223.0 / 255, .dlog) - 100) < 0.05)
        #expect(percent(188.0 / 255, .dlog2) < 90, "188 is recoverable, not clip")
    }

    // MARK: - Official Rec.709 looks (the 709 reading)

    @Test func videoAndIreReadLogAsTheOperatorChooses() {
        func ire(_ linear: Double, _ transfer: MonitorTransfer, rec709: Bool) -> Double {
            let read = LiveColorScience.falseColorReading(
                encoded: LiveColorScience.encode(linear, transfer: transfer), transfer: transfer,
                rec709: rec709)
            return percent(read.encoded, read.transfer)
        }
        func label(_ value: Double) -> String? {
            LiveColorScience.falseColorBand(value: value, scale: .ire, transfer: .rec709)?.label
        }
        // 709: DJI's official looks put 18% grey at 38–41 IRE and +1 stop at 53–54.
        for transfer in [MonitorTransfer.dlog2, .dlog, .dlogm] {
            #expect(label(ire(0.18, transfer, rec709: true)) == "18%MG", "\(transfer) 709 grey")
            #expect(label(ire(0.36, transfer, rec709: true)) == "MG+1", "\(transfer) 709 +1")
        }
        // LOG: the signal, like WAVE, so D-Log2 grey (~30) is a gap.
        #expect(label(ire(0.18, .dlog2, rec709: false)) == nil)
        // Curves without an official look always read the signal.
        #expect(LiveColorScience.rec709LookIRE(encoded: 0.5, transfer: .rec709) == nil)
        #expect(!LiveColorScience.readsThroughLook(transfer: .rec709, rec709: true))
        #expect(LiveColorScience.readsThroughLook(transfer: .dlog2, rec709: true))
    }

    @Test func cineStopAt709KeepsSceneStopsAndClipsWhereTheLookClips() {
        let clip = ceiling.clipByte(transfer: .dlog2)
        let log = LiveColorScience.falseColorClip(
            scale: .sceneStops, transfer: .dlog2, rec709: false, clipByte: clip)
        let look = LiveColorScience.falseColorClip(
            scale: .sceneStops, transfer: .dlog2, rec709: true, clipByte: clip)
        #expect(look.transfer == .dlog2, "CineStop stays on scene stops at 709")
        #expect(look.ceiling < log.ceiling, "the Rec.709 look saturates before the sensor")
        let bands = LiveColorScience.falseColorBands(
            .sceneStops, transfer: look.transfer, clipEncoded: look.ceiling)
        #expect(bands.contains { $0.label == "highlights" }, "light gray still sits above +2")
        let read = LiveColorScience.falseColorReading(
            encoded: 0.5, transfer: .dlog2, rec709: true, scale: .sceneStops)
        #expect(read.encoded == 0.5 && read.transfer == .dlog2)
    }

    /// Android `FalseColorBands.LOOK_SATURATION` mirrors these; change both together.
    @Test func cineStopAt709ClipMatchesTheAndroidMirror() {
        let android: [MonitorTransfer: Double] = [.dlog2: 30.0 / 32, .dlog: 1, .dlogm: 1]
        for (transfer, expected) in android {
            let clip = LiveColorScience.falseColorClip(
                scale: .sceneStops, transfer: transfer, rec709: true,
                clipByte: ceiling.clipByte(transfer: transfer))
            #expect(clip.ceiling == expected, "\(transfer)")
        }
        for transfer in [MonitorTransfer.rec709, .hdr] {
            #expect(!LiveColorScience.readsThroughLook(transfer: transfer, rec709: true))
        }
    }

    // MARK: - Gamut matrices (papers)

    @Test func dGamut2PaperMatrices() {
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
}
