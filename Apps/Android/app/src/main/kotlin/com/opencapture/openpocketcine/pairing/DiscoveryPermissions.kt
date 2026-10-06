package com.opencapture.openpocketcine.pairing

import androidx.compose.runtime.Composable
import com.opencapture.opencine.appkit.PermissionGate
import com.opencapture.openpocketcine.diagnostics.DiagnosticCenter

/** Saved "denied before" answers; existing installs keep theirs. */
private const val PERMISSIONS_PREFERENCES = "openpocketcine.permissions"

/** OpenCine's permission gate with this app's saved answers and diagnostics log. */
@Composable
fun rememberPermissionGate(
    label: String,
    needed: List<String>,
    request: List<String> = needed,
    onGranted: () -> Unit = {},
): PermissionGate =
    com.opencapture.opencine.appkit.rememberPermissionGate(
        label, needed, PERMISSIONS_PREFERENCES,
        log = { DiagnosticCenter.log("info", "permissions", label, it) },
        request = request, onGranted = onGranted,
    )
