package com.opencapture.openpocketcine.conformance

import com.opencapture.monitorui.MonitorCapabilities
import com.opencapture.opencine.appuitesting.ConformanceApp
import com.opencapture.opencine.appuitesting.ConformanceProfile
import com.opencapture.openpocketcine.MainActivity

/** SIMULATED S1 only: the real launcher, cache, gallery and native player; no camera services. */
class GalleryRoundTrip : com.opencapture.opencine.appuitesting.GalleryRoundTrip(PocketLocalReview)

private object PocketLocalReview : ConformanceApp {
    override val activity = MainActivity::class.java
    // A local review has no connected camera or optional camera controls.
    override val profile = ConformanceProfile("PocketCine", MonitorCapabilities())
}
