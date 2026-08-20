package com.opencapture.openpocketcine

import android.content.Context
import android.content.Intent
import android.net.Uri
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Switch
import androidx.compose.material3.SwitchDefaults
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import com.opencapture.openpocketcine.pairing.StartupColors
import com.opencapture.openpocketcine.pairing.startupBackdrop
import com.opencapture.openpocketcine.pairing.startupCard

enum class AppPanel {
    SETTINGS,
    MEDIA,
    PRIVACY,
    TERMS,
    LICENSES,
}

@Composable
fun AppPanelHost(model: AppModel) {
    when (model.homePanel) {
        AppPanel.SETTINGS -> AppSettingsScreen(model)
        AppPanel.MEDIA -> MediaLibraryStubScreen(model)
        AppPanel.PRIVACY -> LegalScreen(model, LegalKind.PRIVACY)
        AppPanel.TERMS -> LegalScreen(model, LegalKind.TERMS)
        AppPanel.LICENSES -> LegalScreen(model, LegalKind.LICENSES)
        null -> Unit
    }
}

@Composable
private fun AppPanelChrome(title: String, onClose: () -> Unit, content: @Composable () -> Unit) {
    Column(Modifier.fillMaxSize().startupBackdrop().padding(top = 16.dp, bottom = 16.dp)) {
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Column(Modifier.weight(1f)) {
                Text(
                    "OPENPOCKETCINE",
                    color = StartupColors.muted,
                    fontSize = 10.sp,
                    fontWeight = FontWeight.SemiBold,
                    letterSpacing = 1.3.sp,
                )
                Text(title, color = StartupColors.ink, fontSize = 17.sp, fontWeight = FontWeight.Bold)
            }
            Box(
                Modifier
                    .clip(RoundedCornerShape(16.dp))
                    .background(StartupColors.accent)
                    .clickable(onClick = onClose)
                    .padding(horizontal = 18.dp, vertical = 10.dp),
            ) {
                Text("Done", color = StartupColors.darkText, fontSize = 16.sp, fontWeight = FontWeight.SemiBold)
            }
        }
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(horizontal = 20.dp, vertical = 12.dp),
            verticalArrangement = Arrangement.spacedBy(16.dp),
        ) {
            content()
        }
    }
}

@Composable
private fun AppSettingsScreen(model: AppModel) {
    val context = LocalContext.current
    AppPanelChrome("Settings", onClose = { model.homePanel = null }) {
        SettingsCard("App behavior") {
            Row(verticalAlignment = Alignment.CenterVertically) {
                Column(Modifier.weight(1f).padding(end = 12.dp)) {
                    Text("Keep Screen Awake", color = StartupColors.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text(
                        "Stops the phone sleeping while OpenPocketCine is open. A monitor should stay lit.",
                        color = StartupColors.muted,
                        fontSize = 12.sp,
                    )
                }
                Switch(
                    checked = model.keepScreenAwake,
                    onCheckedChange = { model.updateKeepScreenAwake(it) },
                    colors =
                        SwitchDefaults.colors(
                            checkedThumbColor = StartupColors.darkText,
                            checkedTrackColor = StartupColors.accent,
                        ),
                )
            }
        }
        SettingsCard("App information") {
            InfoRow("Theme", "Warm Dark")
            InfoRow("Protocol Implementation", "DUML / BLE + Wi-Fi")
            InfoRow("App Version", appVersionText(context))
        }
        SettingsCard("Project & legal") {
            NavRow("Privacy", "What this app stores on this phone.") { model.homePanel = AppPanel.PRIVACY }
            NavRow("Terms", "How you can use OpenPocketCine.") { model.homePanel = AppPanel.TERMS }
            NavRow("Licenses", "Apache 2.0 and third-party notices.") { model.homePanel = AppPanel.LICENSES }
            val source = Uri.parse("https://github.com/erik-sutton95/OpenPocketCine")
            Row(
                Modifier.fillMaxWidth().clickable {
                    context.startActivity(Intent(Intent.ACTION_VIEW, source))
                }.padding(vertical = 8.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Column(Modifier.weight(1f)) {
                    Text("Source Code", color = StartupColors.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
                    Text("github.com/erik-sutton95/OpenPocketCine", color = StartupColors.muted, fontSize = 12.sp)
                }
                Text("↗", color = StartupColors.dim, fontSize = 14.sp)
            }
        }
    }
}

@Composable
private fun MediaLibraryStubScreen(model: AppModel) {
    AppPanelChrome("Media library", onClose = { model.homePanel = null }) {
        Text("Your clips.", color = StartupColors.ink, fontSize = 30.sp, fontWeight = FontWeight.Bold)
        Text(
            "Clip review needs the DJI file protocol, which is not in the live-view capture. Nothing is listed, and nothing is deleted.",
            color = StartupColors.muted,
            fontSize = 14.sp,
        )
        Column(
            Modifier.fillMaxWidth().startupCard().padding(18.dp),
            verticalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            Text("ALL  ·  VIDEOS  ·  PHOTOS", color = StartupColors.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)
            Text("No clips on this phone", color = StartupColors.ink, fontSize = 17.sp, fontWeight = FontWeight.SemiBold)
            Text(
                "Record from the camera body. When a labeled Mimo media capture exists, this grid will fill in.",
                color = StartupColors.muted,
                fontSize = 13.sp,
            )
        }
    }
}

private enum class LegalKind(val title: String, val body: String) {
    PRIVACY(
        "Privacy",
        """
        OpenPocketCine talks to your Osmo Pocket over Bluetooth and the camera's own Wi-Fi. It does not create an account, and it does not send analytics, crash reports, or camera footage to us.

        What stays on this phone
        • Saved camera names and last SSID.
        • Operator preferences such as Keep Screen Awake.

        What never leaves the phone
        • Live HEVC, DUML telemetry, and pairing traffic stay on the local link.

        Android may ask for location so the app can join the camera Wi-Fi or scan BLE. OpenPocketCine does not use that permission for maps, ads, or a location history.

        The canonical privacy policy is https://openpocketcine.app/privacy/
        The source is at github.com/erik-sutton95/OpenPocketCine.
        """.trimIndent(),
    ),
    TERMS(
        "Terms",
        """
        OpenPocketCine is free software under the Apache License 2.0.

        This is an unofficial field monitor. It is not affiliated with DJI. Record from the camera body until start/stop commands are proven.

        The software is provided on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See LICENSE in the repository.
        """.trimIndent(),
    ),
    LICENSES(
        "Licenses",
        """
        OpenPocketCine
        Copyright 2026 Erik Sutton and OpenPocketCine contributors

        Licensed under the Apache License, Version 2.0.

        CubeLUT is adapted from OpenZCine (Apache 2.0). I learned BLE pairing and camera Wi-Fi connection with the help of Osmosis by Konrad Iturbe, and I'm grateful. No DJI SDK is included.

        Full license text: LICENSE. Attribution: NOTICE.
        """.trimIndent(),
    ),
}

@Composable
private fun LegalScreen(model: AppModel, kind: LegalKind) {
    AppPanelChrome(kind.title, onClose = { model.homePanel = null }) {
        Text(
            kind.body,
            color = StartupColors.ink,
            fontSize = 14.sp,
            modifier = Modifier.fillMaxWidth().startupCard().padding(18.dp),
        )
    }
}

@Composable
private fun SettingsCard(title: String, content: @Composable () -> Unit) {
    Column(
        Modifier.fillMaxWidth().startupCard().padding(18.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(title.uppercase(), color = StartupColors.muted, fontSize = 11.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.4.sp)
        content()
    }
}

@Composable
private fun InfoRow(title: String, value: String) {
    Row(Modifier.fillMaxWidth().padding(vertical = 6.dp), verticalAlignment = Alignment.CenterVertically) {
        Text(title, color = StartupColors.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold, modifier = Modifier.weight(1f))
        Text(value, color = StartupColors.muted, fontSize = 14.sp)
    }
}

@Composable
private fun NavRow(title: String, help: String, onClick: () -> Unit) {
    Column(Modifier.fillMaxWidth().clickable(onClick = onClick).padding(vertical = 8.dp)) {
        Text(title, color = StartupColors.ink, fontSize = 15.sp, fontWeight = FontWeight.SemiBold)
        Text(help, color = StartupColors.muted, fontSize = 12.sp)
    }
}

private fun appVersionText(context: Context): String {
    val info =
        runCatching {
            context.packageManager.getPackageInfo(context.packageName, 0)
        }.getOrNull()
    val version = info?.versionName ?: "0.1"
    val code =
        if (android.os.Build.VERSION.SDK_INT >= 28) {
            info?.longVersionCode?.toString() ?: "1"
        } else {
            @Suppress("DEPRECATION")
            info?.versionCode?.toString() ?: "1"
        }
    return "$version ($code)"
}
