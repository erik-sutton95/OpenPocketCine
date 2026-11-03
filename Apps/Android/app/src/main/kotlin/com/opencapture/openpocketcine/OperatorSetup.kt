package com.opencapture.openpocketcine

import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import com.opencapture.opencine.cameracontrols.OperatorAppInformation
import com.opencapture.opencine.cameracontrols.OperatorDiagnostics
import com.opencapture.opencine.cameracontrols.OperatorHelpCopy
import com.opencapture.opencine.cameracontrols.OperatorLinkSample
import com.opencapture.opencine.cameracontrols.OperatorSetupApp
import com.opencapture.opencine.cameracontrols.OperatorSetupState
import com.opencapture.opencine.cameracontrols.formatAppVersion
import com.opencapture.openpocketcine.assists.AppAssistHost
import com.opencapture.openpocketcine.diagnostics.AppDiagnostics
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter
import com.opencapture.opencine.runtime.MonitorGlesUpscaler
import com.opencapture.openpocketcine.lut.LUTPicker
import com.opencapture.openpocketcine.settings.PanelCloseButton

object SettingsHelpCopy : OperatorHelpCopy("OpenPocketCine")

object OpenPocketCineLinks {
    const val SOURCE = "https://github.com/erik-sutton95/OpenPocketCine"
    const val SUPPORT = "https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/q-a"
    const val REPORT_PROBLEM =
        "https://github.com/erik-sutton95/OpenPocketCine/issues/new?template=bug_report.yml"
    const val FEATURE_REQUEST =
        "https://github.com/erik-sutton95/OpenPocketCine/discussions/new?category=ideas"
    const val PRIVACY = "https://openpocketcine.app/privacy/"
    const val TERMS = "https://openpocketcine.app/terms/"
}

internal fun lutPickerAvailable(): Boolean = true

/** The link and body Operator Setup shows, from this app's session. */
@Composable
internal fun AppModel.operatorSetupState(): OperatorSetupState {
    val phase by session.phaseFlow.collectAsState()
    val failure by session.failure.collectAsState()
    val status by session.chromeStatus.collectAsState()
    val camera = session.connectedCamera
    return OperatorSetupState(phase, failure, status.monitorColorMode, session.joinedSSID, camera?.name,
        camera?.model?.family, remember(status) { monitorLayout() },
        lookProfile = camera?.model?.captureProfile?.looks ?: com.opencapture.opencine.dji.DjiCameraLUTProfile.make("pocket", null),
        monitorPresented = isLive)
}

/** Pocket's copy, links, stores and pages, as on main. */
internal fun operatorSetupApp(model: AppModel) = OperatorSetupApp(
    wordmark = "OPENPOCKETCINE",
    help = SettingsHelpCopy,
    prefs = OperatorPrefs,
    assistHost = AppAssistHost,
    upscalers = MonitorGlesUpscaler.supported.map { it.label },
    upscaler = { OperatorPrefs.feedUpscaler(it).label },
    setUpscaler = { context, label -> OperatorPrefs.setFeedUpscaler(context, MonitorGlesUpscaler.fromStored(label)) },
    linkSample = {
        val session = model.session
        OperatorLinkSample(session.decoder.framesEnqueued.get(), session.decoder.lastPresentedAt,
            session.videoPackets, session.hasVideoFormat)
    },
    information = OperatorAppInformation(
        theme = "DJI Black", themeHelp = SettingsHelpCopy.THEME,
        protocol = "DUML / BLE + Wi-Fi", protocolHelp = model.applicationContext.getString(R.string.settings_protocol_help),
        version = formatAppVersion(BuildConfig.VERSION_NAME, BuildConfig.VERSION_CODE.toLong()),
        versionHelp = SettingsHelpCopy.APP_VERSION, termsHelp = model.applicationContext.getString(R.string.settings_terms_help),
    ),
    sourceUrl = OpenPocketCineLinks.SOURCE,
    diagnostics = OperatorDiagnostics(
        AppDiagnostics.reporting, AppDiagnostics.manualReport, AppDiagnostics.incidents,
        diagnosticText = { DiagnosticCenter.boundedDiagnosticText(model.session) },
        shareReport = { DiagnosticCenter.shareReport(it, model.session, copyForFeedback = false) },
    ),
    reportProblem = { model.problemReportOpen = true },
    legal = PocketLegalDocuments,
    lutPicker = { onClose -> LUTPicker(model = model, onClose = onClose) },
    cacheSource = {
        // Every camera bucket, retaining the current gallery's operation fencing and revision.
        val shell by model.shell.state.collectAsState()
        key(shell.monitor?.id) { com.opencapture.opencine.cameracontrols.monitorSettingsCacheSource(model.mediaController().library, model.mediaCacheRoot) }
    },
)

@Composable
fun OperatorSetupScreen(model: AppModel, onClose: () -> Unit) {
    CompositionLocalProvider(LocalMonitorGlass provides null) {
        com.opencapture.opencine.cameracontrols.OperatorSetupScreen(
            model, model.operatorSetupState(), remember(model) { operatorSetupApp(model) }, onClose)
    }
}

@Composable
fun OperatorCloseButton(onClose: () -> Unit, modifier: Modifier = Modifier) {
    PanelCloseButton(onClick = onClose, modifier = modifier)
}
