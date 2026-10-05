import Foundation
import OpenCineAppKit
import OpenPocketViewCore

/// Structured expo lines for the agent loop: os.Logger + a capped Documents journal
/// (OpenCine's `DiagnosticJournal`). Pull with `tools/pull-control-log.sh` (no sudo, no pcap).
let ControlLiveLog = DiagnosticJournal(
    subsystem: "com.opencapture.openpocketcine", category: "session",
    file: FileManager.default.urls(for: .documentDirectory, in: .userDomainMask).first?
        .appendingPathComponent("control-live.log"),
    redact: { PrivacyRedactor.redact($0) })
