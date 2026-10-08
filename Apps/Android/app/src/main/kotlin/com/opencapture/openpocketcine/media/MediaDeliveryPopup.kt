package com.opencapture.openpocketcine.media

import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import com.opencapture.opencine.appkit.MediaShare
import com.opencapture.opencine.appkit.MonitorDeliveryExportService
import com.opencapture.opencine.appkit.MonitorDeliveryFileFacts
import com.opencapture.opencine.appkit.MonitorDeliveryOriginalService
import com.opencapture.opencine.cameracontrols.MonitorOperatorDeliveryHost
import com.opencapture.opencine.cameracontrols.MonitorOriginalDeliverySource
import com.opencapture.opencine.vocabulary.MediaFile
import com.opencapture.opencine.vocabulary.MediaHTTP

/** Captured canonical original IO and existing OS namespace only. */
@Composable
fun MediaDeliveryHost(
    files: List<MediaFile>?, controller: MediaLibraryController, onDismissPopup: () -> Unit,
    onPresentationChange: (Boolean) -> Unit = {},
) {
    val source = remember(controller) {
        MonitorOriginalDeliverySource(controller.library, controller::record,
            fileFacts = { MonitorDeliveryFileFacts(it.filename, it.sizeBytes.takeIf { bytes -> bytes > 0 }) },
            connected = { controller.isLive },
            originals = MonitorDeliveryOriginalService(controller::isDownloaded,
                acquire = controller::download, progress = { controller.downloadProgress[it.path] }),
            // No native conversion service was advertised on this platform; the true original is delivered.
            exporter = MonitorDeliveryExportService { file, _ -> controller.localFile(file) })
    }
    val share = remember { MediaShare(album = "OpenPocketCine") }
    MonitorOperatorDeliveryHost(files, source, share, MediaHTTP::playbackMIMEType,
        onDismissPopup, onPresentationChange)
}
