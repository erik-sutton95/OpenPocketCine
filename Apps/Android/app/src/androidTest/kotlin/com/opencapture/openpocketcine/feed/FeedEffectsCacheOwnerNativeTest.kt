package com.opencapture.openpocketcine.feed

import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.monitorui.MonitorAssistTool
import com.opencapture.monitorui.MonitorFalseColorSelection
import com.opencapture.opencine.appkit.MonitorAssistState
import androidx.compose.runtime.remember
import com.opencapture.opencine.appkitnative.MonitorCacheOwnerComposeDriver
import com.opencapture.opencine.cameracontrols.rememberMonitorFeedEffectsPlans
import com.opencapture.opencine.cameracontrols.MonitorFeedEffectsPlans
import com.opencapture.opencine.runtime.MonitorFeedEffectsCacheOwnerNativeProof
import com.opencapture.opencine.vocabulary.CameraCommands
import com.opencapture.opencine.vocabulary.CameraLUTProfile
import com.opencapture.openpocketcine.bridge.SwiftCore
import org.junit.Before
import org.junit.Test
import kotlin.test.assertTrue
import org.junit.runner.RunWith

/** Actual app packer/profile/facade bindings to the one shared SIMULATED native proof. */
@RunWith(AndroidJUnit4::class)
class FeedEffectsCacheOwnerNativeTest {
    @Before fun loadTheActualStagedLibrary() {
        assertTrue(SwiftCore.isAvailable, "The actual staged Swift library must load before its JNI calls")
    }
    private val proof get() = MonitorFeedEffectsCacheOwnerNativeProof(object : MonitorFeedEffectsCacheOwnerNativeProof.Binding {
        override val context get() = InstrumentationRegistry.getInstrumentation().targetContext
        override fun nativeVersion(): String = SwiftCore.coreVersion()
        override fun packedCube(seed: Int) = SwiftCore.packFalseColorPaint(seed % 8, CameraCommands.COLOR_DLOG2, if (seed < 8) 800 else 1600)
        override val vectorOrdinals = 0..7
        override fun vectorBakers(): Map<String, (Int) -> ByteArray?> = linkedMapOf(
            "paint" to { ordinal -> SwiftCore.packFalseColorPaint(ordinal, CameraCommands.COLOR_DLOG2, 800) },
            "weight" to { ordinal -> SwiftCore.packFalseColorWeight(ordinal, CameraCommands.COLOR_DLOG2, 800) })
        override fun compositionScene(): MonitorFeedEffectsCacheOwnerNativeProof.CompositionScene {
            val driver = MonitorCacheOwnerComposeDriver(InstrumentationRegistry.getInstrumentation()) { context, _ ->
                val plans = rememberMonitorFeedEffectsPlans(SwiftCore)
                val assist = remember(plans) {
                    MonitorAssistState().apply {
                        toggle(MonitorAssistTool.LUT); toggle(MonitorAssistTool.FALSE)
                        setFalseColor(MonitorFalseColorSelection.IRE)
                    }
                }
                plans to remember(plans, context, assist) {
                    { plans.create(context, assist, "off", CameraCommands.COLOR_DLOG2, 800, CameraLUTProfile()) }
                }
            }.start()
            return MonitorFeedEffectsCacheOwnerNativeProof.CompositionScene(
                driver::snapshot, driver::retiredPlan, driver::command, driver::close)
        }
        override fun planOwner(): MonitorFeedEffectsCacheOwnerNativeProof.PlanOwner = object : MonitorFeedEffectsCacheOwnerNativeProof.PlanOwner {
            private val plans = MonitorFeedEffectsPlans(SwiftCore)
            private val assist = MonitorAssistState().apply {
                toggle(MonitorAssistTool.LUT); toggle(MonitorAssistTool.FALSE)
                setFalseColor(MonitorFalseColorSelection.IRE)
            }
            override fun plan() = plans.create(context, assist, "off", CameraCommands.COLOR_DLOG2, 800, CameraLUTProfile())
            override fun close() = plans.close()
        }
    })
    @Test fun actualOldAndNewStagedNativeBytes() = proof.actualNativeBytesMatchOldStagedLibrary(
        requireNotNull(InstrumentationRegistry.getArguments().getString("cache_reference_mode")))
    @Test fun actualNativeCacheCapacityAndRetirement() = proof.actualNativePayloadsObeyEightEntryLruAndImmediateRetirement()
    @Test fun actualEnteredNativeBakeRetires() = proof.enteredActualNativeBakeCannotRefillRetiredOwner()
    @Test fun actualFacadeEscapedPlansKeepRendering() = proof.actualFacadePlansRemainRenderableAfterOnlyTheirCacheRetires()
    @Test fun actualComposeCacheOwnersSurviveCoverageRotationDetachAndFinalRetirement() =
        proof.actualComposeCacheOwnersSurviveCoverageRotationDetachAndFinalRetirement()
}
