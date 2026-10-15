package com.opencapture.openpocketcine

import android.os.SystemClock
import android.view.accessibility.AccessibilityNodeInfo
import androidx.compose.runtime.Recomposer
import androidx.compose.ui.platform.InfiniteAnimationPolicy
import androidx.compose.ui.platform.compositionContext
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.DiscoveryPermissions
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertNotNull
import kotlin.test.assertSame
import kotlin.test.assertTrue

/**
 * A4-25/A4-26: the window paces infinite animations, and a recreated activity (a configuration
 * change the manifest does not declare, such as a locale change) keeps the app root and never
 * shows the launch splash again.
 */
@RunWith(AndroidJUnit4::class)
class MonitorRootRecreationTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()

    @Before fun grantDiscovery() {
        // A permission sheet would take the active window from the monitor.
        val app = instrumentation.targetContext.packageName
        DiscoveryPermissions.discovery().forEach { instrumentation.uiAutomation.grantRuntimePermission(app, it) }
    }

    @Test fun recreationKeepsTheRoot() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            lateinit var first: AppModel
            scenario.onActivity { first = it.model }
            scenario.recreate()
            scenario.onActivity { assertSame(first, it.model, "the recreated activity keeps the root") }
        }
    }

    @Test fun theWindowRecomposerPacesInfiniteAnimations() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            scenario.onActivity { activity ->
                val recomposer = activity.window.decorView.compositionContext as? Recomposer
                assertNotNull(recomposer?.effectCoroutineContext?.get(InfiniteAnimationPolicy), "a paced window recomposer")
            }
        }
    }

    @Test fun recreationNeverShowsTheSplashAgain() {
        ActivityScenario.launch(MainActivity::class.java).use { scenario ->
            SystemClock.sleep(800)
            val splash = brandMarks()
            SystemClock.sleep(3_500) // past the 2.25 s splash and its fade
            val settled = brandMarks()
            assertTrue(splash > settled, "the splash shows its logo at launch ($splash vs $settled)")
            scenario.recreate()
            SystemClock.sleep(800)
            assertEquals(settled, brandMarks(), "no second launch splash")
        }
    }

    /** Nodes described as the app's name in the monitor's window: the splash logo adds one. */
    private fun brandMarks(): Int {
        val root = instrumentation.uiAutomation.rootInActiveWindow
        assertEquals(instrumentation.targetContext.packageName, root?.packageName?.toString(), "the monitor is in front")
        fun count(node: AccessibilityNodeInfo?): Int =
            if (node == null) 0
            else (if (node.contentDescription?.toString() == "OpenPocketCine") 1 else 0) +
                (0 until node.childCount).sumOf { count(node.getChild(it)) }
        return count(root)
    }
}
