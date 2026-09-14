import OpenPocketViewCore
import PhotosUI
import SwiftUI

struct ProblemReportView: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(AppModel.self) private var model
    @State private var reporting = ProblemReporting.shared
    @State private var message = ""
    @State private var email = ""
    @State private var includeDetails = false
    @State private var details: String?
    @State private var error: String?
    @State private var submitted = false
    @State private var showPrivacy = false
    @State private var selectedImages: [PhotosPickerItem] = []
    @State private var images: [ProblemReportImage] = []
    @State private var preparingImages = false

    var body: some View {
        NavigationStack {
            reportForm
                .font(LiveType.ui(size: 15, weight: .regular))
                .navigationTitle("Report a problem").navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) { Button("Close") { dismiss() } }
                }
                .alert(
                    "Report unavailable",
                    isPresented: Binding(get: { error != nil }, set: { if !$0 { error = nil } })
                ) {
                    Button("OK") { error = nil }
                } message: {
                    Text(error ?? "")
                }
        }
        .task(id: selectedImages) {
            guard !selectedImages.isEmpty else { return }
            preparingImages = true
            defer { preparingImages = false }
            for item in selectedImages {
                guard !Task.isCancelled, images.count < ProblemReportImage.maximumCount else {
                    break
                }
                do {
                    let image = try await item.loadTransferable(type: ProblemReportImage.self)
                    guard !Task.isCancelled else { return }
                    if let image {
                        images.append(image)
                    } else {
                        error = "Couldn't open this image. Please choose another."
                    }
                } catch {
                    if !Task.isCancelled {
                        self.error =
                            "Couldn’t prepare this image. Please choose another photo or screenshot."
                    }
                }
            }
            selectedImages = []
        }
        .tint(LiveDesign.accent).preferredColorScheme(.dark)
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentView(kind: .privacy, onClose: { showPrivacy = false }).environment(model)
        }
    }
    private var reportForm: some View {
        Form {
            if !reporting.status.isEmpty && reporting.pending == nil && !submitted {
                Section { Text(reporting.status) }
            }
            if reporting.pending != nil || submitted {
                Section {
                    Text(reporting.status).accessibilityIdentifier("support.report.status")
                    if let pending = reporting.pending {
                        Text("Report ID: \(pending.id)").font(.caption).textSelection(.enabled)
                        Text(
                            "Keep the app open with internet access after leaving camera Wi-Fi. Unsent reports expire after 7 days."
                        )
                        .font(.footnote).foregroundStyle(.secondary)
                        Button(
                            pending.accepted ? "Remove local copy" : "Remove unsent report",
                            role: .destructive
                        ) {
                            do {
                                try reporting.discard()
                                submitted = false
                            } catch {
                                self.error = "Couldn't remove this report. Please try again."
                            }
                        }
                    }
                }
            } else {
                Section("What happened?") {
                    TextEditor(text: $message).frame(minHeight: 110)
                        .accessibilityLabel("What happened?")
                        .onChange(of: message) { _, value in
                            message = String(value.prefix(4_000))
                        }
                    Text(
                        "Describe what you were doing and what went wrong. Please don’t include passwords or other sensitive information."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                }
                Section("Reply email (optional)") {
                    TextField("Email address", text: $email)
                        .keyboardType(.emailAddress).textInputAutocapitalization(.never)
                        .autocorrectionDisabled().accessibilityLabel("Reply email (optional)")
                        .onChange(of: email) { _, value in email = String(value.prefix(254)) }
                    Text("Include an address if you'd like us to contact you.").font(.footnote)
                        .foregroundStyle(.secondary)
                }
                Section {
                    Toggle("Include technical details", isOn: $includeDetails)
                        .onChange(of: includeDetails) { _, include in
                            guard include else {
                                details = nil
                                return
                            }
                            details = DiagnosticCenter.shared.manualReport(session: model.session)
                        }
                    Text(
                        "App and device versions, connection events and errors. No footage, screenshots or GPS location."
                    )
                    .font(.footnote).foregroundStyle(.secondary)
                    if let details, includeDetails {
                        DisclosureGroup("Review technical details") {
                            Text(details).font(.caption.monospaced()).textSelection(.enabled)
                        }
                    }
                }
                imageSection
                Section {
                    Text(
                        "Send this report to OpenCapture through Sentry to help improve the app. Your message, optional email and chosen images are included. This does not enable automatic reports."
                    )
                    .font(.footnote)
                    Button("Reporting privacy") { showPrivacy = true }
                    if !ReliabilityReporting.isAvailable {
                        Text(
                            "Reporting isn't available in this build. Contact support@openpocketcine.app."
                        )
                    }
                    Button("Send report") {
                        do {
                            try reporting.submit(
                                message: message, email: email,
                                diagnostics: includeDetails ? details : nil, images: images)
                            images = []
                            submitted = true
                            includeDetails = false
                            message = ""
                            email = ""
                            details = nil
                        } catch { self.error = error.localizedDescription }
                    }
                    .disabled(
                        message.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
                            || !ReliabilityReporting.isAvailable || preparingImages
                            || !selectedImages.isEmpty
                    )
                    .accessibilityIdentifier("support.report.send")
                }
            }
        }
    }
    private var imageSection: some View {
        Section("Photos or screenshots (optional)") {
            if images.count < ProblemReportImage.maximumCount {
                PhotosPicker(
                    selection: $selectedImages,
                    maxSelectionCount: ProblemReportImage.maximumCount - images.count,
                    matching: .images
                ) { Label("Add photos or screenshots", systemImage: "photo.badge.plus") }
                .disabled(preparingImages)
                .accessibilityIdentifier("support.report.images.add")
            }
            if preparingImages { ProgressView("Preparing images…") }
            ForEach(images) { image in
                HStack {
                    if let preview = UIImage(data: image.jpeg) {
                        Image(uiImage: preview).resizable().scaledToFit().frame(height: 100)
                    }
                    Spacer()
                    Button("Remove", role: .destructive) { images.removeAll { $0.id == image.id } }
                        .disabled(preparingImages)
                        .accessibilityLabel("Remove attached image")
                }
            }
            Text(
                "Choose up to 3 images you have permission to share. Location metadata is removed. Images are sent only with this report."
            )
            .font(.footnote).foregroundStyle(.secondary)
        }
    }

}

struct ReliabilityConsentPrompt: View {
    @Environment(AppModel.self) private var model
    let onChoice: (Bool) -> Void
    @State private var showPrivacy = false
    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text("Help improve OpenPocketCine").font(LiveType.ui(size: 23, weight: .semibold))
                Text(
                    "Optional crash, error and feed-dropout reports are used only to improve the app's stability and reliability."
                )
                Text(
                    "Reports go to OpenCapture through Sentry. No footage, screenshots or GPS location are included. You can turn this on or off later in System."
                )
                .foregroundStyle(.secondary)
                Button("Reporting privacy") { showPrivacy = true }
                Button("Enable automatic reports") { onChoice(true) }
                    .buttonStyle(.borderedProminent).accessibilityIdentifier(
                        "reliability.consent.enable")
                Button("Not now") { onChoice(false) }
                    .buttonStyle(.bordered).accessibilityIdentifier("reliability.consent.decline")
            }
            .font(LiveType.ui(size: 16, weight: .regular)).padding(24)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .tint(LiveDesign.accent).preferredColorScheme(.dark)
        .presentationDetents([.medium, .large]).interactiveDismissDisabled()
        .sheet(isPresented: $showPrivacy) {
            LegalDocumentView(kind: .privacy, onClose: { showPrivacy = false }).environment(model)
        }
    }
}
