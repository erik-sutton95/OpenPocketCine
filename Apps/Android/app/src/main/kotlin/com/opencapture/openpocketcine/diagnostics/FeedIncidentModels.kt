package com.opencapture.openpocketcine.diagnostics

internal object FeedIncidentSchema {
    const val VERSION = 1
}

internal enum class FeedIncidentTestSource(val wire: String) {
    MANUAL("manual"),
    AUTOMATION("automation"),
    FAULT_INJECTION("faultInjection"),
    VERIFICATION("verification"),
    UNKNOWN("unknown"),
    ;

    val rank: Int
        get() =
            when (this) {
                UNKNOWN -> 0
                MANUAL -> 1
                AUTOMATION -> 2
                FAULT_INJECTION -> 3
                VERIFICATION -> 4
            }

    companion object {
        fun fromWire(raw: String?): FeedIncidentTestSource =
            entries.firstOrNull { it.wire == raw } ?: UNKNOWN

        fun derive(
            verification: Boolean,
            injectionActivated: Boolean,
            automation: Boolean,
        ): FeedIncidentTestSource =
            when {
                verification -> VERIFICATION
                injectionActivated -> FAULT_INJECTION
                automation -> AUTOMATION
                else -> MANUAL
            }
    }
}

internal object FeedIncidentBuildIdentity {
    const val MAX_LENGTH = 64

    fun parse(raw: String?): String {
        val trimmed = raw?.trim().orEmpty()
        if (trimmed.isEmpty()) return "unknown"
        return FeedIncidentPrivacy.token(trimmed, MAX_LENGTH)
    }
}

internal object FeedIncidentBounds {
    const val PRELUDE_SECONDS = 60.0
    const val AFTERMATH_SECONDS = 30.0
    const val STALL_SECONDS = 2.0
    const val STRING_LENGTH = 96
    const val RING_COUNT = 60
    const val BREADCRUMB_RING = 32
    const val REPAIR_RING = 32
    const val DURING_COUNT = 60
    const val ERROR_CLASSES = 16
}

internal data class FeedIncidentLimits(
    val maxBundles: Int = 20,
    val maxBundleBytes: Int = 262_144,
    val maxSpoolBytes: Int = 10_485_760,
    val ttlMs: Long = 604_800_000L,
)

internal data class FeedIncidentSessionContext(
    val sessionId: String,
    val appVersion: String,
    val appBuild: String,
    val sourceRevision: String,
    val osName: String,
    val osVersion: String,
    val hardwareClass: String,
    val cameraFamily: String,
    val cameraFirmware: String? = null,
    var decoderGeneration: Int = 0,
    var socketGeneration: Int = 0,
    var testSource: FeedIncidentTestSource = FeedIncidentTestSource.UNKNOWN,
    var buildIdentity: String = "unknown",
)

internal enum class FeedIncidentKind(val wire: String) {
    FRESH_INPUT_STALE_OUTPUT("freshInputStaleOutput"),
    DECODER_ERROR("decoderError"),
    PRESENT_STALLED("presentStalled"),
    ASSIST_STALLED("assistStalled"),
    TRANSPORT_STALL("transportStall"),
    UNEXPECTED_DISCONNECT("unexpectedDisconnect"),
    ;

    companion object {
        fun fromWire(raw: String) = entries.firstOrNull { it.wire == raw } ?: TRANSPORT_STALL
    }
}

internal enum class FeedIncidentFailingStage(val wire: String) {
    PACKET("packet"),
    ACCESS_UNIT("accessUnit"),
    DECODE_ACCEPT("decodeAccept"),
    DECODED_OUTPUT("decodedOutput"),
    ASSIST_OUTPUT("assistOutput"),
    PRESENTATION("presentation"),
    ;

    companion object {
        fun fromWire(raw: String) = entries.firstOrNull { it.wire == raw } ?: PACKET

        fun isKnown(raw: String): Boolean = entries.any { it.wire == raw }
    }
}

internal enum class FeedIncidentOutcome(val wire: String) {
    OPEN("open"),
    RECOVERED("recovered"),
    INTERRUPTED("interrupted"),
    EXHAUSTED("exhausted"),
    SUPPRESSED("suppressed"),
    ;

    companion object {
        fun fromWire(raw: String) = entries.firstOrNull { it.wire == raw } ?: OPEN
    }
}

internal enum class FeedIncidentSuppression { NONE, DISCONNECTED, PLAYBACK, BACKGROUND, NEVER_ESTABLISHED }

internal enum class FeedDecoderErrorOrigin(val wire: String) {
    NONE("none"),
    SYNC("sync"),
    CALLBACK("callback"),
    CREATE("create"),
    ;

    companion object {
        fun fromWire(raw: String) = entries.firstOrNull { it.wire == raw } ?: NONE
    }
}

internal enum class FeedIncidentBreadcrumbKind(val wire: String) {
    SETTINGS_ENTER("settingsEnter"),
    SETTINGS_EXIT("settingsExit"),
    ASSIST_CHANGE("assistChange"),
    SCENE_ACTIVITY("sceneActivity"),
    SURFACE_ATTACH("surfaceAttach"),
    SURFACE_DETACH("surfaceDetach"),
    DECODER_CREATE("decoderCreate"),
    DECODER_INVALIDATE("decoderInvalidate"),
    PATH_CHANGE("pathChange"),
    CAMERA_COMMAND("cameraCommand"),
    ;

    companion object {
        fun fromWire(raw: String) = entries.firstOrNull { it.wire == raw } ?: SCENE_ACTIVITY
    }
}

internal enum class FeedRepairPhase(val wire: String) {
    REQUESTED("requested"),
    BLOCKED("blocked"),
    LOCALLY_SENT("locallySent"),
    PEER_RESPONSE("peerResponse"),
    PICTURE_RESTORED("pictureRestored"),
    ;

    companion object {
        fun fromWire(raw: String) = entries.firstOrNull { it.wire == raw } ?: REQUESTED
    }
}

internal data class FeedIncidentRates(
    val packetHz: Double = 0.0,
    val accessUnitHz: Double = 0.0,
    val decodeSubmitHz: Double = 0.0,
    val decodeAcceptHz: Double = 0.0,
    val decodedOutputHz: Double = 0.0,
    val assistOutputHz: Double = 0.0,
    val presentHz: Double = 0.0,
    val ackHz: Double = 0.0,
)

internal data class FeedIncidentAges(
    val packetAge: Double? = null,
    val accessUnitAge: Double? = null,
    val decodeAcceptAge: Double? = null,
    val decodedOutputAge: Double? = null,
    val assistOutputAge: Double? = null,
    val presentAge: Double? = null,
)

internal data class FeedIncidentQueue(
    val bytes: Int = 0,
    val count: Int = 0,
    val ageMilliseconds: Double = 0.0,
    val incompleteAccessUnits: Int = 0,
    val drops: Int = 0,
)

internal data class FeedIncidentDecoder(
    val generation: Int = 0,
    val formatGeneration: Int = 0,
    val codec: String = "hevc",
    val width: Int = 0,
    val height: Int = 0,
    val lastStatus: Int? = null,
    val lastFlags: Long? = null,
    val origin: FeedDecoderErrorOrigin = FeedDecoderErrorOrigin.NONE,
    val errorClass: String? = null,
    val errorCount: Int = 0,
    val decoderFailed: Boolean = false,
    val errorAge: Double? = null,
    val receivedIrap: Boolean = false,
    val awaitingIrap: Boolean = false,
    val hasDecodableReferences: Boolean = true,
    val lastIrapAge: Double? = null,
    val lastSuccessfulOutputAge: Double? = null,
    val rebuildReason: String? = null,
)

internal data class FeedIncidentLifecycle(
    val foreground: Boolean = true,
    val settingsCovered: Boolean = false,
    val playbackActive: Boolean = false,
    val connected: Boolean = false,
    val liveEstablished: Boolean = false,
    val thermalState: String = "nominal",
    val memoryWarning: Boolean = false,
    val lowPower: Boolean = false,
    val sceneActive: Boolean = true,
    val assistState: String = "off",
    val outputObservable: Boolean = true,
    val presentationExpected: Boolean = true,
)

internal data class FeedIncidentSnapshot(
    val monotonicNow: Double,
    val wallClockMs: Long = 0L,
    val rates: FeedIncidentRates = FeedIncidentRates(),
    val ages: FeedIncidentAges = FeedIncidentAges(),
    val queue: FeedIncidentQueue = FeedIncidentQueue(),
    val decoder: FeedIncidentDecoder = FeedIncidentDecoder(),
    val lifecycle: FeedIncidentLifecycle = FeedIncidentLifecycle(),
    val watchdogAction: String = "none",
    val diagnoserFailure: String = "none",
    val diagnoserRepair: String = "none",
)

internal data class FeedIncidentBreadcrumb(
    val monotonicAt: Double,
    val kind: FeedIncidentBreadcrumbKind,
    val detail: String = "",
)

internal object FeedIncidentNativeBreadcrumb {
    val allowedValues: Map<String, Set<String>> =
        mapOf(
            "sceneState" to setOf("active", "inactive"),
            "assistState" to setOf("off", "identity", "replacement"),
            "path" to setOf("unexpectedDisconnect"),
            "repairPhase" to
                setOf("requested", "blocked", "locallySent", "peerResponse", "pictureRestored"),
            "repairAction" to setOf("decoder", "enable", "session", "endpoint", "rejoin"),
        )

    fun isAllowedMessage(message: String): Boolean =
        FeedIncidentBreadcrumbKind.entries.any { it.wire == message } || message == "repair"

    fun details(kind: FeedIncidentBreadcrumbKind, detail: String): Map<String, String> =
        when (kind) {
            FeedIncidentBreadcrumbKind.SCENE_ACTIVITY -> sanitized(mapOf("sceneState" to detail))
            FeedIncidentBreadcrumbKind.ASSIST_CHANGE -> sanitized(mapOf("assistState" to detail))
            FeedIncidentBreadcrumbKind.PATH_CHANGE -> sanitized(mapOf("path" to detail))
            FeedIncidentBreadcrumbKind.SETTINGS_ENTER,
            FeedIncidentBreadcrumbKind.SETTINGS_EXIT,
            FeedIncidentBreadcrumbKind.SURFACE_ATTACH,
            FeedIncidentBreadcrumbKind.SURFACE_DETACH,
            FeedIncidentBreadcrumbKind.DECODER_CREATE,
            FeedIncidentBreadcrumbKind.DECODER_INVALIDATE,
            FeedIncidentBreadcrumbKind.CAMERA_COMMAND,
            -> emptyMap()
        }

    fun details(repair: FeedRepairRecord): Map<String, String> =
        sanitized(mapOf("repairPhase" to repair.phase.wire, "repairAction" to repair.action))

    fun sanitized(raw: Map<String, String>): Map<String, String> {
        val out = mutableMapOf<String, String>()
        for ((key, value) in raw) {
            val token = FeedIncidentPrivacy.token(value, 32)
            val allowed = allowedValues[key] ?: continue
            if (token !in allowed) continue
            out[key] = token
        }
        return out
    }
}

internal data class FeedRepairRecord(
    val monotonicAt: Double,
    val action: String,
    val phase: FeedRepairPhase,
    val reason: String? = null,
)

internal data class FeedIncidentErrorCount(
    val errorClass: String,
    val count: Int,
)

internal data class FeedIncidentHeader(
    var schemaVersion: Int = FeedIncidentSchema.VERSION,
    var incidentId: String,
    var sessionId: String,
    var kind: FeedIncidentKind,
    var failingStage: FeedIncidentFailingStage,
    var errorClass: String? = null,
    var outcome: FeedIncidentOutcome = FeedIncidentOutcome.OPEN,
    var startedAtWallClockMs: Long,
    var startedAtMonotonic: Double,
    var endedAtMonotonic: Double? = null,
    var firstFailureAt: Double,
    var worstGapSeconds: Double,
    var appVersion: String,
    var appBuild: String,
    var sourceRevision: String,
    var osName: String,
    var osVersion: String,
    var hardwareClass: String,
    var cameraFamily: String,
    var cameraFirmware: String? = null,
    var decoderGeneration: Int = 0,
    var socketGeneration: Int = 0,
    var evictions: Int = 0,
    var assistState: String = "off",
    var healthyExposureSeconds: Double = 0.0,
    var testSource: FeedIncidentTestSource = FeedIncidentTestSource.UNKNOWN,
    var buildIdentity: String = "unknown",
) {
    val processInterrupted: Boolean get() = outcome == FeedIncidentOutcome.INTERRUPTED
}

internal data class FeedIncidentBundle(
    var header: FeedIncidentHeader,
    var prelude: List<FeedIncidentSnapshot>,
    var during: List<FeedIncidentSnapshot> = emptyList(),
    var aftermath: List<FeedIncidentSnapshot> = emptyList(),
    var breadcrumbs: List<FeedIncidentBreadcrumb> = emptyList(),
    var repairs: List<FeedRepairRecord> = emptyList(),
    var aggregatedErrors: List<FeedIncidentErrorCount> = emptyList(),
)

internal data class FeedIncidentVerdict(
    val suppression: FeedIncidentSuppression,
    val kind: FeedIncidentKind? = null,
    val failingStage: FeedIncidentFailingStage? = null,
) {
    val shouldRecord: Boolean
        get() = suppression == FeedIncidentSuppression.NONE && kind != null && failingStage != null
}

internal data class FeedIncidentPersistenceJob(
    val bundle: FeedIncidentBundle,
    val reason: Reason,
) {
    enum class Reason { STARTED, CHECKPOINT, REPAIR, OUTCOME }
}

internal object FeedIncidentPrivacy {
    fun token(raw: String, max: Int = FeedIncidentBounds.STRING_LENGTH): String {
        val clipped = raw.trim().take(max)
        return PrivacyRedactor.redact(clipped)
    }

    fun rate(value: Double): Double = if (value.isFinite() && value >= 0.0) value else 0.0

    fun stamp(value: Double): Double = if (value.isFinite() && value >= 0.0) value else 0.0

    fun age(value: Double?): Double? {
        if (value == null || !value.isFinite() || value < 0.0) return null
        return value
    }

    fun isFresh(age: Double?, threshold: Double): Boolean {
        if (age == null) return false
        return age < threshold
    }

    fun isStale(age: Double?, hertz: Double, flowingAlternative: Boolean, threshold: Double): Boolean {
        if (age != null) return age >= threshold
        return hertz == 0.0 && flowingAlternative
    }

    fun gapSeconds(snapshot: FeedIncidentSnapshot, stage: FeedIncidentFailingStage): Double {
        val ages = snapshot.ages
        val chosen =
            when (stage) {
                FeedIncidentFailingStage.PACKET -> ages.packetAge
                FeedIncidentFailingStage.ACCESS_UNIT -> ages.accessUnitAge
                FeedIncidentFailingStage.DECODE_ACCEPT -> ages.decodeAcceptAge
                FeedIncidentFailingStage.DECODED_OUTPUT -> ages.decodedOutputAge
                FeedIncidentFailingStage.ASSIST_OUTPUT -> ages.assistOutputAge
                FeedIncidentFailingStage.PRESENTATION -> ages.presentAge
            }
        return age(chosen) ?: 0.0
    }
}

internal object FeedIncidentClassifier {
    fun suppression(snapshot: FeedIncidentSnapshot): FeedIncidentSuppression? {
        val life = snapshot.lifecycle
        if (life.playbackActive) return FeedIncidentSuppression.PLAYBACK
        if (!life.connected) return FeedIncidentSuppression.DISCONNECTED
        if (!life.foreground || !life.sceneActive) return FeedIncidentSuppression.BACKGROUND
        if (!life.liveEstablished) return FeedIncidentSuppression.NEVER_ESTABLISHED
        return null
    }

    fun classify(snapshot: FeedIncidentSnapshot): FeedIncidentVerdict {
        suppression(snapshot)?.let {
            return FeedIncidentVerdict(it)
        }
        val life = snapshot.lifecycle
        val threshold = FeedIncidentBounds.STALL_SECONDS
        val packetFresh =
            FeedIncidentPrivacy.isFresh(snapshot.ages.packetAge, threshold) ||
                snapshot.rates.packetHz >= 1.0
        val auFresh =
            FeedIncidentPrivacy.isFresh(snapshot.ages.accessUnitAge, threshold) ||
                snapshot.rates.accessUnitHz >= 1.0
        val inputFresh = packetFresh || auFresh
        val outputStale =
            life.outputObservable &&
                FeedIncidentPrivacy.isStale(
                    snapshot.ages.decodedOutputAge,
                    snapshot.rates.decodedOutputHz,
                    snapshot.rates.decodeSubmitHz >= 1.0 || inputFresh,
                    threshold,
                )
        val outputFresh =
            life.outputObservable &&
                FeedIncidentPrivacy.isFresh(snapshot.ages.decodedOutputAge, threshold)
        val presentStale =
            life.presentationExpected &&
                FeedIncidentPrivacy.isStale(
                    snapshot.ages.presentAge,
                    snapshot.rates.presentHz,
                    true,
                    threshold,
                )
        val assistStale =
            FeedIncidentPrivacy.isStale(
                snapshot.ages.assistOutputAge,
                snapshot.rates.assistOutputHz,
                outputFresh,
                threshold,
            )
        if (life.outputObservable && outputStale) {
            val currentError = isCurrentDecoderFailure(snapshot.decoder)
            val acceptStale =
                FeedIncidentPrivacy.isStale(
                    snapshot.ages.decodeAcceptAge,
                    snapshot.rates.decodeAcceptHz,
                    snapshot.rates.decodeSubmitHz >= 1.0,
                    threshold,
                )
            val stage =
                if (acceptStale && snapshot.rates.decodeSubmitHz >= 1.0) {
                    FeedIncidentFailingStage.DECODE_ACCEPT
                } else {
                    FeedIncidentFailingStage.DECODED_OUTPUT
                }
            val kind =
                when {
                    currentError -> FeedIncidentKind.DECODER_ERROR
                    inputFresh -> FeedIncidentKind.FRESH_INPUT_STALE_OUTPUT
                    else -> FeedIncidentKind.TRANSPORT_STALL
                }
            return FeedIncidentVerdict(FeedIncidentSuppression.NONE, kind, stage)
        }
        if ((outputFresh || !life.outputObservable) && assistStale && snapshot.ages.assistOutputAge != null) {
            return FeedIncidentVerdict(
                FeedIncidentSuppression.NONE,
                FeedIncidentKind.ASSIST_STALLED,
                FeedIncidentFailingStage.ASSIST_OUTPUT,
            )
        }
        if ((outputFresh || !life.outputObservable) && presentStale) {
            return FeedIncidentVerdict(
                FeedIncidentSuppression.NONE,
                FeedIncidentKind.PRESENT_STALLED,
                FeedIncidentFailingStage.PRESENTATION,
            )
        }
        if (!inputFresh) {
            if (life.outputObservable && outputFresh) {
                return FeedIncidentVerdict(FeedIncidentSuppression.NONE)
            }
            if (!life.outputObservable &&
                life.presentationExpected &&
                FeedIncidentPrivacy.isFresh(snapshot.ages.presentAge, threshold)
            ) {
                return FeedIncidentVerdict(FeedIncidentSuppression.NONE)
            }
            return FeedIncidentVerdict(
                FeedIncidentSuppression.NONE,
                FeedIncidentKind.TRANSPORT_STALL,
                if (packetFresh) FeedIncidentFailingStage.ACCESS_UNIT else FeedIncidentFailingStage.PACKET,
            )
        }
        return FeedIncidentVerdict(FeedIncidentSuppression.NONE)
    }

    fun isRecovered(snapshot: FeedIncidentSnapshot): Boolean {
        if (suppression(snapshot) != null) return false
        val life = snapshot.lifecycle
        val threshold = FeedIncidentBounds.STALL_SECONDS
        if (!life.outputObservable && !life.presentationExpected) return false
        if (life.outputObservable) {
            if (!FeedIncidentPrivacy.isFresh(snapshot.ages.decodedOutputAge, threshold)) return false
        }
        if (life.presentationExpected) {
            if (!FeedIncidentPrivacy.isFresh(snapshot.ages.presentAge, threshold)) return false
        }
        return true
    }

    fun isCurrentDecoderFailure(decoder: FeedIncidentDecoder): Boolean {
        if (decoder.decoderFailed) return true
        val errorAge = decoder.errorAge ?: return false
        val success = decoder.lastSuccessfulOutputAge
        return if (success != null) errorAge < success else true
    }
}

internal data class FeedIncidentGrouping(
    val schemaVersion: Int,
    val failingStage: String,
    val errorClass: String,
    val outcome: String,
    val release: String,
    val os: String,
    val hardwareClass: String,
    val cameraFirmware: String,
    val assistState: String,
)

internal data class FeedIncidentVendorEnvelope(
    val schemaVersion: Int,
    val eventName: String,
    val grouping: FeedIncidentGrouping,
    val incidentID: String,
    val sessionID: String,
    val kind: String,
    val worstGapSeconds: Double,
    val healthyExposureSeconds: Double,
    val decoderGeneration: Int,
    val socketGeneration: Int,
    val startedAtWallClockMs: Long,
    val sourceRevision: String,
    val appVersion: String,
    val appBuild: String,
    val cameraFamily: String,
    val testSource: String,
    val buildIdentity: String,
)

internal data class FeedIncidentSessionSummary(
    val sessionID: String,
    val healthyExposureSeconds: Double,
    val incidentCount: Int,
    val outcome: String,
    val sourceRevision: String,
    val recordedAtMs: Long = System.currentTimeMillis(),
    val appVersion: String? = null,
    val appBuild: String? = null,
    val testSource: FeedIncidentTestSource? = null,
    val buildIdentity: String? = null,
)

internal object FeedIncidentExport {
    fun envelope(from: FeedIncidentBundle): FeedIncidentVendorEnvelope {
        val header = from.header
        val grouping =
            FeedIncidentGrouping(
                schemaVersion = header.schemaVersion,
                failingStage = header.failingStage.wire,
                errorClass = header.errorClass ?: "none",
                outcome = header.outcome.wire,
                release = "${header.appVersion}(${header.appBuild})",
                os = "${header.osName} ${header.osVersion}",
                hardwareClass = header.hardwareClass,
                cameraFirmware = header.cameraFirmware ?: "none",
                assistState = header.assistState,
            )
        return FeedIncidentVendorEnvelope(
            schemaVersion = header.schemaVersion,
            eventName = "feed.incident",
            grouping = grouping,
            incidentID = header.incidentId,
            sessionID = header.sessionId,
            kind = header.kind.wire,
            worstGapSeconds = header.worstGapSeconds,
            healthyExposureSeconds = header.healthyExposureSeconds,
            decoderGeneration = header.decoderGeneration,
            socketGeneration = header.socketGeneration,
            startedAtWallClockMs = header.startedAtWallClockMs,
            sourceRevision = header.sourceRevision,
            appVersion = header.appVersion,
            appBuild = header.appBuild,
            cameraFamily = header.cameraFamily,
            testSource = header.testSource.wire,
            buildIdentity = header.buildIdentity,
        )
    }
}

internal object FeedIncidentFileNaming {
    fun incident(id: String): String {
        val safe = id.filter { it.isLetterOrDigit() || it == '-' }
        return "incident-${safe.ifEmpty { "unknown" }}.json"
    }
}

internal object FeedIncidentSampling {
    fun <T> downsample(items: List<T>, keep: Int): List<T> {
        if (keep <= 0 || items.isEmpty()) return emptyList()
        if (items.size <= keep) return items
        if (keep == 1) return listOf(items.last())
        return (0 until keep).map { i ->
            items[i * (items.size - 1) / (keep - 1)]
        }
    }
}
