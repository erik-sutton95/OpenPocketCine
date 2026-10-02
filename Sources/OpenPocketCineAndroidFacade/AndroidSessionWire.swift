import Foundation
import OpenPocketViewCore

/// Darwin-safe wire helpers used by the Android JNI shims. Compiles on macOS
/// so `swift test` still sees a real facade target; JNI itself stays
/// `#if os(Android)` in `SwiftCoreJNI.swift`.
public enum AndroidSessionWire {
    public static var coreVersion: String {
        #if arch(arm64)
            let arch = "arm64"
        #elseif arch(x86_64)
            let arch = "x86_64"
        #else
            let arch = "unknown"
        #endif
        return "OpenPocketViewCore swift-android/\(arch)"
    }

    public static func csd(from annexB: [UInt8]) -> [UInt8]? {
        let nals = Hevc.nalUnits(annexB)
        let avc = LiveVideo.detect(nals: nals) == .avc
        var out: [UInt8] = []
        for nal in nals {
            guard let first = nal.first else { continue }
            let keep: Bool
            if avc {
                let type = Avc.nalType(first)
                keep = type == Avc.sps || type == Avc.pps
            } else {
                let type = Hevc.nalType(first)
                keep = type == Hevc.vps || type == Hevc.sps || type == Hevc.pps
            }
            if keep {
                out.append(contentsOf: [0, 0, 0, 1])
                out.append(contentsOf: nal)
            }
        }
        return out.isEmpty ? nil : out
    }

    public static func nalTypeSummary(_ annexB: [UInt8]) -> String {
        let headers = Hevc.nalHeaders(annexB)
        let avc = LiveVideo.detect(headers: headers) == .avc
        let types = headers.map { avc ? Avc.nalType($0) : Hevc.nalType($0) }
        return Set(types).sorted().map(String.init).joined(separator: ",")
    }

    /// Probe + labels for playback conform preview. Request keys: `nominalFrameRate`,
    /// `minFrameDurationSeconds`, `listedRate`, optional `targetRate` / `sourceSeconds`.
    public static func conformPreviewJSON(_ request: String) -> String {
        let source = ConformPreview.probe(
            nominalFrameRate: jsonOptionalNumber(request, key: "nominalFrameRate"),
            minFrameDurationSeconds: jsonOptionalNumber(request, key: "minFrameDurationSeconds"),
            listedRate: jsonOptionalNumber(request, key: "listedRate"))
        let availability = ConformPreview.availability(for: source)
        var dict: [String: Any] = [
            "isVariableFrameRate": source.isVariableFrameRate,
            "isAlreadyConformed": source.isAlreadyConformed,
            "audioLabel": ConformPreview.audioLabel,
            "conformFloor": NSNumber(value: ConformPreview.conformFloor),
            "targetRates": ConformPreview.targetRates.map { NSNumber(value: $0) },
            "availability": availabilityName(availability),
            "targets": availability.targets.map { NSNumber(value: $0) },
        ]
        if let reason = availability.unavailableReason {
            dict["unavailableReason"] = reason
        }
        if let capture = source.captureRate {
            dict["captureRate"] = NSNumber(value: capture)
            dict["menuHeader"] = ConformPreview.menuHeader(captureRate: capture)
            dict["rateLabel"] = ConformPreview.rateLabel(capture)
            dict["targetLabels"] = availability.targets.map {
                ConformPreview.targetLabel(captureRate: capture, targetRate: $0)
            }
            if let target = jsonOptionalNumber(request, key: "targetRate") {
                let speed = ConformPreview.speed(captureRate: capture, targetRate: target)
                dict["speed"] = NSNumber(value: speed)
                dict["targetLabel"] = ConformPreview.targetLabel(
                    captureRate: capture, targetRate: target)
                dict["label"] = ConformPreview.label(captureRate: capture, targetRate: target)
                if let seconds = jsonOptionalNumber(request, key: "sourceSeconds") {
                    dict["conformedDuration"] = NSNumber(
                        value: ConformPreview.conformedDuration(
                            sourceSeconds: seconds, speed: speed))
                }
            }
        }
        guard JSONSerialization.isValidJSONObject(dict),
            let data = try? JSONSerialization.data(withJSONObject: dict),
            let text = String(data: data, encoding: .utf8)
        else { return "{}" }
        return text
    }

    private static func availabilityName(_ availability: ConformPreview.Availability) -> String {
        switch availability {
        case .available: "available"
        case .unknownRate: "unknownRate"
        case .variableRate: "variableRate"
        case .alreadyConformed: "alreadyConformed"
        case .notHighFrameRate: "notHighFrameRate"
        }
    }

    private static func jsonBool(_ json: String, key: String, default def: Bool) -> Bool {
        if json.contains("\"\(key)\":true") { return true }
        if json.contains("\"\(key)\":false") { return false }
        return def
    }

    private static func jsonOptionalNumber(_ json: String, key: String) -> Double? {
        guard let range = json.range(of: "\"\(key)\":") else { return nil }
        var s = ""
        var started = false
        for ch in json[range.upperBound...] {
            if ch.isWhitespace && !started { continue }
            if !started && ch == "n" { return nil }
            started = true
            if ch == "-" && s.isEmpty {
                s.append(ch)
                continue
            }
            if ch.isNumber || ch == "." || ch == "e" || ch == "E" || ch == "+" {
                s.append(ch)
            } else {
                break
            }
        }
        return Double(s)
    }

    private static func jsonNumber(_ json: String, key: String, default def: Double) -> Double {
        jsonOptionalNumber(json, key: key) ?? def
    }

    private static func jsonBool(_ fields: [String: Substring], key: String, default def: Bool)
        -> Bool
    {
        guard let v = fields[key] else { return def }
        if v.hasPrefix("true") { return true }
        if v.hasPrefix("false") { return false }
        return def
    }

    private static func jsonOptionalNumber(_ fields: [String: Substring], key: String) -> Double? {
        guard let v = fields[key]?.drop(while: \.isWhitespace), v.first != "n" else { return nil }
        let body = v.hasPrefix("-") ? v.dropFirst() : v
        let digits = body.prefix(while: { $0.isNumber || ".eE+".contains($0) })
        return Double(v[v.startIndex..<digits.endIndex])
    }

    private static func jsonNumber(
        _ fields: [String: Substring], key: String, default def: Double
    ) -> Double {
        jsonOptionalNumber(fields, key: key) ?? def
    }

    /// String value from Kotlin `JSONObject`; parsing undoes `quote` escapes such as `\/`.
    private static func jsonString(_ json: String, key: String) -> String? {
        let object = try? JSONSerialization.jsonObject(with: Data(json.utf8))
        return (object as? [String: Any])?[key] as? String
    }
}
