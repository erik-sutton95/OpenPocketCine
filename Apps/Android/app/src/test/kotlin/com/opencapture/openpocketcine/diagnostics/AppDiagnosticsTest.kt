package com.opencapture.openpocketcine.diagnostics

import com.opencapture.openpocketcine.BuildConfig
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertSame

/** The holder wires the host values this app shipped with before diagnostics moved to OpenCine. */
class AppDiagnosticsTest {
    @Test
    fun holderWiresThisAppsNamesDestinationAndRedaction() {
        val host = AppDiagnostics.host
        assertEquals("OpenPocketCine", host.product)
        assertEquals("com.opencapture.openpocketcine@0.1.0+107", host.release("0.1.0", "107"))
        assertEquals(
            "com.opencapture.openpocketcine@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}",
            host.currentRelease,
        )
        assertEquals(if (BuildConfig.DEBUG) "development" else "production", host.environment)
        assertEquals(BuildConfig.SOURCE_REVISION, host.sourceRevision)
        assertEquals(BuildConfig.SENTRY_DSN_ANDROID, host.reportingDsn)
        assertEquals("openpocketcine-android", host.reportingClient)
        assertEquals("support@openpocketcine.app", host.supportEmail)
        assertEquals("openpocketcine.operator", host.preferencesName)
        assertEquals("192.168.2.", AppDiagnostics.gate.cameraIPv4Prefix)
        // DJI redaction: the camera's access point stays readable, other networks do not.
        assertEquals("ssid=OsmoPocket3-A1B2", host.redact("ssid=OsmoPocket3-A1B2"))
        assertEquals("ssid=<redacted>", host.redact("ssid=CafeWiFi"))
        assertSame(AppDiagnostics.gate, AppDiagnostics.reporting.gate)
        assertSame(AppDiagnostics.consent, AppDiagnostics.reporting.consent)
        assertSame(AppDiagnostics.origin, AppDiagnostics.reporting.origin)
    }
}
