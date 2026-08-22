import CoreGraphics
import Foundation
import SwiftUI

/// Parsed Lucide SVG (24×24 stroke icons: path, circle, line, rect).
struct LucideSVGDocument {
    var viewBox: CGRect
    var strokeWidth: CGFloat
    var elements: [Element]

    enum Element {
        case path(String)
        case circle(center: CGPoint, radius: CGFloat)
        case line(CGPoint, CGPoint)
        case roundedRect(CGRect, radius: CGSize)
    }

    static func load(named name: String) -> LucideSVGDocument? {
        guard let url = resourceURL(named: name) else { return nil }
        guard let xml = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        return LucideSVGDocument(xml: xml)
    }

    init?(xml: String) {
        guard let parsed = Self.parse(xml: xml) else { return nil }
        self = parsed
    }

    private init(viewBox: CGRect, strokeWidth: CGFloat, elements: [Element]) {
        self.viewBox = viewBox
        self.strokeWidth = strokeWidth
        self.elements = elements
    }

    func draw(in context: inout GraphicsContext, size: CGSize, filled: Bool) {
        let path = combinedPath()
        guard !path.isEmpty, viewBox.width > 0, viewBox.height > 0, size.width > 0, size.height > 0
        else { return }
        let scale = min(size.width / viewBox.width, size.height / viewBox.height)
        let drawSize = CGSize(width: viewBox.width * scale, height: viewBox.height * scale)
        let origin = CGPoint(
            x: (size.width - drawSize.width) / 2,
            y: (size.height - drawSize.height) / 2)
        var transform = CGAffineTransform.identity
        transform = transform.translatedBy(x: origin.x, y: origin.y)
        transform = transform.scaledBy(x: scale, y: scale)
        transform = transform.translatedBy(x: -viewBox.minX, y: -viewBox.minY)
        let drawn = path.applying(transform)
        let style = StrokeStyle(
            lineWidth: strokeWidth * scale,
            lineCap: .round,
            lineJoin: .round)
        if filled {
            context.fill(drawn, with: .foreground)
        }
        context.stroke(drawn, with: .foreground, style: style)
    }

    func combinedPath() -> Path {
        var path = Path()
        for element in elements {
            switch element {
            case .path(let data):
                path.addPath(SVGPathBuilder.path(from: data))
            case .circle(let center, let radius):
                path.addEllipse(
                    in: CGRect(
                        x: center.x - radius,
                        y: center.y - radius,
                        width: radius * 2,
                        height: radius * 2))
            case .line(let start, let end):
                path.move(to: start)
                path.addLine(to: end)
            case .roundedRect(let rect, let radius):
                path.addRoundedRect(in: rect, cornerSize: radius)
            }
        }
        return path
    }

    private static func resourceURL(named name: String) -> URL? {
        let bundles = [Bundle(for: LucideIconBundleToken.self), Bundle.main]
        let subdirs = ["Icons/lucide", "Resources/Icons/lucide", "lucide", nil]
        for bundle in bundles {
            for subdir in subdirs {
                if let url = bundle.url(
                    forResource: name, withExtension: "svg", subdirectory: subdir)
                {
                    return url
                }
            }
        }
        return nil
    }

    private static func parse(xml: String) -> LucideSVGDocument? {
        guard let svgRange = xml.range(of: "<svg") else { return nil }
        let afterSvg = xml[svgRange.lowerBound...]
        guard let svgEnd = afterSvg.range(of: ">") else { return nil }
        let svgTag = String(xml[svgRange.lowerBound..<svgEnd.upperBound])
        let viewBox =
            parseViewBox(attribute("viewBox", in: svgTag))
            ?? CGRect(
                x: 0, y: 0, width: 24, height: 24)
        let strokeWidth = CGFloat(Double(attribute("stroke-width", in: svgTag) ?? "2") ?? 2)
        var elements: [Element] = []
        var cursor = svgEnd.upperBound
        while cursor < xml.endIndex {
            guard let lt = xml[cursor...].firstIndex(of: "<") else { break }
            let nameStart = xml.index(after: lt)
            if nameStart < xml.endIndex, xml[nameStart] == "/" || xml[nameStart] == "!" {
                cursor = xml.index(after: lt)
                continue
            }
            guard let gt = xml[lt...].firstIndex(of: ">") else { break }
            let tag = String(xml[nameStart..<gt])
            cursor = xml.index(after: gt)
            if let element = parseElement(tag) {
                elements.append(element)
            }
        }
        guard !elements.isEmpty else { return nil }
        return LucideSVGDocument(viewBox: viewBox, strokeWidth: strokeWidth, elements: elements)
    }

    private static func parseElement(_ tag: String) -> Element? {
        let name =
            tag.split(whereSeparator: { $0 == " " || $0 == "/" }).first.map(String.init) ?? ""
        switch name {
        case "path":
            guard let data = attribute("d", in: tag) else { return nil }
            return .path(data)
        case "circle":
            let cx = CGFloat(Double(attribute("cx", in: tag) ?? "0") ?? 0)
            let cy = CGFloat(Double(attribute("cy", in: tag) ?? "0") ?? 0)
            let radius = CGFloat(Double(attribute("r", in: tag) ?? "0") ?? 0)
            return .circle(center: CGPoint(x: cx, y: cy), radius: radius)
        case "ellipse":
            let cx = CGFloat(Double(attribute("cx", in: tag) ?? "0") ?? 0)
            let cy = CGFloat(Double(attribute("cy", in: tag) ?? "0") ?? 0)
            let rx = CGFloat(Double(attribute("rx", in: tag) ?? "0") ?? 0)
            let ry = CGFloat(Double(attribute("ry", in: tag) ?? "0") ?? 0)
            return .roundedRect(
                CGRect(x: cx - rx, y: cy - ry, width: rx * 2, height: ry * 2),
                radius: CGSize(width: rx, height: ry))
        case "polyline", "polygon":
            guard let raw = attribute("points", in: tag) else { return nil }
            let closed = name == "polygon"
            return .path(pointsPathData(raw, closed: closed))
        case "line":
            let x1 = CGFloat(Double(attribute("x1", in: tag) ?? "0") ?? 0)
            let y1 = CGFloat(Double(attribute("y1", in: tag) ?? "0") ?? 0)
            let x2 = CGFloat(Double(attribute("x2", in: tag) ?? "0") ?? 0)
            let y2 = CGFloat(Double(attribute("y2", in: tag) ?? "0") ?? 0)
            return .line(CGPoint(x: x1, y: y1), CGPoint(x: x2, y: y2))
        case "rect":
            let x = CGFloat(Double(attribute("x", in: tag) ?? "0") ?? 0)
            let y = CGFloat(Double(attribute("y", in: tag) ?? "0") ?? 0)
            let width = CGFloat(Double(attribute("width", in: tag) ?? "0") ?? 0)
            let height = CGFloat(Double(attribute("height", in: tag) ?? "0") ?? 0)
            let rx = CGFloat(Double(attribute("rx", in: tag) ?? "0") ?? 0)
            let ry = CGFloat(
                Double(attribute("ry", in: tag) ?? attribute("rx", in: tag) ?? "0") ?? 0)
            return .roundedRect(
                CGRect(x: x, y: y, width: width, height: height),
                radius: CGSize(width: rx, height: ry))
        default:
            return nil
        }
    }

    private static func pointsPathData(_ raw: String, closed: Bool) -> String {
        let numbers = raw.split { $0 == " " || $0 == "," || $0 == "\n" || $0 == "\t" }
            .compactMap { Double($0) }
        guard numbers.count >= 4, numbers.count.isMultiple(of: 2) else { return "" }
        var parts = ["M\(numbers[0]) \(numbers[1])"]
        var index = 2
        while index + 1 < numbers.count {
            parts.append("L\(numbers[index]) \(numbers[index + 1])")
            index += 2
        }
        if closed { parts.append("Z") }
        return parts.joined(separator: " ")
    }

    private static func parseViewBox(_ raw: String?) -> CGRect? {
        guard let raw else { return nil }
        let parts = raw.split { $0 == " " || $0 == "," }.compactMap { Double($0) }
        guard parts.count == 4 else { return nil }
        return CGRect(x: parts[0], y: parts[1], width: parts[2], height: parts[3])
    }

    private static func attribute(_ name: String, in tag: String) -> String? {
        let key = name + "=\""
        guard let start = tag.range(of: key) else { return nil }
        let rest = tag[start.upperBound...]
        guard let end = rest.firstIndex(of: "\"") else { return nil }
        return String(rest[..<end])
    }
}

enum LucideSVGCache {
    private static let lock = NSLock()
    private static var documents: [String: LucideSVGDocument] = [:]

    static func document(named name: String) -> LucideSVGDocument? {
        lock.lock()
        defer { lock.unlock() }
        if let cached = documents[name] { return cached }
        guard let loaded = LucideSVGDocument.load(named: name) else { return nil }
        documents[name] = loaded
        return loaded
    }
}

private final class LucideIconBundleToken: NSObject {}

// MARK: - SVG path data

enum SVGPathBuilder {
    static func path(from data: String) -> Path {
        var builder = SVGPathBuilderState()
        builder.append(data)
        return builder.path
    }
}

private struct SVGPathBuilderState {
    var path = Path()
    var current = CGPoint.zero
    var subpathStart = CGPoint.zero
    var lastCubicControl: CGPoint?
    var lastQuadControl: CGPoint?
    var tokens = SVGPathScanner(data: "")

    mutating func append(_ data: String) {
        tokens = SVGPathScanner(data: data)
        var implicit: UInt8?
        while !tokens.isAtEnd() {
            if let command = tokens.nextCommand() {
                implicit = command
                execute(command)
            } else if let previous = implicit {
                let implied: UInt8
                if previous == UInt8(ascii: "M") {
                    implied = UInt8(ascii: "L")
                } else if previous == UInt8(ascii: "m") {
                    implied = UInt8(ascii: "l")
                } else {
                    implied = previous
                }
                execute(implied)
            } else {
                break
            }
        }
    }

    mutating func execute(_ command: UInt8) {
        let relative = command >= 97
        let kind = relative ? command - 32 : command
        switch kind {
        case UInt8(ascii: "M"):
            guard let point = nextPoint(relative: relative) else { return }
            path.move(to: point)
            current = point
            subpathStart = point
            lastCubicControl = nil
            lastQuadControl = nil
        case UInt8(ascii: "L"):
            guard let point = nextPoint(relative: relative) else { return }
            path.addLine(to: point)
            current = point
            lastCubicControl = nil
            lastQuadControl = nil
        case UInt8(ascii: "H"):
            guard let x = tokens.nextNumber() else { return }
            let point = CGPoint(x: relative ? current.x + x : x, y: current.y)
            path.addLine(to: point)
            current = point
            lastCubicControl = nil
            lastQuadControl = nil
        case UInt8(ascii: "V"):
            guard let y = tokens.nextNumber() else { return }
            let point = CGPoint(x: current.x, y: relative ? current.y + y : y)
            path.addLine(to: point)
            current = point
            lastCubicControl = nil
            lastQuadControl = nil
        case UInt8(ascii: "C"):
            guard let c1 = nextPoint(relative: relative),
                let c2 = nextPoint(relative: relative),
                let end = nextPoint(relative: relative)
            else { return }
            path.addCurve(to: end, control1: c1, control2: c2)
            current = end
            lastCubicControl = c2
            lastQuadControl = nil
        case UInt8(ascii: "S"):
            let c1: CGPoint
            if let previous = lastCubicControl {
                c1 = CGPoint(x: 2 * current.x - previous.x, y: 2 * current.y - previous.y)
            } else {
                c1 = current
            }
            guard let c2 = nextPoint(relative: relative),
                let end = nextPoint(relative: relative)
            else { return }
            path.addCurve(to: end, control1: c1, control2: c2)
            current = end
            lastCubicControl = c2
            lastQuadControl = nil
        case UInt8(ascii: "Q"):
            guard let control = nextPoint(relative: relative),
                let end = nextPoint(relative: relative)
            else { return }
            path.addQuadCurve(to: end, control: control)
            current = end
            lastQuadControl = control
            lastCubicControl = nil
        case UInt8(ascii: "T"):
            let control: CGPoint
            if let previous = lastQuadControl {
                control = CGPoint(x: 2 * current.x - previous.x, y: 2 * current.y - previous.y)
            } else {
                control = current
            }
            guard let end = nextPoint(relative: relative) else { return }
            path.addQuadCurve(to: end, control: control)
            current = end
            lastQuadControl = control
            lastCubicControl = nil
        case UInt8(ascii: "A"):
            guard let rx = tokens.nextNumber(),
                let ry = tokens.nextNumber(),
                let rotation = tokens.nextNumber(),
                let large = tokens.nextFlag(),
                let sweep = tokens.nextFlag()
            else { return }
            guard let end = nextPoint(relative: relative) else { return }
            addEllipticalArc(
                rx: rx, ry: ry, rotationDegrees: rotation, largeArc: large, sweep: sweep, to: end)
            lastCubicControl = nil
            lastQuadControl = nil
        case UInt8(ascii: "Z"):
            path.closeSubpath()
            current = subpathStart
            lastCubicControl = nil
            lastQuadControl = nil
        default:
            break
        }
    }

    mutating func nextPoint(relative: Bool) -> CGPoint? {
        guard let x = tokens.nextNumber(), let y = tokens.nextNumber() else { return nil }
        if relative {
            return CGPoint(x: current.x + x, y: current.y + y)
        }
        return CGPoint(x: x, y: y)
    }

    mutating func addEllipticalArc(
        rx rawRx: CGFloat,
        ry rawRy: CGFloat,
        rotationDegrees: CGFloat,
        largeArc: Bool,
        sweep: Bool,
        to end: CGPoint
    ) {
        let start = current
        if start == end {
            return
        }
        if rawRx == 0 || rawRy == 0 {
            path.addLine(to: end)
            current = end
            return
        }

        var rx = abs(rawRx)
        var ry = abs(rawRy)
        let phi = rotationDegrees * .pi / 180
        let cosPhi = cos(phi)
        let sinPhi = sin(phi)

        let dx = (start.x - end.x) / 2
        let dy = (start.y - end.y) / 2
        let x1p = cosPhi * dx + sinPhi * dy
        let y1p = -sinPhi * dx + cosPhi * dy

        var rx2 = rx * rx
        var ry2 = ry * ry
        let x1p2 = x1p * x1p
        let y1p2 = y1p * y1p
        let lambda = x1p2 / rx2 + y1p2 / ry2
        if lambda > 1 {
            let scale = sqrt(lambda)
            rx *= scale
            ry *= scale
            rx2 = rx * rx
            ry2 = ry * ry
        }

        let numerator = rx2 * ry2 - rx2 * y1p2 - ry2 * x1p2
        let denominator = rx2 * y1p2 + ry2 * x1p2
        var coefficient = denominator == 0 ? 0 : numerator / denominator
        if coefficient < 0 { coefficient = 0 }
        let sign: CGFloat = largeArc != sweep ? 1 : -1
        let co = sign * sqrt(coefficient)
        let cxp = co * (rx * y1p) / ry
        let cyp = co * -(ry * x1p) / rx

        let center = CGPoint(
            x: cosPhi * cxp - sinPhi * cyp + (start.x + end.x) / 2,
            y: sinPhi * cxp + cosPhi * cyp + (start.y + end.y) / 2)

        let theta1 = vectorAngle(1, 0, (x1p - cxp) / rx, (y1p - cyp) / ry)
        var delta = vectorAngle(
            (x1p - cxp) / rx, (y1p - cyp) / ry, (-x1p - cxp) / rx, (-y1p - cyp) / ry)
        if !sweep && delta > 0 { delta -= 2 * .pi }
        if sweep && delta < 0 { delta += 2 * .pi }

        let segmentCount = max(1, Int(ceil(abs(delta) / (.pi / 2) - 1e-6)))
        let segmentDelta = delta / CGFloat(segmentCount)
        let handle = (4 / 3) * tan(segmentDelta / 4)
        var theta = theta1
        for _ in 0..<segmentCount {
            let thetaEnd = theta + segmentDelta
            let p0 = ellipsePoint(center: center, rx: rx, ry: ry, phi: phi, theta: theta)
            let p1 = ellipsePoint(center: center, rx: rx, ry: ry, phi: phi, theta: thetaEnd)
            let d0 = ellipseDerivative(rx: rx, ry: ry, phi: phi, theta: theta)
            let d1 = ellipseDerivative(rx: rx, ry: ry, phi: phi, theta: thetaEnd)
            let c1 = CGPoint(x: p0.x + handle * d0.dx, y: p0.y + handle * d0.dy)
            let c2 = CGPoint(x: p1.x - handle * d1.dx, y: p1.y - handle * d1.dy)
            path.addCurve(to: p1, control1: c1, control2: c2)
            theta = thetaEnd
        }
        current = end
    }
}

private func vectorAngle(_ ux: CGFloat, _ uy: CGFloat, _ vx: CGFloat, _ vy: CGFloat) -> CGFloat {
    atan2(ux * vy - uy * vx, ux * vx + uy * vy)
}

private func ellipsePoint(
    center: CGPoint, rx: CGFloat, ry: CGFloat, phi: CGFloat, theta: CGFloat
) -> CGPoint {
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let x = rx * cos(theta)
    let y = ry * sin(theta)
    return CGPoint(
        x: center.x + cosPhi * x - sinPhi * y,
        y: center.y + sinPhi * x + cosPhi * y)
}

private func ellipseDerivative(
    rx: CGFloat, ry: CGFloat, phi: CGFloat, theta: CGFloat
) -> CGVector {
    let cosPhi = cos(phi)
    let sinPhi = sin(phi)
    let dx = -rx * sin(theta)
    let dy = ry * cos(theta)
    return CGVector(dx: cosPhi * dx - sinPhi * dy, dy: sinPhi * dx + cosPhi * dy)
}

private struct SVGPathScanner {
    let scalars: [UInt8]
    var index = 0

    init(data: String) {
        scalars = Array(data.utf8)
    }

    mutating func isAtEnd() -> Bool {
        skipSeparators()
        return index >= scalars.count
    }

    mutating func nextCommand() -> UInt8? {
        skipSeparators()
        guard index < scalars.count else { return nil }
        let value = scalars[index]
        let isLetter = (value >= 65 && value <= 90) || (value >= 97 && value <= 122)
        guard isLetter else { return nil }
        index += 1
        return value
    }

    mutating func nextNumber() -> CGFloat? {
        skipSeparators()
        guard index < scalars.count else { return nil }
        let start = index
        let first = scalars[index]
        if first == 0x2B || first == 0x2D { index += 1 }
        var sawDigit = false
        var sawDot = false
        while index < scalars.count {
            let value = scalars[index]
            if value >= 0x30 && value <= 0x39 {
                sawDigit = true
                index += 1
            } else if value == 0x2E && !sawDot {
                sawDot = true
                index += 1
            } else if (value == 0x65 || value == 0x45) && (sawDigit || sawDot) {
                index += 1
                if index < scalars.count {
                    let sign = scalars[index]
                    if sign == 0x2B || sign == 0x2D { index += 1 }
                }
                while index < scalars.count && scalars[index] >= 0x30 && scalars[index] <= 0x39 {
                    index += 1
                }
                break
            } else {
                break
            }
        }
        guard sawDigit || (sawDot && index > start + 1) else {
            index = start
            return nil
        }
        let slice = scalars[start..<index]
        guard let text = String(bytes: slice, encoding: .utf8), let value = Double(text) else {
            index = start
            return nil
        }
        return CGFloat(value)
    }

    mutating func nextFlag() -> Bool? {
        skipSeparators()
        guard index < scalars.count else { return nil }
        let value = scalars[index]
        if value == 0x30 {
            index += 1
            return false
        }
        if value == 0x31 {
            index += 1
            return true
        }
        return nil
    }

    private mutating func skipSeparators() {
        while index < scalars.count {
            let value = scalars[index]
            if value == 0x20 || value == 0x09 || value == 0x0A || value == 0x0D || value == 0x2C {
                index += 1
            } else {
                break
            }
        }
    }
}
