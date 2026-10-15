package com.opencapture.openpocketcine.session

import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import android.content.Context
import com.opencapture.opencine.dji.FaceDetectorPort
import com.opencapture.opencine.media.FeedIncidentSink
import com.opencapture.opencine.media.FeedIncidentTestSource
import com.opencapture.opencine.media.FeedIncidentSessionContext
import com.opencapture.opencine.dji.DjiSessionHost
import com.opencapture.openpocketcine.BuildConfig
import com.opencapture.openpocketcine.OperatorPrefs

/** This app's side of OpenCine's DJI session: operator preferences, diagnostics, build identity, ML Kit. */
class AppSessionHost(context: Context) : DjiSessionHost {
    private val appContext = context.applicationContext

    override fun shutterUsesAngle(): Boolean = OperatorPrefs.shutterUsesAngle(appContext)
    override fun shutterAngleDegrees(): Double = OperatorPrefs.shutterAngleDegrees(appContext)
    override fun setShutterAngleDegrees(degrees: Double) = OperatorPrefs.setShutterAngleDegrees(appContext, degrees)
    override fun nativeISOHopEnabled(): Boolean = OperatorPrefs.nativeISOHopEnabled(appContext)

    override fun beginCameraPath(): AutoCloseable = AppDiagnostics.reporting.beginCameraPath()
    override val incidents: FeedIncidentSink get() = AppDiagnostics.incidents
    override fun incidentTestSource(): FeedIncidentTestSource = AppDiagnostics.origin.currentTestSource()
    override fun incidentBuildIdentity(): String = AppDiagnostics.origin.currentBuildIdentity()
    override fun incidentSessionContext(sessionId: String, cameraFamily: String,
        decoderGeneration: Int, socketGeneration: Int): FeedIncidentSessionContext =
        AppDiagnostics.incidents.sessionContext(sessionId, cameraFamily,
            decoderGeneration = decoderGeneration, socketGeneration = socketGeneration)

    override val appVersion: String get() = BuildConfig.VERSION_NAME
    override val appBuild: String get() = BuildConfig.VERSION_CODE.toString()
    override val sourceRevision: String get() = BuildConfig.SOURCE_REVISION
    override val debugBuild: Boolean get() = BuildConfig.DEBUG

    override fun createFaceDetector(): FaceDetectorPort = LiveFaceDetector()
}
