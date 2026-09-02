package com.opencapture.openpocketcine.diagnostics

/** Lockstep with Swift `PrivacyRedactor`. */
object PrivacyRedactor {
    const val COMPACT_CHARACTER_CAP = 1400

    fun redact(text: String): String {
        var out = text
        out = out.replace(Regex("(?i)(/Users|/home)/[^/\\s]+"), "$1/<redacted>")
        out = out.replace(Regex("(?i)\\\\Users\\\\[^\\\\\\s]+"), "\\\\Users\\\\<redacted>")
        out = out.replace(Regex("(?i)\\b[A-Z0-9._%+\\-]+@[A-Z0-9.\\-]+\\.[A-Z]{2,}\\b"), "<email>")
        out = out.replace(Regex("\\b(?:[0-9A-Fa-f]{2}:){5}[0-9A-Fa-f]{2}\\b"), "<mac>")
        out =
            out.replace(
                Regex("(?i)\\b(password|passphrase|psk|wifiPassword)\\s*[:=]\\s*\\S+"),
                "$1=<redacted>",
            )
        out = out.replace(Regex("(?i)\\bBearer\\s+[A-Za-z0-9._\\-]+"), "Bearer <redacted>")
        out =
            out.replace(Regex("(?i)\\b(ssid)\\s*[:=]\\s*([^\\s,;]+)")) { match ->
                val value = match.groupValues.getOrNull(2) ?: ""
                if (isCameraNetwork(value)) match.value else "ssid=<redacted>"
            }
        out =
            out.replace(Regex("\\b(\\d{1,3})(\\.\\d{1,3}){3}\\b")) { match ->
                val ip = match.value
                if (isLocalIPv4(ip)) ip else "<ip>"
            }
        return out
    }

    fun clampCompact(text: String): String =
        if (text.length <= COMPACT_CHARACTER_CAP) text
        else text.take(COMPACT_CHARACTER_CAP - 1) + "…"

    fun isCameraNetwork(raw: String): Boolean {
        val n = raw.lowercase().replace("\"", "").replace("'", "")
        return n.contains("osmo") ||
            n.contains("pocket") ||
            n.contains("nano") ||
            n.contains("muse") ||
            n.contains("atto") ||
            n.contains("xtra") ||
            n.contains("edge")
    }

    fun isLocalIPv4(ip: String): Boolean {
        if (ip.startsWith("127.") || ip.startsWith("192.168.") || ip.startsWith("10.")) return true
        if (ip.startsWith("172.")) {
            val second = ip.split(".").getOrNull(1)?.toIntOrNull() ?: return false
            return second in 16..31
        }
        return false
    }
}
