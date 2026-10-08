import MonitorPresentation
import MonitorUI
import OpenCineCameraControls
import OpenCineMedia
import SwiftUI

struct AssistIconFrameKey: PreferenceKey {
    static var defaultValue: [MonitorAssistSelection: CGRect] = [:]

    static func reduce(
        value: inout [MonitorAssistSelection: CGRect],
        nextValue: () -> [MonitorAssistSelection: CGRect]
    ) {
        value.merge(nextValue(), uniquingKeysWith: { $1 })
    }
}

/// Source facts and the bounded SDK preview for the common operator inspector.
struct AssistLongPressOverlay: View {
    let tool: MonitorAssistSelection
    var assist: LiveAssistState
    let anchor: CGRect
    var toolbar: CGRect = .zero
    let viewport: CGSize
    var safeArea: EdgeInsets = EdgeInsets()
    var ceilingY: CGFloat = 0
    var onDismiss: () -> Void
    @Environment(AppModel.self) private var model

    var body: some View {
        let transfer = model.monitorTransfer ?? model.monitorColorMode.map(MonitorTransfer.init) ?? .rec709
        MonitorOperatorAssistInspector(tool: tool, assist: assist, stores: .app, looks: .app,
            palette: LiveDesign.self, haptics: .app, transfer: transfer,
            clipByte: model.monitorSamples.exposureCeiling.clipByte(transfer: transfer),
            viewport: viewport, safeArea: safeArea, onDismiss: onDismiss) { selected in
            AssistInspectorPreview(tool: selected)
        } lookMenu: {
            LUTAssist.longPressMenu(assist: assist)
        }
    }
}
