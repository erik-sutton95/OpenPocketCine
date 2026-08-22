package com.opencapture.openpocketcine

import androidx.activity.compose.BackHandler
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.safeDrawing
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp

enum class LegalKind(val title: String) {
    PRIVACY("Privacy"),
    TERMS("Terms"),
    LICENSES("Licenses"),
    NOTICE("NOTICE"),
    ;

    val body: String
        get() =
            when (this) {
                PRIVACY -> PRIVACY_BODY
                TERMS -> TERMS_BODY
                LICENSES -> LICENSES_BODY
                NOTICE -> NOTICE_BODY
            }
}

@Composable
fun LegalDocumentScreen(
    kind: LegalKind,
    onClose: () -> Unit,
) {
    BackHandler(onBack = onClose)
    val shape = RoundedCornerShape(LiveDesign.CORNER_RADIUS_DP.dp)
    Box(
        Modifier
            .fillMaxSize()
            .background(LiveDesign.background)
            .windowInsetsPadding(WindowInsets.safeDrawing),
    ) {
        Column(
            Modifier
                .fillMaxSize()
                .padding(start = 16.dp, end = 16.dp, top = 14.dp, bottom = 12.dp),
        ) {
            Column(Modifier.padding(start = 45.dp)) {
                Text(
                    "OPENPOCKETCINE",
                    style = LiveType.ui(9.5f, FontWeight.Bold).copy(letterSpacing = 0.8.sp),
                    color = LiveDesign.accent,
                )
                Text(
                    kind.title,
                    style = LiveType.title(24f, FontWeight.SemiBold),
                    color = LiveDesign.text,
                )
            }
            Spacer(Modifier.height(12.dp))
            Text(
                kind.body,
                style = LiveType.ui(14f, FontWeight.Normal).copy(lineHeight = 19.sp),
                color = LiveDesign.text,
                modifier =
                    Modifier
                        .fillMaxWidth()
                        .weight(1f)
                        .verticalScroll(rememberScrollState())
                        .background(LiveDesign.surface, shape)
                        .border(1.dp, LiveDesign.hairline, shape)
                        .padding(16.dp),
            )
        }
        OperatorCloseButton(
            onClose = onClose,
            modifier =
                Modifier
                    .align(Alignment.TopStart)
                    .padding(start = 16.dp, top = 16.dp),
        )
    }
}

private val PRIVACY_BODY =
    """
OpenPocketCine talks to your Osmo Pocket over Bluetooth and the camera's own Wi-Fi. It does not create an account, and it does not send analytics, crash reports, or camera footage to us.

What stays on this phone
• Saved camera names and last SSID. The camera Wi-Fi password is stored in the Android Keystore on this phone only.
• Operator preferences such as Keep Screen Awake and the last LUT look.
• Imported .cube files you choose to open.

What never leaves the phone
• Live HEVC, DUML telemetry, and pairing traffic stay on the local link. We do not operate a cloud.

Third parties
• Apple (or Google) may process permission prompts and OS diagnostics under their own policies. TestFlight or Play betas may send crash reports to the developer under Apple or Google terms.
• Frame.io is optional. If this build is configured and you sign in, clips you pick upload device → Adobe. The token stays in the on-device Keystore.
• Saving a clip or using the share sheet is something you start. Apple or the app you pick then handles that file.
• AF-C face boxes are computed on this phone from the live preview. Face geometry is not uploaded.
• The source is at github.com/erik-sutton95/OpenPocketCine.

Android may ask for location so the app can join the camera Wi-Fi or scan BLE. OpenPocketCine does not use that permission for maps, ads, or a location history.

This is not legal advice. The canonical website policy is https://openpocketcine.app/privacy/
    """.trimIndent()

private val TERMS_BODY =
    """
OpenPocketCine is free software under the Apache License 2.0. You may use, modify, and share it under that license.

This is an unofficial field monitor. It is not affiliated with, endorsed by, or supported by DJI. "DJI", "Osmo", and "Osmo Pocket" are trademarks of SZ DJI Technology Co., Ltd., used only to identify the cameras the app can talk to.

Reverse-engineered protocol behavior can be incomplete or wrong. Do not rely on this app as the only way to start or stop a take — record from the camera body until those commands are proven.

The software is provided on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See LICENSE in the repository.

By using the app you agree to follow the Code of Conduct when participating in the project.
    """.trimIndent()

private val LICENSES_BODY =
    """
OpenPocketCine
Copyright 2026 Erik Sutton and OpenPocketCine contributors

Licensed under the Apache License, Version 2.0. You may obtain a copy of the License at:

http://www.apache.org/licenses/LICENSE-2.0

The portable .cube parser (CubeLUT) is adapted from OpenZCine, also Apache 2.0.

HUD icons are Lucide (ISC; some glyphs also MIT from Feather). See THIRD-PARTY-NOTICES.

I learned the BLE pairing and camera Wi-Fi connection path with the help of Osmosis by Konrad Iturbe, and I'm grateful. OpenPocketCine is its own implementation. The field-monitor architecture follows OpenZCine.

No DJI SDK is included or required.

Full license text: LICENSE in the repository. Attribution: NOTICE.
    """.trimIndent()

private val NOTICE_BODY =
    """
OpenPocketCine
Copyright 2026 Erik Sutton and OpenPocketCine contributors

This product is licensed under the Apache License, Version 2.0 (see LICENSE).
The portable .cube parser (`CubeLUT`) is adapted from OpenZCine (Apache 2.0).
HUD icons are Lucide (ISC; Feather-derived glyphs also MIT).

This project is not affiliated with or endorsed by SZ DJI Technology Co., Ltd.
"DJI", "Osmo", "Osmo Pocket", and "Mimo" are trademarks of SZ DJI Technology Co., Ltd.,
used for identification only.
No DJI SDK or proprietary DJI documentation is included in, distributed with, or required
by this project.
    """.trimIndent()
