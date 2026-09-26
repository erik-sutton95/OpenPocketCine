import OpenPocketViewCore
import SwiftUI

/// A confirmation applies to the same cameras, modes and confirmed recording
/// states that the operator saw. Timestamps are excluded so telemetry refreshes
/// do not dismiss it; replacement links and changed command availability do.
struct MultiviewRecordContext: Equatable {
    struct Camera: Equatable {
        let tile: UUID
        let camera: UUID?
        let driver: ObjectIdentifier?
        let mode: Int
        let recording: Bool?
        let available: Bool
        let busy: Bool
    }
    let cameras: [Camera]
    let busy: Bool
    let closing: Bool

    @MainActor init(session: MultiviewSession, tile: MultiviewSession.Tile? = nil) {
        cameras = (tile.map { [$0] } ?? session.recordingTiles).map {
            Camera(
                tile: $0.id, camera: $0.camera?.id, driver: $0.driver.map(ObjectIdentifier.init),
                mode: $0.settings.shootingMode, recording: $0.recordingActive,
                available: $0.recordingAvailable,
                busy: $0.recordingBusy || $0.connecting || $0.recovering)
        }
        busy = session.busy || session.groupRecordingBusy
        closing = session.closing
    }

    var stopping: Bool { cameras.contains { $0.recording == true } }
    var canConfirm: Bool {
        !busy && !closing && !cameras.isEmpty
            && cameras.allSatisfy {
                $0.camera != nil && $0.available && !$0.busy && $0.recording != nil
            }
    }
}

struct MultiviewRecordAction<Label: View>: View {
    let session: MultiviewSession
    var tile: MultiviewSession.Tile?
    let confirmationEnabled: Bool
    @ViewBuilder let label: () -> Label
    @State private var showingConfirmation = false
    @State private var pending: MultiviewRecordContext?

    private var context: MultiviewRecordContext { .init(session: session, tile: tile) }
    private var title: String {
        tile == nil
            ? (context.stopping ? "Stop recording on all cameras?" : "Record on all cameras?")
            : (context.stopping ? "Stop recording?" : "Start recording?")
    }

    var body: some View {
        Button {
            guard context.canConfirm else { return }
            if confirmationEnabled {
                pending = context
                showingConfirmation = true
            } else {
                perform(context)
            }
        } label: {
            label()
        }
        .disabled(!context.canConfirm)
        .confirmationDialog(title, isPresented: $showingConfirmation, titleVisibility: .visible) {
            Button(context.stopping ? "Stop" : "Start", role: context.stopping ? .destructive : nil)
            {
                guard let pending else { return }
                self.pending = nil
                perform(pending)
            }
            Button("Cancel", role: .cancel) { pending = nil }
        } message: {
            Text(
                tile?.camera?.name
                    ?? "Each camera confirms independently; recording is not synchronized.")
        }
        .onChange(of: context) { _, _ in
            pending = nil
            showingConfirmation = false
        }
    }

    private func perform(_ approved: MultiviewRecordContext) {
        Task { @MainActor in
            guard approved == context, context.canConfirm else { return }
            if let tile {
                await session.toggleRecording(tile)
            } else {
                await session.toggleAllRecording()
            }
        }
    }
}
