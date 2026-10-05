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
}
