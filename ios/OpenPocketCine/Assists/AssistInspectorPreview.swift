import MonitorPresentation
import MonitorUI
import OpenCineAppKitApple
import OpenCineCameraControls
import OpenPocketViewCore
import OpenCineMedia
import SwiftUI

enum AssistInspectorPreviewPolicy {
    static let maximumImageDimension = CGFloat(MonitorInspectorImageSizing.maximumDimension)
    static let refreshInterval: Duration = .nanoseconds(
        Int64(MonitorPreviewAdmission.minimumIntervalNanoseconds))

    static func height(width: CGFloat, tool: MonitorAssistSelection) -> CGFloat {
        CGFloat(MonitorInspectorPreviewPolicy.height(width: Double(width), tool: tool))
    }
    static func isImage(_ tool: MonitorAssistSelection) -> Bool {
        MonitorInspectorPreviewPolicy.isImage(tool)
    }

    /// The inspector forces its selected image tool on in this local copy only.
    /// Other pixel warnings are omitted so the operator can assess this tool.
    @MainActor
    static func imageEffects(
        assist: LiveAssistState, tool: MonitorAssistSelection, transfer: MonitorTransfer,
        ceiling: OpenCineMedia.ScopeExposureCeiling
    ) -> MonitorFrameEffects {
        assist.inspectorImageEffects(
            tool: tool, transfer: transfer,
            clipByte: ceiling.clipByte(transfer: transfer))
    }

    /// Cheap option snapshot, including settings of a tool that is off on the
    /// main picture. This must not resolve or prepare a preview-only LUT.
    @MainActor
    static func imageOptions(
        assist: LiveAssistState, tool: MonitorAssistSelection, transfer: MonitorTransfer,
        ceiling: OpenCineMedia.ScopeExposureCeiling
    ) -> MonitorFrameEffects {
        assist.inspectorImageOptions(
            tool: tool, transfer: transfer,
            clipByte: ceiling.clipByte(transfer: transfer))
    }
}

/// Native source, look and calibration facts for the common inspector owner.
struct AssistInspectorPreview: View {
    var tool: MonitorAssistSelection
    var pictureEffects: MonitorFrameEffects? = nil
    @Environment(AppModel.self) private var model

    var body: some View {
        MonitorOperatorInspectorPreview(tool: tool, assist: model.assist,
            stores: .app, haptics: .app,
            source: MonitorInspectorImageSource(renderer: model.inspectorPreview, samples: model.monitorSamples),
            readCustomName: { LUTPreferences.app.selectedCustomFileName }, pictureEffects: pictureEffects,
            prepareEffects: { frame in
                AssistInspectorPreviewPolicy.imageEffects(assist: model.assist, tool: tool,
                    transfer: frame.transfer, ceiling: model.monitorSamples.exposureCeiling)
            }, readBundle: { model.monitorSamples.displayBundle },
            readAudio: { model.session.status.audioMeters },
            readAudioSensitivity: { model.session.status.audioChannel?.label },
            configureDisplay: scopeDisplay)
    }
}
