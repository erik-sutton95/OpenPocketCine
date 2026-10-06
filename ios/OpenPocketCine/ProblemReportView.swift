import OpenCineAppKit
import OpenPocketViewCore
import SwiftUI

/// The shared report form on this app's reporting, support address, accent and privacy page.
struct ProblemReportView: View {
    @Environment(AppModel.self) private var model

    var body: some View {
        ProblemReportSheet(
            reporting: AppDiagnostics.problemReporting,
            isAvailable: AppDiagnostics.reporting.isAvailable,
            supportEmail: "support@openpocketcine.app", accent: LiveDesign.accent,
            technicalDetails: { DiagnosticCenter.shared.manualReport(session: model.session) },
            privacy: { close in
                LegalDocumentView(kind: .privacy, onClose: close).environment(model)
            })
    }
}

/// The shared first-launch ask for automatic reports, in this app's name.
struct ReliabilityConsentPrompt: View {
    @Environment(AppModel.self) private var model
    let onChoice: (Bool) -> Void

    var body: some View {
        ReliabilityConsentSheet(
            productName: "OpenPocketCine", accent: LiveDesign.accent, onChoice: onChoice,
            privacy: { close in
                LegalDocumentView(kind: .privacy, onClose: close).environment(model)
            })
    }
}
