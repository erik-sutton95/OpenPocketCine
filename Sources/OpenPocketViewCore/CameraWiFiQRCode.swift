import Foundation

/// Standard Wi-Fi QR payload for an explicitly revealed, local join code.
/// Treat the result as a password: never log, persist, or advertise it.
public enum CameraWiFiQRCode {
    public static func payload(ssid: String, password: String) -> String? {
        guard !ssid.isEmpty, !password.isEmpty else { return nil }
        return "WIFI:T:WPA;S:\(escape(ssid));P:\(escape(password));;"
    }

    private static func escape(_ value: String) -> String {
        var result = ""
        for character in value {
            if "\\;,:\"".contains(character) { result.append("\\") }
            result.append(character)
        }
        return result
    }
}
