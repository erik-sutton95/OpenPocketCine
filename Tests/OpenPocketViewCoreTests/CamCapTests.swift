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

    @Test func subscriptionIncludesShutterCap() {
        #expect(Commands.subscriptionKeys.contains(CamCapShutter.subscribeKey))
        #expect(Commands.subscriptionKeys.contains(CamCapIso.subscribeKey))
        #expect(Commands.subscriptionKeys.contains(CamCapColorMode.subscribeKey))
    }

    @Test func nanoColorCapListsThreeCapturedModes() {
        let value: [UInt8] = [0x01, 0x04, 0x00, 0x03, 0x00, 0x3F, 0x3D]
        #expect(CamCapColorMode.parse(value) == [.dLogM, .normal, .normal10])
        #expect(ColorMode.parseImageEffect([0, 0, 0x3D]) == .normal10)
        #expect(ColorMode.parseImageEffect([0, 0, 0x00]) == .dLogM)
        #expect(MonitorTransfer(.normal10) == .rec709)
        #expect(MonitorTransfer(.dLogM) == .dlog)
        var s = CameraStatus()
        #expect(
            CameraStatusDecoder.applySubscribePush(
                SubscribePush.pack(name: "camcap_color_mode", value: value), to: &s))
        #expect(s.availableColorModes == [.dLogM, .normal, .normal10])
        #expect(
            CamCapColorMode.wheel(available: s.availableColorModes, family: .nano)
                == [.normal, .normal10, .dLogM])
    }

    @Test func emptyAvailableShowsOnlyCurrent() {
        #expect(CamCapShutter.wheelDenoms(available: [], current: 80) == [80])
        #expect(CamCapShutter.wheelDenoms(available: [], current: -1).isEmpty)
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

    private static func hex(_ s: String) -> [UInt8] {
        stride(from: 0, to: s.count, by: 2).map {
            let i = s.index(s.startIndex, offsetBy: $0)
            return UInt8(s[i..<s.index(i, offsetBy: 2)], radix: 16)!
        }
    }
}
