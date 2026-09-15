package com.opencapture.openpocketcine.diagnostics

import java.text.SimpleDateFormat
import java.util.Date
import java.util.Locale
import java.util.TimeZone
import org.json.JSONArray
import org.json.JSONObject

internal object FeedIncidentJson {
    private val iso =
        SimpleDateFormat("yyyy-MM-dd'T'HH:mm:ss'Z'", Locale.US).apply {
            timeZone = TimeZone.getTimeZone("UTC")
        }

    fun encode(bundle: FeedIncidentBundle): ByteArray = bundleJson(bundle).toString().toByteArray(Charsets.UTF_8)

    fun decode(bytes: ByteArray): FeedIncidentBundle? =
        runCatching { parseBundle(JSONObject(String(bytes, Charsets.UTF_8))) }.getOrNull()

    fun encodedSize(bundle: FeedIncidentBundle): Int = encode(bundle).size

    fun formatWall(ms: Long): String = iso.format(Date(ms))

    private fun bundleJson(bundle: FeedIncidentBundle): JSONObject =
        JSONObject()
            .put("header", headerJson(bundle.header))
            .put("prelude", snapshotArray(bundle.prelude))
            .put("during", snapshotArray(bundle.during))
            .put("aftermath", snapshotArray(bundle.aftermath))
            .put("breadcrumbs", breadcrumbArray(bundle.breadcrumbs))
            .put("repairs", repairArray(bundle.repairs))
            .put("aggregatedErrors", errorArray(bundle.aggregatedErrors))

    private fun headerJson(header: FeedIncidentHeader): JSONObject =
        JSONObject()
            .put("schemaVersion", header.schemaVersion)
            .put("incidentID", header.incidentId)
            .put("sessionID", header.sessionId)
            .put("kind", header.kind.wire)
            .put("failingStage", header.failingStage.wire)
            .put("outcome", header.outcome.wire)
            .put("startedAtWallClock", iso.format(Date(header.startedAtWallClockMs)))
            .put("startedAtMonotonic", header.startedAtMonotonic)
            .put("firstFailureAt", header.firstFailureAt)
            .put("worstGapSeconds", header.worstGapSeconds)
            .put("appVersion", header.appVersion)
            .put("appBuild", header.appBuild)
            .put("sourceRevision", header.sourceRevision)
            .put("osName", header.osName)
            .put("osVersion", header.osVersion)
            .put("hardwareClass", header.hardwareClass)
            .put("cameraFamily", header.cameraFamily)
            .put("decoderGeneration", header.decoderGeneration)
            .put("socketGeneration", header.socketGeneration)
            .put("evictions", header.evictions)
            .put("assistState", header.assistState)
            .put("healthyExposureSeconds", header.healthyExposureSeconds)
            .put("testSource", header.testSource.wire)
            .put("buildIdentity", header.buildIdentity)
            .also {
                header.errorClass?.let { value -> it.put("errorClass", value) }
                header.endedAtMonotonic?.let { value -> it.put("endedAtMonotonic", value) }
                header.cameraFirmware?.let { value -> it.put("cameraFirmware", value) }
            }

    private fun snapshotArray(items: List<FeedIncidentSnapshot>): JSONArray {
        val array = JSONArray()
        items.forEach { array.put(snapshotJson(it)) }
        return array
    }

    private fun snapshotJson(snap: FeedIncidentSnapshot): JSONObject =
        JSONObject()
            .put("monotonicNow", snap.monotonicNow)
            .put("wallClock", iso.format(Date(snap.wallClockMs)))
            .put(
                "rates",
                JSONObject()
                    .put("packetHz", snap.rates.packetHz)
                    .put("accessUnitHz", snap.rates.accessUnitHz)
                    .put("decodeSubmitHz", snap.rates.decodeSubmitHz)
                    .put("decodeAcceptHz", snap.rates.decodeAcceptHz)
                    .put("decodedOutputHz", snap.rates.decodedOutputHz)
                    .put("assistOutputHz", snap.rates.assistOutputHz)
                    .put("presentHz", snap.rates.presentHz)
                    .put("ackHz", snap.rates.ackHz),
            )
            .put("ages", agesJson(snap.ages))
            .put(
                "queue",
                JSONObject()
                    .put("bytes", snap.queue.bytes)
                    .put("count", snap.queue.count)
                    .put("ageMilliseconds", snap.queue.ageMilliseconds)
                    .put("incompleteAccessUnits", snap.queue.incompleteAccessUnits)
                    .put("drops", snap.queue.drops),
            )
            .put(
                "decoder",
                JSONObject()
                    .put("generation", snap.decoder.generation)
                    .put("formatGeneration", snap.decoder.formatGeneration)
                    .put("codec", snap.decoder.codec)
                    .put("width", snap.decoder.width)
                    .put("height", snap.decoder.height)
                    .put("origin", snap.decoder.origin.wire)
                    .put("errorCount", snap.decoder.errorCount)
                    .put("decoderFailed", snap.decoder.decoderFailed)
                    .put("receivedIrap", snap.decoder.receivedIrap)
                    .put("awaitingIrap", snap.decoder.awaitingIrap)
                    .put("hasDecodableReferences", snap.decoder.hasDecodableReferences)
                    .also { obj ->
                        snap.decoder.errorClass?.let { obj.put("errorClass", it) }
                        snap.decoder.errorAge?.let { obj.put("errorAge", it) }
                        snap.decoder.lastIrapAge?.let { obj.put("lastIrapAge", it) }
                        snap.decoder.lastSuccessfulOutputAge?.let { obj.put("lastSuccessfulOutputAge", it) }
                        snap.decoder.rebuildReason?.let { obj.put("rebuildReason", it) }
                    },
            )
            .put(
                "lifecycle",
                JSONObject()
                    .put("foreground", snap.lifecycle.foreground)
                    .put("settingsCovered", snap.lifecycle.settingsCovered)
                    .put("playbackActive", snap.lifecycle.playbackActive)
                    .put("connected", snap.lifecycle.connected)
                    .put("liveEstablished", snap.lifecycle.liveEstablished)
                    .put("thermalState", snap.lifecycle.thermalState)
                    .put("memoryWarning", snap.lifecycle.memoryWarning)
                    .put("lowPower", snap.lifecycle.lowPower)
                    .put("sceneActive", snap.lifecycle.sceneActive)
                    .put("assistState", snap.lifecycle.assistState)
                    .put("outputObservable", snap.lifecycle.outputObservable)
                    .put("presentationExpected", snap.lifecycle.presentationExpected),
            )
            .put("watchdogAction", snap.watchdogAction)
            .put("diagnoserFailure", snap.diagnoserFailure)
            .put("diagnoserRepair", snap.diagnoserRepair)

    private fun breadcrumbArray(items: List<FeedIncidentBreadcrumb>): JSONArray {
        val array = JSONArray()
        items.forEach {
            array.put(
                JSONObject()
                    .put("monotonicAt", it.monotonicAt)
                    .put("kind", it.kind.wire)
                    .put("detail", it.detail),
            )
        }
        return array
    }

    private fun repairArray(items: List<FeedRepairRecord>): JSONArray {
        val array = JSONArray()
        items.forEach {
            array.put(
                JSONObject()
                    .put("monotonicAt", it.monotonicAt)
                    .put("action", it.action)
                    .put("phase", it.phase.wire)
                    .also { obj -> it.reason?.let { reason -> obj.put("reason", reason) } },
            )
        }
        return array
    }

    private fun errorArray(items: List<FeedIncidentErrorCount>): JSONArray {
        val array = JSONArray()
        items.forEach {
            array.put(JSONObject().put("errorClass", it.errorClass).put("count", it.count))
        }
        return array
    }

    private fun agesJson(ages: FeedIncidentAges): JSONObject {
        val json = JSONObject()
        ages.packetAge?.let { json.put("packetAge", it) }
        ages.accessUnitAge?.let { json.put("accessUnitAge", it) }
        ages.decodeAcceptAge?.let { json.put("decodeAcceptAge", it) }
        ages.decodedOutputAge?.let { json.put("decodedOutputAge", it) }
        ages.assistOutputAge?.let { json.put("assistOutputAge", it) }
        ages.presentAge?.let { json.put("presentAge", it) }
        return json
    }

    private fun parseBundle(json: JSONObject): FeedIncidentBundle =
        FeedIncidentBundle(
            header = parseHeader(json.getJSONObject("header")),
            prelude = parseSnapshots(json.optJSONArray("prelude")),
            during = parseSnapshots(json.optJSONArray("during")),
            aftermath = parseSnapshots(json.optJSONArray("aftermath")),
            breadcrumbs = parseBreadcrumbs(json.optJSONArray("breadcrumbs")),
            repairs = parseRepairs(json.optJSONArray("repairs")),
            aggregatedErrors = parseErrors(json.optJSONArray("aggregatedErrors")),
        )

    private fun parseHeader(json: JSONObject): FeedIncidentHeader =
        FeedIncidentHeader(
            schemaVersion = json.optInt("schemaVersion", FeedIncidentSchema.VERSION),
            incidentId = json.optString("incidentID"),
            sessionId = json.optString("sessionID"),
            kind = FeedIncidentKind.fromWire(json.optString("kind")),
            failingStage = FeedIncidentFailingStage.fromWire(json.optString("failingStage")),
            errorClass = json.optStringOrNull("errorClass"),
            outcome = FeedIncidentOutcome.fromWire(json.optString("outcome")),
            startedAtWallClockMs = parseWall(json.optString("startedAtWallClock")),
            startedAtMonotonic = json.optDouble("startedAtMonotonic", 0.0),
            endedAtMonotonic = json.optDoubleOrNull("endedAtMonotonic"),
            firstFailureAt = json.optDouble("firstFailureAt", 0.0),
            worstGapSeconds = json.optDouble("worstGapSeconds", 0.0),
            appVersion = json.optString("appVersion"),
            appBuild = json.optString("appBuild"),
            sourceRevision = json.optString("sourceRevision"),
            osName = json.optString("osName"),
            osVersion = json.optString("osVersion"),
            hardwareClass = json.optString("hardwareClass"),
            cameraFamily = json.optString("cameraFamily"),
            cameraFirmware = json.optStringOrNull("cameraFirmware"),
            decoderGeneration = json.optInt("decoderGeneration"),
            socketGeneration = json.optInt("socketGeneration"),
            evictions = json.optInt("evictions"),
            assistState = json.optString("assistState", "off"),
            healthyExposureSeconds = json.optDouble("healthyExposureSeconds", 0.0),
            testSource = FeedIncidentTestSource.fromWire(json.optStringOrNull("testSource")),
            buildIdentity = FeedIncidentBuildIdentity.parse(json.optStringOrNull("buildIdentity")),
        )

    private fun parseSnapshots(array: JSONArray?): List<FeedIncidentSnapshot> {
        if (array == null) return emptyList()
        return (0 until array.length()).map { index ->
            val json = array.getJSONObject(index)
            val rates = json.optJSONObject("rates") ?: JSONObject()
            val ages = json.optJSONObject("ages") ?: JSONObject()
            val queue = json.optJSONObject("queue") ?: JSONObject()
            val decoder = json.optJSONObject("decoder") ?: JSONObject()
            val life = json.optJSONObject("lifecycle") ?: JSONObject()
            FeedIncidentSnapshot(
                monotonicNow = json.optDouble("monotonicNow", 0.0),
                wallClockMs = parseWall(json.optString("wallClock")),
                rates =
                    FeedIncidentRates(
                        packetHz = rates.optDouble("packetHz"),
                        accessUnitHz = rates.optDouble("accessUnitHz"),
                        decodeSubmitHz = rates.optDouble("decodeSubmitHz"),
                        decodeAcceptHz = rates.optDouble("decodeAcceptHz"),
                        decodedOutputHz = rates.optDouble("decodedOutputHz"),
                        assistOutputHz = rates.optDouble("assistOutputHz"),
                        presentHz = rates.optDouble("presentHz"),
                        ackHz = rates.optDouble("ackHz"),
                    ),
                ages =
                    FeedIncidentAges(
                        packetAge = ages.optDoubleOrNull("packetAge"),
                        accessUnitAge = ages.optDoubleOrNull("accessUnitAge"),
                        decodeAcceptAge = ages.optDoubleOrNull("decodeAcceptAge"),
                        decodedOutputAge = ages.optDoubleOrNull("decodedOutputAge"),
                        assistOutputAge = ages.optDoubleOrNull("assistOutputAge"),
                        presentAge = ages.optDoubleOrNull("presentAge"),
                    ),
                queue =
                    FeedIncidentQueue(
                        bytes = queue.optInt("bytes"),
                        count = queue.optInt("count"),
                        ageMilliseconds = queue.optDouble("ageMilliseconds"),
                        incompleteAccessUnits = queue.optInt("incompleteAccessUnits"),
                        drops = queue.optInt("drops"),
                    ),
                decoder =
                    FeedIncidentDecoder(
                        generation = decoder.optInt("generation"),
                        formatGeneration = decoder.optInt("formatGeneration"),
                        codec = decoder.optString("codec", "hevc"),
                        width = decoder.optInt("width"),
                        height = decoder.optInt("height"),
                        origin = FeedDecoderErrorOrigin.fromWire(decoder.optString("origin", "none")),
                        errorClass = decoder.optStringOrNull("errorClass"),
                        errorCount = decoder.optInt("errorCount"),
                        decoderFailed = decoder.optBoolean("decoderFailed"),
                        errorAge = decoder.optDoubleOrNull("errorAge"),
                        receivedIrap = decoder.optBoolean("receivedIrap"),
                        awaitingIrap = decoder.optBoolean("awaitingIrap"),
                        hasDecodableReferences = decoder.optBoolean("hasDecodableReferences", true),
                        lastIrapAge = decoder.optDoubleOrNull("lastIrapAge"),
                        lastSuccessfulOutputAge = decoder.optDoubleOrNull("lastSuccessfulOutputAge"),
                        rebuildReason = decoder.optStringOrNull("rebuildReason"),
                    ),
                lifecycle =
                    FeedIncidentLifecycle(
                        foreground = life.optBoolean("foreground", true),
                        settingsCovered = life.optBoolean("settingsCovered"),
                        playbackActive = life.optBoolean("playbackActive"),
                        connected = life.optBoolean("connected"),
                        liveEstablished = life.optBoolean("liveEstablished"),
                        thermalState = life.optString("thermalState", "nominal"),
                        memoryWarning = life.optBoolean("memoryWarning"),
                        lowPower = life.optBoolean("lowPower"),
                        sceneActive = life.optBoolean("sceneActive", true),
                        assistState = life.optString("assistState", "off"),
                        outputObservable = life.optBoolean("outputObservable", true),
                        presentationExpected = life.optBoolean("presentationExpected", true),
                    ),
                watchdogAction = json.optString("watchdogAction", "none"),
                diagnoserFailure = json.optString("diagnoserFailure", "none"),
                diagnoserRepair = json.optString("diagnoserRepair", "none"),
            )
        }
    }

    private fun parseBreadcrumbs(array: JSONArray?): List<FeedIncidentBreadcrumb> {
        if (array == null) return emptyList()
        return (0 until array.length()).map {
            val json = array.getJSONObject(it)
            FeedIncidentBreadcrumb(
                monotonicAt = json.optDouble("monotonicAt"),
                kind = FeedIncidentBreadcrumbKind.fromWire(json.optString("kind")),
                detail = json.optString("detail"),
            )
        }
    }

    private fun parseRepairs(array: JSONArray?): List<FeedRepairRecord> {
        if (array == null) return emptyList()
        return (0 until array.length()).map {
            val json = array.getJSONObject(it)
            FeedRepairRecord(
                monotonicAt = json.optDouble("monotonicAt"),
                action = json.optString("action"),
                phase = FeedRepairPhase.fromWire(json.optString("phase")),
                reason = json.optStringOrNull("reason"),
            )
        }
    }

    private fun parseErrors(array: JSONArray?): List<FeedIncidentErrorCount> {
        if (array == null) return emptyList()
        return (0 until array.length()).map {
            val json = array.getJSONObject(it)
            FeedIncidentErrorCount(json.optString("errorClass"), json.optInt("count"))
        }
    }

    private fun parseWall(raw: String): Long =
        runCatching { iso.parse(raw)?.time }.getOrNull()
            ?: raw.toLongOrNull()
            ?: 0L

    private fun JSONObject.optStringOrNull(key: String): String? {
        if (!has(key) || isNull(key)) return null
        val value = optString(key)
        return value.takeIf { it.isNotEmpty() && it != "null" }
    }

    private fun JSONObject.optDoubleOrNull(key: String): Double? {
        if (!has(key) || isNull(key)) return null
        val value = optDouble(key, Double.NaN)
        return value.takeIf { it.isFinite() }
    }
}
