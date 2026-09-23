package com.opencapture.openpocketcine.session

import android.Manifest
import android.annotation.SuppressLint
import android.bluetooth.BluetoothAdapter
import android.bluetooth.BluetoothDevice
import android.bluetooth.BluetoothGatt
import android.bluetooth.BluetoothGattCallback
import android.bluetooth.BluetoothGattCharacteristic
import android.bluetooth.BluetoothGattDescriptor
import android.bluetooth.BluetoothManager
import android.bluetooth.BluetoothProfile
import android.bluetooth.le.ScanCallback
import android.bluetooth.le.ScanResult
import android.bluetooth.le.ScanSettings
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.pm.PackageManager
import android.os.Build
import android.os.Handler
import android.os.HandlerThread
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.core.content.ContextCompat
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.openpocketcine.pairing.FoundCameraIdentity
import java.util.UUID
import kotlinx.coroutines.CancellableContinuation
import kotlinx.coroutines.channels.BufferOverflow
import kotlinx.coroutines.flow.MutableSharedFlow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharedFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asSharedFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.suspendCancellableCoroutine
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.coroutines.resume
import kotlin.coroutines.resumeWithException

/**
 * BLE scan + GATT for Osmo cameras. Port of iOS `BleLink`: service fff0, notify fff4,
 * write fff5, arm-pairing `[01 00]` on fff4 with response, paced without-response writes.
 */
class BleLink(context: Context) {
    private val appContext = context.applicationContext
    private val adapter: BluetoothAdapter? =
        appContext.getSystemService(BluetoothManager::class.java)?.adapter
    private val worker = HandlerThread("opc.ble").also { it.start() }
    private val handler = Handler(worker.looper)
    private val main = Handler(Looper.getMainLooper())

    private val foundDevices = linkedMapOf<String, BluetoothDevice>()
    private val _found = MutableStateFlow<List<FoundCamera>>(emptyList())
    val found: StateFlow<List<FoundCamera>> = _found.asStateFlow()
    private val _radioOn = MutableStateFlow(adapter?.isEnabled == true)
    val radioOn: StateFlow<Boolean> = _radioOn.asStateFlow()
    private var wantsScan = false
    private var radioReceiverRegistered = false

    private val radioReceiver =
        object : BroadcastReceiver() {
            override fun onReceive(context: Context, intent: Intent) {
                if (intent.action != BluetoothAdapter.ACTION_STATE_CHANGED) return
                val state = intent.getIntExtra(BluetoothAdapter.EXTRA_STATE, BluetoothAdapter.ERROR)
                val on = state == BluetoothAdapter.STATE_ON
                _radioOn.value = on
                if (on) {
                    startScanIfWanted()
                } else {
                    stopScanner()
                }
            }
        }

    private val _frames =
        MutableSharedFlow<DumlFrame>(extraBufferCapacity = 64, onBufferOverflow = BufferOverflow.DROP_OLDEST)
    val frames: SharedFlow<DumlFrame> = _frames.asSharedFlow()

    private var scanning = false
    private var gatt: BluetoothGatt? = null
    private var fff4: BluetoothGattCharacteristic? = null
    private var fff5: BluetoothGattCharacteristic? = null
    private var initialization: BleInitialization? = null
    private val operations = CallbackOperationOwner<BluetoothGatt>()
    private var activeAttempt: CallbackOperationOwner.Token<BluetoothGatt>? = null
    private var connectContinuation: CancellableContinuation<Unit>? = null
    private var connectTimeout: Runnable? = null
    private var discoveryStartedFor: BluetoothGatt? = null
    private val writeQueue = ArrayDeque<ByteArray>()
    private var writing = false
    private val connectSettled = AtomicBoolean(false)
    var onLinkLost: (() -> Unit)? = null

    init {
        val filter = IntentFilter(BluetoothAdapter.ACTION_STATE_CHANGED)
        ContextCompat.registerReceiver(
            appContext,
            radioReceiver,
            filter,
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        radioReceiverRegistered = true
    }

    private val scanCallback =
        object : ScanCallback() {
            override fun onScanResult(callbackType: Int, result: ScanResult) {
                classify(result)?.let { camera ->
                    foundDevices[camera.address] = result.device
                    val current = _found.value
                    val idx = current.indexOfFirst { it.id == camera.id }
                    if (idx < 0) {
                        _found.value = current + camera
                    } else if (
                        FoundCameraIdentity.shouldReplace(
                            current[idx].name,
                            current[idx].modelId,
                            camera.name,
                            camera.modelId,
                        )
                    ) {
                        _found.value = current.toMutableList().also { it[idx] = camera }
                    }
                }
            }

            override fun onScanFailed(errorCode: Int) {
                Log.w(TAG, "BLE scan failed code=$errorCode")
                scanning = false
            }
        }

    @SuppressLint("MissingPermission")
    fun startScan() {
        wantsScan = true
        startScanIfWanted()
    }

    @SuppressLint("MissingPermission")
    private fun startScanIfWanted() {
        if (!wantsScan) return
        val radio = adapter
        if (radio == null || !radio.isEnabled) {
            _radioOn.value = false
            Log.w(TAG, "BLE scan waiting: Bluetooth is not fully on (state=${radio?.state})")
            return
        }
        _radioOn.value = true
        val scanner = radio.bluetoothLeScanner ?: run {
            Log.w(TAG, "BLE scan skipped: no LE scanner")
            return
        }
        if (scanning) return
        if (!hasScanPermission()) {
            Log.w(TAG, "BLE scan skipped: nearby-device permission not granted")
            return
        }
        foundDevices.clear()
        _found.value = emptyList()
        val settings =
            ScanSettings.Builder().setScanMode(ScanSettings.SCAN_MODE_LOW_LATENCY).build()
        val started =
            runCatching { scanner.startScan(null, settings, scanCallback) }
                .onFailure { Log.w(TAG, "BLE scan failed to start", it) }
                .isSuccess
        scanning = started
        if (started) Log.i(TAG, "BLE scan started")
    }

    private fun hasScanPermission(): Boolean {
        val required =
            if (Build.VERSION.SDK_INT >= 31) {
                Manifest.permission.BLUETOOTH_SCAN
            } else {
                Manifest.permission.ACCESS_FINE_LOCATION
            }
        return ContextCompat.checkSelfPermission(appContext, required) ==
            PackageManager.PERMISSION_GRANTED
    }

    @SuppressLint("MissingPermission")
    fun stopScan() {
        wantsScan = false
        stopScanner()
    }

    @SuppressLint("MissingPermission")
    private fun stopScanner() {
        if (!scanning) return
        scanning = false
        runCatching { adapter?.bluetoothLeScanner?.stopScan(scanCallback) }
    }

    @SuppressLint("MissingPermission")
    suspend fun connect(camera: FoundCamera) {
        // Multiview links and saved-cleanup resets connect by address without this link's scan.
        val device = foundDevices[camera.address]
            ?: runCatching { adapter?.getRemoteDevice(camera.address) }.getOrNull()
            ?: error("camera disappeared")
        stopScan()
        suspendCancellableCoroutine { cont ->
            val attempt = operations.begin()
            handler.post {
                runOwnedConnectionStart(operations, attempt, cont) {
                    closeGatt(IllegalStateException("replaced"))
                    if (!cont.isActive) {
                        operations.finish(attempt)
                        return@runOwnedConnectionStart
                    }
                    activeAttempt = attempt
                    connectContinuation = cont
                    initialization = BleInitialization(
                        requestNotify = { channel ->
                            val current = gatt
                            val characteristic = if (channel == BleInitialization.Channel.FFF4) fff4 else fff5
                            if (current == null || characteristic == null) BleRequestResult.LinkClosed
                            else requestNotify(current, characteristic)
                        },
                        requestArm = {
                            val current = gatt
                            val characteristic = fff4
                            if (current == null || characteristic == null) BleRequestResult.LinkClosed
                            else requestPairingArm(current, characteristic)
                        },
                        complete = { error ->
                            if (error == null) finishConnect(null) else closeGatt(error)
                        },
                        nowMs = SystemClock::elapsedRealtime,
                        journal = { DiagnosticCenter.log("info", "ble", "initialization", it) },
                    )
                    val timeout =
                        Runnable {
                            operations.runIfCurrent(attempt) {
                                initialization?.timedOut()
                                closeGatt(IllegalStateException("Bluetooth connect timed out"))
                                operations.finish(attempt)
                            }
                        }
                    connectTimeout = timeout
                    handler.postDelayed(timeout, 10_000)
                    try {
                        val connected = device.connectGatt(
                            appContext, false, gattCallback(attempt), BluetoothDevice.TRANSPORT_LE,
                        ) ?: error("Bluetooth connection unavailable")
                        gatt = connected
                        operations.attach(attempt, connected)
                    } catch (error: RuntimeException) {
                        closeGatt(error)
                        operations.finish(attempt)
                    }
                }
            }
            cont.invokeOnCancellation {
                handler.post {
                    operations.runIfCurrent(attempt) {
                        closeGatt(IllegalStateException("cancelled"))
                        operations.finish(attempt)
                    }
                }
            }
        }
    }

    fun send(bytes: ByteArray) {
        val attempt = operations.current() ?: return
        handler.post {
            operations.runIfCurrent(attempt) {
                writeQueue.addLast(bytes)
                pumpWrites()
            }
        }
    }

    fun disconnect() {
        // Invalidate callbacks now, before the worker receives this cleanup.
        // A replacement connect will own cleaning up the previous GATT itself.
        val barrier = operations.begin()
        handler.post {
            operations.runIfCurrent(barrier) {
                closeGatt(IllegalStateException("camera disappeared"))
                operations.finish(barrier)
            }
        }
    }

    @SuppressLint("MissingPermission")
    private fun startDiscovery(gatt: BluetoothGatt) {
        if (discoveryStartedFor === gatt || this.gatt !== gatt) return
        discoveryStartedFor = gatt
        if (!gatt.discoverServices()) closeGatt(IllegalStateException("service discovery failed"))
    }

    @SuppressLint("MissingPermission")
    private fun closeGatt(error: Throwable) {
        discoveryStartedFor = null
        finishConnect(error)
        connectSettled.set(false)
        activeAttempt?.resource = null
        activeAttempt = null
        writeQueue.clear()
        writing = false
        initialization?.close()
        initialization = null
        val closing = gatt
        gatt = null
        fff4 = null
        fff5 = null
        runCatching { closing?.disconnect() }
        runCatching { closing?.close() }
    }

    fun close() {
        disconnect()
        wantsScan = false
        if (radioReceiverRegistered) {
            runCatching { appContext.unregisterReceiver(radioReceiver) }
            radioReceiverRegistered = false
        }
        worker.quitSafely()
    }

    @SuppressLint("MissingPermission")
    private fun pumpWrites() {
        if (writing || writeQueue.isEmpty()) return
        val characteristic = fff5 ?: return
        val g = gatt ?: return
        val attempt = activeAttempt ?: return
        writing = true
        val payload = writeQueue.removeFirst()
        val sent =
            runCatching {
                if (Build.VERSION.SDK_INT >= 33) {
                    g.writeCharacteristic(
                        characteristic,
                        payload,
                        BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE,
                    )
                } else {
                    @Suppress("DEPRECATION")
                    characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_NO_RESPONSE
                    @Suppress("DEPRECATION")
                    characteristic.value = payload
                    @Suppress("DEPRECATION")
                    g.writeCharacteristic(characteristic)
                }
            }
        if (sent.isFailure) {
            val error = sent.exceptionOrNull() ?: IllegalStateException("BLE write failed")
            if (dropLinkIfDeadBinder(error)) return
            Log.w(TAG, "BLE write failed — dropping this payload", error)
            writing = false
            pumpWrites()
            return
        }
        handler.postDelayed(
            {
                operations.runIfCurrent(attempt, g) {
                    writing = false
                    pumpWrites()
                }
            },
            120,
        )
    }

    private fun finishConnect(error: Throwable?) {
        connectTimeout?.let { handler.removeCallbacks(it) }
        connectTimeout = null
        val cont = connectContinuation ?: return
        connectContinuation = null
        if (!cont.isActive) return
        if (error != null) {
            connectSettled.set(false)
            cont.resumeWithException(error)
        } else {
            connectSettled.set(true)
            cont.resume(Unit)
        }
    }

    private fun notifyLinkLostIfSettled(attempt: CallbackOperationOwner.Token<BluetoothGatt>) {
        if (!connectSettled.getAndSet(false)) return
        main.post { operations.runIfCurrent(attempt) { onLinkLost?.invoke() } }
    }

    private fun dropLinkIfDeadBinder(error: Throwable): Boolean {
        if (!BleBinderFailure.isDeadBinder(error)) return false
        Log.w(TAG, "BLE binder died — dropping the link", error)
        val attempt = activeAttempt
        if (attempt != null) notifyLinkLostIfSettled(attempt)
        closeGatt(error)
        return true
    }

    private fun onGattCallback(
        attempt: CallbackOperationOwner.Token<BluetoothGatt>,
        source: BluetoothGatt,
        action: () -> Unit,
    ) {
        // Android may dispatch on binder threads; all GATT state lives on worker.
        handler.post { operations.runIfCurrent(attempt, source, action) }
    }

    @SuppressLint("MissingPermission")
    private fun classify(result: ScanResult): FoundCamera? {
        val record = result.scanRecord ?: return null
        val name = record.deviceName ?: runCatching { result.device.name }.getOrNull()
        var modelId: Int? = null
        var isDji = false
        for (companyId in DJI_COMPANY_IDS) {
            val payload = record.getManufacturerSpecificData(companyId) ?: continue
            isDji = true
            if (SwiftCore.isAvailable) {
                val decoded = SwiftCore.bleAdvertModelId(payload)
                if (decoded >= 0) modelId = decoded
            }
        }
        val nameLooksDji =
            name?.lowercase()?.let { n ->
                listOf("osmo", "pocket", "nano", "dji", "action", "xtra", "edge").any { n.contains(it) }
            } == true
        if (!isDji && !nameLooksDji) return null
        // Read the MAC before resolving: its OUI is what identifies an Xtra rebrand, which
        // advertises the same model id as the DJI original but speaks 10004 with no poke.
        val address = result.device.address ?: return null
        val model =
            if (SwiftCore.isAvailable) {
                CameraModel.fromJson(
                    SwiftCore.resolveCameraModel(modelId ?: -1, name, address, isDji))
            } else {
                CameraModel.default.copy(name = name ?: CameraModel.default.name)
            }
        val id = UUID.nameUUIDFromBytes("ble:$address".toByteArray()).toString()
        return FoundCamera(
            id = id,
            address = address,
            name = name ?: "DJI camera",
            model = model,
            modelId = modelId,
        )
    }

    private fun gattCallback(attempt: CallbackOperationOwner.Token<BluetoothGatt>) =
        object : BluetoothGattCallback() {
            @SuppressLint("MissingPermission")
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                onGattCallback(attempt, gatt) {
                    if (status != BluetoothGatt.GATT_SUCCESS || newState == BluetoothProfile.STATE_DISCONNECTED) {
                        DiagnosticCenter.log(
                            "warning", "ble", "connectionState",
                            "ble: connection state status=$status newState=$newState connectSettled=${connectSettled.get()}",
                        )
                        finishConnect(IllegalStateException("the camera disconnected"))
                        notifyLinkLostIfSettled(attempt)
                        closeGatt(IllegalStateException("the camera disconnected"))
                    } else if (newState == BluetoothProfile.STATE_CONNECTED) {
                        initialization?.connected()
                        // Android GATT runs one request at a time. discoverServices()
                        // issued while the MTU exchange was pending was silently dropped
                        // on a Xiaomi / Android 12 phone: connected at 846 ms, then the
                        // 10 s connect deadline expired in discovery (#369, #351).
                        // Osmosis discovers from onMtuChanged; do the same, with a
                        // fallback for stacks that never report the MTU.
                        if (gatt.requestMtu(512)) {
                            handler.postDelayed(
                                { operations.runIfCurrent(attempt, gatt) { startDiscovery(gatt) } },
                                MTU_DISCOVERY_FALLBACK_MS,
                            )
                        } else {
                            startDiscovery(gatt)
                        }
                    }
                }
            }

            override fun onMtuChanged(gatt: BluetoothGatt, mtu: Int, status: Int) {
                onGattCallback(attempt, gatt) { startDiscovery(gatt) }
            }

            @SuppressLint("MissingPermission")
            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                onGattCallback(attempt, gatt) {
                    initialization?.discoveryStatus(status)
                    val service = gatt.getService(SERVICE_FFF0)
                    if (status != BluetoothGatt.GATT_SUCCESS || service == null) {
                        closeGatt(IllegalStateException("camera has no DUML service"))
                        return@onGattCallback
                    }
                    fff4 = service.getCharacteristic(CHAR_FFF4)
                    fff5 = service.getCharacteristic(CHAR_FFF5)
                    if (fff4 == null || fff5 == null) {
                        closeGatt(IllegalStateException("camera has no DUML service"))
                        return@onGattCallback
                    }
                    initialization?.servicesDiscovered()
                }
            }

            @SuppressLint("MissingPermission")
            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                onGattCallback(attempt, gatt) {
                    val channel = when (descriptor.characteristic.uuid) {
                        CHAR_FFF4 -> BleInitialization.Channel.FFF4
                        CHAR_FFF5 -> BleInitialization.Channel.FFF5
                        else -> return@onGattCallback
                    }
                    initialization?.notificationWritten(channel, status)
                }
            }

            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                onGattCallback(attempt, gatt) {
                    if (characteristic.uuid == CHAR_FFF4) {
                        initialization?.armWritten(status)
                    }
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                @Suppress("DEPRECATION")
                val value = characteristic.value?.copyOf()
                onGattCallback(attempt, gatt) { ingest(value) }
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                val copy = value.copyOf()
                onGattCallback(attempt, gatt) { ingest(copy) }
            }
        }

    @SuppressLint("MissingPermission")
    private fun requestNotify(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ): BleRequestResult = try {
        admitBleNotification(
            enableLocal = { gatt.setCharacteristicNotification(characteristic, true) },
            closeIfDeadBinder = ::dropLinkIfDeadBinder,
            writeDescriptor = {
                val cccd = characteristic.getDescriptor(CCCD)
                if (cccd == null) {
                    BleRequestResult.MissingDescriptor
                } else {
                    val enable = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
                    if (Build.VERSION.SDK_INT >= 33) {
                        BleRequestResult.fromStatus(gatt.writeDescriptor(cccd, enable))
                    } else {
                        @Suppress("DEPRECATION")
                        cccd.value = enable
                        @Suppress("DEPRECATION")
                        BleRequestResult.fromBoolean(gatt.writeDescriptor(cccd))
                    }
                }
            },
        )
    } catch (error: Throwable) {
        if (dropLinkIfDeadBinder(error)) BleRequestResult.LinkClosed
        else {
            Log.w(TAG, "BLE notify setup failed", error)
            BleRequestResult.HandledFailure
        }
    }

    @SuppressLint("MissingPermission")
    private fun requestPairingArm(
        gatt: BluetoothGatt,
        characteristic: BluetoothGattCharacteristic,
    ): BleRequestResult = try {
        val payload = byteArrayOf(0x01, 0x00)
        if (Build.VERSION.SDK_INT >= 33) {
            BleRequestResult.fromStatus(
                gatt.writeCharacteristic(characteristic, payload, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT),
            )
        } else {
            @Suppress("DEPRECATION")
            characteristic.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            characteristic.value = payload
            @Suppress("DEPRECATION")
            BleRequestResult.fromBoolean(gatt.writeCharacteristic(characteristic))
        }
    } catch (error: Throwable) {
        if (dropLinkIfDeadBinder(error)) BleRequestResult.LinkClosed
        else {
            Log.w(TAG, "BLE pairing arm write failed", error)
            BleRequestResult.HandledFailure
        }
    }

    private fun ingest(value: ByteArray?) {
        if (value == null || value.isEmpty() || !SwiftCore.isAvailable) return
        val packed = SwiftCore.scanDuml(value) ?: return
        for (frame in DumlCodec.unpackFrames(packed)) {
            val emitted = _frames.tryEmit(frame)
            if (!emitted) Log.w(TAG, "frame overflow 0x${frame.cmdSet.toString(16)}/${frame.cmdId.toString(16)}")
        }
    }

    companion object {
        /** An MTU reply normally lands in tens of ms; never let it block discovery. */
        const val MTU_DISCOVERY_FALLBACK_MS = 1_500L
        private const val TAG = "BleLink"
        private val SERVICE_FFF0 = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
        private val CHAR_FFF4 = UUID.fromString("0000fff4-0000-1000-8000-00805f9b34fb")
        private val CHAR_FFF5 = UUID.fromString("0000fff5-0000-1000-8000-00805f9b34fb")
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private val DJI_COMPANY_IDS = intArrayOf(0x08AA, 0xF7AA, 0xE5C0)
    }
}
