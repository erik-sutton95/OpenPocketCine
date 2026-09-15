package com.opencapture.openpocketcine.diagnostics

import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.net.NetworkCapabilities
import android.net.NetworkRequest
import android.os.Handler
import android.os.Looper
import com.opencapture.openpocketcine.BuildConfig
import io.sentry.Attachment
import io.sentry.Breadcrumb
import io.sentry.Sentry
import io.sentry.SentryEvent
import io.sentry.SentryLevel
import io.sentry.android.core.SentryAndroid
import io.sentry.android.core.SentryAndroidOptions
import io.sentry.protocol.Message
import java.io.File
import java.util.Date
import java.util.UUID
import java.util.concurrent.Executors
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicLong

/**
 * Opt-in Sentry adapter, installed by the app and gated by camera-session activity.
 * Does not start without persisted consent and a valid https DSN. Does not mark
 * an incident delivered when it is only queued.
 */
internal object ReliabilityReporting {
    private val executor =
        Executors.newSingleThreadExecutor { runnable ->
            Thread(runnable, "opc.reliability").apply { isDaemon = true }
        }
    private val sdkStarted = AtomicBoolean(false)
    private val epoch = AtomicLong(0)
    private val pendingCaptureIds = mutableSetOf<String>()
    private val pendingEventIds = mutableMapOf<String, String>()
    private val lock = Any()
    private val idlePollScheduled = AtomicBoolean(false)
    private val resumeScheduled = AtomicBoolean(false)
    @Volatile private var resumeAttempt = 0
    @Volatile private var captureHandler: ((SentryEvent, ByteArray) -> Unit)? = null
    @Volatile private var finalizedSpoolLoader: () -> List<FeedIncidentBundle> = { emptyList() }
    @Volatile private var sessionSummaryLoader: () -> List<FeedIncidentSessionSummary> = { emptyList() }
    @Volatile private var appContext: Context? = null
    @Volatile private var networkCallback: ConnectivityManager.NetworkCallback? = null
    @Volatile var dsnHost: String? = null
    @Volatile var sdkCacheRoot: File =
        File(System.getProperty("java.io.tmpdir") ?: ".", "opc-reliability-sdk")

    val isOptedIn: Boolean
        get() = ReliabilityReportingConsent.isOptedIn

    val isAvailable: Boolean
        get() = ReliabilityReportingDSN.isAvailable

    fun noteBreadcrumb(source: FeedIncidentBreadcrumb) {
        if (!isOptedIn) return
        val breadcrumb = Breadcrumb()
        breadcrumb.category = "feed"
        breadcrumb.message = source.kind.wire
        val details = FeedIncidentNativeBreadcrumb.details(source.kind, source.detail)
        for ((key, value) in details) {
            breadcrumb.setData(key, value)
        }
        Sentry.addBreadcrumb(breadcrumb)
    }

    fun noteRepair(repair: FeedRepairRecord) {
        if (!isOptedIn) return
        val breadcrumb = Breadcrumb()
        breadcrumb.category = "feed"
        breadcrumb.message = "repair"
        val details = FeedIncidentNativeBreadcrumb.details(repair)
        for ((key, value) in details) {
            breadcrumb.setData(key, value)
        }
        Sentry.addBreadcrumb(breadcrumb)
    }

    fun applyOriginalTags(tags: Map<String, String>?, scope: io.sentry.IScope) {
        if (tags == null) return
        for ((key, value) in tags) {
            scope.setTag(key, value)
        }
    }

    fun noteCurrentTestSource(source: FeedIncidentTestSource) {
        if (!isOptedIn) return
        postOnMain {
            Sentry.configureScope { scope -> scope.setTag("testSource", source.wire) }
        }
    }

    fun install(context: Context) {
        val app = context.applicationContext
        appContext = app
        ReliabilityReportingConsent.bind(
            app.getSharedPreferences("openpocketcine.operator", Context.MODE_PRIVATE),
        )
        ReliabilityReportingDSN.buildDsn = BuildConfig.SENTRY_DSN_ANDROID
        sdkCacheRoot = File(app.cacheDir, "opc-reliability-sdk")
        ReliabilityReportingDSN.configured()?.let { dsn ->
            dsnHost = ReliabilityReportingHostPolicy.host(fromDSN = dsn)
        }
        ReliabilityReportingGate.extraCameraPathProbe = { processBoundToCamera(app) }
        finalizedSpoolLoader = { FeedIncidentRuntime.loadFinalized() }
        sessionSummaryLoader = { FeedIncidentRuntime.loadSessionSummaries() }
        applySdkState()
    }

    fun setCameraSessionActive(active: Boolean) {
        ReliabilityReportingGate.setCameraSessionActive(active)
        if (active) {
            ReliabilityReportingGate.cancelPending()
        } else {
            if (!sdkStarted.get() && ReliabilityReportingConsent.isOptedIn) {
                applySdkState()
            }
            enqueueFinalizedFromSpool()
            scheduleResumeIfIdle()
            ManualProblemReport.noteCameraPathClear()
        }
    }

    fun setConsent(on: Boolean) {
        bumpEpoch()
        ReliabilityReportingConsent.setOptedIn(on)
        if (!on) ReliabilityReportingGate.cancelPending(includeIndependent = false)
        applySdkState()
    }

    fun setFinalizedSpoolLoader(loader: () -> List<FeedIncidentBundle>) {
        executor.execute { finalizedSpoolLoader = loader }
    }

    fun setSessionSummaryLoader(loader: () -> List<FeedIncidentSessionSummary>) {
        executor.execute { sessionSummaryLoader = loader }
    }

    fun shouldStartSdk(): Boolean =
        ReliabilityReportingConsent.isOptedIn && ReliabilityReportingDSN.configured() != null

    fun isFinalized(bundle: FeedIncidentBundle): Boolean =
        when (bundle.header.outcome) {
            FeedIncidentOutcome.OPEN -> false
            FeedIncidentOutcome.RECOVERED,
            FeedIncidentOutcome.INTERRUPTED,
            FeedIncidentOutcome.EXHAUSTED,
            FeedIncidentOutcome.SUPPRESSED,
            -> true
        }

    fun enqueueFinalized(bundle: FeedIncidentBundle) {
        val capturedEpoch = currentEpoch()
        executor.execute { captureIfFinalized(bundle, capturedEpoch) }
    }

    fun enqueueFinalizedFromSpool() {
        val capturedEpoch = currentEpoch()
        executor.execute {
            if (!ReliabilityReportingConsent.isOptedIn ||
                capturedEpoch != currentEpoch() ||
                ReliabilityReportingGate.shouldBlockUpload
            ) {
                return@execute
            }
            for (bundle in finalizedSpoolLoader()) {
                if (isFinalized(bundle)) captureIfFinalized(bundle, capturedEpoch)
            }
            for (summary in sessionSummaryLoader()) {
                captureSessionSummary(summary, capturedEpoch)
            }
        }
    }

    fun noteSessionSummary(summary: FeedIncidentSessionSummary) {
        val capturedEpoch = currentEpoch()
        executor.execute { captureSessionSummary(summary, capturedEpoch) }
    }

    fun receipt(forIncidentID: String): ReliabilityReportingReceipt? =
        ReliabilityReportingReceipts.load(forIncidentID, sdkCacheRoot)

    fun setCaptureHandlerForTests(handler: ((SentryEvent, ByteArray) -> Unit)?) {
        captureHandler = handler
    }

    fun noteTransportSuccess(eventID: String) {
        if (!ReliabilityReportingConsent.isOptedIn) return
        synchronized(lock) {
            for ((id, pendingEventID) in pendingEventIds) {
                if (pendingEventID.equals(eventID, ignoreCase = true)) {
                    ReliabilityReportingReceipts.store(
                        ReliabilityReportingReceipt(
                            incidentID = id,
                            eventID = eventID,
                            state = ReliabilityReportingReceiptState.CONFIRMED,
                            updatedAt = System.currentTimeMillis(),
                        ),
                        sdkCacheRoot,
                    )
                }
            }
        }
        ReliabilityReportingReceipts.markConfirmed(eventID, sdkCacheRoot)
    }

    fun applyPrivacyOptions(options: SentryAndroidOptions) {
        options.isSendDefaultPii = false
        options.isEnableAutoSessionTracking = false
        options.maxCacheItems = 30
        options.maxAttachmentSize = 256 * 1_024L
        options.shutdownTimeoutMillis = 0
        options.connectionTimeoutMillis = 20_000
        options.readTimeoutMillis = 20_000
        options.maxBreadcrumbs = 32
        options.isEnableUserInteractionTracing = false
        options.isEnableUserInteractionBreadcrumbs = false
        options.isEnableAutoActivityLifecycleTracing = false
        options.isEnableActivityLifecycleTracingAutoFinish = false
        options.isEnableFramesTracking = false
        options.isEnablePerformanceV2 = false
        options.isAttachScreenshot = false
        options.isAttachViewHierarchy = false
        options.isAttachStacktrace = false
        options.release =
            "com.opencapture.openpocketcine@${BuildConfig.VERSION_NAME}+${BuildConfig.VERSION_CODE}"
        options.dist = BuildConfig.VERSION_CODE.toString()
        options.environment = if (BuildConfig.DEBUG) "development" else "production"
        options.isAnrEnabled = true
        options.isEnableUncaughtExceptionHandler = true
        options.isEnableNdk = true
        options.isEnableRootCheck = false
        options.isCollectAdditionalContext = false
        options.enableAllAutoBreadcrumbs(false)
        options.sessionReplay.sessionSampleRate = 0.0
        options.sessionReplay.onErrorSampleRate = 0.0
        options.tracesSampleRate = 0.0
        options.setBeforeBreadcrumb { breadcrumb, _ ->
            ReliabilityReportingPrivacy.scrubBreadcrumb(breadcrumb)
        }
        options.setBeforeSend { event, _ ->
            if (!ReliabilityReportingConsent.isOptedIn) return@setBeforeSend null
            ReliabilityReportingPrivacy.scrub(event)
        }
        options.setBeforeSendTransaction { _, _ -> null }
        options.setTransportGate(ReliabilityReportingGate)
        options.setTransportFactory(ReliabilityReportingTransportFactory())
        runCatching { options.logs.isEnabled = false }
        runCatching { options.setEnableLegacyProfiling(false) }
        runCatching { options.anrProfilingSampleRate = null }
        runCatching { options.isTombstoneEnabled = false }
        runCatching { options.isEnableAppStartProfiling = false }
    }

    fun makeOptions(dsn: String): SentryAndroidOptions {
        val options = SentryAndroidOptions()
        options.dsn = dsn
        options.cacheDirPath = sdkCacheRoot.absolutePath
        applyPrivacyOptions(options)
        return options
    }

    private fun applySdkState() {
        val consent = ReliabilityReportingConsent.isOptedIn
        val dsn = ReliabilityReportingDSN.configured()
        if (consent && dsn != null) {
            dsnHost = ReliabilityReportingHostPolicy.host(fromDSN = dsn)
            scheduleIdlePoll()
            observeInternetIfNeeded()
            startSdk(dsn)
        } else {
            stopAndPurgeSdkOwned()
        }
    }

    private fun observeInternetIfNeeded() {
        val app = appContext ?: return
        if (networkCallback != null) return
        val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return
        val callback =
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = onPathChanged()
                override fun onLost(network: Network) = onPathChanged()
                override fun onCapabilitiesChanged(network: Network, caps: NetworkCapabilities) =
                    onPathChanged()
            }
        networkCallback = callback
        runCatching {
            cm.registerNetworkCallback(
                NetworkRequest.Builder().addCapability(NetworkCapabilities.NET_CAPABILITY_INTERNET).build(),
                callback,
            )
        }
    }

    private fun onPathChanged() {
        postOnMain {
            if (!ReliabilityReportingConsent.isOptedIn) return@postOnMain
            if (ReliabilityReportingGate.shouldBlockUpload) {
                ReliabilityReportingGate.cancelPending()
            } else {
                ReliabilityReportingDSN.configured()?.let { dsn ->
                    if (!sdkStarted.get()) startSdk(dsn)
                }
                enqueueFinalizedFromSpool()
                scheduleResumeIfIdle()
            }
        }
    }

    private fun startSdk(dsn: String) {
        if (sdkStarted.get()) {
            enqueueFinalizedFromSpool()
            return
        }
        val capturedEpoch = currentEpoch()
        dsnHost = ReliabilityReportingHostPolicy.host(fromDSN = dsn)
        executor.execute {
            if (capturedEpoch != currentEpoch() || !ReliabilityReportingConsent.isOptedIn) return@execute
            sdkCacheRoot.mkdirs()
            postOnMain {
                if (capturedEpoch != currentEpoch() || !ReliabilityReportingConsent.isOptedIn) {
                    return@postOnMain
                }
                if (sdkStarted.compareAndSet(false, true)) {
                    val app = appContext
                    if (app == null) {
                        sdkStarted.set(false)
                    } else {
                        SentryAndroid.init(app) { configured ->
                            configured.dsn = dsn
                            configured.cacheDirPath = sdkCacheRoot.absolutePath
                            applyPrivacyOptions(configured)
                            configured.isForceInit = true
                        }
                        Sentry.configureScope { scope ->
                            scope.setTag("sourceRevision", BuildConfig.SOURCE_REVISION)
                            scope.setTag("testSource", FeedIncidentOrigin.currentTestSource().wire)
                            scope.setTag("buildIdentity", FeedIncidentOrigin.currentBuildIdentity())
                        }
                    }
                }
                enqueueFinalizedFromSpool()
                scheduleResumeIfIdle()
            }
        }
    }

    private fun stopAndPurgeSdkOwned() {
        val callback = networkCallback
        networkCallback = null
        val app = appContext
        if (callback != null && app != null) {
            val cm = app.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager
            runCatching { cm?.unregisterNetworkCallback(callback) }
        }
        ReliabilityReportingGate.cancelPending()
        val close = {
            if (sdkStarted.compareAndSet(true, false)) {
                Sentry.close()
            }
            executor.execute {
                ReliabilityReportingReceipts.purge(sdkCacheRoot)
                sdkCacheRoot.deleteRecursively()
            }
        }
        runOnMain(close)
    }

    private fun runOnMain(block: () -> Unit) {
        val looper = runCatching { Looper.getMainLooper() }.getOrNull()
        if (looper == null || Looper.myLooper() == looper) {
            block()
        } else {
            Handler(looper).post(block)
        }
    }

    private fun postOnMain(delayMs: Long = 0L, block: () -> Unit) {
        val looper = runCatching { Looper.getMainLooper() }.getOrNull()
        if (looper == null) {
            if (delayMs == 0L) block()
            return
        }
        if (delayMs == 0L) Handler(looper).post(block) else Handler(looper).postDelayed(block, delayMs)
    }

    private fun captureIfFinalized(bundle: FeedIncidentBundle, capturedEpoch: Long) {
        if (capturedEpoch != currentEpoch() || !ReliabilityReportingConsent.isOptedIn) return
        if (!isFinalized(bundle)) return
        val envelope = ReliabilityReportingPrivacy.validatedEnvelope(bundle) ?: return
        val json = ReliabilityReportingPrivacy.typedJson(bundle) ?: return
        val eventId = ReliabilityReportingPrivacy.eventId(envelope.incidentID)
        val event = makeEvent(envelope, eventId)
        capturePayload(event, json, envelope.incidentID, capturedEpoch)
    }

    private fun captureSessionSummary(summary: FeedIncidentSessionSummary, capturedEpoch: Long) {
        if (capturedEpoch != currentEpoch() || !ReliabilityReportingConsent.isOptedIn) return
        if (summary.outcome == "live") return
        if (runCatching { UUID.fromString(summary.sessionID) }.getOrNull() == null) return
        if (!summary.healthyExposureSeconds.isFinite() || summary.healthyExposureSeconds < 0.0) return
        val json =
            org.json.JSONObject()
                .put("sessionID", summary.sessionID)
                .put("healthyExposureSeconds", summary.healthyExposureSeconds)
                .put("incidentCount", summary.incidentCount)
                .put("outcome", summary.outcome)
                .put("sourceRevision", summary.sourceRevision)
                .toString()
                .toByteArray(Charsets.UTF_8)
        if (json.size > 4_096) return
        val event = SentryEvent()
        event.level = SentryLevel.INFO
        event.eventId = ReliabilityReportingPrivacy.eventId(summary.sessionID)
        event.timestamp = Date(summary.recordedAtMs)
        event.release = if (summary.appVersion != null && summary.appBuild != null)
            "com.opencapture.openpocketcine@${summary.appVersion}+${summary.appBuild}"
        else "legacy-session-unknown-release"
        event.dist = summary.appBuild
        val message = Message()
        message.formatted = "Feed session summary"
        event.message = message
        event.fingerprints = listOf("feed-session", "schema:1")
        event.setTag("kind", "sessionSummary")
        event.setTag("outcome", summary.outcome)
        event.setTag("sourceRevision", summary.sourceRevision)
        event.setTag("testSource", (summary.testSource ?: FeedIncidentTestSource.UNKNOWN).wire)
        event.setTag("buildIdentity", FeedIncidentBuildIdentity.parse(summary.buildIdentity))
        event.setExtra("healthyExposureSeconds", summary.healthyExposureSeconds)
        event.setExtra("incidentCount", summary.incidentCount)
        event.setExtra("sourceRevision", summary.sourceRevision)
        event.setExtra("testSource", (summary.testSource ?: FeedIncidentTestSource.UNKNOWN).wire)
        event.setExtra("buildIdentity", FeedIncidentBuildIdentity.parse(summary.buildIdentity))
        capturePayload(
            ReliabilityReportingPrivacy.scrub(event),
            json,
            "session-" + summary.sessionID,
            capturedEpoch,
        )
    }

    private fun capturePayload(
        event: SentryEvent,
        json: ByteArray,
        id: String,
        capturedEpoch: Long,
    ) {
        if (capturedEpoch != currentEpoch() ||
            !ReliabilityReportingConsent.isOptedIn ||
            ReliabilityReportingGate.shouldBlockUpload
        ) {
            return
        }
        ReliabilityReportingReceipts.applyTTL(sdkCacheRoot)
        val existing = ReliabilityReportingReceipts.load(id, sdkCacheRoot)
        if (existing != null) {
            if (existing.state == ReliabilityReportingReceiptState.CONFIRMED) return
            if (System.currentTimeMillis() - existing.updatedAt < 300_000L) return
        }
        synchronized(lock) {
            if (!pendingCaptureIds.add(id)) return
            pendingEventIds[id] = event.eventId.toString()
        }
        val handler = captureHandler
        if (handler != null) {
            handler(event, json)
            synchronized(lock) {
                pendingCaptureIds.remove(id)
                pendingEventIds.remove(id)
            }
            if (currentEpoch() == capturedEpoch && ReliabilityReportingConsent.isOptedIn) {
                val receipt = ReliabilityReportingReceipts.load(id, sdkCacheRoot)
                if (receipt?.state != ReliabilityReportingReceiptState.CONFIRMED) {
                    ReliabilityReportingReceipts.store(
                        ReliabilityReportingReceipt(
                            incidentID = id,
                            eventID = event.eventId.toString(),
                            state = ReliabilityReportingReceiptState.QUEUED,
                            updatedAt = System.currentTimeMillis(),
                        ),
                        sdkCacheRoot,
                    )
                }
            }
            return
        }
        postOnMain {
            try {
                if (capturedEpoch != currentEpoch() ||
                    !ReliabilityReportingConsent.isOptedIn ||
                    (!sdkStarted.get() && captureHandler == null)
                ) {
                    return@postOnMain
                }
                Sentry.captureEvent(event) { scope ->
                    scope.clearAttachments()
                    scope.addAttachment(Attachment(json, "$id.json", "application/json"))
                    applyOriginalTags(event.tags, scope)
                }
                executor.execute {
                    if (capturedEpoch != currentEpoch() || !ReliabilityReportingConsent.isOptedIn) {
                        return@execute
                    }
                    val receipt = ReliabilityReportingReceipts.load(id, sdkCacheRoot)
                    if (receipt?.state == ReliabilityReportingReceiptState.CONFIRMED) return@execute
                    ReliabilityReportingReceipts.store(
                        ReliabilityReportingReceipt(
                            incidentID = id,
                            eventID = event.eventId.toString(),
                            state = ReliabilityReportingReceiptState.QUEUED,
                            updatedAt = System.currentTimeMillis(),
                        ),
                        sdkCacheRoot,
                    )
                }
            } finally {
                executor.execute {
                    synchronized(lock) {
                        pendingCaptureIds.remove(id)
                        pendingEventIds.remove(id)
                    }
                }
            }
        }
    }

    private fun makeEvent(envelope: FeedIncidentVendorEnvelope, eventId: io.sentry.protocol.SentryId): SentryEvent {
        val event = SentryEvent()
        event.level = SentryLevel.ERROR
        event.eventId = eventId
        event.timestamp = Date(envelope.startedAtWallClockMs)
        event.release = "com.opencapture.openpocketcine@${envelope.appVersion}+${envelope.appBuild}"
        event.dist = envelope.appBuild
        val message = Message()
        message.formatted = "feed incident ${envelope.grouping.failingStage}"
        event.message = message
        event.fingerprints =
            ReliabilityReportingPrivacy.fingerprint(
                envelope.schemaVersion,
                envelope.kind,
                envelope.grouping.failingStage,
                envelope.grouping.errorClass,
            )
        event.setTag("failingStage", envelope.grouping.failingStage)
        event.setTag("errorClass", envelope.grouping.errorClass)
        event.setTag("outcome", envelope.grouping.outcome)
        event.setTag("kind", envelope.kind)
        event.setTag("sourceRevision", envelope.sourceRevision)
        event.setTag("cameraFamily", envelope.cameraFamily)
        event.setTag("cameraFirmware", envelope.grouping.cameraFirmware)
        event.setTag("hardwareClass", envelope.grouping.hardwareClass)
        event.setTag("testSource", envelope.testSource)
        event.setTag("buildIdentity", envelope.buildIdentity)
        event.setExtra("schemaVersion", envelope.schemaVersion)
        event.setExtra("failingStage", envelope.grouping.failingStage)
        event.setExtra("errorClass", envelope.grouping.errorClass)
        event.setExtra("outcome", envelope.grouping.outcome)
        event.setExtra("kind", envelope.kind)
        event.setExtra("hardwareClass", envelope.grouping.hardwareClass)
        event.setExtra("cameraFirmware", envelope.grouping.cameraFirmware)
        event.setExtra("assistState", envelope.grouping.assistState)
        event.setExtra("decoderGeneration", envelope.decoderGeneration)
        event.setExtra("socketGeneration", envelope.socketGeneration)
        event.setExtra("worstGapSeconds", envelope.worstGapSeconds)
        event.setExtra("healthyExposureSeconds", envelope.healthyExposureSeconds)
        event.setExtra("sourceRevision", envelope.sourceRevision)
        event.setExtra("testSource", envelope.testSource)
        event.setExtra("buildIdentity", envelope.buildIdentity)
        event.contexts["feed"] =
            mapOf(
                "schemaVersion" to envelope.schemaVersion,
                "failingStage" to envelope.grouping.failingStage,
                "errorClass" to envelope.grouping.errorClass,
                "outcome" to envelope.grouping.outcome,
                "kind" to envelope.kind,
                "assistState" to envelope.grouping.assistState,
                "hardwareClass" to envelope.grouping.hardwareClass,
                "testSource" to envelope.testSource,
                "buildIdentity" to envelope.buildIdentity,
            )
        return ReliabilityReportingPrivacy.scrub(event)
    }

    private fun scheduleIdlePoll() {
        if (!idlePollScheduled.compareAndSet(false, true)) return
        postOnMain(30_000L) {
            idlePollScheduled.set(false)
            if (!ReliabilityReportingConsent.isOptedIn) return@postOnMain
            val dsn = ReliabilityReportingDSN.configured() ?: return@postOnMain
            startSdk(dsn)
            if (!ReliabilityReportingGate.shouldBlockUpload) {
                enqueueFinalizedFromSpool()
                scheduleResumeIfIdle()
            }
            scheduleIdlePoll()
        }
    }

    private fun scheduleResumeIfIdle() {
        if (ReliabilityReportingGate.shouldBlockUpload ||
            !ReliabilityReportingConsent.isOptedIn ||
            !sdkStarted.get() ||
            !resumeScheduled.compareAndSet(false, true)
        ) {
            return
        }
        val attempt = resumeAttempt
        resumeAttempt = minOf(resumeAttempt + 1, 6)
        val jitter = ((attempt * 37) % 100).toDouble() / 100.0
        val delayMs = (ReliabilityReportingBackoff.delaySeconds(attempt, jitter) * 1000).toLong()
        val capturedEpoch = currentEpoch()
        executor.execute {
            try {
                Thread.sleep(delayMs)
            } catch (_: InterruptedException) {
                Thread.currentThread().interrupt()
            }
            try {
                if (capturedEpoch != currentEpoch() ||
                    !ReliabilityReportingConsent.isOptedIn ||
                    ReliabilityReportingGate.shouldBlockUpload ||
                    !sdkStarted.get()
                ) {
                    return@execute
                }
                Sentry.flush(2_000)
                postOnMain { resumeAttempt = 0 }
            } finally {
                postOnMain { resumeScheduled.set(false) }
            }
        }
    }

    private fun bumpEpoch() {
        epoch.incrementAndGet()
    }

    private fun currentEpoch(): Long = epoch.get()

    private fun processBoundToCamera(context: Context): Boolean {
        val cm = context.getSystemService(Context.CONNECTIVITY_SERVICE) as? ConnectivityManager ?: return false
        val bound = cm.boundNetworkForProcess ?: return false
        val caps = cm.getNetworkCapabilities(bound) ?: return false
        if (!caps.hasTransport(NetworkCapabilities.TRANSPORT_WIFI)) return false
        val props = cm.getLinkProperties(bound) ?: return false
        return props.linkAddresses.any { addr ->
            val host = (addr.address as? java.net.Inet4Address)?.hostAddress
            host?.startsWith("192.168.2.") == true
        }
    }
}
