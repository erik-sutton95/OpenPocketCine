package com.opencapture.openpocketcine.diagnostics

import com.opencapture.openpocketcine.BuildConfig

/** Current-run origin only. Cached incidents keep the values persisted with them. */
internal object FeedIncidentOrigin {
    @Volatile var overrideTestSourceForTests: FeedIncidentTestSource? = null
    @Volatile var overrideBuildIdentityForTests: String? = null
    @Volatile var injectionActivatedForTests: Boolean = false

    fun resetForTests() {
        overrideTestSourceForTests = null
        overrideBuildIdentityForTests = null
        injectionActivatedForTests = false
    }

    fun currentTestSource(): FeedIncidentTestSource {
        overrideTestSourceForTests?.let { return it }
        val env = System.getenv()
        val verification =
            env["OPV_RELIABILITY_VERIFY"] in
                setOf("incident", "gatedIncident", "crash", "hang", "resume")
        return FeedIncidentTestSource.derive(
            verification = verification,
            injectionActivated = injectionActivatedForTests,
            automation = isAutomationLaunch(env) || isAutomatedHarness(),
        )
    }

    fun isAutomationLaunch(environment: Map<String, String>): Boolean {
        if (environment["OPV_FEED_STRESS"] == "1") return true
        if (environment["OPV_PHYSICAL_UI_REVIEW"] == "1") return true
        if (!environment["OPV_UI_REVIEW_SCREEN"].isNullOrEmpty()) return true
        return false
    }

    fun currentBuildIdentity(): String {
        overrideBuildIdentityForTests?.let { return FeedIncidentBuildIdentity.parse(it) }
        return FeedIncidentBuildIdentity.parse(runCatching { BuildConfig.BUILD_IDENTITY }.getOrNull())
    }

    private fun isAutomatedHarness(): Boolean {
        return try {
            Class.forName("org.junit.Test")
            true
        } catch (_: ClassNotFoundException) {
            try {
                Class.forName("androidx.test.platform.app.InstrumentationRegistry")
                true
            } catch (_: ClassNotFoundException) {
                false
            }
        }
    }
}
