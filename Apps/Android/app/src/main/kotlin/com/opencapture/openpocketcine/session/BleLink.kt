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
import android.util.Log
import androidx.core.content.ContextCompat
import com.opencapture.openpocketcine.bridge.SwiftCore
import java.util.UUID
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
    private var fff4NotifySettled = false
    private var fff5NotifySettled = false
    private var pairingArmed = false
    private var connectContinuation: kotlin.coroutines.Continuation<Unit>? = null
    private var connectTimeout: Runnable? = null
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
                    if (current.none { it.id == camera.id }) {
                        _found.value = current + camera
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
        val device = foundDevices[camera.address] ?: error("camera disappeared")
        stopScan()
        pairingArmed = false
        fff4NotifySettled = false
        fff5NotifySettled = false
        fff4 = null
        fff5 = null
        connectSettled.set(false)
        suspendCancellableCoroutine { cont ->
            handler.post {
                connectContinuation?.resumeWithException(IllegalStateException("replaced"))
                connectContinuation = cont
                val timeout =
                    Runnable {
                        finishConnect(IllegalStateException("Bluetooth connect timed out"))
                        runCatching { gatt?.disconnect() }
                    }
                connectTimeout = timeout
                handler.postDelayed(timeout, 10_000)
                gatt = device.connectGatt(appContext, false, gattCallback, BluetoothDevice.TRANSPORT_LE)
            }
            cont.invokeOnCancellation {
                handler.post {
                    finishConnect(IllegalStateException("cancelled"))
                    runCatching { gatt?.disconnect() }
                }
            }
        }
    }

    fun send(bytes: ByteArray) {
        handler.post {
            writeQueue.addLast(bytes)
            pumpWrites()
        }
    }

    @SuppressLint("MissingPermission")
    fun disconnect() {
        connectSettled.set(false)
        handler.post {
            finishConnect(IllegalStateException("camera disappeared"))
            writeQueue.clear()
            writing = false
            pairingArmed = false
            runCatching { gatt?.disconnect() }
            runCatching { gatt?.close() }
            gatt = null
            fff4 = null
            fff5 = null
        }
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
        writing = true
        val payload = writeQueue.removeFirst()
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
        handler.postDelayed(
            {
                writing = false
                pumpWrites()
            },
            120,
        )
    }

    private fun finishConnect(error: Throwable?) {
        connectTimeout?.let { handler.removeCallbacks(it) }
        connectTimeout = null
        val cont = connectContinuation ?: return
        connectContinuation = null
        if (error != null) {
            connectSettled.set(false)
            cont.resumeWithException(error)
        } else {
            connectSettled.set(true)
            cont.resume(Unit)
        }
    }

    private fun notifyLinkLostIfSettled() {
        if (!connectSettled.getAndSet(false)) return
        val cb = onLinkLost
        main.post { cb?.invoke() }
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
        val model =
            if (SwiftCore.isAvailable) {
                CameraModel.fromJson(SwiftCore.resolveCameraModel(modelId ?: -1, name))
            } else {
                CameraModel.default.copy(name = name ?: CameraModel.default.name)
            }
        val address = result.device.address ?: return null
        val id = UUID.nameUUIDFromBytes("ble:$address".toByteArray()).toString()
        return FoundCamera(
            id = id,
            address = address,
            name = name ?: "DJI camera",
            model = model,
            modelId = modelId,
        )
    }

    private val gattCallback =
        object : BluetoothGattCallback() {
            @SuppressLint("MissingPermission")
            override fun onConnectionStateChange(gatt: BluetoothGatt, status: Int, newState: Int) {
                if (newState == BluetoothProfile.STATE_CONNECTED) {
                    gatt.requestMtu(512)
                    gatt.discoverServices()
                } else if (newState == BluetoothProfile.STATE_DISCONNECTED) {
                    finishConnect(IllegalStateException("the camera disconnected"))
                    notifyLinkLostIfSettled()
                }
            }

            @SuppressLint("MissingPermission")
            override fun onServicesDiscovered(gatt: BluetoothGatt, status: Int) {
                val service = gatt.getService(SERVICE_FFF0)
                if (service == null) {
                    finishConnect(IllegalStateException("camera has no DUML service"))
                    return
                }
                fff4 = service.getCharacteristic(CHAR_FFF4)
                fff5 = service.getCharacteristic(CHAR_FFF5)
                if (fff4 == null || fff5 == null) {
                    finishConnect(IllegalStateException("camera has no DUML service"))
                    return
                }
                requestNotify(gatt, fff4!!)
            }

            @SuppressLint("MissingPermission")
            override fun onDescriptorWrite(
                gatt: BluetoothGatt,
                descriptor: BluetoothGattDescriptor,
                status: Int,
            ) {
                val uuid = descriptor.characteristic.uuid
                if (uuid == CHAR_FFF4) fff4NotifySettled = true
                if (uuid == CHAR_FFF5) fff5NotifySettled = true
                if (uuid == CHAR_FFF4) {
                    fff5?.let { requestNotify(gatt, it) }
                }
                maybeArmPairing(gatt)
            }

            @SuppressLint("MissingPermission")
            override fun onCharacteristicWrite(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                status: Int,
            ) {
                if (characteristic.uuid == CHAR_FFF4) {
                    if (status == BluetoothGatt.GATT_SUCCESS) finishConnect(null)
                    else finishConnect(IllegalStateException("pairing arm failed"))
                }
            }

            @Deprecated("Deprecated in Java")
            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
            ) {
                @Suppress("DEPRECATION")
                ingest(characteristic.value)
            }

            override fun onCharacteristicChanged(
                gatt: BluetoothGatt,
                characteristic: BluetoothGattCharacteristic,
                value: ByteArray,
            ) {
                ingest(value)
            }
        }

    @SuppressLint("MissingPermission")
    private fun requestNotify(gatt: BluetoothGatt, characteristic: BluetoothGattCharacteristic) {
        gatt.setCharacteristicNotification(characteristic, true)
        val cccd = characteristic.getDescriptor(CCCD) ?: run {
            if (characteristic.uuid == CHAR_FFF4) fff4NotifySettled = true
            if (characteristic.uuid == CHAR_FFF5) fff5NotifySettled = true
            maybeArmPairing(gatt)
            return
        }
        val enable = BluetoothGattDescriptor.ENABLE_NOTIFICATION_VALUE
        if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeDescriptor(cccd, enable)
        } else {
            @Suppress("DEPRECATION")
            cccd.value = enable
            @Suppress("DEPRECATION")
            gatt.writeDescriptor(cccd)
        }
    }

    @SuppressLint("MissingPermission")
    private fun maybeArmPairing(gatt: BluetoothGatt) {
        if (pairingArmed || !fff4NotifySettled || !fff5NotifySettled) return
        val char = fff4 ?: return
        pairingArmed = true
        val payload = byteArrayOf(0x01, 0x00)
        if (Build.VERSION.SDK_INT >= 33) {
            gatt.writeCharacteristic(char, payload, BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT)
        } else {
            @Suppress("DEPRECATION")
            char.writeType = BluetoothGattCharacteristic.WRITE_TYPE_DEFAULT
            @Suppress("DEPRECATION")
            char.value = payload
            @Suppress("DEPRECATION")
            gatt.writeCharacteristic(char)
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
        private const val TAG = "BleLink"
        private val SERVICE_FFF0 = UUID.fromString("0000fff0-0000-1000-8000-00805f9b34fb")
        private val CHAR_FFF4 = UUID.fromString("0000fff4-0000-1000-8000-00805f9b34fb")
        private val CHAR_FFF5 = UUID.fromString("0000fff5-0000-1000-8000-00805f9b34fb")
        private val CCCD = UUID.fromString("00002902-0000-1000-8000-00805f9b34fb")
        private val DJI_COMPANY_IDS = intArrayOf(0x08AA, 0xF7AA, 0xE5C0)
    }
}
