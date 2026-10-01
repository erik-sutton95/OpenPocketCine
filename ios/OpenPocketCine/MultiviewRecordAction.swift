import OpenCineMulticam
import OpenPocketViewCore
import SwiftUI

/// A confirmation applies to the plan the operator saw: the same cameras (tile slots), sessions,
/// links (control epochs), modes, command availability and reported recording states, as the
/// engine's admission fingerprint records them. Timestamps and routine telemetry are excluded so
/// refreshes do not dismiss it; a replacement link, a changed camera or availability does.
struct MultiviewRecordContext: Equatable {
    let plan: RecordPlan
    let busy: Bool
    let closing: Bool

    @MainActor init(session: MultiviewSession, tile: MultiviewSession.Tile? = nil) {
        plan = session.recordPlan(for: tile)
        busy = session.busy || session.groupRecordingBusy
        closing = session.closing
    }

    var stopping: Bool { plan.direction == .stop }
    /// Strict policy: every requested camera eligible, at least one to command.
    var canConfirm: Bool { !busy && !closing && plan.isExecutable }

    /// Why the plan is refused, for the disabled control's accessibility hint.
    var refusal: String? {
        guard plan.isRefused, let reason = plan.exclusions.first?.reason else { return nil }
        switch reason {
        case .busy, .cameraTransitioning: return "A camera is busy."
        case .rejected(.recordingStateUnknown): return "Waiting for a camera's record state."
        case .rejected(.unavailable(.mode)): return "A camera is not in a video mode."
        default: return "A camera is not connected."
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
    private func title(_ context: MultiviewRecordContext) -> String {
        tile == nil
            ? (context.stopping ? "Stop recording on all cameras?" : "Record on all cameras?")
            : (context.stopping ? "Stop recording?" : "Start recording?")
    }

    var body: some View {
        // One plan per render for the modifiers; the tap and the confirmation re-read it fresh.
        let now = context
        return Button {
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
        .disabled(!now.canConfirm)
        .accessibilityHint(now.refusal ?? "")
        .confirmationDialog(
            title(now), isPresented: $showingConfirmation, titleVisibility: .visible
        ) {
            Button(now.stopping ? "Stop" : "Start", role: now.stopping ? .destructive : nil) {
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
        .onChange(of: now) { _, _ in
            pending = nil
            showingConfirmation = false
        }
    }

    private func perform(_ approved: MultiviewRecordContext) {
        Task { @MainActor in
            guard approved == context, context.canConfirm else { return }
            await session.record(approved.plan, together: tile == nil)
        }
    }
}
