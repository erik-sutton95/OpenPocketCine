package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.opencine.cameracontrols.MonitorLegalDocumentScreen
import com.opencapture.opencine.cameracontrols.MonitorLegalPage
import com.opencapture.openpocketcine.media.MediaLibraryScreen

enum class AppPanel {
    SETTINGS,
    MEDIA,
    PRIVACY,
}

@Composable
fun AppPanelHost(model: AppModel) {
    when (model.homePanel) {
        AppPanel.SETTINGS -> ShellCoverPage(model, ShellModel.Cover.SETTINGS)
        AppPanel.MEDIA -> ShellCoverPage(model, ShellModel.Cover.MEDIA)
        AppPanel.PRIVACY -> MonitorLegalDocumentScreen(PocketLegalDocuments, MonitorLegalPage.PRIVACY) { model.homePanel = null }
        null -> Unit
    }
}

/** Native page content over navigation and monitor ownership supplied by the shared shell. */
@Composable
internal fun ShellCoverPage(model: AppModel, cover: ShellModel.Cover) {
    when (cover) {
        ShellModel.Cover.SETTINGS -> OperatorSetupScreen(model) { model.shell.dismissCover() }
        ShellModel.Cover.MEDIA -> MediaLibraryScreen(model) { model.shell.dismissCover() }
    }
}
