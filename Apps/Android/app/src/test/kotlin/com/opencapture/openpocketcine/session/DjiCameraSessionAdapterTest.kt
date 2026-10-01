package com.opencapture.openpocketcine.session

import com.opencapture.opencine.core.CameraCommand
import com.opencapture.opencine.core.CameraCommandIntent
import com.opencapture.opencine.core.CameraSnapshot
import com.opencapture.opencine.core.CommandPreconditions
import com.opencapture.opencine.core.CommandRejection
import com.opencapture.opencine.core.CommandStage
import com.opencapture.opencine.core.ConnectionState
import com.opencapture.opencine.core.ISOValue
import com.opencapture.opencine.core.MonotonicInstant
import com.opencapture.opencine.core.Observation
import com.opencapture.opencine.core.PowerStatus
import com.opencapture.opencine.core.Rational
import com.opencapture.opencine.core.RecordingState
import com.opencapture.opencine.core.SettingKey
import com.opencapture.opencine.core.SettingValue
import com.opencapture.opencine.core.ShutterValue
import com.opencapture.opencine.core.WhiteBalanceValue
import com.opencapture.openpocketcine.core.ConnectionPhase
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.runTest
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertTrue
import kotlin.time.Duration.Companion.milliseconds
import kotlin.time.Duration.Companion.seconds

/**
 * CORE-02 gate checks for the Android Pocket seam (iOS `DJICameraSessionAdapterTests`): declared
 * support is routed, reported state stays separate from requested state, an unconfirmed settle
 * is never success, and record start/stop is explicit and idempotent.
 */
@OptIn(ExperimentalCoroutinesApi::class)
class DjiCameraSessionAdapterTest {
    @Test
    fun everyDeclaredCapabilityReachesTheWire() = runTest {
        val keys = adapter(FakePort()).current.capabilities.descriptors.keys
        assertEquals(setOf(SettingKey.ISO, SettingKey.WHITE_BALANCE, SettingKey.RECORDING), keys)
        for (key in keys) {
            val port = FakePort()
            val seam = adapter(port)
            val snapshot = seam.current
            val intent = assertNotNull(validIntent(key, snapshot), "no test value for $key")
            val receipt = seam.submit(CameraCommand(intent, CommandPreconditions(snapshot)))
            assertEquals(CommandStage.Sent, receipt.stage, "$key is declared, so a valid request must reach the wire")
            assertEquals(1, port.fired.size)
        }
    }

    @Test
    fun undeclaredSettingStaysUnknownInsteadOfPretending() = runTest {
        val receipt = adapter(FakePort()).request(
            CameraCommandIntent.Set(SettingValue.Shutter(ShutterValue.Duration(Rational(1, 50)))),
        )
        assertEquals(CommandStage.Rejected(CommandRejection.SupportUnknown), receipt.stage)
    }

    @Test
    fun whiteBalanceRequestStaysPendingUntilTheCameraReportsIt() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.setWhiteBalanceCustom(5_600, 0)
        assertEquals(CommandStage.Sent, receipt.stage)
        assertEquals(listOf("wb 5600 0"), port.fired)
        port.answer(ControlWireEvent.ACKNOWLEDGED)
        assertEquals(CommandStage.AwaitingObservation, seam.receipt(receipt.operation)?.stage, "An ACK is not a value")
        assertEquals(
            SettingValue.WhiteBalance(WhiteBalanceValue.Auto),
            seam.current.value(SettingKey.WHITE_BALANCE).value,
            "Reported stays the camera's Auto",
        )
        port.state = port.state.copy(whiteBalance = ReportedWhiteBalance(CameraCommands.WB_CUSTOM, 5_600, 0))
        seam.sessionDidChange()
        assertEquals(CommandStage.Confirmed, seam.receipt(receipt.operation)?.stage)
        assertEquals(
            SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(5_600)),
            seam.current.value(SettingKey.WHITE_BALANCE).value,
        )
    }

    @Test
    fun isoIsConfirmedOnlyByItsOwnReadback() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.setIsoIndex(0x06)
        port.answer(ControlWireEvent.ACKNOWLEDGED)
        port.state = port.state.copy(whiteBalance = ReportedWhiteBalance(CameraCommands.WB_AUTO, 0, 3))
        seam.sessionDidChange()
        assertEquals(CommandStage.AwaitingObservation, seam.receipt(receipt.operation)?.stage)
        assertEquals(SettingValue.Iso(ISOValue.Manual(400)), seam.current.value(SettingKey.ISO).value)
        port.state = port.state.copy(isoIndex = 0x06)
        seam.sessionDidChange()
        assertEquals(CommandStage.Confirmed, seam.receipt(receipt.operation)?.stage)
    }

    @Test
    fun acknowledgedWithoutReadbackTimesOutInsteadOfSucceeding() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.request(CameraCommandIntent.StartRecording)
        port.answer(ControlWireEvent.ACKNOWLEDGED)
        testScheduler.advanceTimeBy(seam.readbackTimeout + 1.milliseconds)
        assertEquals(CommandStage.TimedOut, seam.outcome(receipt.operation)?.stage)
        assertEquals(RecordingState.IDLE, seam.current.recording.value)
    }

    @Test
    fun settleWithoutAckOrMatchingStatusIsNeverSuccess() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.setWhiteBalanceCustom(4_300, 0)
        // `settleInflightTimeout` with no ACK and no matching report.
        port.answer(ControlWireEvent.UNCONFIRMED)
        assertEquals(CommandStage.TimedOut, seam.receipt(receipt.operation)?.stage)
        port.answer(ControlWireEvent.ACKNOWLEDGED)
        assertEquals(CommandStage.TimedOut, seam.receipt(receipt.operation)?.stage, "A late ACK never rewrites it")
    }

    @Test
    fun cameraRefusalIsRejected() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.request(CameraCommandIntent.StartRecording)
        port.answer(ControlWireEvent.REFUSED)
        assertEquals(CommandStage.Rejected(CommandRejection.CameraRefused), seam.receipt(receipt.operation)?.stage)
    }

    @Test
    fun replacedRequestThatNeverLeftIsNotSent() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.setIsoIndex(0x06)
        port.answer(ControlWireEvent.NOT_SENT)
        assertEquals(
            CommandStage.Failed(com.opencapture.opencine.core.CommandFailure.NOT_SENT),
            seam.receipt(receipt.operation)?.stage,
        )
    }

    @Test
    fun startWhileRecordingSendsNothing() = runTest {
        val port = FakePort(recording = true)
        val seam = adapter(port)
        assertEquals(CommandStage.Confirmed, seam.request(CameraCommandIntent.StartRecording).stage)
        port.state = port.state.copy(recording = false)
        assertEquals(CommandStage.Confirmed, seam.request(CameraCommandIntent.StopRecording).stage)
        assertTrue(port.fired.isEmpty(), "No record frame was fired")
    }

    @Test
    fun unknownRecordingStateRefusesTheToggleShapedWire() = runTest {
        val port = FakePort(recording = null)
        val seam = adapter(port)
        assertEquals(null, seam.current.recording.value, "Unknown is not idle")
        assertEquals(CommandStage.Rejected(CommandRejection.RecordingStateUnknown), seam.shutter()?.stage)
        assertTrue(port.fired.isEmpty())
        assertEquals("Waiting for the camera's record state", port.note)
    }

    @Test
    fun shutterResolvesToAnExplicitIntentFromTheReportedState() = runTest {
        for (recording in listOf(false, true)) {
            val port = FakePort(recording = recording)
            val receipt = adapter(port).shutter()
            assertEquals(
                if (recording) CameraCommandIntent.StopRecording else CameraCommandIntent.StartRecording,
                receipt?.intent,
            )
            assertEquals(listOf("record ${!recording}"), port.fired)
        }
    }

    @Test
    fun photoModeFiresAStillWithoutARecordIntent() = runTest {
        val port = FakePort()
        port.state = port.state.copy(shootingMode = CameraCommands.SHOOT_PHOTO)
        assertEquals(null, adapter(port).shutter())
        assertEquals(listOf("photo"), port.fired)
    }

    @Test
    fun replacedLinkEndsInFlightWorkAndRefusesOldPreconditions() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val before = seam.current
        val receipt = seam.setIsoIndex(0x06)
        seam.linkDidChange()
        assertEquals(CommandStage.OutcomeUnknown, seam.receipt(receipt.operation)?.stage)
        val stale = seam.submit(
            CameraCommand(CameraCommandIntent.Set(SettingValue.Iso(ISOValue.Manual(800))), CommandPreconditions(before)),
        )
        assertEquals(CommandStage.Rejected(CommandRejection.StaleEpoch), stale.stage)
    }

    @Test
    fun missingTelemetryStaysUnknown() = runTest {
        val port = FakePort()
        port.state = PocketControlState()
        val snapshot = adapter(port).current
        assertEquals(ConnectionState.Discovered, snapshot.connection)
        assertEquals(Observation.unknown, snapshot.recording)
        assertEquals(PowerStatus.unknown, snapshot.power)
        assertEquals(Observation.unknown, snapshot.storage)
        assertTrue(snapshot.settings.isEmpty())
        assertEquals(
            CommandStage.Rejected(CommandRejection.NotConnected),
            adapter(port).setIsoIndex(0x06).stage,
        )
    }

    @Test
    fun wireTimeoutEndsADroppedRequestAsUnknown() = runTest {
        val port = FakePort()
        val seam = adapter(port)
        val receipt = seam.setIsoIndex(0x06)
        testScheduler.advanceTimeBy(seam.wireTimeout + 1.seconds)
        assertEquals(CommandStage.OutcomeUnknown, seam.receipt(receipt.operation)?.stage)
    }

    private fun TestScope.adapter(port: FakePort) =
        DjiCameraSessionAdapter(port, backgroundScope) { MonotonicInstant(testScheduler.currentTime.milliseconds) }

    private fun validIntent(key: SettingKey, snapshot: CameraSnapshot): CameraCommandIntent? =
        when (key) {
            SettingKey.RECORDING ->
                if (snapshot.recording.value == RecordingState.RECORDING) {
                    CameraCommandIntent.StopRecording
                } else {
                    CameraCommandIntent.StartRecording
                }
            SettingKey.ISO -> {
                val current = snapshot.value(key).value
                snapshot.capabilities[key]?.domain?.choices?.firstOrNull { it != current }?.let {
                    CameraCommandIntent.Set(it)
                }
            }
            SettingKey.WHITE_BALANCE -> CameraCommandIntent.Set(SettingValue.WhiteBalance(WhiteBalanceValue.Kelvin(4_300)))
            // A newly declared key needs a test value here, or this test cannot vouch for it.
            else -> null
        }

    /** A linked Pocket in Video reporting ISO 400, Auto WB and the given record state. */
    private class FakePort(recording: Boolean? = false) : PocketControlPort {
        var state =
            PocketControlState(
                linkReady = true,
                phase = ConnectionPhase.LIVE,
                shootingMode = CameraCommands.SHOOT_VIDEO,
                isoChoices = listOf(0x00, 0x03, 0x04, 0x05, 0x06, 0x07),
                isoIndex = 0x05,
                whiteBalance = ReportedWhiteBalance(CameraCommands.WB_AUTO, 0, 0),
                recording = recording,
            )
        val fired = mutableListOf<String>()
        var note: String? = null
        private var stage: ((ControlWireEvent) -> Unit)? = null

        fun answer(event: ControlWireEvent) {
            stage?.invoke(event)
        }

        private fun fire(name: String, onStage: ((ControlWireEvent) -> Unit)?) {
            fired += name
            stage = onStage
            onStage?.invoke(ControlWireEvent.SENT)
        }

        override fun controlState() = state

        override fun setIsoIndex(index: Int, onStage: ((ControlWireEvent) -> Unit)?) = fire("iso $index", onStage)

        override fun setWhiteBalanceAuto(tint: Int?, onStage: ((ControlWireEvent) -> Unit)?) =
            fire("wb auto $tint", onStage)

        override fun setWhiteBalance(kelvin: Int, tint: Int, onStage: ((ControlWireEvent) -> Unit)?) =
            fire("wb $kelvin $tint", onStage)

        override fun setRecording(start: Boolean, onStage: ((ControlWireEvent) -> Unit)?) =
            fire("record $start", onStage)

        override fun takePhoto() {
            fired += "photo"
        }

        override fun noteControlRejection(note: String) {
            this.note = note
        }
    }
}
