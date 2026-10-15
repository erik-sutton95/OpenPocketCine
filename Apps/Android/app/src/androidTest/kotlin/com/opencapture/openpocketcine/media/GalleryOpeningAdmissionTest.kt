package com.opencapture.openpocketcine.media

import android.content.Context
import android.content.ContextWrapper
import android.content.SharedPreferences
import android.graphics.Bitmap
import android.graphics.Color
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import android.view.MotionEvent
import android.view.accessibility.AccessibilityNodeInfo
import androidx.activity.compose.setContent
import androidx.test.core.app.ActivityScenario
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import com.opencapture.opencine.appkit.MonitorMediaCatalogCapture
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.BackdropRenderActivity
import com.opencapture.opencine.vocabulary.MediaFile
import java.io.ByteArrayOutputStream
import java.io.File
import java.util.UUID
import org.junit.Assert.*
import org.junit.Test
import org.junit.runner.RunWith

/** SIMULATED local source metadata; actual app cache, gallery slot, photo wrapper and native Close. */
@RunWith(AndroidJUnit4::class)
class GalleryOpeningAdmissionTest {
    @Test fun sameIdentityRefreshKeepsTheOriginalPhotoOpeningAndCloseReturnsToGallery() {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val base = instrumentation.targetContext.applicationContext
        val domain = "gallery-opening." + UUID.randomUUID()
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
        var model: AppModel? = null
        try {
            ActivityScenario.launch(BackdropRenderActivity::class.java).use { scenario ->
                scenario.onActivity { activity ->
                    val app = AppModel(context)
                    model = app
                    val cache = app.mediaCache
                    val camera = "SIMULATED-gallery"
                    cache.rememberCameraId(camera)
                    val image = Bitmap.createBitmap(64, 48, Bitmap.Config.ARGB_8888)
                    image.eraseColor(Color.GREEN)
                    val bytes = ByteArrayOutputStream().also { image.compress(Bitmap.CompressFormat.PNG, 100, it) }.toByteArray()
                    image.recycle()
                    val file = MediaFile("SIMULATED-original.JPG", "SIMULATED-original-thumb.JPG", sizeBytes = bytes.size.toLong())
                    cache.persistCatalog(listOf(file), camera)
                    cache.fileCache(camera, file).apply { parentFile!!.mkdirs(); writeBytes(bytes) }
                    cache.thumbnailFile(camera, file).apply { parentFile!!.mkdirs(); writeBytes(bytes) }
                    activity.setContent { MediaLibraryScreen(app, onClose = {}) }
                }
                await("original gallery row") { node("SIMULATED-original.JPG") != null }
                val row = requireNotNull(node("SIMULATED-original.JPG"))
                val bounds = Rect().also(row::getBoundsInScreen)
                scenario.onActivity { activity ->
                    val library = model!!.mediaController().library
                    val original = library.state.value.records.single()
                    val admission = library.actionToken
                    val time = SystemClock.uptimeMillis()
                    val location = IntArray(2)
                    activity.window.decorView.getLocationOnScreen(location)
                    for (action in listOf(MotionEvent.ACTION_DOWN, MotionEvent.ACTION_UP)) {
                        val event = MotionEvent.obtain(time, SystemClock.uptimeMillis(), action,
                            bounds.exactCenterX() - location[0], bounds.exactCenterY() - location[1], 0)
                        try { activity.window.decorView.dispatchTouchEvent(event) } finally { event.recycle() }
                    }
                    library.applyLocalRecords(MonitorMediaCatalogCapture(resetLibrary = true,
                        upserts = listOf(original.copy(asset = original.asset.copy(filename = "SIMULATED-refreshed.JPG")))), admission)
                    assertEquals("SIMULATED-refreshed.JPG", library.state.value.records.single().asset.filename)
                    assertEquals("The refresh retains source identity, so a late relookup is observable", admission, library.actionToken)
                }
                await("original captured photo title") {
                    node("SIMULATED-original.JPG") != null && node("Back to media") != null
                }
                saveScreen("captured-photo-before-close.png")
                val close = requireNotNull(node("Back to media", clickable = true))
                assertTrue(close.performAction(AccessibilityNodeInfo.ACTION_CLICK))
                await("returned actual gallery") {
                    node("SIMULATED-refreshed.JPG") != null && node("Back to media") == null
                }
                saveScreen("actual-gallery-after-close.png")
            }
        } finally {
            instrumentation.runOnMainSync { model?.close() }
            domains.forEach { base.deleteSharedPreferences(it) }
            root.deleteRecursively()
        }
    }

    private fun await(label: String, predicate: () -> Boolean) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val end = SystemClock.uptimeMillis() + 5_000
        while (SystemClock.uptimeMillis() < end) {
            instrumentation.waitForIdleSync()
            if (predicate()) return
            SystemClock.sleep(32)
        }
        saveScreen("failed-${label.replace(' ', '-')}.png")
        fail("Actual gallery/photo must show $label")
    }

    private fun node(label: String, clickable: Boolean = false): AccessibilityNodeInfo? {
        val automation = InstrumentationRegistry.getInstrumentation().uiAutomation
        if (Build.VERSION.SDK_INT >= 34) automation.clearCache()
        val pending = ArrayDeque<AccessibilityNodeInfo>()
        automation.rootInActiveWindow?.let(pending::add)
        var count = 0
        while (pending.isNotEmpty() && count++ < 5_000) {
            val value = pending.removeFirst()
            if (value.isVisibleToUser && (!clickable || value.isClickable) &&
                (value.text?.toString() == label || value.contentDescription?.toString() == label)) return value
            for (index in 0 until value.childCount) value.getChild(index)?.let(pending::add)
        }
        return null
    }

    private fun saveScreen(name: String) {
        val instrumentation = InstrumentationRegistry.getInstrumentation()
        val path = File(instrumentation.targetContext.getExternalFilesDir(null), "S02/$name")
        path.parentFile!!.mkdirs()
        val image = instrumentation.uiAutomation.takeScreenshot() ?: return
        try { path.outputStream().use { image.compress(Bitmap.CompressFormat.PNG, 100, it) } }
        finally { image.recycle() }
    }
}
