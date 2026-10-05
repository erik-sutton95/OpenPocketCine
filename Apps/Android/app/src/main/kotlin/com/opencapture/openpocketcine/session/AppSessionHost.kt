package com.opencapture.openpocketcine.session

import android.content.Context
import com.opencapture.opencine.dji.FaceDetectorPort
import com.opencapture.opencine.dji.FeedIncidentSink
import com.opencapture.opencine.media.FeedIncidentTestSource
import com.opencapture.opencine.dji.DjiSessionHost
import com.opencapture.openpocketcine.BuildConfig
import com.opencapture.openpocketcine.OperatorPrefs
import com.opencapture.openpocketcine.diagnostics.FeedIncidentOrigin
import com.opencapture.openpocketcine.diagnostics.FeedIncidentRuntime
import com.opencapture.openpocketcine.diagnostics.ReliabilityReporting

/** This app's side of OpenCine's DJI session: operator preferences, diagnostics, build identity, ML Kit. */
class AppSessionHost(context: Context) : DjiSessionHost {
    private val appContext = context.applicationContext

    override fun shutterUsesAngle(): Boolean = OperatorPrefs.shutterUsesAngle(appContext)
    override fun shutterAngleDegrees(): Double = OperatorPrefs.shutterAngleDegrees(appContext)
    override fun setShutterAngleDegrees(degrees: Double) = OperatorPrefs.setShutterAngleDegrees(appContext, degrees)
    override fun nativeISOHopEnabled(): Boolean = OperatorPrefs.nativeISOHopEnabled(appContext)

    override fun setCameraSessionActive(active: Boolean) = ReliabilityReporting.setCameraSessionActive(active)
    override val incidents: FeedIncidentSink get() = FeedIncidentRuntime
    override fun incidentTestSource(): FeedIncidentTestSource = FeedIncidentOrigin.currentTestSource()
    override fun incidentBuildIdentity(): String = FeedIncidentOrigin.currentBuildIdentity()

    override val appVersion: String get() = BuildConfig.VERSION_NAME
    override val appBuild: String get() = BuildConfig.VERSION_CODE.toString()
    override val sourceRevision: String get() = BuildConfig.SOURCE_REVISION
    override val debugBuild: Boolean get() = BuildConfig.DEBUG

    override fun createFaceDetector(): FaceDetectorPort = LiveFaceDetector()
}
