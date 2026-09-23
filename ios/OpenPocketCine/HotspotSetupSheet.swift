import OpenPocketViewCore
import SwiftUI

/// "Add setup" on a saved camera (#406): the phone-hotspot way in. Saving connects over
/// it at once; Camera Wi-Fi stays as the other setup chip.
struct HotspotSetupSheet: View {
    let camera: SavedCamera
    var save: (String, String) -> Void
    @Environment(\.dismiss) private var dismiss
    @State private var ssid = ""
    @State private var password = ""

    /// Personal Hotspot requires 8+ characters; `07/47` carries at most 32/63 bytes.
    private var valid: Bool {
        let name = ssid.trimmingCharacters(in: .whitespacesAndNewlines)
        return password.count >= 8
            && (try? MulticamCommands.join(ssid: name, password: password, seq: 0)) != nil
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Hotspot name", text: $ssid)
                        .textInputAutocapitalization(.never).autocorrectionDisabled()
                        .accessibilityIdentifier("hotspotSetup.ssid")
                    SecureField("Hotspot password", text: $password)
                        .textContentType(.password)
                        .accessibilityIdentifier("hotspotSetup.password")
                } header: {
                    Text("This phone's Personal Hotspot for \(camera.displayName)")
                } footer: {
                    Text(
                        "In Settings → Personal Hotspot, turn on Allow Others to Join and Maximize Compatibility. The name is this phone's name in Settings → General → About. The camera leaves its own Wi-Fi and joins this hotspot; Camera Wi-Fi stays available as the other setup."
                    )
                }
            }
            .navigationTitle("Add setup")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Connect") {
                        save(ssid.trimmingCharacters(in: .whitespacesAndNewlines), password)
                        dismiss()
                    }
                    .disabled(!valid)
                    .accessibilityIdentifier("hotspotSetup.connect")
                }
            }
        }
        .tint(LiveDesign.accent)
        .preferredColorScheme(.dark)
        .onAppear {
            // A hotspot saved by Multiview or another camera is this same phone's.
            if let last = MultiviewNetworkStore.savedNetworks().last(where: { $0.hotspot == true })
            {
                ssid = last.ssid
                password = last.password
            }
        }
    }
}
