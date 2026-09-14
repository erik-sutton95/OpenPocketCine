package com.opencapture.openpocketcine.diagnostics

import kotlin.test.Test
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class BoundedDiagnosticFormatterTest {
    private val env =
        BoundedDiagnosticFormatter.Environment(
            appVersion = "1.0",
            appBuild = "12",
            osName = "Android",
            osVersion = "15",
            deviceModel = "Pixel",
            cameraFamily = "pocket4pro",
            cameraModel = "Osmo Pocket 4 Pro",
            phase = "live",
            vpnActive = false,
        )

    @Test
    fun keepsEnvironmentNewestJournalTypedIncidentsAndFaultsInsteadOfOldMetricKit() {
        val journal = (1..400).map { "journal-line-$it recent-event" }
        val extras =
            listOf(
                "metrickit-old.json" to """{"metric":"${"x".repeat(28_000)}"}""",
                "incidents.txt" to "id=inc-new kind=decoderError stage=decodedOutput",
                "incident-inc-new.json" to """{"header":{"incidentID":"inc-new"},"prelude":[]}""",
                "session-summary.json" to """{"sessionID":"sess-1","outcome":"ended","incidentCount":1}""",
            )
        val faults = listOf("old-fault", "fault diagnostics uncaught newest-fault")
        val body =
            BoundedDiagnosticFormatter.format(
                environment = env,
                journal = journal,
                exceptions = faults,
                extras = extras,
                generatedAtMs = 1_700_000_000_000L,
            )
        assertTrue(body.contains("app: 1.0 (12)"))
        assertTrue(body.contains("phase: live"))
        assertTrue(body.contains("journal-line-400"))
        assertTrue(body.contains("recent-event"))
        assertTrue(body.contains("id=inc-new"))
        assertTrue(body.contains("\"incidentID\":\"inc-new\""))
        assertTrue(body.contains("\"prelude\":[]"))
        assertTrue(body.contains("sess-1"))
        assertTrue(body.contains("newest-fault"))
        assertTrue(body.length <= BoundedDiagnosticFormatter.CHARACTER_CAP)
        assertFalse(body.contains("\"metric\":"))
        assertTrue(body.contains("omitted extra metrickit-old.json"))
        assertFalse(body.contains("incidents: none captured"))
    }

    @Test
    fun omitsOversizedJsonWholeRatherThanChoppingIt() {
        val huge = "incident-huge.json" to """{"header":{"incidentID":"huge"},"blob":"${"y".repeat(40_000)}"}"""
        val body =
            BoundedDiagnosticFormatter.format(
                environment = env,
                journal = listOf("newest-history-line"),
                exceptions = listOf("compact-fault"),
                extras = listOf("incidents.txt" to "id=inc-new", huge),
                generatedAtMs = 0L,
            )
        assertTrue(body.contains("newest-history-line"))
        assertTrue(body.contains("compact-fault"))
        assertTrue(body.contains("id=inc-new"))
        assertFalse(body.contains("\"incidentID\":\"huge\""))
        assertTrue(body.contains("omitted extra incident-huge.json"))
        assertFalse(body.contains("\"blob\":"))
        assertTrue(body.length <= BoundedDiagnosticFormatter.CHARACTER_CAP)
    }
    @Test
    fun retainsOversizedNewestEvidenceAndDoesNotLoopOnHugeHeader() {
        val report = BoundedDiagnosticFormatter.format(
            env, listOf("error latest " + "x".repeat(40_000)),
            listOf("decoder failed DiagnosticCenterC12currentStack"),
            listOf("incidents.txt" to ("newest incident\n" + "old detail\n".repeat(4_000))))
        assertTrue(report.contains("error latest"))
        assertTrue(report.contains("decoder failed"))
        assertTrue(report.contains("newest incident"))
        assertTrue(report.length <= 32_000)
        val huge = BoundedDiagnosticFormatter.format(env.copy(appVersion = "v".repeat(40_000)), emptyList(), emptyList())
        assertTrue(huge.length <= 32_000)
        assertTrue(huge.contains("truncated"))
    }
}
