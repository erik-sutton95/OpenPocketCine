import Foundation
import Testing

@testable import OpenPocketViewCore

/// The Swift half of `Tests/Fixtures/camfov-vectors.tsv`.
///
/// Kotlin re-implements `CamFov` and `VideoResolution` by hand, and nothing in
/// the build links the two. Both suites read the same rows so a change that
/// lands on one side and not the other fails a test instead of shipping.
@Suite struct CamFovVectorTests {
    /// Fixtures live next to the sources, so walk up from this file rather
    /// than trusting whatever directory the test runner was started in.
    static let vectors: [[String]] = {
        let root = URL(fileURLWithPath: #filePath)
            .deletingLastPathComponent()  // OpenPocketViewCoreTests
            .deletingLastPathComponent()  // Tests
            .deletingLastPathComponent()  // repo root
        let path = root.appendingPathComponent("Tests/Fixtures/camfov-vectors.tsv").path
        let text = (try? String(contentsOfFile: path, encoding: .utf8)) ?? ""
        return
            text
            .split(separator: "\n", omittingEmptySubsequences: true)
            .map(String.init)
            .filter { !$0.hasPrefix("#") && !$0.isEmpty }
            .map { $0.components(separatedBy: "\t") }
    }()

    static func num(_ field: String) -> Double? {
        field == "-" ? nil : Double(field)
    }

    static func list(_ field: String) -> [Double] {
        field == "-" ? [] : field.split(separator: ",").compactMap { Double($0) }
    }

    /// Same tolerance both suites use: the fixture is 4-decimal text, not bits.
    static func close(_ a: Double?, _ b: Double?) -> Bool {
        guard let a, let b else { return a == nil && b == nil }
        return abs(a - b) < 1e-4
    }

    static func resolution(_ field: String) -> VideoResolution? {
        field == "-" ? nil : UInt8(field, radix: 16).map(VideoResolution.init(rawValue:))
    }

    @Test func fixtureIsPresentAndCoversEveryKind() {
        #expect(Self.vectors.count > 250, "fixture missing or truncated")
        let kinds = Set(Self.vectors.map { $0[0] })
        #expect(
            kinds == [
                "factorRaw", "factorLens", "lensPosition", "displayLabel", "displayTenths",
                "matches", "nextJump", "previousJump", "stopWithinCycle", "pocket3ZoomMax",
                "sizeTitle", "activeZoomStops", "ceilingNote",
            ])
    }

    @Test func swiftCoreMatchesEveryVector() {
        for row in Self.vectors {
            let want = row[row.count - 1]
            switch row[0] {
            case "factorRaw":
                let got = CamFov.factor(raw: UInt32(row[1]) ?? 0)
                #expect(Self.close(got, Self.num(want)), "factorRaw \(row[1])")
            case "factorLens":
                let got = CamFov.factor(lens: UInt16(row[1]) ?? 0)
                #expect(Self.close(got, Self.num(want)), "factorLens \(row[1])")
            case "lensPosition":
                let got = CamFov.lensPosition(for: Double(row[1]) ?? 0)
                #expect("\(got)" == want, "lensPosition \(row[1])")
            case "displayLabel":
                #expect(CamFov.displayLabel(factor: Double(row[1]) ?? 0) == want, "label \(row[1])")
            case "displayTenths":
                let got = CamFov.displayTenths(Double(row[1]) ?? 0)
                #expect(Self.close(got, Self.num(want)), "tenths \(row[1])")
            case "matches":
                let got = CamFov.matches(Double(row[1]) ?? 0, Double(row[2]) ?? 0)
                #expect(got == (want == "true"), "matches \(row[1]) \(row[2])")
            case "nextJump":
                let got = CamFov.nextJump(from: Double(row[1]) ?? 0, stops: Self.list(row[2]))
                #expect(Self.close(got, Self.num(want)), "nextJump \(row[1]) \(row[2])")
            case "previousJump":
                let got = CamFov.previousJump(from: Double(row[1]) ?? 0, stops: Self.list(row[2]))
                #expect(Self.close(got, Self.num(want)), "previousJump \(row[1]) \(row[2])")
            case "stopWithinCycle":
                let got = CamFov.stopWithinCycle(Double(row[1]) ?? 0, stops: Self.list(row[2]))
                #expect(Self.close(got, Self.num(want)), "stopWithinCycle \(row[1]) \(row[2])")
            case "pocket3ZoomMax":
                let got = Self.resolution(row[1])?.pocket3ZoomMax
                #expect(Self.close(got, Self.num(want)), "pocket3ZoomMax \(row[1])")
            case "sizeTitle":
                #expect(Self.resolution(row[1])?.sizeTitle == want, "sizeTitle \(row[1])")
            case "activeZoomStops":
                let family: CameraBodyFamily = {
                    switch row[2] {
                    case "pocket": .pocket
                    case "nano": .nano
                    default: .other
                    }
                }()
                let model = CameraModel(name: row[1])
                // Kotlin carries `family` as a field; Swift derives it from the
                // name. The fixture pins both readings to the same answer.
                #expect(model.family == family, "family \(row[1])")
                let got = model.activeZoomStops(
                    resolution: Self.resolution(row[3]), shootingMode: Int(row[4]) ?? -1)
                let expected = Self.list(want)
                #expect(got.count == expected.count, "stops count \(row[1]) \(row[3]) \(row[4])")
                for (a, b) in zip(got, expected) {
                    #expect(Self.close(a, b), "stops \(row[1]) \(row[3]) \(row[4])")
                }
            case "ceilingNote":
                let got = CamFov.ceilingNote(
                    size: row[1], held: Double(row[2]) ?? 0, stops: Self.list(row[3]))
                #expect((got ?? "-") == want, "ceilingNote \(row[1]) \(row[2])")
            default:
                Issue.record("unknown vector kind \(row[0])")
            }
        }
    }
}
