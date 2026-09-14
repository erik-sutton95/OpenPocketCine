package com.opencapture.openpocketcine.diagnostics

import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.AlertDialog
import androidx.compose.material3.OutlinedTextField
import androidx.compose.material3.OutlinedTextFieldDefaults
import androidx.compose.material3.Text
import androidx.compose.material3.TextButton
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Dialog
import com.opencapture.openpocketcine.AppModel
import com.opencapture.openpocketcine.ChromeShape
import com.opencapture.openpocketcine.LiveDesign
import com.opencapture.openpocketcine.LiveType
import com.opencapture.openpocketcine.SettingsHelpCopy
import com.opencapture.openpocketcine.settings.SettingsActionPill
import com.opencapture.openpocketcine.settings.SettingsSwitchGraphic
import com.opencapture.openpocketcine.settings.settingsClickable
import androidx.compose.ui.semantics.Role

@Composable
internal fun ManualProblemReportDialog(
    model: AppModel,
    onClose: () -> Unit,
    onPrivacy: () -> Unit,
) {
    if (!ManualProblemReport.isConfigured()) {
        AlertDialog(
            onDismissRequest = onClose,
            title = { Text("Report unavailable", color = LiveDesign.text) },
            text = {
                Text(
                    "This build cannot send a report. You can still save a diagnostic report under Diagnostic options.",
                    color = LiveDesign.muted,
                )
            },
            confirmButton = {
                TextButton(onClick = onClose) { Text("OK", color = LiveDesign.accent) }
            },
            containerColor = LiveDesign.surface,
        )
        return
    }
    val report by ManualProblemReport.snapshot.collectAsState()
    var message by remember { mutableStateOf("") }
    var email by remember { mutableStateOf("") }
    var includeTech by remember { mutableStateOf(false) }
    var preview by remember { mutableStateOf("") }
    var error by remember { mutableStateOf<String?>(null) }
    LaunchedEffect(includeTech) {
        preview =
            if (includeTech) DiagnosticCenter.boundedDiagnosticText(model.session) else ""
    }
    Dialog(onDismissRequest = onClose) {
        Column(
            Modifier
                .fillMaxWidth()
                .heightIn(max = 640.dp)
                .background(LiveDesign.surface, ChromeShape)
                .border(1.dp, LiveDesign.hairline, ChromeShape)
                .padding(16.dp)
                .verticalScroll(rememberScrollState()),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text(
                "Report a problem",
                style = LiveType.ui(16f, FontWeight.SemiBold),
                color = LiveDesign.text,
            )
            Text(
                SettingsHelpCopy.REPORT_PROBLEM,
                style = LiveType.ui(12f, FontWeight.Normal),
                color = LiveDesign.muted,
            )
            if (!report.allowsNewSubmit) {
                Text(
                    "${report.statusLabel}${report.eventId?.let { " · $it" } ?: ""}",
                    style = LiveType.mono(11f, FontWeight.Medium),
                    color = LiveDesign.accent,
                )
                Text(
                    "Discard the queued report before sending another.",
                    style = LiveType.ui(12f, FontWeight.Normal),
                    color = LiveDesign.muted,
                )
            } else {
                val fieldColors =
                    OutlinedTextFieldDefaults.colors(
                        focusedTextColor = LiveDesign.text,
                        unfocusedTextColor = LiveDesign.text,
                        focusedBorderColor = LiveDesign.accent,
                        unfocusedBorderColor = LiveDesign.hairline,
                        focusedLabelColor = LiveDesign.accent,
                        unfocusedLabelColor = LiveDesign.muted,
                        cursorColor = LiveDesign.accent,
                    )
                OutlinedTextField(
                    value = message,
                    onValueChange = { message = it.take(ManualProblemReport.MESSAGE_MAX) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("What happened?") },
                    supportingText = {
                        Text("${message.length}/${ManualProblemReport.MESSAGE_MAX}", color = LiveDesign.faint)
                    },
                    minLines = 4,
                    maxLines = 8,
                    colors = fieldColors,
                )
                OutlinedTextField(
                    value = email,
                    onValueChange = { email = it.take(ManualProblemReport.EMAIL_MAX) },
                    modifier = Modifier.fillMaxWidth(),
                    label = { Text("Reply email (optional)") },
                    supportingText = {
                        Text("${email.length}/${ManualProblemReport.EMAIL_MAX}", color = LiveDesign.faint)
                    },
                    singleLine = true,
                    colors = fieldColors,
                )
                Row(
                    Modifier
                        .fillMaxWidth()
                        .settingsClickable(role = Role.Switch) { includeTech = !includeTech },
                    verticalAlignment = Alignment.CenterVertically,
                    horizontalArrangement = Arrangement.spacedBy(10.dp),
                ) {
                    Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(2.dp)) {
                        Text(
                            "Include technical details",
                            style = LiveType.ui(13f, FontWeight.SemiBold),
                            color = LiveDesign.text,
                        )
                        Text(
                            "Off by default. Review the preview before sending. No footage or screenshots.",
                            style = LiveType.ui(11f, FontWeight.Normal),
                            color = LiveDesign.muted,
                        )
                    }
                    SettingsSwitchGraphic(isOn = includeTech)
                }
                if (includeTech && preview.isNotEmpty()) {
                    Text(
                        "Technical details preview",
                        style = LiveType.ui(11f, FontWeight.SemiBold),
                        color = LiveDesign.muted,
                    )
                    Text(
                        preview,
                        style = LiveType.mono(10f),
                        color = LiveDesign.text,
                        modifier =
                            Modifier
                                .fillMaxWidth()
                                .background(LiveDesign.background.copy(alpha = 0.5f), ChromeShape)
                                .padding(8.dp),
                    )
                }
            }
            Text(
                "OpenCapture receives this through Sentry. Sending does not turn on automatic reports. Do not include passwords or private footage.",
                style = LiveType.ui(11f, FontWeight.Normal),
                color = LiveDesign.muted,
            )
            error?.let {
                Text(it, style = LiveType.ui(12f, FontWeight.SemiBold), color = LiveDesign.rec)
            }
            Row(
                Modifier.fillMaxWidth(),
                horizontalArrangement = Arrangement.spacedBy(8.dp, Alignment.End),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                TextButton(onClick = onPrivacy) {
                    Text("Reporting Privacy", color = LiveDesign.muted)
                }
                SettingsActionPill("Cancel", tint = LiveDesign.muted, background = LiveDesign.faint.copy(alpha = 0.2f), onClick = onClose)
                if (report.allowsNewSubmit) {
                    SettingsActionPill("Send report") {
                        if (includeTech && preview.isBlank()) {
                            error = "Technical details are not ready. Wait, or turn them off to send your description."
                            return@SettingsActionPill
                        }
                        when (
                            ManualProblemReport.submit(
                                message = message,
                                replyEmail = email,
                                diagnostics =
                                    if (includeTech) {
                                        preview
                                    } else {
                                        null
                                    },
                            )
                        ) {
                            ManualSubmitResult.QUEUED -> onClose()
                            ManualSubmitResult.INVALID ->
                                error = "Add a description and check the optional email address."
                            ManualSubmitResult.UNAVAILABLE ->
                                error = "This build cannot send a report."
                            ManualSubmitResult.STORAGE_ERROR ->
                                error = "Could not save this report. Your text is still here; please try again."
                            ManualSubmitResult.PENDING_EXISTS ->
                                error = "A report is already waiting to send."
                        }
                    }
                } else if (report.allowsDiscard) {
                    SettingsActionPill("Discard") {
                        ManualProblemReport.discard()
                        onClose()
                    }
                }
            }
        }
    }
}

@Composable
internal fun AutomaticReportsPrompt(
    onPrivacy: () -> Unit,
    onEnable: () -> Unit,
    onNotNow: () -> Unit,
) {
    AlertDialog(
        onDismissRequest = {},
        title = { Text("Help improve OpenPocketCine", color = LiveDesign.text) },
        text = {
            Column(verticalArrangement = Arrangement.spacedBy(8.dp)) {
                Text(
                    "Optional crash, error and feed-dropout reports are used only to improve app stability and reliability. Sent to OpenCapture through Sentry. No footage, screenshots or GPS location. You can change this in System.",
                    color = LiveDesign.muted,
                )
                TextButton(onClick = onPrivacy) {
                    Text("Reporting privacy", color = LiveDesign.accent)
                }
            }
        },
        confirmButton = {
            TextButton(onClick = onEnable) { Text("Enable automatic reports", color = LiveDesign.accent) }
        },
        dismissButton = {
            TextButton(onClick = onNotNow) { Text("Not now", color = LiveDesign.muted) }
        },
        containerColor = LiveDesign.surface,
    )
}
