package com.opencapture.openpocketcine

import android.graphics.Rect
import android.os.PowerManager
import android.os.SystemClock
import android.view.KeyEvent
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.openpocketcine.core.ConnectionPhase
import com.opencapture.openpocketcine.bridge.SwiftCore
import com.opencapture.openpocketcine.session.LivePipelineCadence
import com.opencapture.openpocketcine.session.SessionRecoveryUi
import java.io.File
import java.util.UUID
import java.util.concurrent.atomic.AtomicInteger
import kotlin.random.Random
import kotlin.test.assertTrue
import org.json.JSONObject
import org.junit.Assume.assumeTrue
import org.junit.Test
import org.junit.runner.RunWith

/** Opt-in physical camera test. Ordinary connectedDebugAndroidTest skips it. */
@RunWith(AndroidJUnit4::class)
class FeedStressTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val arguments = InstrumentationRegistry.getArguments()
    private lateinit var scenario: ActivityScenario<MainActivity>
    private lateinit var model: AppModel
    private lateinit var events: File
    private lateinit var fault: FeedStressFault
    private val stages = listOf(LivePipelineCadence.Stage.VIDEO, LivePipelineCadence.Stage.AU,
        LivePipelineCadence.Stage.OUTPUT, LivePipelineCadence.Stage.PRESENT)
    private var action = "setup"
    private var commands = 0
    private val acknowledgments = AtomicInteger()
    private val commandFailures = AtomicInteger()
    private class StressFailure(val code: String) : AssertionError(code)

    /** Host compatibility probe: no activity, connection, impairment or controls. */
    @Test fun runnerContract() {
        assumeTrue(arguments.getString("opcStress") == "1")
        check(BuildConfig.DEBUG)
        val contract = JSONObject().put("schema", 2)
            .put("scenarios", "joystick,lifecycle,settings")
            .put("profiles", "burst,combined,loss")
        File(reportRoot(), "contract.json").writeText(contract.toString())
    }

    @Test fun connectionUiAndControlsUnderPacketLoss() {
        assumeTrue("Use just android-feed-stress with a physical phone and saved Pocket camera",
            arguments.getString("opcStress") == "1")
        check(BuildConfig.DEBUG)
        val seed = arguments.getString("opcSeed", "401").toLong()
        val seconds = arguments.getString("opcSeconds", "300").toLong()
        val profile = arguments.getString("opcProfile", "combined")
        val requested = arguments.getString("opcScenario", "all")
        val actions = listOf("settings", "joystick", "lifecycle")
        require(requested == "all" || requested in actions)
        val selected = if (requested == "all") actions else listOf(requested)
        require(seconds in 180..1740 && profile in FeedStressFault.PROFILES)
        val root = reportRoot()
        events = File(root, "events.ndjson")
        fault = FeedStressFault(seed, SystemClock::elapsedRealtime)
        val summary = JSONObject().put("schema", 2).put("evidence", "device_instrumentation")
            .put("platform", "android").put("seed", seed).put("profile", profile)
            .put("requested_seconds", seconds)
            .put("build_identity", installedBuildString("BUILD_IDENTITY"))
            .put("source_revision", installedBuildString("SOURCE_REVISION"))
            .put("requested_scenarios", selected.sorted().joinToString(","))
            .put("recording_allowed", false).put("status", "failed")
        var completed = 0
        val completedActions = mutableSetOf<String>()
        var failure: Throwable? = null
        try {
            scenario = ActivityScenario.launch(MainActivity::class.java)
            scenario.onActivity { activity ->
                model = activity.model
                check(model.savedCameras.size == 1) { "Exactly one saved camera is required" }
                check(!model.session.status.value.isRecording) { "Existing recording is not allowed" }
                model.session.debugVideoPacketAdmission = fault::admit
                model.reconnect(model.savedCameras.single())
            }
            val deadline = SystemClock.elapsedRealtime() + seconds * 1000
            waitHealthy(30_000, minOf(deadline, SystemClock.elapsedRealtime() + 120_000))
            check(model.session.hasGimbal) { "A Pocket camera with a gimbal is required" }
            val iso = model.session.status.value.isoIndex
            check(iso in CaptureLists.isoIndices(model.session.status.value)) { "Current ISO is unavailable" }
            summary.put("camera_model_id", model.session.connectedCamera?.modelId ?: -1)
            scenario.onActivity {
                model.session.debugCameraSetResult = { key, ok ->
                    if (key == SwiftCore.waitKey(SwiftCore.CMD_SET_ISO_INDEX)) {
                        if (ok) acknowledgments.incrementAndGet() else commandFailures.incrementAndGet()
                    }
                }
            }
            val random = Random(seed)
            val schedule = selected.shuffled(random)
            while (SystemClock.elapsedRealtime() + (if (completed > 0) 60_000 else 25_000) < deadline) {
                if (completed > 0) waitHealthy(30_000, deadline - 25_000)
                if (SystemClock.elapsedRealtime() + 25_000 >= deadline) break
                val next = schedule[completed % schedule.size]
                action = next
                val dropsBefore = fault.dropped
                val acksBefore = acknowledgments.get()
                val failuresBefore = commandFailures.get()
                fault.arm(profile)
                mark("fault_armed")
                try {
                    when (next) {
                        "settings" -> {
                            clickDescription("Settings")
                            findDescription("Operator Setup", text = true)
                            // Reassert the current ISO through the real SET mailbox while
                            // Settings is open. No format, exposure or recording intent changes.
                            repeat(30) {
                                scenario.onActivity { it.model.setIsoIndex(iso) }
                                commands += 1
                                pause(100)
                            }
                            pressBack()
                        }
                        "joystick" -> dragStick()
                        "lifecycle" -> {
                            instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_HOME)
                            pause(1500)
                            val intent = instrumentation.targetContext.packageManager
                                .getLaunchIntentForPackage(instrumentation.targetContext.packageName)!!
                            intent.addFlags(android.content.Intent.FLAG_ACTIVITY_NEW_TASK)
                            instrumentation.targetContext.startActivity(intent)
                            pause(1500)
                            findDescription("Gimbal stick")
                        }
                    }
                } finally {
                    fault.disarm()
                    mark("fault_disarmed")
                }
                assertTrue(fault.dropped > dropsBefore, "Fault did not overlap $next")
                val recoveryStart = SystemClock.elapsedRealtime()
                val recoveryDeadline = minOf(deadline, recoveryStart + 16_000)
                if (next == "settings") waitControls(acksBefore, failuresBefore, recoveryDeadline)
                waitHealthy(2_000, recoveryDeadline)
                mark("recovered", SystemClock.elapsedRealtime() - recoveryStart)
                completed += 1
                completedActions.add(next)
            }
            assertTrue(completedActions.containsAll(schedule), "Incomplete scenario coverage; increase the time limit")
            summary.put("status", "passed")
        } catch (caught: Throwable) {
            failure = caught
            summary.put("failure", (caught as? StressFailure)?.code ?: "instrumentation_error")
            if (caught is StressFailure && caught.code == "fresh_picture_deadline" && action != "setup") {
                // Keep the failed 16s verdict, but let production escalation run.
                // Closing the activity here would cancel the owner at its deadline.
                fault.disarm()
                mark("failure_observed")
                val aftermathStart = SystemClock.elapsedRealtime()
                try {
                    waitHealthy(2_000, aftermathStart + 60_000)
                    val elapsed = SystemClock.elapsedRealtime() - aftermathStart
                    summary.put("aftermath", "recovered").put("aftermath_recovery_ms", elapsed)
                    mark("aftermath_recovered", elapsed)
                } catch (aftermathFailure: Throwable) {
                    summary.put("aftermath", "no_fresh_picture")
                        .put("aftermath_failure", (aftermathFailure as? StressFailure)?.code ?: "instrumentation_error")
                    mark("aftermath_ended")
                }
            }
        } finally {
            fault.disarm()
            var teardownFailure: Throwable? = null
            if (::model.isInitialized) {
                model.session.debugVideoPacketAdmission = null
                try {
                    instrumentation.runOnMainSync {
                        model.session.debugCameraSetResult = null
                        model.endGimbalStick()
                    }
                } catch (caught: Throwable) { teardownFailure = caught }
            }
            try {
                if (::scenario.isInitialized) scenario.close()
            } catch (caught: Throwable) { teardownFailure = teardownFailure ?: caught }
            if (teardownFailure != null) {
                summary.put("status", "failed")
                failure = failure ?: teardownFailure
            }
            summary.put("teardown", if (teardownFailure == null) "passed" else "failed")
            summary.put("covered_scenarios", completedActions.sorted().joinToString(","))
            summary.put("completed_scenarios", completed).put("commands_offered", commands)
                .put("commands_acknowledged", acknowledgments.get()).put("commands_failed", commandFailures.get())
                .put("injected_packets", fault.dropped).put("last_scenario", action)
            File(root, "summary.json").writeText(summary.toString(2))
        }
        failure?.let { throw it }
    }

    private fun reportRoot(): File {
        val run = arguments.getString("opcRun") ?: UUID.randomUUID().toString().replace("-", "")
        require(run.matches(Regex("[a-f0-9]{32}")))
        return File(instrumentation.targetContext.filesDir, "connection-stress/$run").also { it.mkdirs() }
    }

    // Read the target APK at runtime. Kotlin may inline BuildConfig string
    // constants from the APK used to compile this test, which can be different
    // when the host deliberately reuses an installed app.
    private fun installedBuildString(name: String): String =
        instrumentation.targetContext.classLoader
            .loadClass("${MainActivity::class.java.packageName}.BuildConfig")
            .getField(name).get(null) as String

    private fun waitControls(acksBefore: Int, failuresBefore: Int, deadline: Long) {
        while (SystemClock.elapsedRealtime() < deadline) {
            if (commandFailures.get() != failuresBefore) throw StressFailure("camera_set_failed")
            var pending = -1
            scenario.onActivity { pending = it.model.session.pendingCameraSetCount }
            if (commandFailures.get() != failuresBefore) throw StressFailure("camera_set_failed")
            if (pending == 0 && acknowledgments.get() > acksBefore
                && SystemClock.elapsedRealtime() < deadline) return
            pause(100)
        }
        throw StressFailure("camera_set_did_not_settle")
    }

    private fun mark(event: String, recoveryMs: Long? = null) {
        val row = JSONObject().put("sample_ns", System.nanoTime()).put("event", event)
            .put("wall_time_ms", System.currentTimeMillis())
            .put("scenario", action).put("dropped", fault.dropped)
        recoveryMs?.let { row.put("recovery_ms", it) }
        events.appendText(row.toString() + "\n")
    }

    private fun waitHealthy(duration: Long, deadline: Long) {
        var previous = sample()
        var healthySince: Long? = null
        var advancing = 0
        while (SystemClock.elapsedRealtime() < deadline) {
            pause(1000)
            if (SystemClock.elapsedRealtime() >= deadline) break
            val current = sample()
            val fresh = stages.all { (current.ageMs[it] ?: -1.0) in 0.0..<2000.0 }
            val flowing = current.timeNs > previous.timeNs && stages.all {
                current.counts.getValue(it) > previous.counts.getValue(it)
            }
            if (fresh && flowing && model.session.phaseFlow.value == ConnectionPhase.LIVE
                && model.session.recoveryState.value == SessionRecoveryUi.Idle) {
                if (healthySince == null) healthySince = SystemClock.elapsedRealtime()
                advancing += 1
                if (advancing >= 2 && SystemClock.elapsedRealtime() - healthySince >= duration
                    && SystemClock.elapsedRealtime() < deadline) return
            } else {
                healthySince = null
                advancing = 0
            }
            previous = current
        }
        throw StressFailure("fresh_picture_deadline")
    }

    private fun sample(): LivePipelineCadence.Snapshot {
        if (model.session.status.value.isRecording) throw StressFailure("unexpected_recording")
        val power = instrumentation.targetContext.getSystemService(PowerManager::class.java)
        if (power.currentThermalStatus >= PowerManager.THERMAL_STATUS_SEVERE) throw StressFailure("thermal_halt")
        val value = model.session.cadence.snapshot()
        val row = JSONObject().put("sample_ns", value.timeNs).put("scenario", action)
            .put("wall_time_ms", System.currentTimeMillis())
            .put("phase", model.session.phaseFlow.value.name).put("dropped", fault.dropped)
            .put("recovery_state", model.session.recoveryState.value.javaClass.simpleName)
            .put("commands_offered", commands).put("thermal", power.currentThermalStatus)
            .put("commands_acknowledged", acknowledgments.get()).put("commands_failed", commandFailures.get())
        for (stage in stages) {
            row.put(stage.name.lowercase(), value.counts[stage])
            row.put(stage.name.lowercase() + "_age_ms", value.ageMs[stage])
        }
        events.appendText(row.toString() + "\n")
        return value
    }

    private fun pause(ms: Long) { SystemClock.sleep(ms) }

    private fun findDescription(label: String, text: Boolean = false): AccessibilityNodeInfo {
        fun find(node: AccessibilityNodeInfo): AccessibilityNodeInfo? {
            if (node.packageName?.toString() != instrumentation.targetContext.packageName) return null
            if ((if (text) node.text else node.contentDescription)?.toString() == label) return node
            for (index in 0 until node.childCount) {
                val child = node.getChild(index) ?: continue
                find(child)?.let { return it }
            }
            return null
        }
        val deadline = SystemClock.elapsedRealtime() + 4000
        while (SystemClock.elapsedRealtime() < deadline) {
            instrumentation.uiAutomation.rootInActiveWindow?.let { find(it)?.let { found -> return found } }
            pause(100)
        }
        throw StressFailure("missing_control")
    }

    private fun clickDescription(label: String) {
        val bounds = Rect()
        findDescription(label).getBoundsInScreen(bounds)
        touch(bounds.exactCenterX(), bounds.exactCenterY(), bounds.exactCenterX(), bounds.exactCenterY(), 100)
        pause(300)
    }

    private fun pressBack() {
        instrumentation.sendKeyDownUpSync(KeyEvent.KEYCODE_BACK)
        pause(300)
        findDescription("Gimbal stick")
    }

    private fun dragStick() {
        val bounds = Rect()
        findDescription("Gimbal stick").getBoundsInScreen(bounds)
        // Small physical throw, released with ACTION_UP even if input injection fails.
        touch(bounds.exactCenterX(), bounds.exactCenterY(),
            bounds.exactCenterX() + bounds.width() * .12f, bounds.exactCenterY(), 1500)
    }

    private fun touch(x0: Float, y0: Float, x1: Float, y1: Float, duration: Long) {
        val down = SystemClock.uptimeMillis()
        fun event(action: Int, x: Float, y: Float) {
            val event = MotionEvent.obtain(down, SystemClock.uptimeMillis(), action, x, y, 0)
            try { check(instrumentation.uiAutomation.injectInputEvent(event, true)) }
            finally { event.recycle() }
        }
        try {
            event(MotionEvent.ACTION_DOWN, x0, y0)
            repeat(10) {
                pause(duration / 10)
                event(MotionEvent.ACTION_MOVE, x0 + (x1 - x0) * (it + 1) / 10,
                    y0 + (y1 - y0) * (it + 1) / 10)
            }
        } finally { event(MotionEvent.ACTION_UP, x1, y1) }
    }
}
