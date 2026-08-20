package com.opencapture.openpocketcine.session

import android.os.Handler
import android.os.Looper
import android.util.Log
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.pairing.CameraApJoiner
import java.net.DatagramPacket
import java.net.DatagramSocket
import java.net.InetAddress
import java.net.InetSocketAddress
import java.net.Socket
import java.util.concurrent.atomic.AtomicBoolean
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random

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
    private var socket: DatagramSocket? = null
    private var pokeSocket: Socket? = null
    private var receiver: Thread? = null
    private var ackThread: Thread? = null

    private var sessionId = 0
    private var baseSeq = 0
    private var udpSeq = 0
    private var dumlSeq = 0xA000
    private var cmdCounter = 0
    private var peerCursor = 0
    private var camChannel = 0
    @Volatile private var handshakeAcked = false
    @Volatile private var liveViewEnabled = false
    private var depacketizer = 0L
    private val rawVideoPackets = AtomicInteger(0)
    private val loggedLeftoverGop = AtomicBoolean(false)

    var onStatusFrame: ((DumlFrame) -> Unit)? = null
    var onAccessUnit: ((ByteArray) -> Unit)? = null

    val videoPackets: Int get() = rawVideoPackets.get()
    val droppedIncomplete: Int
        get() = if (depacketizer != 0L && SwiftCore.isAvailable) SwiftCore.depacketizerDropped(depacketizer) else 0

    fun open() {
        check(SwiftCore.isAvailable) { "Swift core is not loaded" }
        close()
        if (tcpPoke) runCatching { poke7001() }
        sessionId = Random.nextInt(0x1000, 0xFFFE)
        baseSeq = Random.nextInt(0x1000, 0xF000) and 0xFFF8
        camChannel = baseSeq
        udpSeq = 0
        dumlSeq = 0xA000
        cmdCounter = 0
        peerCursor = 0
        handshakeAcked = false
        liveViewEnabled = false
        loggedLeftoverGop.set(false)
        rawVideoPackets.set(0)
        depacketizer = SwiftCore.depacketizerCreate()
        val sock = DatagramSocket()
        sock.soTimeout = 250
        joiner.bindSocket(sock)
        socket = sock
        running.set(true)
        receiver =
            Thread({ receiveLoop() }, "opc.datalink.rx").also { it.isDaemon = true; it.start() }

        val handshake = SwiftCore.handshakePayload(baseSeq) ?: error("handshake payload")
        for (i in 0 until 20) {
            sendRaw(0x00, handshake)
            Thread.sleep(350)
            if (handshakeAcked) break
        }
        if (!handshakeAcked) error("camera never answered the datalink handshake")
        repeat(5) {
            Thread.sleep(400)
            sendAck()
        }
        udpSeq = (camChannel + 8) and 0xFFFF
        register()
        subscribe()
        ackThread =
            Thread({ ackPump() }, "opc.datalink.ack").also { it.isDaemon = true; it.start() }
    }

    fun keepalive() {
        sendCommand(SwiftCore.CMD_APP_PRESENCE)
        sendAck()
    }

    fun startLiveView() {
        liveViewEnabled = true
        sendCommand(SwiftCore.CMD_LIVE_VIEW_ENABLE)
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
        if (!SwiftCore.isAvailable) return
        cmdCounter = (cmdCounter + 1) and 0xFF
        val frameBytes =
            SwiftCore.encodeDuml(sender, receiver, dumlSeq, flags, cmdSet, cmdId, payload) ?: return
        dumlSeq = (dumlSeq + 1) and 0xFFFF
        val routing = SwiftCore.routingHeader(udpSeq, cmdCounter, false) ?: return
        val header =
            SwiftCore.transportHeader(0x05, routing.size + frameBytes.size, sessionId, udpSeq) ?: return
        write(header + routing + frameBytes)
        udpSeq = (udpSeq + 8) and 0xFFFF
    }

    fun close() {
        running.set(false)
        liveViewEnabled = false
        ackThread?.interrupt()
        receiver?.interrupt()
        ackThread = null
        receiver = null
        runCatching { socket?.close() }
        socket = null
        runCatching { pokeSocket?.close() }
        pokeSocket = null
        if (depacketizer != 0L && SwiftCore.isAvailable) {
            SwiftCore.depacketizerDestroy(depacketizer)
            depacketizer = 0L
        }
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
        val header =
            SwiftCore.transportHeader(pktType, payload.size, sessionId, udpSeq) ?: return
        write(header + payload)
        udpSeq = (udpSeq + 8) and 0xFFFF
    }

    fun sendCommand(kind: Int, extra: String? = null) {
        cmdCounter = (cmdCounter + 1) and 0xFF
        val frameBytes = SwiftCore.command(kind, dumlSeq, extra)
        dumlSeq = (dumlSeq + 1) and 0xFFFF
        val routing = SwiftCore.routingHeader(udpSeq, cmdCounter, false) ?: return
        val header =
            SwiftCore.transportHeader(0x05, routing.size + frameBytes.size, sessionId, udpSeq) ?: return
        write(header + routing + frameBytes)
        udpSeq = (udpSeq + 8) and 0xFFFF
    }

    /** `0x04/0x01` flags `0x00`, no ACK. Built with `encodeDuml` so it works on the shipped core. */
    fun sendGimbalStick(axis0: Int, axis1: Int) {
        if (!SwiftCore.isAvailable) return
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
        cmdCounter = (cmdCounter + 1) and 0xFF
        dumlSeq = (dumlSeq + 1) and 0xFFFF
        val routing = SwiftCore.routingHeader(udpSeq, cmdCounter, false) ?: return
        val header =
            SwiftCore.transportHeader(0x05, routing.size + frame.size, sessionId, udpSeq) ?: return
        write(header + routing + frame)
        udpSeq = (udpSeq + 8) and 0xFFFF
    }

    private fun sendAck() {
        val payload = SwiftCore.ackPayload(peerCursor, baseSeq) ?: return
        val header = SwiftCore.transportHeader(0x04, payload.size, sessionId, 0) ?: return
        write(header + payload)
    }

    private fun write(bytes: ByteArray) {
        val sock = socket ?: return
        val packet = DatagramPacket(bytes, bytes.size, InetAddress.getByName(CAMERA_HOST), port)
        runCatching { sock.send(packet) }
    }

    private fun ackPump() {
        while (running.get()) {
            sendAck()
            try {
                Thread.sleep(25)
            } catch (_: InterruptedException) {
                break
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
            } catch (_: Exception) {
                continue
            }
            if (packet.length <= 0) continue
            ingest(packet.data.copyOf(packet.length))
        }
    }

    private fun ingest(datagram: ByteArray) {
        if (datagram.size >= 10) {
            val ch = (datagram[8].toInt() and 0xFF) or ((datagram[9].toInt() and 0xFF) shl 8)
            if (ch != 0) camChannel = ch
        }
        if (datagram.size >= 8 && datagram[6] == 0x00.toByte()) handshakeAcked = true
        if (datagram.size == 34 && datagram[6] == 0x01.toByte()) {
            peerCursor = (datagram[10].toInt() and 0xFF) or ((datagram[11].toInt() and 0xFF) shl 8)
        } else if (datagram.size >= 6 && datagram[6] == 0x02.toByte()) {
            val seq = SwiftCore.transportSeq(datagram)
            if (seq >= 0) peerCursor = seq
        }
        if (datagram.size > 20 && datagram[6] == 0x02.toByte()) {
            if (!liveViewEnabled) {
                if (loggedLeftoverGop.compareAndSet(false, true)) {
                    Log.i(TAG, "datalink: drop leftover video before enable")
                }
                return
            }
            rawVideoPackets.incrementAndGet()
            if (depacketizer != 0L) {
                val au = SwiftCore.depacketizerFeed(depacketizer, datagram)
                if (au != null) {
                    val callback = onAccessUnit
                    main.post { callback?.invoke(au) }
                }
            }
            return
        }
        val packed = SwiftCore.scanDuml(datagram) ?: return
        val frames = DumlCodec.unpackFrames(packed)
        if (frames.isEmpty()) return
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

    companion object {
        private const val TAG = "DatalinkDriver"
        private const val CAMERA_HOST = "192.168.2.1"
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
            )
    }
}
