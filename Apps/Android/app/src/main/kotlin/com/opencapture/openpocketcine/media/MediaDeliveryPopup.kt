package com.opencapture.openpocketcine.media

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.platform.LocalContext
import com.opencapture.opencine.appkit.MediaShare
import com.opencapture.opencine.appkit.MonitorDeliveryExportService
import com.opencapture.opencine.appkit.MonitorDeliveryFileFacts
import com.opencapture.opencine.appkit.MonitorDeliveryOriginalService
import com.opencapture.opencine.cameracontrols.MonitorOriginalDeliveryHost
import com.opencapture.opencine.cameracontrols.MonitorOriginalDeliverySource
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaHTTP

/** The app's gallery share namespace; the root chrome presents what a delivery run prepared. */
val PocketMediaShare = MediaShare(album = "OpenPocketCine")

/** Captured canonical original IO only; the app-scoped coordinator owns every run. */
@Composable
fun MediaDeliveryHost(
    files: List<MediaFile>?, controller: MediaLibraryController, onDismissPopup: () -> Unit,
    onPresentationChange: (Boolean) -> Unit = {},
) {
    val context = LocalContext.current.applicationContext
    val source = remember(controller) {
        MonitorOriginalDeliverySource(controller.library, controller::record,
            fileFacts = { MonitorDeliveryFileFacts(it.filename, it.sizeBytes.takeIf { bytes -> bytes > 0 }) },
            connected = { controller.isLive },
            originals = MonitorDeliveryOriginalService(controller::isDownloaded,
                acquire = controller::download, progress = { controller.downloadProgress[it.path] }),
            // No native conversion service was advertised on this platform; the true original is delivered.
            exporter = MonitorDeliveryExportService { file, _ -> controller.localFile(file) })
    }
    val photos = remember(context) { PocketMediaShare.photos(context) { MediaHTTP.playbackMIMEType(it.name) } }
    MonitorOriginalDeliveryHost(files, source, photos, onDismissPopup, onPresentationChange)
}
