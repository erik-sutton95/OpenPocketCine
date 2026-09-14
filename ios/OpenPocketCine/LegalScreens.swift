import SwiftUI

/// In-app legal pages. Canonical website copy lives at openpocketcine.app/privacy and /terms.
struct LegalDocumentView: View {
    @Environment(AppModel.self) private var model
    let kind: Kind
    var onClose: (() -> Void)? = nil

    var body: some View {
        GeometryReader { proxy in
            let insets = proxy.safeAreaInsets

            ZStack(alignment: .topLeading) {
                LiveDesign.background

                VStack(alignment: .leading, spacing: 12) {
                    VStack(alignment: .leading, spacing: 3) {
                        Text("OpenPocketCine")
                            .font(LiveType.ui(size: 9.5, weight: .bold))
                            .kerning(0.8)
                            .foregroundStyle(LiveDesign.accent)
                            .textCase(.uppercase)
                            .padding(
                                .leading,
                                OperatorPanelMetrics.closeButtonClearance(safeArea: insets))
                        Text(kind.title)
                            .font(LiveType.ui(size: 24, weight: .semibold))
                            .foregroundStyle(LiveDesign.text)
                            .padding(
                                .leading,
                                OperatorPanelMetrics.closeButtonClearance(safeArea: insets))
                    }

                    ScrollView {
                        Text(kind.body)
                            .font(LiveType.ui(size: 14, weight: .regular))
                            .foregroundStyle(LiveDesign.text)
                            .lineSpacing(5)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(16)
                            .background(
                                LiveDesign.surface,
                                in: RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                            )
                            .overlay(
                                RoundedRectangle(cornerRadius: LiveDesign.cornerRadius)
                                    .stroke(LiveDesign.hairline, lineWidth: 1)
                            )
                    }
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
                .padding(.top, OperatorPanelMetrics.topPadding(safeArea: insets))
                .padding(.leading, OperatorPanelMetrics.leadingPadding(safeArea: insets))
                .padding(.trailing, OperatorPanelMetrics.trailingPadding(safeArea: insets))
                .padding(.bottom, OperatorPanelMetrics.bottomPadding(safeArea: insets))

                CloseButton(action: dismiss, size: OperatorPanelMetrics.closeSize)
                    .padding(.leading, OperatorPanelMetrics.closeLeading)
                    .padding(.top, OperatorPanelMetrics.closeTopPadding(safeArea: insets))
            }
            .ignoresSafeArea()
        }
        .preferredColorScheme(.dark)
    }

    private func dismiss() {
        if let onClose {
            onClose()
        } else {
            model.homePanel = nil
        }
    }

    enum Kind: String, Identifiable {
        case privacy, terms, licenses, notice
        var id: String { rawValue }

        var title: String {
            switch self {
            case .privacy: "Privacy"
            case .terms: "Terms"
            case .licenses: "Licenses"
            case .notice: "NOTICE"
            }
        }

        var body: String {
            switch self {
            case .privacy:
                """
                OpenPocketCine talks to your Osmo Pocket over Bluetooth and the camera's own Wi-Fi. The app has no account. Automatic error reports are optional and off by default.

                OpenCapture is the data controller. Privacy or deletion requests: support@openpocketcine.app.

                Optional reliability reports
                With your consent, configured builds send crash, hang and feed diagnostics, app/OS/device versions and session health counts through Sentry. No footage, screenshots, raw camera packets or GPS location are included. Sentry receives the connection IP; stored event IP and derived geography are removed. Event storage uses Germany. Some provider processing may occur internationally.
                Turn reporting off in Operator Setup at any time without losing app features. This clears pending SDK uploads, but does not delete reports already received. Contact us privately to request deletion. The website policy explains retention, transfers and your rights.

                Reporting a problem yourself
                Report a problem sends your description and any optional reply email to OpenCapture through Sentry when you tap Send report. Technical details are included only if you choose them and can be reviewed first. You can choose up to three photos or screenshots and review or remove them before sending. Selected images are resized and re-encoded without original filenames or location metadata. Only share images you have permission to send; no images are attached automatically. This one-off submission does not enable automatic reports. Unsent reports stay privately on this phone, expire after 7 days (removed when the app next runs), wait until you leave camera Wi-Fi, and can be removed before delivery. Do not include passwords or other sensitive information in your message. You can decline the first-launch prompt and enable automatic reports later in System.

                What stays on this phone
                • Saved camera names and last SSID. The camera Wi-Fi password is stored in the iOS Keychain on this phone only.
                • Operator preferences such as Keep Screen Awake and the last LUT look.
                • Imported .cube files you choose to open.

                What never leaves the phone
                • Live HEVC, DUML telemetry, and pairing traffic stay on the local link. We do not operate a cloud.

                Third parties
                • Apple (or Google) may process permission prompts and OS diagnostics under their own policies. TestFlight or Play betas may send crash reports to the developer under Apple or Google terms.
                • Frame.io is optional. If this build is configured and you sign in, clips you pick upload device → Adobe. The token stays in the on-device Keychain.
                • Saving a clip or using the share sheet is something you start. Apple or the app you pick then handles that file.
                • AF-C face boxes are computed on this phone from the live preview. Face geometry is not uploaded.
                • The source is at github.com/erik-sutton95/OpenPocketCine.

                The full privacy policy is https://openpocketcine.app/privacy/
                """
            case .terms:
                """
                OpenPocketCine is free software under the Apache License 2.0. You may use, modify, and share it under that license.

                This is an unofficial field monitor. It is not affiliated with, endorsed by, or supported by DJI. "DJI", "Osmo", and "Osmo Pocket" are trademarks of SZ DJI Technology Co., Ltd., used only to identify the cameras the app can talk to.

                Reverse-engineered protocol behavior can be incomplete or wrong. Do not rely on this app as the only way to start or stop a take — record from the camera body until those commands are proven.

                The software is provided on an "AS IS" BASIS, WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND. See LICENSE in the repository.

                By using the app you agree to follow the Code of Conduct when participating in the project.
                """
            case .licenses:
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
                """
            case .notice:
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
                """
            }
        }
    }
}
