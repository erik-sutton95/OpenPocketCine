import SwiftUI
import UIKit
import XCTest

@testable import OpenPocketCine

final class LiveTypeTests: XCTestCase {
    func testBundledLandingFacesRegister() {
        for name in LiveType.bundledPostScriptNames {
            XCTAssertNotNil(
                UIFont(name: name, size: 16),
                "UIAppFonts should register landing face \(name)")
        }
    }

    func testReadoutsStayMonospaced() {
        let readout = LiveType.ui(size: 17, weight: .medium, design: .monospaced)
        let systemMono = Font.system(size: 17, weight: .medium, design: .monospaced)
        XCTAssertEqual(String(describing: readout), String(describing: systemMono))
    }
}
