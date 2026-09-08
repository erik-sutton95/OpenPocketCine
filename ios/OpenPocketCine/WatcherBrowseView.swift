import OpenPocketViewCore
import SwiftUI

struct WatcherBrowseView: View {
    @Environment(AppModel.self) private var model
    @State private var passcode = ""

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("Watch a feed")
                    .font(LiveType.ui(size: 22, weight: .bold, design: .rounded))
                    .foregroundStyle(StartupColors.ink)
                Spacer()
                Button("Close") { model.stopWatching() }
                    .font(LiveType.ui(size: 15, weight: .semibold))
            }
            Text("Other phones sharing nearby. You do not join camera Wi-Fi.")
                .font(LiveType.ui(size: 13, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)

            switch model.relayClient.status {
            case .needsPasscode:
                passcodePrompt
            case .failed(let message):
                Text(message)
                    .font(LiveType.ui(size: 14, weight: .medium))
                    .foregroundStyle(LiveDesign.rec)
            case .connecting:
                Text("Joining…")
                    .font(LiveType.ui(size: 14, weight: .medium))
                    .foregroundStyle(StartupColors.muted)
            default:
                EmptyView()
            }

            if model.relayBrowser.hosts.isEmpty {
                Text(
                    "No feeds yet. On the other iPhone, open Operator Setup → Sharing and turn on Share this feed. Allow Local Network if asked."
                )
                .font(LiveType.ui(size: 14, weight: .regular, design: .rounded))
                .foregroundStyle(StartupColors.muted)
                .padding(.top, 8)
            } else {
                ForEach(model.relayBrowser.hosts) { host in
                    Button {
                        model.joinWatcher(host)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(host.name)
                                .font(LiveType.ui(size: 16, weight: .semibold))
                                .foregroundStyle(StartupColors.ink)
                            if !host.cameraName.isEmpty {
                                Text(host.cameraName)
                                    .font(LiveType.ui(size: 12, weight: .regular))
                                    .foregroundStyle(StartupColors.muted)
                            }
                        }
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .padding(.vertical, 10)
                    }
                    .buttonStyle(.plain)
                }
            }
            Spacer()
        }
        .padding(20)
        .onAppear { model.startWatcherBrowse() }
    }

    private var passcodePrompt: some View {
        VStack(alignment: .leading, spacing: 8) {
            Text("This feed needs a passcode.")
                .font(LiveType.ui(size: 14, weight: .medium))
            SecureField("Passcode", text: $passcode)
                .textFieldStyle(.roundedBorder)
            Button("Join") {
                model.retryWatcherPasscode(passcode)
            }
            .buttonStyle(StartupFilledButtonStyle())
        }
    }
}
