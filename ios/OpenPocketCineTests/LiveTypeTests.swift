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
}
