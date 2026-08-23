import SwiftUI
import XCTest

@testable import OpenPocketCine

final class OpcIconTests: XCTestCase {
    func testCatalogNamesMatchLucideFiles() {
        XCTAssertEqual(
            OpcIcon.allCases.map(\.lucideName),
            [
                "aperture",
                "audio-lines",
                "audio-waveform",
                "blend",
                "camera",
                "chart-column",
                "check",
                "chevron-down",
                "chevron-left",
                "chevron-right",
                "chevron-up",
                "chevrons-up-down",
                "circle",
                "circle-check",
                "circle-play",
                "circle-plus",
                "contrast",
                "copy",
                "crosshair",
                "download",
                "ellipsis",
                "eye",
                "eye-off",
                "film",
                "flip-horizontal-2",
                "folder",
                "focus",
                "funnel",
                "grid-3x3",
                "image",
                "info",
                "layers",
                "layout-grid",
                "layout-list",
                "list-filter",
                "lock",
                "maximize",
                "minimize",
                "monitor",
                "mountain",
                "palette",
                "pause",
                "pencil",
                "play",
                "plus",
                "radio",
                "refresh-cw",
                "rotate-cw",
                "scan",
                "settings",
                "share",
                "signal",
                "skip-back",
                "skip-forward",
                "sliders-horizontal",
                "sliders-vertical",
                "smartphone",
                "square",
                "square-dashed",
                "star",
                "sun",
                "thermometer",
                "timer",
                "trash",
                "unplug",
                "upload",
                "video",
                "volume-2",
                "volume-x",
                "wifi",
                "wifi-off",
                "x",
                "zap",
                "zoom-in",
            ])
    }

    func testEachBundledIconParses() {
        for icon in OpcIcon.allCases {
            let document = LucideSVGDocument.load(named: icon.lucideName)
            XCTAssertNotNil(document, "missing or invalid \(icon.lucideName).svg")
            XCTAssertFalse(document?.elements.isEmpty ?? true, icon.lucideName)
            XCTAssertFalse(document?.combinedPath().isEmpty ?? true, icon.lucideName)
        }
    }

    func testLockShackleArcsUp() {
        let path = SVGPathBuilder.path(from: "M7 11V7a5 5 0 0 1 10 0v4")
        let bounds = path.boundingRect
        XCTAssertEqual(bounds.minX, 7, accuracy: 0.05)
        XCTAssertEqual(bounds.maxX, 17, accuracy: 0.05)
        XCTAssertEqual(bounds.maxY, 11, accuracy: 0.05)
        XCTAssertEqual(bounds.minY, 2, accuracy: 0.2)
    }

    func testChevronAndXPaths() {
        let chevron = SVGPathBuilder.path(from: "m15 18-6-6 6-6")
        XCTAssertEqual(chevron.boundingRect.minX, 9, accuracy: 0.05)
        XCTAssertEqual(chevron.boundingRect.maxX, 15, accuracy: 0.05)

        let xml = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke-width="2">
              <path d="M18 6 6 18" />
              <path d="m6 6 12 12" />
            </svg>
            """
        let document = LucideSVGDocument(xml: xml)
        XCTAssertEqual(document?.elements.count, 2)
        let bounds = document?.combinedPath().boundingRect ?? .zero
        XCTAssertEqual(bounds.minX, 6, accuracy: 0.05)
        XCTAssertEqual(bounds.maxX, 18, accuracy: 0.05)
    }

    func testPolylineAndEllipseParse() {
        let xml = """
            <svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 24 24" stroke-width="2">
              <polyline points="20 6 9 17 4 12" />
              <ellipse cx="12" cy="12" rx="4" ry="2" />
            </svg>
            """
        let document = LucideSVGDocument(xml: xml)
        XCTAssertEqual(document?.elements.count, 2)
        let bounds = document?.combinedPath().boundingRect ?? .zero
        XCTAssertEqual(bounds.minX, 4, accuracy: 0.05)
        XCTAssertEqual(bounds.maxX, 20, accuracy: 0.05)
        XCTAssertEqual(bounds.minY, 6, accuracy: 0.05)
        XCTAssertEqual(bounds.maxY, 17, accuracy: 0.05)
    }
}
