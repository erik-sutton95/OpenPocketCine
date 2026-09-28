package com.opencapture.openpocketcine.multiview

import com.opencapture.openpocketcine.bridge.SwiftCore
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFailsWith
import kotlin.test.assertFalse

class StationJoinTest {
    private val identity = byteArrayOf(0, 5, 'O'.code.toByte(), 's'.code.toByte())

    /** Core decisions reduced to the captured replies these tests script. */
    private val decide: (String, String) -> String? = { kind, json ->
        when (kind) {
            "stationDecision" -> when {
                json.contains("\"0001\"") -> "alreadyStation"
                json.contains("\"0000\"") -> "setAndVerify"
                else -> "reject"
            }
            "acceptsSetter" -> (json.contains("\"00\"") || json.contains("\"0000\"")).toString()
            "joinDecision" -> if (json.contains("\"00\"")) "connected" else "rejected"
            else -> null
        }
    }

    private fun join(hotspot: Boolean = false, probe: Boolean = false) = StationJoin(
        ssid = "Studio", password = "password", hotspot = hotspot, hasPreview = true,
        missingRoleQueryE0 = false, probeExistingStation = probe,
        policy = StationJoin.Policy(maximumAttempts = 3, prepareSettleMs = 0, replyTimeoutMs = 1, retryDelayMs = 0),
        decide = decide,
    )

    private class Camera(var role: String = "0000", val joinReplies: MutableList<String?> = mutableListOf("00")) {
        val sent = mutableListOf<Int>()

        suspend fun exchange(kind: Int, extra: String?): ByteArray {
            sent += kind
            return when (kind) {
                SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE -> bytes(role)
                SwiftCore.CMD_MULTICAM_STATION_MODE -> { role = if (extra == "1") "0001" else "0000"; bytes("00") }
                SwiftCore.CMD_MULTICAM_JOIN -> joinReplies.removeAt(0)?.let(::bytes)
                    ?: withTimeout(1) { kotlinx.coroutines.delay(1_000); ByteArray(0) }
                else -> error("unexpected $kind")
            }
        }

        private fun bytes(hex: String) = hex.chunked(2).map { it.toInt(16).toByte() }.toByteArray()
    }

    @Test
    fun movesTheCameraToStationAndJoins() = runBlocking {
        val camera = Camera()
        val statuses = mutableListOf<String>()
        val outcome = join().run(
            identity, exchange = { kind, extra, _ -> camera.exchange(kind, extra) }, send = { camera.sent += it },
            status = { statuses += it }, hotspotReady = { false }, verifyOnNetwork = { error("not probed") },
            sleep = {},
        )
        assertEquals(StationJoin.Outcome.JOINED, outcome)
        assertEquals(
            listOf(
                SwiftCore.CMD_MULTICAM_VIDEO_MODE, SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE,
                SwiftCore.CMD_MULTICAM_STATION_MODE, SwiftCore.CMD_MULTICAM_WIFI_WORK_MODE, SwiftCore.CMD_MULTICAM_JOIN,
            ),
            camera.sent,
        )
        assertEquals("Joining Wi-Fi · attempt 1 of 3", statuses.last())
    }

    @Test
    fun lostJoinReplyIsVerifiedOnTheNetworkInsteadOfFailing() = runBlocking {
        val camera = Camera(joinReplies = mutableListOf(null, null))
        var probes = 0
        val outcome = join().run(
            identity, exchange = { kind, extra, _ -> camera.exchange(kind, extra) }, send = {},
            status = {}, hotspotReady = { false }, verifyOnNetwork = { ++probes == 2 }, sleep = {},
        )
        assertEquals(StationJoin.Outcome.VERIFIED, outcome)
        assertEquals(2, probes)
    }

    @Test
    fun savedSetupProbesACameraAlreadyInStationRoleBeforeRejoining() = runBlocking {
        val camera = Camera(role = "0001")
        val outcome = join(probe = true).run(
            identity, exchange = { kind, extra, _ -> camera.exchange(kind, extra) }, send = {},
            status = {}, hotspotReady = { false }, verifyOnNetwork = { true }, sleep = {},
        )
        assertEquals(StationJoin.Outcome.VERIFIED, outcome)
        assertFalse(SwiftCore.CMD_MULTICAM_JOIN in camera.sent)
    }

    @Test
    fun hotspotThatNeverAppearsFailsAfterTheJoin() {
        val camera = Camera()
        assertFailsWith<StationJoin.Failure.HotspotUnavailable> {
            runBlocking {
                join(hotspot = true).run(
                    identity, exchange = { kind, extra, _ -> camera.exchange(kind, extra) }, send = {},
                    status = {}, hotspotReady = { false }, verifyOnNetwork = { false }, sleep = {},
                )
            }
        }
    }

    @Test
    fun rejectedJoinAndBadIdentityFail() {
        assertFailsWith<StationJoin.Failure.JoinRejected> {
            runBlocking {
                val camera = Camera(joinReplies = mutableListOf("01"))
                join().run(identity, exchange = { k, e, _ -> camera.exchange(k, e) }, send = {}, status = {},
                    hotspotReady = { false }, verifyOnNetwork = { false }, sleep = {})
            }
        }
        assertFailsWith<StationJoin.Failure.Rejected> {
            runBlocking {
                join().run(byteArrayOf(1, 2, 3), exchange = { _, _, _ -> ByteArray(0) }, send = {}, status = {},
                    hotspotReady = { false }, verifyOnNetwork = { false }, sleep = {})
            }
        }
        // A lost reply surfaces as TimeoutCancellationException in the session's waitFrame.
        assertFailsWith<StationJoin.Failure.JoinSilent> {
            runBlocking {
                val camera = Camera(joinReplies = mutableListOf(null, null, null))
                join().run(identity, exchange = { k, e, _ -> camera.exchange(k, e) }, send = {}, status = {},
                    hotspotReady = { false }, verifyOnNetwork = { false }, sleep = {})
            }
        }
    }
}
