package com.opencapture.openpocketcine.diagnostics

import com.opencapture.opencine.appkit.diagnostics.DiagnosticsHost
import com.opencapture.opencine.appkit.diagnostics.FeedIncidentOrigin
import com.opencapture.opencine.appkit.diagnostics.FeedIncidentRuntime
import com.opencapture.opencine.appkit.diagnostics.ManualProblemReport
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReporting
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingConsent
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingDSN
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingGate
import com.opencapture.opencine.appkit.diagnostics.ReliabilityReportingHostPolicy
import com.opencapture.opencine.vocabulary.PrivacyRedactor
import com.opencapture.openpocketcine.BuildConfig

/** The app's diagnostics: OpenCine's runtime with this app's names, destination, Sentry and OkHttp. */
internal object AppDiagnostics {
    val host =
        DiagnosticsHost(
            product = "OpenPocketCine",
            releasePackage = "com.opencapture.openpocketcine",
            versionName = BuildConfig.VERSION_NAME,
            versionCode = BuildConfig.VERSION_CODE,
            debug = BuildConfig.DEBUG,
            sourceRevision = BuildConfig.SOURCE_REVISION,
            reportingDsn = BuildConfig.SENTRY_DSN_ANDROID,
            reportingClient = "openpocketcine-android",
            supportEmail = "support@openpocketcine.app",
            preferencesName = "openpocketcine.operator",
            redact = PrivacyRedactor::redact,
        )
    val dsn = ReliabilityReportingDSN()
    val consent = ReliabilityReportingConsent(dsn)
    val gate = ReliabilityReportingGate(consent, ReliabilityReportingHostPolicy(), cameraIPv4Prefix = "192.168.2.")
    val origin = FeedIncidentOrigin({ BuildConfig.BUILD_IDENTITY }, host.redact)
    val reporting =
        ReliabilityReporting(host, consent, dsn, gate, origin, ::SentryReliabilitySink) {
            manualReport.noteCameraPathClear()
        }
    val incidents = FeedIncidentRuntime(reporting)
    val manualReport = ManualProblemReport(host, dsn, gate, OkHttpManualReportUpload)
}
