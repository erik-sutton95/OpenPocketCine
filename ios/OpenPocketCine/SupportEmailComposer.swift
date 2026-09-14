import MessageUI
import SwiftUI

struct SupportEmailPayload: Identifiable {
    let id = UUID()
    let data: Data
}

/// The operator reviews and sends the email; opening this composer sends nothing.
struct SupportEmailComposer: UIViewControllerRepresentable {
    let report: Data
    let onClose: (Bool) -> Void

    func makeCoordinator() -> Coordinator { Coordinator(onClose: onClose) }

    func makeUIViewController(context: Context) -> MFMailComposeViewController {
        let composer = MFMailComposeViewController()
        composer.mailComposeDelegate = context.coordinator
        composer.setToRecipients(["support@openpocketcine.app"])
        composer.setSubject("OpenPocketCine — report a problem")
        composer.setMessageBody(
            "What happened?\n\n\nTechnical details are attached to help us investigate. Please do not include private footage or passwords.",
            isHTML: false)
        composer.addAttachmentData(report, mimeType: "text/plain", fileName: "diagnostics.txt")
        return composer
    }

    func updateUIViewController(_ controller: MFMailComposeViewController, context: Context) {}

    final class Coordinator: NSObject, MFMailComposeViewControllerDelegate {
        let onClose: (Bool) -> Void
        init(onClose: @escaping (Bool) -> Void) { self.onClose = onClose }
        func mailComposeController(
            _ controller: MFMailComposeViewController,
            didFinishWith result: MFMailComposeResult, error: Error?
        ) { onClose(result == .failed || error != nil) }
    }
}
