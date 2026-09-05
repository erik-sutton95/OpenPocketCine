import Testing

@testable import OpenPocketViewCore

@Suite struct CamCapTests {
    @Test func twentyFivePListDiffersFromSixtyP() {
        let p25 = CamCapShutter.parseDenoms(Self.shutter25p)
        let p60 = CamCapShutter.parseDenoms(Self.shutter60p)
        #expect(!p25.isEmpty && !p60.isEmpty)
        #expect(p25 != p60)
        #expect(p25.contains(25))
        #expect(!p60.contains(25))
        #expect(!p60.contains(40))
        #expect(!p60.contains(30))
    }

    @Test func fiftyAndSixtyPPayloadIncludesOneFiftieth() {
        let p60 = CamCapShutter.parseDenoms(Self.shutter60p)
        #expect(p60.contains(50))

        var status50 = CameraStatus()
        status50.fps = 50
        status50.availableShutterDenoms = p60
        #expect(
            CamCapShutter.wheelDenoms(available: status50.availableShutterDenoms, current: 50)
                .contains(50))

        var status60 = CameraStatus()
        status60.fps = 60
        status60.availableShutterDenoms = p60
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: CamCapShutter.subscribeKey, value: Self.shutter60p),
                to: &status60))
        #expect(status60.availableShutterDenoms.contains(50))
        #expect(status60.fps == 60)
    }

    @Test func twentyFourPLikePayloadOmitsOneFiftieth() {
        let p24 = CamCapShutter.parseDenoms(Self.shutter24p)
        #expect(!p24.contains(50))
        #expect(p24.contains(60))
        #expect(p24.contains(4))
    }

    @Test func wheelCannotOfferSpeedMissingFromPayload() {
        let available = CamCapShutter.parseDenoms(Self.shutter60p)
        let wheel = CamCapShutter.wheelDenoms(available: available, current: 48)
        #expect(wheel == available)
        #expect(!wheel.contains(48))
        #expect(!wheel.contains(13))
        #expect(!wheel.contains(125))
        #expect(CamCapShutter.nearestDenom(48, in: wheel) == 50)
        #expect(CamCapShutter.nearestDenom(25, in: wheel) == 12)
    }

    @Test func cameraOrderIsPreservedAndUnique() {
        let denoms = CamCapShutter.parseDenoms(Self.shutter25p)
        #expect(denoms.first == 16_000)
        #expect(denoms.last == 4)
        #expect(Set(denoms).count == denoms.count)
    }

    @Test func subscribePushCachesShutterAndIso() {
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: CamCapShutter.subscribeKey, value: Self.shutter25p), to: &s
            ))
        #expect(s.availableShutterDenoms.contains(50))
        #expect(s.availableShutterDenoms.contains(25))

        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: CamCapIso.subscribeKey, value: Self.isoDLog2), to: &s))
        #expect(s.availableIsoIndices == [.iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200])

        let before = s.availableShutterDenoms
        #expect(
            !CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: CamCapShutter.subscribeKey, value: [0x00]), to: &s))
        #expect(s.availableShutterDenoms == before)
    }

    @Test func isoStepsSkipAutoAndStopAtEnds() {
        #expect(IsoIndex.stepped(from: .iso100, stops: 1, available: IsoIndex.allCases) == .iso200)
        #expect(IsoIndex.stepped(from: .iso25600, stops: 1, available: IsoIndex.allCases) == nil)
        #expect(IsoIndex.stepped(from: .auto, stops: 1, available: IsoIndex.allCases) == nil)
        #expect(
            IsoIndex.stepped(from: .iso400, stops: -1, available: [.iso200, .iso400, .iso800])
                == .iso200)
    }

    @Test func shutterStepsOpenTowardSlower() {
        let denoms = [16_000, 8_000, 100, 50, 25, 4]
        #expect(CamCapShutter.steppedDenom(from: 50, steps: 1, available: denoms) == 25)
        #expect(CamCapShutter.steppedDenom(from: 50, steps: -1, available: denoms) == 100)
        #expect(CamCapShutter.steppedDenom(from: 16_000, steps: -1, available: denoms) == nil)
        #expect(CamCapShutter.steppedDenom(from: 4, steps: 1, available: denoms) == nil)
        #expect(CamCapShutter.steppedDenom(from: 48, steps: 1, available: denoms) == 25)
    }

    @Test func isoAutoOnlyAndFallback() {
        #expect(CamCapIso.parseIndices(Self.isoAutoOnly) == [.auto])
        #expect(CamCapIso.wheelIndices(available: [.auto], fallback: IsoIndex.allCases) == [.auto])
        #expect(
            CamCapIso.wheelIndices(available: [], fallback: [.iso100, .iso200]) == [
                .iso100, .iso200,
            ])
    }

    @Test func dLogStars400AndDLog2Stars1600() {
        let dlog2 = CamCapIso.parseIndices(Self.isoDLog2)
        #expect(dlog2 == [.iso100, .iso200, .iso400, .iso800, .iso1600, .iso3200])
        #expect(CamCapIso.markedLabels(transfer: .dlog) == ["400"])
        #expect(CamCapIso.markedLabels(transfer: .dlog2) == ["1600"])
        #expect(CamCapIso.markedLabels(colorMode: .dLog) == ["400"])
        #expect(CamCapIso.markedLabels(colorMode: .dLog2) == ["1600"])
        #expect(CamCapIso.baseISO(transfer: .dlog) == 400)
        #expect(CamCapIso.baseISO(transfer: .dlog2) == 1600)
        for other in ["100", "200", "800", "3200", "6400", "Auto"] {
            #expect(!CamCapIso.markedLabels(transfer: .dlog).contains(other))
            #expect(!CamCapIso.markedLabels(transfer: .dlog2).contains(other))
        }
        #expect(CamCapIso.markedLabels(transfer: .dlog).isDisjoint(with: ["1600"]))
        #expect(CamCapIso.markedLabels(transfer: .dlog2).isDisjoint(with: ["400"]))
    }

    @Test func rec709AndHLGStarNothing() {
        #expect(CamCapIso.markedLabels(transfer: .rec709).isEmpty)
        #expect(CamCapIso.markedLabels(transfer: .hdr).isEmpty)
        #expect(CamCapIso.markedLabels(transfer: nil).isEmpty)
        #expect(CamCapIso.markedLabels(colorMode: .normal).isEmpty)
        #expect(CamCapIso.markedLabels(colorMode: .hdr).isEmpty)
        #expect(CamCapIso.baseISO(transfer: .rec709) == nil)
        #expect(CamCapIso.baseISO(colorMode: nil) == nil)
    }

    @Test func nativeISOHopsOnlyWhenStillOnBase() {
        #expect(
            CamCapIso.nativeISOHop(from: .dLog2, to: .dLog, current: .iso1600) == .iso400)
        #expect(
            CamCapIso.nativeISOHop(from: .dLog, to: .dLog2, current: .iso400) == .iso1600)
        #expect(
            CamCapIso.nativeISOHop(from: .dLog2, to: .dLog, current: .iso800) == nil)
        #expect(
            CamCapIso.nativeISOHop(from: .dLog, to: .dLog2, current: .iso800) == nil)
        #expect(
            CamCapIso.nativeISOHop(from: .dLog, to: .dLog2, current: .auto) == nil)
        #expect(
            CamCapIso.nativeISOHop(from: .dLog2, to: .normal, current: .iso1600) == nil)
        #expect(
            CamCapIso.nativeISOHop(from: .normal, to: .dLog2, current: .iso100) == nil)
        #expect(
            CamCapIso.nativeISOHop(from: .dLog2, to: .dLog2, current: .iso1600) == nil)
        #expect(
            CamCapIso.nativeISOHop(from: nil, to: .dLog, current: .iso1600) == nil)
        #expect(
            CamCapIso.nativeISOHop(
                from: .dLog2, to: .dLog, current: .iso1600, hopEnabled: false) == nil)
        #expect(
            CamCapIso.nativeISOHop(
                from: .dLog, to: .dLog2, current: .iso400, hopEnabled: false) == nil)
        #expect(
            CamCapIso.nativeISOHop(
                from: .dLog2, to: .dLog, current: .iso1600, hopEnabled: true) == .iso400)
    }

    @Test func isoStarDoesNotReplaceCamcapList() {
        let fromCap = CamCapIso.parseIndices(Self.isoDLog2)
        let wheel = CamCapIso.wheelIndices(available: fromCap, fallback: ColorMode.dLog2.isoIndices)
        #expect(wheel == fromCap)
        #expect(CamCapIso.markedLabels(transfer: .dlog2) == ["1600"])
        #expect(
            wheel.map(\.label).contains("400"), "400 stays on the D-Log2 camcap list, unstarred")
    }

    @Test func isoAutoMaxTablesMatchColorMode() {
        let normal: [UInt8] = [
            0x02, 0x0B, 0x00, 0x08, 0x02, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08, 0x09, 0x64, 0x00,
        ]
        let parsedN = CamCapIsoAutoMax.parse(normal)
        #expect(parsedN?.base == 100)
        #expect(parsedN?.limits == ColorMode.normal.isoAutoLimits)
        #expect(parsedN?.limits == ColorMode.hdr.isoAutoLimits)

        let dlog: [UInt8] = [0x02, 0x07, 0x00, 0x04, 0x04, 0x05, 0x06, 0x07, 0x90, 0x01]
        let parsedD = CamCapIsoAutoMax.parse(dlog)
        #expect(parsedD?.base == 400)
        #expect(parsedD?.limits == ColorMode.dLog.isoAutoLimits)

        let dlog2: [UInt8] = [0x01, 0x01, 0x00, 0x00]
        #expect(CamCapIsoAutoMax.parse(dlog2)?.limits.isEmpty == true)
        #expect(ColorMode.dLog2.offersIsoAuto == false)
        #expect(ColorMode.dLog2.isoAutoLimits.isEmpty)
        #expect(!ColorMode.dLog2.isoIndices.contains(.auto))
        #expect(ColorMode.dLog.offersIsoAuto)
        #expect(ColorMode.normal.offersIsoAuto)
        #expect(ColorMode.hdr.offersIsoAuto)
    }

    /// #180: Auto ISO range labels use the body's Rec.709 floor. SET bytes stay
    /// `IsoLimit` — Pocket 3 "100–400" was 50–400 on the camera.
    @Test func rec709IsoAutoFloorFollowsTheBody() {
        let p3 = CameraModel.resolve(modelId: 0x0020, name: nil)
        let p4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        let p4p = CameraModel.resolve(modelId: 0x0022, name: nil)
        #expect(p3.isoAutoRangeFloor == 50)
        #expect(p4.isoAutoRangeFloor == 50)
        #expect(p4p.isoAutoRangeFloor == 100)
        #expect(CameraModel.default.isoAutoRangeFloor == 100)
        #expect(
            CameraModel.resolve(modelId: nil, name: "OsmoPocket3-A1B2").isoAutoRangeFloor == 50)

        #expect(ColorMode.normal.isoAutoBase(for: p3) == 50)
        #expect(ColorMode.hdr.isoAutoBase(for: p3) == 50)
        #expect(ColorMode.dLogM.isoAutoBase(for: p3) == 50)
        #expect(ColorMode.normal.isoAutoBase(for: p4) == 50)
        #expect(ColorMode.normal.isoAutoBase(for: p4p) == 100)
        #expect(ColorMode.normal.isoAutoBase == 100, "unknown body keeps captured 4 Pro floor")
        #expect(ColorMode.dLog.isoAutoBase(for: p3) == 400, "D-Log floor is color, not body")
        #expect(ColorMode.dLog2.isoAutoBase(for: p3) == nil)

        #expect(ColorMode.normal.isoAutoLabels(for: p3).first == "50–200")
        #expect(ColorMode.normal.isoAutoLabels(for: p3).contains("50–400"))
        #expect(!ColorMode.normal.isoAutoLabels(for: p3).contains("100–400"))
        #expect(ColorMode.normal.isoAutoLabels(for: p4p).first == "100–200")
        #expect(IsoLimit.max400.label(base: 50) == "50–400")
    }

    @Test func subscriptionIncludesShutterCap() {
        #expect(Commands.subscriptionKeys.contains(CamCapShutter.subscribeKey))
        #expect(Commands.subscriptionKeys.contains(CamCapIso.subscribeKey))
        #expect(Commands.subscriptionKeys.contains(CamCapColorMode.subscribeKey))
        #expect(Commands.subscriptionKeys.contains(CamCapVideoFormat.subscribeKey))
    }

    @Test func nanoColorCapListsThreeCapturedModes() {
        let value: [UInt8] = [0x01, 0x04, 0x00, 0x03, 0x00, 0x3F, 0x3D]
        let nano = CameraModel.resolve(modelId: 0x0019, name: nil)
        #expect(CamCapColorMode.parse(value, model: nano) == [.normal, .normal10, .dLogM])
        #expect(ColorMode.parseImageEffect([0, 0, 0x00], model: nano) == .normal)
        #expect(ColorMode.parseImageEffect([0, 0, 0x3F], model: nano) == .normal10)
        #expect(ColorMode.parseImageEffect([0, 0, 0x3D], model: nano) == .dLogM)
        #expect(MonitorTransfer(.normal10) == .rec709)
        #expect(MonitorTransfer(.dLogM) == .dlog)
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "camcap_color_mode", value: value), to: &s, model: nano))
        #expect(s.availableColorModes == [.normal, .normal10, .dLogM])
        #expect(
            CamCapColorMode.wheel(available: s.availableColorModes, family: .nano)
                == [.normal, .normal10, .dLogM])
    }

    @Test func emptyAvailableShowsOnlyCurrent() {
        #expect(CamCapShutter.wheelDenoms(available: [], current: 80) == [80])
        #expect(CamCapShutter.wheelDenoms(available: [], current: -1).isEmpty)
    }

    @Test func videoFormatTableIsResFpsPairs() {
        let formats = CamCapVideoFormat.parse(Self.videoFormatPocket4Pro)
        #expect(formats.count == 12)
        #expect(formats.first == VideoFormat(resolution: .p4K, frameRate: .fps24))
        #expect(formats.contains(VideoFormat(resolution: .p4K, frameRate: .fps60)))
        #expect(formats.contains(VideoFormat(resolution: .p1080, frameRate: .fps24)))
        #expect(!formats.contains(where: { $0.frameRate.fps > 60 }))
        #expect(
            CamCapVideoFormat.resolutions(available: formats, current: .p4K)
                == [.p4K, .p1080])
        #expect(
            CamCapVideoFormat.frameRates(
                available: formats, resolution: .p4K, current: .fps25
            ).map(\.fps) == [24, 25, 30, 48, 50, 60])
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(
                    name: CamCapVideoFormat.subscribeKey, value: Self.videoFormatPocket4Pro),
                to: &s))
        #expect(s.availableVideoFormats.count == 12)
        #expect(
            CamCapVideoFormat.frameRates(
                available: [], resolution: .p4K, current: .fps24
            ).map(\.fps) == [24, 25, 30, 48, 50, 60])
    }

    @Test func colorModesFollowTheBody() {
        let pro = CameraModel.resolve(modelId: 0x0022, name: nil)
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: nil)
        let nano = CameraModel.resolve(modelId: 0x0019, name: nil)
        #expect(ColorMode.available(for: pro) == [.normal, .hdr, .dLog, .dLog2])
        #expect(ColorMode.available(for: pocket4) == [.normal, .hdr, .dLog])
        #expect(ColorMode.available(for: pocket3) == [.normal, .hdr, .dLogM])
        #expect(ColorMode.available(for: nano) == [.normal, .normal10, .dLogM])
        #expect(ColorMode.dLogM.label(for: .pocket) == "D-Log M")
        #expect(ColorMode(label: "D-Log M") == .dLogM)
        #expect(!ColorMode.available(for: pocket3).contains(.dLog2))
        #expect(!ColorMode.available(for: pocket3).contains(.dLog))
        #expect(!ColorMode.available(for: pocket4).contains(.dLog2))
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: nil, name: "OsmoPocket4P-ABCD"))
                .contains(.dLog2))
        #expect(
            !ColorMode.available(for: CameraModel.resolve(modelId: nil, name: "OsmoPocket4-ABCD"))
                .contains(.dLog2))
        #expect(
            ColorMode.available(for: CameraModel.resolve(modelId: nil, name: "OsmoPocket3-ABCD"))
                == [.normal, .hdr, .dLogM])
        #expect(
            !CamCapColorMode.wheel(
                available: [.normal, .hdr, .dLog, .dLog2], model: pocket3
            ).contains(.dLog2))
        #expect(
            !CamCapColorMode.wheel(
                available: [.normal, .hdr, .dLog, .dLog2], model: pocket4
            ).contains(.dLog2))
        #expect(
            CamCapColorMode.wheel(
                available: [.normal, .hdr, .dLog, .dLog2], model: pro
            ) == [.normal, .hdr, .dLog, .dLog2])
    }

    /// #176: Pocket 3 Rec.709 is `00`, D-Log M is `3D`. `3F` is Pocket 4 Normal
    /// and is rejected; sending `00` as D-Log M switched the body to Normal.
    @Test func pocket3ColorWireSwapsNormalAndDLogM() {
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: nil)
        let muse = CameraModel.resolve(modelId: nil, name: "Xtra Muse")
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        let nano = CameraModel.resolve(modelId: 0x0019, name: nil)

        #expect(ColorMode.normal.wireByte(for: pocket3) == 0x00)
        #expect(ColorMode.dLogM.wireByte(for: pocket3) == 0x3D)
        #expect(ColorMode.hdr.wireByte(for: pocket3) == 0x3C)
        #expect(ColorMode.normal.wireByte(for: muse) == 0x00)
        #expect(ColorMode.dLogM.wireByte(for: muse) == 0x3D)

        #expect(ColorMode.fromWire(0x00, model: pocket3) == .normal)
        #expect(ColorMode.fromWire(0x3D, model: pocket3) == .dLogM)
        #expect(ColorMode.fromWire(0x3C, model: pocket3) == .hdr)
        #expect(ColorMode.parseImageEffect([0, 0, 0x00], model: pocket3) == .normal)
        #expect(ColorMode.parseImageEffect([0, 0, 0x3D], model: pocket3) == .dLogM)

        #expect(Commands.setColorMode(.normal, model: pocket3).payload == [0x00])
        #expect(Commands.setColorMode(.dLogM, model: pocket3).payload == [0x3D])
        #expect(Commands.setColorMode(.hdr, model: pocket3).payload == [0x3C])

        #expect(ColorMode.normal.wireByte(for: pocket4) == 0x3F)
        #expect(ColorMode.normal.wireByte(for: nano) == 0x00)
        #expect(ColorMode.normal10.wireByte(for: nano) == 0x3F)
        #expect(ColorMode.dLogM.wireByte(for: nano) == 0x3D)
        #expect(ColorMode.fromWire(0x00, model: nano) == .normal)
        #expect(ColorMode.fromWire(0x3F, model: nano) == .normal10)
        #expect(ColorMode.fromWire(0x3D, model: nano) == .dLogM)
        #expect(Commands.setColorMode(.normal, model: pocket4).payload == [0x3F])
        #expect(Commands.setColorMode(.normal, model: nano).payload == [0x00])
        #expect(Commands.setColorMode(.normal10, model: nano).payload == [0x3F])
        #expect(Commands.setColorMode(.dLogM, model: nano).payload == [0x3D])
        #expect(Commands.setColorMode(.dLogM).payload == [0x00])

        let cap: [UInt8] = [0x01, 0x04, 0x00, 0x03, 0x00, 0x3C, 0x3D]
        #expect(CamCapColorMode.parse(cap, model: pocket3) == [.normal, .hdr, .dLogM])
        #expect(
            CamCapColorMode.wheel(available: [.normal, .hdr, .dLogM], model: pocket3)
                == [.normal, .hdr, .dLogM])

        var s = CameraStatus()
        var effect = [UInt8](repeating: 0, count: 16)
        effect[2] = 0x00
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_image_effect", value: effect),
                to: &s, model: pocket3))
        #expect(s.colorMode == .normal)
        effect[2] = 0x3D
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "cam_image_effect", value: effect),
                to: &s, model: pocket3))
        #expect(s.colorMode == .dLogM)
    }

    @Test func zoomStopsFollowTheBody() {
        let pro = CameraModel.resolve(modelId: 0x0022, name: nil)
        let pocket4 = CameraModel.resolve(modelId: 0x0021, name: nil)
        let pocket3 = CameraModel.resolve(modelId: 0x0020, name: nil)
        let nano = CameraModel.resolve(modelId: 0x0019, name: nil)
        #expect(pro.zoomStops == [1, 3, 6, 12])
        #expect(pocket4.zoomStops == [1, 2, 4])
        #expect(pocket3.zoomStops == [1, 2, 4])
        #expect(nano.zoomStops == [1])
        #expect(pocket3.activeZoomStops(resolution: .p4K, shootingMode: 0x01) == [1, 2])
        #expect(pocket3.activeZoomStops(resolution: .p1080, shootingMode: 0x01) == [1, 2, 4])
        #expect(pocket4.activeZoomStops(resolution: .p4K, shootingMode: 0x01) == [1, 2, 4])
        #expect(pro.activeZoomStops(resolution: .p4K, shootingMode: 0x00) == [1, 3])
        #expect(pocket4.activeZoomStops(resolution: .p4K, shootingMode: 0x00) == [1])
        #expect(CamFov.nextJump(from: 1, stops: [1, 2, 4]) == 2)
        #expect(CamFov.nextJump(from: 2, stops: [1, 2, 4]) == 4)
        #expect(CamFov.nextJump(from: 4, stops: [1, 2, 4]) == 1)
        #expect(CamFov.previousJump(from: 1, stops: [1, 2, 4]) == 1)
        #expect(CamFov.previousJump(from: 2, stops: [1, 2, 4]) == 1)
        #expect(CamFov.previousJump(from: 4, stops: [1, 2, 4]) == 2)
        #expect(CamFov.previousJump(from: 3) == 1)
        #expect(CamFov.previousJump(from: 12) == 6)
        #expect(CamFov.chipWrite(forJump: 2) == .lens(CamFov.lensPosition(for: 2)))
        #expect(CamFov.chipWrite(forJump: 4) == .lens(CamFov.lensPosition(for: 4)))
        #expect(CamFov.clamp(12, max: 4) == 4)
        #expect(CamFov.isJumpStop(2, stops: [1, 2, 4]))
        #expect(!CamFov.isJumpStop(2))
    }

    private static let shutter25p = hex(
        "016d000002000101001e00052180be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280002880001e80001980000c80000a8000088000068000058000048000"
    )
    private static let shutter60p = hex(
        "0164000002000101001e00051e80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80003280000c80000a8000088000068000058000048000"
    )
    private static let shutter24p = hex(
        "0161000002000101001e00051d80be00409f00009900889300a08f00808c00c48900d08700408600e28400e88300208300808200f48100908100408100f08000c88000a080007880006480005080003c80000c80000a8000088000068000058000048000"
    )
    private static let isoDLog2: [UInt8] = [
        0x01, 0x08, 0x00, 0x00, 0x06, 0x03, 0x04, 0x05, 0x06, 0x07, 0x08,
    ]
    private static let isoAutoOnly: [UInt8] = [0x01, 0x03, 0x00, 0x00, 0x01, 0x00]
    /// `camcap_video_format` Pocket 4 Pro Video mode (`mimo-live-start-20260828`).
    private static let videoFormatPocket4Pro = hex(
        "0125000c1001001002001003001004001005001006000a06000a05000a04000a03000a02000a0100"
    )

    private static func hex(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map {
            let i = s.index(s.startIndex, offsetBy: $0)
            return UInt8(s[i..<s.index(i, offsetBy: 2)], radix: 16)!
        }
    }
}
