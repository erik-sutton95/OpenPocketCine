import SwiftUI
import XCTest

@testable import OpenPocketCine

final class OpcIconTests: XCTestCase {
    func testCatalogNamesMatchLucideFiles() {
        XCTAssertEqual(
            OpcIcon.allCases.map(\.lucideName),
            [
                "camera",
                "chevron-left",
                "chevron-right",
                "contrast",
                "crosshair",
                "grid-3x3",
                "layers",
                "lock",
                "pause",
                "play",
                "settings",
                "share",
                "star",
                "trash",
                "video",
                "x",
                "zap",
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
}
