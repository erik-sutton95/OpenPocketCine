package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import com.opencapture.opencine.appkit.ShellModel
import com.opencapture.openpocketcine.media.MediaLibraryScreen

enum class AppPanel {
    SETTINGS,
    MEDIA,
    PRIVACY,
    TERMS,
    LICENSES,
    NOTICE,
}

@Composable
fun AppPanelHost(model: AppModel) {
    when (model.homePanel) {
        AppPanel.SETTINGS -> ShellCoverPage(model, ShellModel.Cover.SETTINGS)
        AppPanel.MEDIA -> ShellCoverPage(model, ShellModel.Cover.MEDIA)
        AppPanel.PRIVACY -> LegalDocumentScreen(LegalKind.PRIVACY) { model.homePanel = null }
        AppPanel.TERMS -> LegalDocumentScreen(LegalKind.TERMS) { model.homePanel = null }
        AppPanel.LICENSES -> LegalDocumentScreen(LegalKind.LICENSES) { model.homePanel = null }
        AppPanel.NOTICE -> LegalDocumentScreen(LegalKind.NOTICE) { model.homePanel = null }
        null -> Unit
    }
}

@Composable
fun MediaLibraryHost(model: AppModel) {
    MediaLibraryScreen(model) { model.homePanel = null }
}

/** Native page content over navigation and monitor ownership supplied by the shared shell. */
@Composable
internal fun ShellCoverPage(model: AppModel, cover: ShellModel.Cover) {
    when (cover) {
        ShellModel.Cover.SETTINGS -> OperatorSetupScreen(model) { model.shell.dismissCover() }
        ShellModel.Cover.MEDIA -> MediaLibraryScreen(model) { model.shell.dismissCover() }
    }
}
