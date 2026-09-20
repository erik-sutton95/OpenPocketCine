package com.opencapture.openpocketcine.session

/** Native submission is distinct from its later GATT completion callback. */
internal sealed interface BleRequestResult {
    data object Accepted : BleRequestResult
    data class Rejected(val status: Int? = null) : BleRequestResult
    data object LocalRegistrationFailed : BleRequestResult
    data object MissingDescriptor : BleRequestResult
    data object HandledFailure : BleRequestResult
    data object LinkClosed : BleRequestResult

    companion object {
        fun fromBoolean(accepted: Boolean): BleRequestResult =
            if (accepted) Accepted else Rejected()

        fun fromStatus(status: Int): BleRequestResult =
            if (status == 0) Accepted else Rejected(status)
    }
}

internal fun admitBleNotification(
    enableLocal: () -> Boolean,
    writeDescriptor: () -> BleRequestResult,
    closeIfDeadBinder: (Throwable) -> Boolean = { false },
): BleRequestResult {
    val enabled = try {
        enableLocal()
    } catch (error: Throwable) {
        return if (closeIfDeadBinder(error)) BleRequestResult.LinkClosed else BleRequestResult.LocalRegistrationFailed
    }
    if (!enabled) return BleRequestResult.LocalRegistrationFailed
    return writeDescriptor()
}

/** One GATT attempt's initialization, invoked only inside BleLink's owner fence.
 * CCCD settlement is tolerant, but local FFF4 notification registration is required
 * to receive replies. Pairing succeeds only after the admitted FFF4 arm write
 * actually completes successfully.
 */
internal class BleInitialization(
    private val requestNotify: (Channel) -> BleRequestResult,
    private val requestArm: () -> BleRequestResult,
    private val complete: (Throwable?) -> Unit,
    private val nowMs: () -> Long = { System.nanoTime() / 1_000_000 },
    private val journal: (String) -> Unit = {},
) {
    enum class Channel { FFF4, FFF5 }
    enum class Stage(val label: String) {
        CONNECTION("connection"), DISCOVERY("discovery"),
        FFF4_NOTIFY("fff4_notify"), FFF5_NOTIFY("fff5_notify"),
        PAIRING_ARM("pairing_arm"), READY("ready"),
    }

    var stage = Stage.CONNECTION
        private set
    private val startedAt = nowMs()
    private var pendingNotify: Channel? = null
    private var notificationsStarted = false
    private var armed = false
    private var active = true

    init { record("started") }

    fun connected() {
        if (!active || stage != Stage.CONNECTION) return
        stage = Stage.DISCOVERY
        record("connected status=0")
    }

    fun discoveryStatus(status: Int) {
        if (active) record("services status=$status")
    }

    fun servicesDiscovered() {
        if (!active || notificationsStarted) return
        notificationsStarted = true
        notify(Channel.FFF4)
    }

    fun notificationWritten(channel: Channel, status: Int) {
        if (!active || pendingNotify != channel) return
        record("descriptor_callback status=$status")
        settleNotification(channel)
    }

    fun armWritten(status: Int) {
        if (!active || !armed) return
        record("arm_callback status=$status")
        active = false
        if (status == 0) {
            stage = Stage.READY
            record("completed")
            complete(null)
        } else {
            complete(IllegalStateException("pairing arm failed"))
        }
    }

    fun timedOut() {
        if (active) record("timeout")
    }

    fun close() {
        if (active) record("closed")
        active = false
    }

    private fun notify(channel: Channel) {
        if (!active) return
        pendingNotify = channel
        stage = if (channel == Channel.FFF4) Stage.FFF4_NOTIFY else Stage.FFF5_NOTIFY
        record("notify_requested")
        val result = requestNotify(channel)
        recordResult(result)
        when (result) {
            BleRequestResult.Accepted -> Unit // Only the callback settles an admitted write.
            BleRequestResult.LinkClosed -> active = false // BleLink already performed cleanup.
            BleRequestResult.LocalRegistrationFailed -> {
                if (channel == Channel.FFF4) {
                    active = false
                    complete(IllegalStateException("Bluetooth notification setup failed"))
                } else {
                    settleNotification(channel)
                }
            }
            else -> settleNotification(channel)
        }
    }

    private fun settleNotification(channel: Channel) {
        if (!active || pendingNotify != channel) return
        pendingNotify = null
        if (channel == Channel.FFF4) notify(Channel.FFF5) else arm()
    }

    private fun arm() {
        if (!active || armed) return
        armed = true
        stage = Stage.PAIRING_ARM
        record("arm_requested")
        val result = requestArm()
        recordResult(result)
        when (result) {
            BleRequestResult.Accepted -> Unit
            BleRequestResult.LinkClosed -> active = false
            else -> {
                active = false
                complete(IllegalStateException("pairing arm failed"))
            }
        }
    }

    private fun recordResult(result: BleRequestResult) {
        val detail = when (result) {
            BleRequestResult.Accepted -> "admitted=1"
            is BleRequestResult.Rejected -> "admitted=0 reason=rejected" +
                (result.status?.let { " status=$it" } ?: "")
            BleRequestResult.MissingDescriptor -> "admitted=0 reason=missing_cccd"
            BleRequestResult.LocalRegistrationFailed -> "admitted=0 reason=local_registration"
            BleRequestResult.HandledFailure -> "admitted=0 reason=exception"
            BleRequestResult.LinkClosed -> "admitted=0 reason=link_closed"
        }
        record(detail)
    }

    private fun record(event: String) {
        journal("ble: initialization stage=${stage.label} elapsedMs=${(nowMs() - startedAt).coerceAtLeast(0)} $event")
    }
}
