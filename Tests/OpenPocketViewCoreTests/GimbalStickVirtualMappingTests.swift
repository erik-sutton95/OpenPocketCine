import OpenPocketViewCore
import Testing

@Suite
struct GimbalStickVirtualMappingTests {
    @Test func defaultMappingMatchesLegacyEncode() {
        #expect(GimbalStick.Mapping.defaults.invertPan == false)
        #expect(GimbalStick.Mapping.defaults.invertTilt == false)
        #expect(GimbalStick.Mapping.defaults.deadzone == GimbalStick.deadzone)
        #expect(GimbalStick.Mapping.defaults.curve == .standard)
        #expect(GimbalStick.Mapping.defaults.curve.expo == GimbalStick.analogExpo)
        #expect(GimbalStick.Mapping.defaults.isDefault)
        #expect(GimbalStick.deadzone == 0.08)
        #expect(GimbalStick.defaultDeadzonePercent == 8)
        #expect(GimbalStick.deadzoneFromPercent(8) == GimbalStick.deadzone)
        let samples: [Double] = [-1, -0.7, -0.5, -0.08, 0, 0.08, 0.5, 0.7, 1]
        let expected: [Int: [UInt16]] = [
            1: [887, 962, 995, 1024, 1024, 1024, 1053, 1086, 1162],
            4: [474, 774, 909, 1024, 1024, 1024, 1139, 1274, 1574],
            5: [474, 712, 881, 1024, 1024, 1024, 1167, 1336, 1574],
        ]
        for (sensitivity, wire) in expected {
            let axes = samples.map { GimbalStick.axis($0, sensitivity: sensitivity) }
            #expect(axes == wire)
            let mapped = samples.map {
                GimbalStick.axis($0, sensitivity: sensitivity, mapping: .defaults)
            }
            #expect(mapped == wire)
            let pan = samples.map {
                GimbalStick.encode(x: $0, y: 0, sensitivity: sensitivity).axis1
            }
            #expect(pan == wire)
        }
        #expect(GimbalStick.encode(x: 0.04, y: -0.04) == (GimbalStick.center, GimbalStick.center))
    }

    @Test func operatorInvertComposesPictureInvertOnce() {
        let right = GimbalStick.encode(x: 1, y: 0)
        let picture = GimbalStick.encode(x: 1, y: 0, invertPan: true)
        let opPan = GimbalStick.encode(
            x: 1, y: 0, mapping: GimbalStick.Mapping(invertPan: true))
        let both = GimbalStick.encode(
            x: 1, y: 0, invertPan: true, mapping: GimbalStick.Mapping(invertPan: true))
        #expect(picture.axis1 == GimbalStick.min)
        #expect(opPan.axis1 == GimbalStick.min)
        #expect(both.axis1 == right.axis1)
        #expect(both.axis0 == GimbalStick.center)
        let opTilt = GimbalStick.encode(
            x: 0, y: 1, mapping: GimbalStick.Mapping(invertTilt: true))
        #expect(opTilt.axis0 == GimbalStick.min)
        #expect(opTilt.axis1 == GimbalStick.center)
        let tiltAndPan = GimbalStick.encode(
            x: 1, y: 1,
            invertPan: true,
            mapping: GimbalStick.Mapping(invertPan: true, invertTilt: true))
        #expect(tiltAndPan.axis0 == GimbalStick.min)
        #expect(tiltAndPan.axis1 == GimbalStick.max)
    }

    @Test func linearPathIgnoresVirtualMapping() {
        let mapped = GimbalStick.Mapping(
            invertPan: true, invertTilt: true, deadzone: 0.25, curve: .fine)
        let linear = GimbalStick.encode(
            x: 1, y: 1, invertPan: false, linear: true, mapping: mapped)
        let plain = GimbalStick.encode(x: 1, y: 1, linear: true)
        #expect(linear == plain)
        #expect(linear.axis0 == GimbalStick.max)
        #expect(linear.axis1 == GimbalStick.max)
    }

    @Test func deadzoneBoundaries() {
        #expect(GimbalStick.clampedDeadzone(-1) == 0)
        #expect(GimbalStick.clampedDeadzone(0.5) == 0.25)
        #expect(GimbalStick.clampedDeadzone(.nan) == GimbalStick.deadzone)
        #expect(GimbalStick.clampedDeadzonePercent(-4) == 0)
        #expect(GimbalStick.clampedDeadzonePercent(99) == 25)
        #expect(GimbalStick.deadzoneFromPercent(0) == 0)
        #expect(GimbalStick.deadzoneFromPercent(25) == 0.25)
        #expect(GimbalStick.analogCurve(0.2, deadzone: 0.25) == 0)
        #expect(
            GimbalStick.axis(0.2, mapping: GimbalStick.Mapping(deadzone: 0.25))
                == GimbalStick.center)
        let full = GimbalStick.axis(1, mapping: GimbalStick.Mapping(deadzone: 0.25))
        #expect(full == GimbalStick.max)
        #expect(GimbalStick.analogCurve(0.04, deadzone: 0) != 0)
        #expect(GimbalStick.analogCurve(0, deadzone: 0) == 0)
        let rest = GimbalStick.encode(
            x: 0.24, y: 0, mapping: GimbalStick.Mapping(deadzone: 0.25))
        #expect(rest == (GimbalStick.center, GimbalStick.center))
    }

    @Test func curvesAreMonotonicAndBounded() {
        for curve in GimbalStick.ResponseCurve.allCases {
            var previous = -1.01
            for step in 0...20 {
                let x = Double(step) / 20
                let y = GimbalStick.analogCurve(
                    x, deadzone: GimbalStick.deadzone, expo: curve.expo)
                #expect(y >= previous - 1e-12)
                #expect(y >= 0 && y <= 1)
                previous = y
                let axis = GimbalStick.axis(x, mapping: GimbalStick.Mapping(curve: curve))
                #expect(axis >= GimbalStick.min && axis <= GimbalStick.max)
                let neg = GimbalStick.analogCurve(
                    -x, deadzone: GimbalStick.deadzone, expo: curve.expo)
                #expect(neg == -y)
            }
            #expect(GimbalStick.analogCurve(1, expo: curve.expo) == 1)
            #expect(GimbalStick.analogCurve(0, expo: curve.expo) == 0)
        }
        let mid = 0.5
        let linear = abs(GimbalStick.analogCurve(mid, expo: 1))
        let standard = abs(GimbalStick.analogCurve(mid, expo: 2))
        let fine = abs(GimbalStick.analogCurve(mid, expo: 3))
        #expect(linear > standard)
        #expect(standard > fine)
        #expect(GimbalStick.ResponseCurve.parse(nil) == .standard)
        #expect(GimbalStick.ResponseCurve.parse("nope") == .standard)
        #expect(GimbalStick.ResponseCurve.parse("FINE") == .fine)
        #expect(GimbalStick.ResponseCurve.fromLabel("Linear") == .linear)
        #expect(GimbalStick.ResponseCurve.fromLabel("Standard") == .standard)
        #expect(GimbalStick.ResponseCurve.fromLabel("Fine") == .fine)
        #expect(GimbalStick.ResponseCurve.fromLabel("nope") == .standard)
    }

    @Test func wireStaysInsideTravel() {
        let mapping = GimbalStick.Mapping(
            invertPan: true, invertTilt: true, deadzone: 0, curve: .linear)
        for x in stride(from: -1.2, through: 1.2, by: 0.2) {
            for y in stride(from: -1.2, through: 1.2, by: 0.2) {
                let axes = GimbalStick.encode(
                    x: x, y: y, invertPan: true, sensitivity: 5, mapping: mapping)
                #expect(axes.axis0 >= GimbalStick.min && axes.axis0 <= GimbalStick.max)
                #expect(axes.axis1 >= GimbalStick.min && axes.axis1 <= GimbalStick.max)
            }
        }
        let rest = GimbalStick.encode(x: 0, y: 0, mapping: mapping)
        #expect(rest == (GimbalStick.center, GimbalStick.center))
    }
}
