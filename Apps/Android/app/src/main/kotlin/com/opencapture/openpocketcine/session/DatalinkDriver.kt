package com.opencapture.openpocketcine.session

import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.pairing.CameraApJoiner
import java.io.IOException
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.Inet4Address
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.Executors
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import java.util.concurrent.atomic.AtomicLong
import kotlin.random.Random

/** iOS `DatalinkError.noHandshake` — recoverable, never `error()` / crash. */
class DatalinkHandshakeException(message: String) : IOException(message)

/**
 * DUML-over-UDP datalink. Byte builders live in Swift; this owns the socket,
 * session/seq counters, 40 Hz ACK pump, and HEVC depacketizer handle.
 */
class DatalinkDriver(
    private val joiner: CameraApJoiner,
    private val port: Int,
    private val tcpPoke: Boolean,
    private val pairingToken: String,
) {
    private val main = Handler(Looper.getMainLooper())
    private val running = AtomicBoolean(false)
    private val sendLock = Any()
    private val sendExecutor = Executors.newSingleThreadExecutor { Thread(it, "opc.datalink.tx") }
    private val decodeExecutor = Executors.newSingleThreadExecutor { Thread(it, "opc.hevc") }
    private var socket: DatagramSocket? = null
    private var pokeSocket: Socket? = null
    private var receiver: Thread? = null
    private var ackThread: Thread? = null

    private var sessionId = 0
    private var baseSeq = 0
    private var udpSeq = 0
    private var dumlSeq = 0xA000
    private var cmdCounter = 0
    /** Latest video transport seq — ACK pump must echo this (iOS `videoAssembler.peerCursor`). */
    private val peerCursor = AtomicInteger(0)
    private val hasVideoSeq = AtomicBoolean(false)
    /** pktType 0x03 command-reply window (every GET/SET ACK). Mimo ACK group 1. */
    private val ackedDataCursor = AtomicInteger(0)
    private val hasAckedData = AtomicBoolean(false)
    /** Third ACK group, seeded from 34-byte pktType 0x01 telemetry. */
    private val extraCursor = AtomicInteger(0)
    private val hasExtra = AtomicBoolean(false)
    private var camChannel = 0
    @Volatile private var handshakeAcked = false
    @Volatile private var liveViewEnabled = false
    private val closed = AtomicBoolean(false)
    private var depacketizer = 0L
    private val inboundLogs = AtomicInteger(0)
    private val rawVideoPackets = AtomicInteger(0)
    private val leftoverVideoPackets = AtomicInteger(0)
    private val loggedLeftoverGop = AtomicBoolean(false)
    private val lastVideoElapsed = AtomicLong(0)
    private val lastStatusElapsed = AtomicLong(0)
    private val lastAccessUnitElapsed = AtomicLong(0)
    private val lastRebuildElapsed = AtomicLong(0)
    private val lastEnableSentElapsed = AtomicLong(0)
    private val lastLiveViewReplyElapsed = AtomicLong(0)
    @Volatile private var rebuilding = false
    private val sendFailLogs = AtomicInteger(0)
    private val writeRejected = AtomicBoolean(false)
    private val gimbalLock = Any()
    @Volatile private var gimbalAxis0 = CameraCommands.GIMBAL_STICK_CENTER
    @Volatile private var gimbalAxis1 = CameraCommands.GIMBAL_STICK_CENTER
    @Volatile private var gimbalStickHeld = false
    @Volatile private var gimbalSendRest = false
    private val lastGimbalStickElapsed = AtomicLong(0)

    var onStatusFrame: ((DumlFrame) -> Unit)? = null
    var onAccessUnit: ((ByteArray) -> Unit)? = null

    val videoPackets: Int get() = rawVideoPackets.get()
    val droppedIncomplete: Int
        get() = if (depacketizer != 0L && SwiftCore.isAvailable) SwiftCore.depacketizerDropped(depacketizer) else 0
    val lastVideoPacketAt: Long? get() = lastVideoElapsed.get().takeIf { it > 0 }
    val lastStatusAt: Long? get() = lastStatusElapsed.get().takeIf { it > 0 }
    val lastAccessUnitAt: Long? get() = lastAccessUnitElapsed.get().takeIf { it > 0 }
    val lastRebuildAt: Long? get() = lastRebuildElapsed.get().takeIf { it > 0 }
    val isTcpPokeReady: Boolean get() = pokeSocket?.isConnected == true
    val isRebuilding: Boolean get() = rebuilding
    val needsRebuild: Boolean get() = writeRejected.get()
    val isClosed: Boolean get() = closed.get()

    /**
     * iOS `DatalinkDriver.open(afterHandshake:)`: handshake, register,
     * subscribe, 40 Hz ACK pump, then `0x09/0xa8`, then ingest 0x02.
     * Do not sit on a 2 s ACK settle — that drops the camera GOP.
     */
    fun open(afterHandshake: (() -> Unit)? = null) {
        check(SwiftCore.isAvailable) { "Swift core is not loaded" }
        check(!closed.get()) { "datalink closed" }
        discardUdp(keepPoke = true)
        if (tcpPoke) ensurePoke()
        liveViewEnabled = false
        loggedLeftoverGop.set(false)
        inboundLogs.set(0)
        rawVideoPackets.set(0)
        leftoverVideoPackets.set(0)
        lastVideoElapsed.set(0)
        lastStatusElapsed.set(0)
        lastAccessUnitElapsed.set(0)
        lastEnableSentElapsed.set(0)
        lastLiveViewReplyElapsed.set(0)
        sendFailLogs.set(0)
        if (depacketizer == 0L) depacketizer = SwiftCore.depacketizerCreate()
        else runCatching { SwiftCore.depacketizerReset(depacketizer) }

        var rebinds = 0
        var keepBind = false
        while (true) {
            if (closed.get() || Thread.currentThread().isInterrupted) return
            if (!keepBind) {
                resetHandshakeSession()
                startUdpReceiver()
            }
            keepBind = false
            val handshake = SwiftCore.handshakePayload(baseSeq) ?: error("handshake payload")
            for (send in 1..HANDSHAKE_SENDS_PER_BIND) {
                if (handshakeAcked) break
                val receiveArmed = running.get() && receiver?.isAlive == true
                val connectionReady = socket != null && !closed.get()
                if (!LiveViewEnablePolicy.canSendHandshake(receiveArmed, connectionReady)) {
                    Log.i(
                        TAG,
                        "datalink: handshake UDP not ready reader=$receiveArmed — will rebind",
                    )
                    break
                }
                sendRaw(0x00, handshake)
                val deadline = SystemClock.elapsedRealtime() + HANDSHAKE_SEND_INTERVAL_MS
                while (SystemClock.elapsedRealtime() < deadline) {
                    if (handshakeAcked) break
                    Thread.sleep(HANDSHAKE_POLL_MS)
                }
                if (handshakeAcked) break
            }
            if (handshakeAcked) {
                Log.i(TAG, "datalink: handshake acked session=$sessionId")
                if (camChannel != 0) udpSeq = (camChannel + 8) and 0xFFFF
                sendAck()
                register()
                subscribe()
                startAckPump()
                // Mimo 20260828: HEVC 17 ms after DHCP, 0xa8 at +3 s. Arm ingest
                // on handshake ack — do not wait subscribe settle or enable.
                armLiveVideo()
                // Subscribe is fire-and-forget. Enable in the same 9 ms burst is
                // ignored (iOS hops to MainActor after subscribe; Mimo comes
                // from gallery). Always wait the settle — leftover 0x01 must
                // not collapse it to 0 ms.
                settleAfterSubscribe(SUBSCRIBE_SETTLE_MS)
                // Stay on this IO thread. Posting 0x09/0xa8 to Main trips
                // StrictMode (NetworkOnMainThread) and the camera never
                // starts HEVC — pkts=0, WAITING FOR LIVE VIEW.
                if (closed.get() || Thread.currentThread().isInterrupted) return
                afterHandshake?.invoke()
                armLiveVideo()
                return
            }
            val inbound = inboundLogs.get()
            when (
                LiveViewEnablePolicy.handshakeTimeoutStep(
                    pathReady = joiner.isProcessBound(),
                    rebindsUsed = rebinds,
                    inboundDatagrams = inbound,
                    rebindLimit = HANDSHAKE_REBIND_LIMIT,
                )
            ) {
                LiveViewEnablePolicy.HandshakeTimeoutStep.KEEP_SOCKET -> {
                    Log.i(TAG, "datalink: handshake miss inbound=$inbound — keep UDP, retry sends")
                    keepBind = true
                    continue
                }
                LiveViewEnablePolicy.HandshakeTimeoutStep.FAIL -> {
                    Log.i(TAG, "datalink: handshake never acked inbound=$inbound")
                    throw handshakeTimeoutFailure()
                }
                LiveViewEnablePolicy.HandshakeTimeoutStep.REBIND_UDP -> {
                    rebinds += 1
                    Log.i(
                        TAG,
                        "datalink: handshake miss inbound=$inbound — SoftAP up, rebind UDP " +
                            "($rebinds/$HANDSHAKE_REBIND_LIMIT)",
                    )
                    discardUdp(keepPoke = true)
                    Thread.sleep(HANDSHAKE_RETRY_PAUSE_MS)
                }
            }
        }
    }

    fun keepalive() {
        sendCommand(SwiftCore.CMD_APP_PRESENCE)
        sendAck()
    }

    private fun settleAfterSubscribe(timeoutMs: Long) {
        val deadline = SystemClock.elapsedRealtime() + timeoutMs
        while (SystemClock.elapsedRealtime() < deadline) {
            try {
                Thread.sleep(10)
            } catch (_: InterruptedException) {
                break
            }
        }
        val status = if (lastStatusElapsed.get() > 0) 1 else 0
        Log.i(TAG, "datalink: subscribe settled ${timeoutMs}ms status=$status")
    }

    fun startLiveView(receiver: Int = CameraCommands.LIVE_VIEW_ENABLE_RECEIVER_POCKET) {
        val extra = receiver.toString()
        if (receiver == CameraCommands.LIVE_VIEW_ENABLE_RECEIVER_POCKET) {
            sendCommand(SwiftCore.CMD_LIVE_VIEW_ENABLE, extra)
        } else {
            sendDuml(
                cmdSet = 0x09,
                cmdId = CameraCommands.CMD_LIVE_VIEW,
                payload = CameraCommands.liveViewEnablePayload(),
                receiver = receiver,
            )
        }
        lastEnableSentElapsed.set(SystemClock.elapsedRealtime())
        Log.i(
            TAG,
            "datalink: sent 0x09/0xa8 rcv=0x${receiver.toString(16)} " +
                "videoPkts=$videoPackets tcp=${if (isTcpPokeReady) 1 else 0}",
        )
        // Accept 0x02 on this write, not after an ACK. Recover enables must
        // also ingest the next VPS (iOS `startLiveView` does not wait).
        armLiveVideo()
    }

    /** iOS `DatalinkDriver.exitPlayback`. Live enable ACKs E0 while the body is in playback. */
    fun exitPlayback() {
        sendCommand(SwiftCore.CMD_EXIT_PLAYBACK)
        Log.i(TAG, "datalink: sent exit playback")
    }

    /** iOS `armLiveVideo`: first arm resets leftover GOP; re-arm only raises the gate. */
    fun armLiveVideo() {
        val first = !liveViewEnabled
        if (first && depacketizer != 0L && SwiftCore.isAvailable) {
            runCatching { SwiftCore.depacketizerReset(depacketizer) }
        }
        liveViewEnabled = true
        loggedLeftoverGop.set(false)
        if (first) Log.i(TAG, "datalink: armed pktType 0x02 ingest")
    }

    /** Nano `0x02/0x09` start/stop. No CMD kind yet — encodeDuml. */
    fun sendNanoGate(start: Boolean) {
        sendDuml(
            cmdSet = 0x02,
            cmdId = CameraCommands.CMD_NANO_GATE,
            payload = CameraCommands.nanoLiveViewGate(start),
        )
    }

    /**
     * Tear down a dead UDP bind and open a new socket. Keeps session/seq, the
     * depacketizer, and TCP 7001. Live-view enable is the caller's job.
     */
    fun rebuildUdpKeepingSession() {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            if (sendExecutor.isShutdown) return
            // Wait so the following 0x09/0xa8 lands on the new 5-tuple, not the
            // socket we are about to close (WAITING FOR LIVE VIEW, videoPkts=0).
            runCatching {
                sendExecutor.submit { rebuildUdpOnNetwork() }.get(3, TimeUnit.SECONDS)
            }.onFailure { Log.w(TAG, "datalink: UDP rebuild wait failed", it) }
            return
        }
        rebuildUdpOnNetwork()
    }

    @Synchronized
    private fun rebuildUdpOnNetwork() {
        if (closed.get() || rebuilding) return
        if (!joiner.isProcessBound()) return
        rebuilding = true
        writeRejected.set(false)
        lastRebuildElapsed.set(SystemClock.elapsedRealtime())
        try {
            Log.i(TAG, "datalink: rebuilding UDP (keep session, keep TCP 7001)")
            val wasAccepting = liveViewEnabled
            discardUdp(keepPoke = true)
            // Pre-rebuild clocks are the old 5-tuple. Leaving lastStatus young
            // looks like encoder-pause on the new bind (iOS noteRebuild).
            lastVideoElapsed.set(0)
            lastAccessUnitElapsed.set(0)
            lastStatusElapsed.set(0)
            startUdpReceiver()
            startAckPump()
            if (LiveViewEnablePolicy.shouldRearmLiveIngestAfterUDPRebuild(wasAccepting)) {
                armLiveVideo()
            }
            sendAck()
            sendCommand(SwiftCore.CMD_APP_PRESENCE)
        } finally {
            rebuilding = false
        }
    }

    /**
     * Send a CRC-valid DUML request over the datalink. Payloads come from
     * [CameraCommands] — this only wraps [SwiftCore.encodeDuml] the same way
     * the predefined command kinds are sent.
     */
    fun sendDuml(
        cmdSet: Int,
        cmdId: Int,
        payload: ByteArray = ByteArray(0),
        flags: Int = CameraCommands.FLAG_REQUEST,
        receiver: Int = CameraCommands.RX_CAMERA,
        sender: Int = CameraCommands.SENDER_APP,
    ) {
        if (closed.get() || !SwiftCore.isAvailable) return
        onSendThread { sendDumlLocked(cmdSet, cmdId, payload, flags, receiver, sender) }
    }

    private fun sendDumlLocked(
        cmdSet: Int,
        cmdId: Int,
        payload: ByteArray,
        flags: Int,
        receiver: Int,
        sender: Int,
    ) {
        synchronized(sendLock) {
            if (socket == null) return
            val frameBytes =
                SwiftCore.encodeDuml(sender, receiver, dumlSeq, flags, cmdSet, cmdId, payload)
                    ?: return
            cmdCounter = (cmdCounter + 1) and 0xFF
            val routing = SwiftCore.routingHeader(udpSeq, cmdCounter, false) ?: return
            val header =
                SwiftCore.transportHeader(0x05, routing.size + frameBytes.size, sessionId, udpSeq)
                    ?: return
            writeOnNetwork(header + routing + frameBytes)
            dumlSeq = (dumlSeq + 1) and 0xFFFF
            udpSeq = (udpSeq + 8) and 0xFFFF
        }
    }

    fun close() {
        closed.set(true)
        liveViewEnabled = false
        onAccessUnit = null
        onStatusFrame = null
        discardUdp(keepPoke = false)
        runCatching { pokeSocket?.close() }
        pokeSocket = null
        sendExecutor.shutdownNow()
        decodeExecutor.shutdownNow()
        if (depacketizer != 0L && SwiftCore.isAvailable) {
            SwiftCore.depacketizerDestroy(depacketizer)
            depacketizer = 0L
        }
    }

    private fun resetHandshakeSession() {
        sessionId = Random.nextInt(0x1000, 0xFFFE)
        baseSeq = Random.nextInt(0x1000, 0xF000) and 0xFFF8
        camChannel = baseSeq
        udpSeq = 0
        dumlSeq = 0xA000
        cmdCounter = 0
        peerCursor.set(0)
        hasVideoSeq.set(false)
        ackedDataCursor.set(0)
        hasAckedData.set(false)
        extraCursor.set(0)
        hasExtra.set(false)
        handshakeAcked = false
    }

    private fun startUdpReceiver() {
        // Handbook: unbound → Network.bindSocket → bind 0.0.0.0:0 → connect
        // 192.168.2.1:9004. iOS binds DHCP + ephemeral
        // (`NWParameters.requiredLocalEndpoint` port 0). Mimo live-entry uses
        // an ephemeral client port (63270 in mimo-disconnect-20260822). Device
        // logs that actually presented a picture used local=/192.168.2.71:34273
        // (ephemeral). Binding local :9004 accepted handshake + 0x01 and
        // dropped every pktType 0x02 (WAITING FOR LIVE VIEW, videoPkts=0).
        val sock = DatagramSocket(null)
        sock.reuseAddress = true
        sock.soTimeout = 250
        runCatching { sock.receiveBufferSize = 512 * 1024 }
        joiner.bindSocket(sock)
        val bindHost = Inet4Address.getByName(WILDCARD_BIND_HOST)
        sock.bind(InetSocketAddress(bindHost, UDP_BIND_PORT))
        runCatching { sock.connect(InetSocketAddress(InetAddress.getByName(CAMERA_HOST), port)) }
            .onFailure { Log.w(TAG, "datalink: UDP connect failed — sending unconnected", it) }
        val dhcp = joiner.cameraLocalIPv4() ?: "-"
        val label = if (sock.isConnected) "connected" else "unconnected"
        Log.i(
            TAG,
            "datalink: UDP $label $CAMERA_HOST:$port dhcp=$dhcp " +
                "local=${sock.localSocketAddress} rcvbuf=${sock.receiveBufferSize}",
        )
        socket = sock
        running.set(true)
        receiver =
            Thread({ receiveLoop() }, "opc.datalink.rx").also { it.isDaemon = true; it.start() }
    }

    /** iOS `startAckPump`: pktType 0x04 every 25 ms on its own loop, latest video seq. */
    private fun startAckPump() {
        if (ackThread?.isAlive == true) return
        ackThread =
            Thread(
                {
                    var flipTicks = 0
                    while (running.get()) {
                        sendWindowAck()
                        tickGimbalStick()
                        flipTicks += 1
                        if (flipTicks >= 40) {
                            flipTicks = 0
                            sendCommand(SwiftCore.CMD_GET_SELFIE_FLIP)
                        }
                        try {
                            Thread.sleep(ACK_INTERVAL_MS)
                        } catch (_: InterruptedException) {
                            break
                        }
                    }
                },
                "opc.datalink.ack",
            ).also { it.isDaemon = true; it.start() }
    }

    /** Drop the live UDP socket only. TCP 7001 stays up when [keepPoke] is true. */
    private fun discardUdp(keepPoke: Boolean) {
        liveViewEnabled = false
        running.set(false)
        val rx = receiver
        val ack = ackThread
        receiver = null
        ackThread = null
        runCatching { socket?.close() }
        socket = null
        rx?.interrupt()
        ack?.interrupt()
        runCatching { rx?.join(200) }
        runCatching { ack?.join(200) }
        if (!keepPoke) {
            runCatching { pokeSocket?.close() }
            pokeSocket = null
        }
    }

    private fun ensurePoke() {
        if (pokeSocket?.isConnected == true) {
            Log.i(TAG, "datalink: TCP 7001 poke already ready")
            return
        }
        runCatching { poke7001() }
            .onSuccess { Log.i(TAG, "datalink: TCP 7001 poke ready") }
            .onFailure { Log.w(TAG, "datalink: TCP 7001 poke failed — trying UDP", it) }
    }

    private fun register() {
        sendCommand(SwiftCore.CMD_APP_DEVICE_INFO)
        sendAck()
        sendCommand(SwiftCore.CMD_APP_PRESENCE)
        sendAck()
        sendCommand(SwiftCore.CMD_GIMBAL_INIT)
        sendAck()
    }

    private fun subscribe() {
        var subId = 0x69DFL
        for (key in SUBSCRIPTION_KEYS) {
            sendCommand(SwiftCore.CMD_SUBSCRIBE, "$key\u001f$subId")
            subId += 1
        }
        sendAck()
    }

    private fun sendRaw(pktType: Int, payload: ByteArray) {
        onSendThread {
            synchronized(sendLock) {
                if (socket == null) return@synchronized
                val header =
                    SwiftCore.transportHeader(pktType, payload.size, sessionId, udpSeq)
                        ?: return@synchronized
                writeOnNetwork(header + payload)
                udpSeq = (udpSeq + 8) and 0xFFFF
            }
        }
    }

    fun sendCommand(kind: Int, extra: String? = null) {
        if (closed.get()) return
        onSendThread { sendCommandLocked(kind, extra) }
    }

    private fun sendCommandLocked(kind: Int, extra: String?) {
        synchronized(sendLock) {
            if (socket == null) return
            val frameBytes = SwiftCore.command(kind, dumlSeq, extra)
            val routing = SwiftCore.routingHeader(udpSeq, (cmdCounter + 1) and 0xFF, false) ?: return
            val header =
                SwiftCore.transportHeader(0x05, routing.size + frameBytes.size, sessionId, udpSeq)
                    ?: return
            cmdCounter = (cmdCounter + 1) and 0xFF
            writeOnNetwork(header + routing + frameBytes)
            dumlSeq = (dumlSeq + 1) and 0xFFFF
            udpSeq = (udpSeq + 8) and 0xFFFF
        }
    }

    /** Latest `0x04/0x01` axes. The ACK pump emits them on the UDP send lock. */
    fun noteGimbalStick(axis0: Int, axis1: Int) {
        if (closed.get()) return
        if (axis0 == CameraCommands.GIMBAL_STICK_CENTER &&
            axis1 == CameraCommands.GIMBAL_STICK_CENTER
        ) {
            restGimbalStick()
            return
        }
        synchronized(gimbalLock) {
            gimbalAxis0 = axis0
            gimbalAxis1 = axis1
            gimbalStickHeld = true
            gimbalSendRest = false
        }
    }

    /** One center packet, then silence. Same ACK thread as window ACK. */
    fun restGimbalStick() {
        synchronized(gimbalLock) {
            gimbalAxis0 = CameraCommands.GIMBAL_STICK_CENTER
            gimbalAxis1 = CameraCommands.GIMBAL_STICK_CENTER
            gimbalStickHeld = false
            gimbalSendRest = true
        }
    }

    private fun tickGimbalStick() {
        val now = SystemClock.elapsedRealtime()
        val packet: Pair<Int, Int>? =
            synchronized(gimbalLock) {
                val last = lastGimbalStickElapsed.get()
                if (!CameraCommands.shouldEmitGimbalStick(
                        gimbalStickHeld, gimbalSendRest, now, last,
                    )
                ) {
                    return@synchronized null
                }
                if (!CameraCommands.shouldEmitGimbalStickOnSocket(
                        rest = gimbalSendRest,
                        liveAccepting = liveViewEnabled,
                        hasConnection = socket != null,
                    )
                ) {
                    return@synchronized null
                }
                lastGimbalStickElapsed.set(now)
                val rest = gimbalSendRest
                val axis0 = if (rest) CameraCommands.GIMBAL_STICK_CENTER else gimbalAxis0
                val axis1 = if (rest) CameraCommands.GIMBAL_STICK_CENTER else gimbalAxis1
                if (rest) {
                    gimbalSendRest = false
                    gimbalStickHeld = false
                }
                axis0 to axis1
            }
        val axes = packet ?: return
        sendGimbalStick(axes.first, axes.second)
    }

    /** `0x04/0x01` flags `0x00`, no ACK. Built with `encodeDuml` so it works on the shipped core. */
    fun sendGimbalStick(axis0: Int, axis1: Int) {
        if (!SwiftCore.isAvailable) return
        synchronized(sendLock) {
            sendGimbalStickLocked(axis0, axis1)
        }
    }

    private fun sendGimbalStickLocked(axis0: Int, axis1: Int) {
        if (socket == null) return
        val payload = CameraCommands.gimbalStickPayload(axis0, axis1)
        val frame =
            SwiftCore.encodeDuml(
                SwiftCore.SENDER_APP,
                SwiftCore.RX_GIMBAL,
                dumlSeq,
                SwiftCore.FLAG_NOTIFY,
                0x04,
                0x01,
                payload,
            ) ?: return
        val routing = SwiftCore.routingHeader(udpSeq, (cmdCounter + 1) and 0xFF, false) ?: return
        val header =
            SwiftCore.transportHeader(0x05, routing.size + frame.size, sessionId, udpSeq) ?: return
        cmdCounter = (cmdCounter + 1) and 0xFF
        writeOnNetwork(header + routing + frame)
        dumlSeq = (dumlSeq + 1) and 0xFFFF
        udpSeq = (udpSeq + 8) and 0xFFFF
    }

    private fun sendAck() {
        sendWindowAck()
    }

    /** Handbook / iOS `noteAckWindows`: 0x03 seq in ACK group 1, 0x01 seeds extra. */
    private fun noteAckWindows(datagram: ByteArray) {
        if (datagram.size < 8) return
        when (datagram[6].toInt() and 0xFF) {
            0x01 -> if (datagram.size >= 34) {
                val acked =
                    (datagram[18].toInt() and 0xFF) or ((datagram[19].toInt() and 0xFF) shl 8)
                val extra =
                    (datagram[26].toInt() and 0xFF) or ((datagram[27].toInt() and 0xFF) shl 8)
                if (!hasAckedData.get()) {
                    ackedDataCursor.set(acked)
                    hasAckedData.set(true)
                }
                extraCursor.set(extra)
                hasExtra.set(true)
            }
            0x03 -> {
                val seq = SwiftCore.transportSeq(datagram)
                if (seq >= 0) {
                    ackedDataCursor.set(seq)
                    hasAckedData.set(true)
                }
            }
        }
    }

    /** Handbook / iOS `sendWindowAck`: 34 B pktType 0x04 echoing video + 0x03 cursors. */
    private fun sendWindowAck() {
        val cursor = peerCursor.get()
        val acked = if (hasAckedData.get()) ackedDataCursor.get() else baseSeq
        val extra = if (hasExtra.get()) extraCursor.get() else baseSeq
        val payload = SwiftCore.ackPayload(cursor, acked, extra) ?: return
        val header = SwiftCore.transportHeader(0x04, payload.size, sessionId, 0) ?: return
        write(header + payload)
    }

    private fun write(bytes: ByteArray) {
        if (closed.get()) return
        onSendThread { writeOnNetwork(bytes) }
    }

    /** Seq stamp + send must not run on Main (NetworkOnMainThread + seq/ACK races). */
    private fun onSendThread(body: () -> Unit) {
        if (Looper.myLooper() == Looper.getMainLooper()) {
            if (sendExecutor.isShutdown) return
            sendExecutor.execute(body)
            return
        }
        body()
    }

    private fun writeOnNetwork(bytes: ByteArray) {
        val sock = socket ?: return
        val packet =
            if (sock.isConnected) {
                DatagramPacket(bytes, bytes.size)
            } else {
                DatagramPacket(bytes, bytes.size, InetAddress.getByName(CAMERA_HOST), port)
            }
        synchronized(sendLock) {
            runCatching { sock.send(packet) }
                .onSuccess { writeRejected.set(false) }
                .onFailure { err ->
                    writeRejected.set(true)
                    if (sendFailLogs.incrementAndGet() <= 3) {
                        Log.w(TAG, "datalink: UDP send failed", err)
                    }
                }
        }
    }

    private fun receiveLoop() {
        val buf = ByteArray(2048)
        while (running.get()) {
            val sock = socket ?: break
            val packet = DatagramPacket(buf, buf.size)
            try {
                sock.receive(packet)
                if (packet.length > 0) ingest(packet.data.copyOf(packet.length))
            } catch (_: java.net.SocketTimeoutException) {
            } catch (e: Exception) {
                if (!running.get()) break
                Log.w(TAG, "datalink: UDP receive failed", e)
            }
        }
    }

    private fun ingest(datagram: ByteArray) {
        val nIn = inboundLogs.incrementAndGet()
        val pktType = if (datagram.size > 6) datagram[6].toInt() and 0xFF else -1
        if (nIn <= 16) {
            val head =
                datagram.take(24).joinToString("") { b ->
                    (b.toInt() and 0xFF).toString(16).padStart(2, '0')
                }
            Log.i(
                TAG,
                "datalink: inbound #$nIn bytes=${datagram.size} pktType=0x${pktType.toString(16)} hex=$head",
            )
        }
        if (datagram.size >= 10) {
            val ch = (datagram[8].toInt() and 0xFF) or ((datagram[9].toInt() and 0xFF) shl 8)
            if (ch != 0) camChannel = ch
        }
        if (datagram.size >= 8 && datagram[6] == 0x00.toByte()) handshakeAcked = true
        noteAckWindows(datagram)
        if (datagram.size == 34 && datagram[6] == 0x01.toByte()) {
            if (!hasVideoSeq.get()) {
                peerCursor.set(
                    (datagram[10].toInt() and 0xFF) or ((datagram[11].toInt() and 0xFF) shl 8),
                )
            }
        } else if (datagram.size >= 6 && datagram[6] == 0x02.toByte()) {
            val seq = SwiftCore.transportSeq(datagram)
            if (seq >= 0) {
                peerCursor.set(seq)
                hasVideoSeq.set(true)
            }
        }
        if (datagram.size > 20 && datagram[6] == 0x02.toByte()) {
            if (!liveViewEnabled) {
                val dropped = leftoverVideoPackets.incrementAndGet()
                if (loggedLeftoverGop.compareAndSet(false, true) || dropped <= 8) {
                    Log.i(
                        TAG,
                        "datalink: drop leftover video before ingest #$dropped bytes=${datagram.size}",
                    )
                }
                return
            }
            lastVideoElapsed.set(SystemClock.elapsedRealtime())
            val n = rawVideoPackets.incrementAndGet()
            if (n <= 8) {
                Log.i(TAG, "datalink: video pktType=0x02 #$n bytes=${datagram.size}")
            }
            if (depacketizer != 0L) {
                val au = SwiftCore.depacketizerFeed(depacketizer, datagram)
                if (au != null) {
                    lastAccessUnitElapsed.set(SystemClock.elapsedRealtime())
                    val callback = onAccessUnit
                    if (!closed.get() && !decodeExecutor.isShutdown) {
                        decodeExecutor.execute { callback?.invoke(au) }
                    }
                }
            }
            return
        }
        val packed = SwiftCore.scanDuml(datagram) ?: return
        val frames = DumlCodec.unpackFrames(packed)
        if (frames.isEmpty()) return
        lastStatusElapsed.set(SystemClock.elapsedRealtime())
        frames.forEach { frame ->
            if (frame.cmdSet == 0x09 && (frame.cmdId and 0xFF) == 0xA8) {
                val pay0 = frame.payload.firstOrNull()?.toInt()?.and(0xFF) ?: -1
                lastLiveViewReplyElapsed.set(SystemClock.elapsedRealtime())
                Log.i(
                    TAG,
                    "datalink: 0x09/0xa8 reply flags=0x${(frame.flags and 0xFF).toString(16)} " +
                        "pay0=0x${pay0.toString(16)} bytes=${frame.payload.size}",
                )
            }
        }
        val callback = onStatusFrame
        main.post { frames.forEach { callback?.invoke(it) } }
    }

    private fun poke7001() {
        val sock = Socket()
        joiner.bindSocket(sock)
        sock.connect(InetSocketAddress(CAMERA_HOST, 7001), 2_000)
        val frame = SwiftCore.command(SwiftCore.CMD_SET_PAIRING_PIN, extra = pairingToken)
        sock.getOutputStream().write(frame)
        sock.getOutputStream().flush()
        pokeSocket = sock
        Thread.sleep(400)
    }

    /**
     * Recoverable datalink failures. iOS `DatalinkDriver.DatalinkError`.
     * Do not use Kotlin `error()` here — that is `IllegalStateException` and
     * Play Vitals treats an uncaught one as a crash (#189).
     */
    sealed class DatalinkError(message: String) : Exception(message) {
        class NoHandshake : DatalinkError("camera never answered the datalink handshake")
    }

    companion object {
        private const val TAG = "DatalinkDriver"
        private const val CAMERA_HOST = "192.168.2.1"
        internal const val WILDCARD_BIND_HOST = "0.0.0.0"

        /** Handshake miss after rebind/path-lost. Pairing or recovery, not a crash. */
        internal fun handshakeTimeoutFailure(): Exception = DatalinkError.NoHandshake()

        /** Ephemeral local port. Camera 9004 is the remote, not the client bind. */
        internal const val UDP_BIND_PORT = 0

        /**
         * Android UDP bind host after `Network.bindSocket`. Always the wildcard —
         * the SoftAP Network pin is the path, not a DHCP bind. [localIPv4] is
         * logged as `dhcp=` only. Local port is ephemeral (0), matching iOS
         * and Mimo — not camera 9004.
         */
        internal fun udpBindPort(): Int = UDP_BIND_PORT

        internal fun udpBindHost(@Suppress("UNUSED_PARAMETER") localIPv4: String?): String =
            WILDCARD_BIND_HOST

        private const val HANDSHAKE_SENDS_PER_BIND = 20
        private const val HANDSHAKE_SEND_INTERVAL_MS = 350L
        private const val HANDSHAKE_POLL_MS = 20L
        private const val HANDSHAKE_REBIND_LIMIT = 3
        private const val HANDSHAKE_RETRY_PAUSE_MS = 500L
        private const val ACK_INTERVAL_MS = 25L
        /** Camera ignores 0x09/0xa8 until subscribe is processed. */
        private const val SUBSCRIBE_SETTLE_MS = 150L
        private val SUBSCRIPTION_KEYS =
            listOf(
                "camcap_mode_profile",
                "camcap_video_format",
                "camcap_fov",
                "camcap_iso",
                "camcap_shutter",
                "camcap_photo_storage_format",
                "camcap_color_mode",
                "cam_storage",
                "cam_status",
                "timecode_info",
                "cam_expo_param",
                "cam_video_param_v2",
                "cam_record_time",
                "cam_image_effect",
                "cam_lens_state",
                "cam_fov",
                "cam_audio_status_v2",
            )
    }
}
