package com.opencapture.openpocketcine.multiview

import com.opencapture.openpocketcine.bridge.SwiftCore
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.TimeoutCancellationException
import kotlinx.coroutines.delay
import org.json.JSONObject

/**
 * Captured BLE sequence that moves an Osmo from its own access point onto another network:
 * Video mode, station role, then `07/47` join with bounded retry. iOS core `StationJoin`,
 * shared by Multiview and the per-camera Wi-Fi and Hotspot setups (#406). Transport-free:
 * the caller supplies the BLE exchange and the LAN probe.
 */
class StationJoin(
    private val ssid: String,
    private val password: String,
    private val hotspot: Boolean,
    /** The model has a captured preview profile (`MulticamSupport.hasPreview`). */
    private val hasPreview: Boolean,
    private val missingRoleQueryE0: Boolean,
    /** Multiview's bounded path for models without a captured preview profile. */
    private val experimental: Boolean = false,
    /**
     * Camera already in station role: try the LAN before re-sending the join. Multiview
     * always re-joins; a saved setup reconnect probes first.
     */
    private val probeExistingStation: Boolean = false,
    private val policy: Policy = Policy.fromCore(),
    private val decide: (String, String) -> String? = SwiftCore::multicamDecision,
) {
    enum class Outcome {
        /** The camera accepted the join; the caller still finds and verifies it on the LAN. */
        JOINED,
        /** `verifyOnNetwork` already found and verified the camera. */
        VERIFIED,
    }

    sealed class Failure(message: String) : Exception(message) {
        class Rejected : Failure("Camera could not complete this step. Check the Wi-Fi details and try again.")
        class UnsupportedRole : Failure(
            "This camera did not report a supported Wi-Fi mode. Shared Wi-Fi setup is experimental for this model.")
        class RoleRefused : Failure("The camera did not accept shared Wi-Fi mode.")
        class RoleStarting : Failure("Camera Wi-Fi is still starting. Retry with the camera nearby.")
        class JoinSilent : Failure("Camera Wi-Fi did not respond. Retry setup with the camera nearby.")
        class JoinRejected : Failure(
            "The camera could not join the Wi-Fi. Check the password and that the network is in range. " +
                "WPA3-only networks refuse some cameras: use WPA2/WPA3 with PMF optional.")
        class HotspotUnavailable : Failure(
            "Turn on the hotspot and let other devices join, then retry. The hotspot network is not available yet.")
    }

    /** Core `MulticamJoinPolicy`. */
    data class Policy(
        val maximumAttempts: Int = 3,
        val prepareSettleMs: Long = 10_000,
        val replyTimeoutMs: Long = 45_000,
        val retryDelayMs: Long = 5_000,
    ) {
        companion object {
            fun fromCore(): Policy {
                val json = SwiftCore.multicamDecision("joinPolicy", "{}")
                    ?.let { runCatching { JSONObject(it) }.getOrNull() } ?: JSONObject()
                return Policy(
                    maximumAttempts = json.optInt("maximumAttempts", 3),
                    prepareSettleMs = json.optLong("prepareSettleSeconds", 10) * 1_000,
                    replyTimeoutMs = (json.optDouble("replyTimeoutSeconds", 45.0) * 1_000).toLong(),
                    retryDelayMs = json.optLong("retryDelaySeconds", 5) * 1_000,
                )
            }
        }
    }

    /**
     * [identity] is the camera's `07/07` reply read before the role change. It is the only
     * proof that a LAN address is this body, so [verifyOnNetwork] checks it. [exchange]
     * sends a `SwiftCore.CMD_*` kind and returns the reply payload; it throws on a lost
     * reply.
     */
    suspend fun run(
        identity: ByteArray,
        exchange: suspend (kind: Int, extra: String?, timeoutMs: Long) -> ByteArray,
        send: (kind: Int) -> Unit,
        status: (String) -> Unit,
        hotspotReady: () -> Boolean,
        verifyOnNetwork: suspend () -> Boolean,
        log: (String) -> Unit = {},
        sleep: suspend (Long) -> Unit = { delay(it) },
    ): Outcome {
        if (identity.size <= 2 || identity[0].toInt() != 0) throw Failure.Rejected()
        if (hasPreview && !experimental) {
            status("Selecting Video mode")
            send(SwiftCore.CMD_MULTICAM_VIDEO_MODE)
            sleep(2_000)
        }
        val role = exchange(SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE, null, ROLE_TIMEOUT_MS)
        val allowMissing = experimental || (missingRoleQueryE0 && hex(role) == "e0")
        val decision = decide(
            "stationDecision",
            JSONObject().put("reply", hex(role)).put("allowMissingQuery", allowMissing).toString(),
        ) ?: "reject"
        val missingRoleQuery = decision == "setWithoutReadback"
        log("station experimental=$experimental decision=$decision")
        if (decision == "alreadyStation" && probeExistingStation && (!hotspot || hotspotReady())) {
            status("Finding camera on Wi-Fi")
            if (verifyOnNetwork()) return Outcome.VERIFIED
        }
        if (decision != "alreadyStation") {
            if (decision == "reject") throw Failure.UnsupportedRole()
            val switched = exchange(SwiftCore.CMD_MULTICAM_STATION_MODE, "1", ROLE_TIMEOUT_MS)
            val accepted = decide(
                "acceptsSetter",
                JSONObject().put("reply", hex(switched)).put("missingQuery", missingRoleQuery).toString(),
            ) == "true"
            if (!accepted) throw Failure.RoleRefused()
            // The missing-getter shape has no readback; its join result and LAN identity
            // check remain required.
            if (!missingRoleQuery) {
                var stationReady = false
                for (poll in 0 until 6) {
                    val reported = hex(exchange(SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE, null, ROLE_TIMEOUT_MS))
                    if (reported == "0001") {
                        stationReady = true
                        break
                    }
                    if (reported != "0000") throw Failure.Rejected()
                    sleep(2_000)
                }
                if (!stationReady) throw Failure.RoleStarting()
            }
        }
        status("Waiting for camera Wi-Fi")
        sleep(policy.prepareSettleMs)
        var attempt = 1
        joinLoop@ while (attempt <= policy.maximumAttempts) {
            status("Joining Wi-Fi · attempt $attempt of ${policy.maximumAttempts}")
            val joined = try {
                exchange(SwiftCore.CMD_MULTICAM_JOIN, "$ssid\u001f$password", policy.replyTimeoutMs)
            } catch (error: TimeoutCancellationException) {
                null
            } catch (error: CancellationException) {
                throw error
            } catch (_: Exception) {
                null
            }
            if (joined == null) {
                log("join reply timeout; checking verified LAN identity")
                // A lost BLE reply is not proof that association failed.
                if (!hotspot || hotspotReady()) {
                    try {
                        if (verifyOnNetwork()) return Outcome.VERIFIED
                    } catch (error: CancellationException) {
                        throw error
                    } catch (_: Exception) {
                        // Not found on the LAN: fall through to the bounded join retry.
                    }
                }
                if (attempt < policy.maximumAttempts) {
                    sleep(policy.retryDelayMs)
                    attempt += 1
                    continue
                }
                throw Failure.JoinSilent()
            }
            // Only the fixed-size result is logged, never the credential request.
            log("Wi-Fi join attempt=$attempt result=${hex(joined.copyOf(minOf(4, joined.size)))}")
            // A retry on the last attempt falls through as joined, as in core; the LAN
            // identity check still decides.
            when (decide("joinDecision", JSONObject().put("reply", hex(joined)).put("attempt", attempt).toString())) {
                "connected" -> break@joinLoop
                "retry" -> {
                    status("Retrying Wi-Fi connection")
                    sleep(policy.retryDelayMs)
                    attempt += 1
                }
                else -> throw Failure.JoinRejected()
            }
        }
        if (hotspot) {
            // The phone's hotspot bridge may appear only after the camera associates.
            status("Waiting for the hotspot")
            var waited = 0L
            while (!hotspotReady() && waited < HOTSPOT_WAIT_MS) {
                sleep(250)
                waited += 250
            }
            if (!hotspotReady()) throw Failure.HotspotUnavailable()
        }
        return Outcome.JOINED
    }

    private companion object {
        const val ROLE_TIMEOUT_MS = 12_000L
        const val HOTSPOT_WAIT_MS = 15_000L
    }
}
