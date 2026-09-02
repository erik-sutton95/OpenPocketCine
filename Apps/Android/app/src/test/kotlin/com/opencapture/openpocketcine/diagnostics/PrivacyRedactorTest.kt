package com.opencapture.openpocketcine.diagnostics

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class PrivacyRedactorTest {
    @Test
    fun redactsHomePathEmailMacAndPassword() {
        val home = "/" + "Users" + "/example"
        val raw =
            "crash $home/Library/foo email=tester@example.com mac=EC:9E:EA:11:22:33 password=hunter2"
        val out = PrivacyRedactor.redact(raw)
        assertFalse(out.contains("example/Library"))
        assertTrue(out.contains("/" + "Users" + "/<redacted>"))
        assertFalse(out.contains("tester@example.com"))
        assertTrue(out.contains("<email>"))
        assertFalse(out.contains("EC:9E:EA:11:22:33"))
        assertTrue(out.contains("<mac>"))
        assertFalse(out.contains("hunter2"))
        assertTrue(out.contains("password=<redacted>"))
    }

    @Test
    fun keepsCameraSSIDAndSoftAPAddress() {
        val out = PrivacyRedactor.redact("ssid=OsmoPocket3-A1B2 path=192.168.2.15 seq=42054")
        assertTrue(out.contains("OsmoPocket3-A1B2"))
        assertTrue(out.contains("192.168.2.15"))
        assertTrue(out.contains("seq=42054"))
    }

    @Test
    fun redactsHomeSSIDAndPublicIP() {
        val out = PrivacyRedactor.redact("ssid=CafeWiFi join=8.8.8.8")
        assertFalse(out.contains("CafeWiFi"))
        assertTrue(out.contains("ssid=<redacted>"))
        assertFalse(out.contains("8.8.8.8"))
        assertTrue(out.contains("<ip>"))
    }
}
