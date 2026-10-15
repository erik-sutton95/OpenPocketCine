package com.opencapture.openpocketcine

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.os.SystemClock
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.MonitorSettingsCacheModel
import com.opencapture.opencine.appkit.MonitorSettingsCacheSource
import java.io.File
import java.util.UUID
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.Test
import org.junit.runner.RunWith
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

/**
 * Settings > Storage counts and clears the current camera's gallery cache, the one rule Insta and
 * iOS follow (F09: Pocket counted and cleared every camera's folder). SIMULATED cache bytes for two
 * cameras in an isolated context; the actual app model, settings composition and settings owner.
 */
@RunWith(AndroidJUnit4::class)
class SettingsMediaCacheTest {
    @Test fun settingsCountAndClearTheCurrentCamerasGalleryCache() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val base = instrumentation.targetContext.applicationContext
        val domain = "settings-cache." + UUID.randomUUID()
        val root = File(base.cacheDir, domain)
        val domains = mutableSetOf<String>()
        val context = object : ContextWrapper(base) {
            override fun getApplicationContext(): Context = this
            override fun getNoBackupFilesDir(): File = File(root, "no-backup")
            override fun getFilesDir(): File = File(root, "files")
            override fun getCacheDir(): File = File(root, "cache")
            override fun getSharedPreferences(name: String, mode: Int): SharedPreferences {
                val key = "$domain.$name"; domains += key
                return base.getSharedPreferences(key, mode)
            }
        }
        fun gallery(camera: String, bytes: Int): Pair<File, File> {
            val folder = File(context.noBackupFilesDir, "OpenPocketCine/media/$camera")
            val original = File(folder, "files/DJI_20261003140001_0001_D.MP4").apply { parentFile!!.mkdirs(); writeBytes(ByteArray(bytes) { 7 }) }
            return original to File(folder, "index.json").apply { writeText("[]") }
        }
        val (original, catalog) = gallery("current", 4_096)
        val (otherOriginal, _) = gallery("other", 65_536)
        val written = original.length() + catalog.length()
        context.getSharedPreferences("openpocketcine.media", Context.MODE_PRIVATE).edit()
            .putString("opc.media.lastCameraID", "current").commit()
        var model: AppModel? = null
        try {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                var source: MonitorSettingsCacheSource? = null
                scenario.onActivity { activity ->
                    model = AppModel(context)
                    val app = operatorSetupApp(model!!)
                    activity.setContent { source = requireNotNull(app.cacheSource)(context) }
                }
                val deadline = SystemClock.uptimeMillis() + 5_000
                while (source == null && SystemClock.uptimeMillis() < deadline) {
                    instrumentation.waitForIdleSync(); SystemClock.sleep(50)
                }
                val captured = requireNotNull(source) { "Settings composed no cache source" }
                runBlocking(Dispatchers.Main) {
                    val settings = MonitorSettingsCacheModel(this)
                    settings.refresh(captured)
                    val counted = withTimeout(10_000) { settings.state.first { it.bytes != null || it.readFailed } }
                    assertEquals(written, counted.bytes, "Settings counts the current camera's gallery only")
                    settings.requestClear()
                    settings.clear()
                    withTimeout(10_000) { settings.state.first { !it.clearing } }
                    settings.retire()
                }
                assertFalse(original.exists(), "Clear cache removes the current camera's originals")
                assertTrue(catalog.isFile, "Clear cache keeps the clip list")
                assertTrue(otherOriginal.isFile, "Clear cache leaves other cameras' galleries")
            }
        } finally {
            instrumentation.runOnMainSync { model?.close() }
            domains.forEach { base.deleteSharedPreferences(it) }
            root.deleteRecursively()
        }
    }
}
