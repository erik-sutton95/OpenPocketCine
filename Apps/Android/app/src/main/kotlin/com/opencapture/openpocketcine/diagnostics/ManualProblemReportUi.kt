package com.opencapture.openpocketcine.diagnostics

import androidx.compose.runtime.Composable
import com.opencapture.openpocketcine.AppModel

/** OpenCine's problem report form over this app's report and session diagnostics. */
@Composable
internal fun ManualProblemReportDialog(model: AppModel, onClose: () -> Unit, onPrivacy: () -> Unit) =
    com.opencapture.opencine.appkit.diagnostics.ManualProblemReportDialog(
        AppDiagnostics.manualReport, { DiagnosticCenter.boundedDiagnosticText(model.session) },
        actionMinimumTouchTarget = false, onClose = onClose, onPrivacy = onPrivacy,
    )
