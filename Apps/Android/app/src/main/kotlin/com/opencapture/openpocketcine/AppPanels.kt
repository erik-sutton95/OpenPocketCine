package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
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
        AppPanel.SETTINGS -> OperatorSetupScreen(model) { model.homePanel = null }
        AppPanel.MEDIA -> MediaLibraryHost(model)
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
