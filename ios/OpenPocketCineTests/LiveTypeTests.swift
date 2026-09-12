import MonitorUI
import SwiftUI
import UIKit
import XCTest

@testable import OpenPocketCine

final class LiveTypeTests: XCTestCase {
    func testSharedPackageFacesRegister() {
        _ = MonitorTheme.font(16)
        for name in LiveType.bundledPostScriptNames {
            XCTAssertNotNil(
                UIFont(name: name, size: 16),
                "MonitorUI should register shared face \(name)")
        }
    }

    func testReadoutsUseTheSharedSoraFace() {
        let readout = LiveType.ui(size: 17, weight: .medium, design: .monospaced)
        let shared = MonitorTheme.font(17, weight: .medium)
        XCTAssertEqual(String(describing: readout), String(describing: shared))
        _ = MonitorTheme.font(17)
        XCTAssertNotNil(UIFont(name: "Sora-Regular", size: 17))
    }
}
