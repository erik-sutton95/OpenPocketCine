package com.opencapture.openpocketcine

import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.os.BatteryManager
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.platform.LocalContext
import androidx.core.content.ContextCompat
import kotlin.math.roundToInt

data class PhoneBatteryReadout(
    val percent: Int?,
    val externalPower: Boolean?,
)

@Composable
fun rememberPhoneBatteryReadout(): PhoneBatteryReadout {
    val context = LocalContext.current.applicationContext
    val manager = remember(context) { context.getSystemService(BatteryManager::class.java) }
    var readout by remember(manager) {
        mutableStateOf(
            PhoneBatteryReadout(
                percent = readPhoneBatteryPercent(manager),
                externalPower = null,
            ),
        )
    }
    DisposableEffect(context, manager) {
        val receiver =
            object : BroadcastReceiver() {
                override fun onReceive(receiveContext: Context?, intent: Intent?) {
                    readout = readPhoneBatteryReadout(intent, manager)
                }
            }
        var registered = false
        val sticky =
            runCatching {
                    ContextCompat.registerReceiver(
                        context,
                        receiver,
                        IntentFilter(Intent.ACTION_BATTERY_CHANGED),
                        ContextCompat.RECEIVER_NOT_EXPORTED,
                    ).also { registered = true }
                }
                .getOrNull()
        if (sticky != null) readout = readPhoneBatteryReadout(sticky, manager)
        onDispose {
            if (registered) runCatching { context.unregisterReceiver(receiver) }
        }
    }
    return readout
}

@Composable
fun ObservePhoneBattery(model: AppModel) {
    val readout = rememberPhoneBatteryReadout()
    LaunchedEffect(readout) {
        model.applyPhoneBattery(readout.percent ?: -1, readout.externalPower == true)
    }
}

fun readPhoneBatteryReadout(intent: Intent?, manager: BatteryManager?): PhoneBatteryReadout {
    val level = intent?.getIntExtra(BatteryManager.EXTRA_LEVEL, Int.MIN_VALUE)
    val scale = intent?.getIntExtra(BatteryManager.EXTRA_SCALE, Int.MIN_VALUE)
    val status = intent?.getIntExtra(BatteryManager.EXTRA_STATUS, BatteryManager.BATTERY_STATUS_UNKNOWN)
    val broadcastPercent =
        if (level != null && scale != null && level >= 0 && scale > 0) {
            validBatteryPercent((level.toDouble() * 100.0 / scale.toDouble()).roundToInt())
        } else {
            null
        }
    val externalPower =
        when (status) {
            BatteryManager.BATTERY_STATUS_CHARGING,
            BatteryManager.BATTERY_STATUS_FULL,
            -> true
            BatteryManager.BATTERY_STATUS_DISCHARGING,
            BatteryManager.BATTERY_STATUS_NOT_CHARGING,
            -> false
            else -> null
        }
    return PhoneBatteryReadout(
        percent = broadcastPercent ?: readPhoneBatteryPercent(manager),
        externalPower = externalPower,
    )
}

fun readPhoneBatteryPercent(manager: BatteryManager?): Int? =
    runCatching { manager?.getIntProperty(BatteryManager.BATTERY_PROPERTY_CAPACITY) }
        .getOrNull()
        .let(::validBatteryPercent)

private fun validBatteryPercent(value: Int?): Int? =
    value?.takeIf { it in 0..100 }
