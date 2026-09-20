# Connection regression audit — 2026-09-20

## Scope and evidence limits

Follow-up to the [current Sentry review](2026-09-20-sentry-current-issues.md),
focused on reports of increased **Waiting for live view** and dropouts since
before UI 2.0. The investigation compared release history, refreshed all current
issue event pages, read new incident attachments, and exercised actual queue,
decoder, screen and recovery boundaries with deterministic regressions.

The additional inventory contains 63 feed incidents, 55 session summaries and
two stackless SDK-inferred watchdog terminations, all reporting build 111 source
`3a3f858`. Some are delayed uploads of earlier occurrences. These are additional
events, not unique outages or operators. Correlated incident families can describe
the same interruption. Neither this count nor the earlier tiny build 120 sample
establishes a release failure rate. Android has no comparable hosted incident
sample in this inventory. Fresh 90-day queries of the separate Sentry Logs
service returned zero records for both projects; attached diagnostic journals
remain the available logged-error evidence.

No new feature request was found among the six manual reports. Their routing
and the earlier resolved native groups remain documented in the first review.
Current live-failure groups remain open: a reproducible source defect does not
establish the cause of every field report. Raw telemetry, attachments and any
identifying data remain in ignored local storage.

## Release boundaries

| Boundary | Source and evidence |
| --- | --- |
| Reported open beta build 63 | Exact source commit unavailable. Earlier build-63 reports and the cumulative notes in [PR #332](https://github.com/erik-sutton95/OpenPocketCine/pull/332) establish its existence, but those notes explicitly lacked the App Store Connect commit mapping. |
| Build 106, before UI 2.0 | `0c9f68a`, [PR #336](https://github.com/erik-sutton95/OpenPocketCine/pull/336); [PR #337](https://github.com/erik-sutton95/OpenPocketCine/pull/337) identifies the processed build. Endpoint negotiation and picture-proof ownership already changed here. |
| Immediate parent of UI 2.0 | `9b30b93`, a notes-only change. This is an exact source comparison boundary, not a substitute for build 63. |
| UI 2.0 | `8d51f0e`, [PR #338](https://github.com/erik-sutton95/OpenPocketCine/pull/338). Includes live policy, queue, decoder and FPS-aging changes as well as the interface. Its initial Cloud build failed; [PR #352](https://github.com/erik-sutton95/OpenPocketCine/pull/352) repaired the dependency lockfile. |
| Reported build 111 | `3a3f858`, [PR #356](https://github.com/erik-sutton95/OpenPocketCine/pull/356), confirmed by source revision in telemetry and the retained archive. |
| Prior Sentry fixes | `4caa2da`, [PR #372](https://github.com/erik-sutton95/OpenPocketCine/pull/372); later HDR display is `9a0e721`, #375. Build 111 predates both. |

The exact UI 2.0 comparison is `git diff 9b30b93 8d51f0e`. Store build counters
cannot be reconstructed from `Version.xcconfig` or an archive's unexported
`CFBundleVersion` alone. No claim is made that all defects below were absent in
build 63.

## Reproduced defects

| Defect | Introduction / scope | Reproduction and correction |
| --- | --- | --- |
| Established picture replaced by startup waiting | UI 2.0; iOS shell | The new stats aging clears FPS after two seconds. The existing warmup policy then hides an already-established retained picture. A real session test ages stats after rolling pictures and fails on `isFeedWarming`. Warmup now remains completed until the connection resets; recovery retains its separate RECOV state. Android already gates startup waiting on `hasPicture`. |
| Old retained keyframe hides blocked admission | UI 2.0; compressed queue | Overflow preserves an older IRAP but rejects subsequent P-frames until a new random-access boundary. Delivering discontinuity before that retained IRAP clears the decoder's repair demand even though admission stays blocked. A synthetic HEVC stream through the actual assembler and decoder leaves the watchdog idle on compressed-only iOS output. Delivery now preserves the outstanding discontinuity after an older retained batch and clears it only for a current safe suffix. |
| Retired Android drain consumes replacement keyframe | UI 2.0; Android admission/drain race | An old decode task takes the new endpoint's pending batch before checking its generation, discards that batch and clears the new scheduled hop. The production-method replay delivers no replacement keyframe. Admission, drain consumption and scheduling cleanup now check the endpoint epoch under the queue lock; decoder callbacks remain outside that lock. |
| Already-admitted Android callback crosses decoder lifetime | Additional endpoint/callback race | A deterministic interleaving pauses an old drain after its epoch check, advances the endpoint/decoder lifetime and queues the replacement IRAP, then releases the old callback. The queue is preserved, but the old IRAP can clear the replacement decoder's reference hold. Decoder input now checks owner and epoch inside its existing mutation lock, independent of admission queue locking. Retired AU and discontinuity callbacks cannot mutate replacement references. |
| Fresh traffic can leave first picture waiting forever | Older policy gap, exposed by missed random access | After the initial enable and one resend, fresh P-frames return `wait` through a 180-second replay with no picture. The existing 16-second picture deadline now hands off to negotiated recovery. Pocket 3 FORMAT ownership and GOP grace remain intact; no periodic enable is added. |
| Repeated controls indefinitely renew stalled-stage grace | UI 2.0 decoder/AU recovery branches | A SET every three seconds suppresses recovery for a minute while decoder output or complete AUs remain absent. Grace is now capped by progress at the stage that actually stopped. Fresh fragments cannot renew an AU stall; fresh AUs cannot renew native-output silence. Held zoom/stick, GOP grace, readiness and healthy output retain their existing protections. |
| Gallery return repeatedly starts the stream | Predates UI 2.0; both shells | The production resume policy requests nine enables within roughly three seconds when the first picture is slow, repeatedly resetting GOP grace. Resume now sends one accepted live-start operation and uses a bounded picture wait under one recovery owner. |
| Repair picture deadline survives intentional playback | Endpoint wait before UI 2.0; decoder wait added in UI 2.0 | The production endpoint completion method requests full session recovery while media browsing intentionally owns the camera. Media generations retire old picture requirements without cancelling an endpoint negotiation already in flight; returning to live claims a new bounded owner. |

The preceding PR change also fixes retired iOS display hosts writing geometry
and bindings after replacement. Its reproduced zero-size readiness failure is
covered in the [first audit](2026-09-20-sentry-current-issues.md). It is not newly
attributed to UI 2.0 here.

## Negative findings and remaining unknowns

- A hosted `LiveViewScreen` test establishes rolling pictures and repeatedly
  covers Settings and changes geometry. The current host, bindings and picture
  progress survive. Ordinary Settings coverage is not an unconditional view
  replacement or decoder teardown.
- No permanent foreground-task or first-picture FORMAT task latch was found.
  Existing waits have bounds and generation-checked cleanup. This does not
  prove every physical foreground sequence succeeds.
- The newly downloaded native watchdog terminations have no causal stack.
  They cannot be assigned to a nearby feed incident or dismissed as synthetic.
- Some attachments show fresh complete AUs, failed native decode and delayed
  repair, followed by prompt output after an enable. Current incident fields
  omit several command/readiness/owner gates, so exact causal attribution is
  incomplete. A long output age may include intentional playback; it must not
  be reported as an equally long continuous live outage.
- Presentation-only stalls with fresh decoder output still do not request a
  camera PLI. A general renderer-only repair owner is outside this correction.

## Verification and physical qualification

The retained fixtures are synthetic; none are camera captures. Shortened clocks
in ownership tests do not change production budgets. Regression evidence:

- First-picture and repeated-control replay: three failing assertions before
  correction; the permanent portable suite covers deadlines, held controls,
  healthy output and Pocket 3 FORMAT ownership.
- iOS warmup: the established-picture stats-aging test failed before the guard.
  Queue integration failed with an idle watchdog while new P-frames were
  rejected. The real assembler → decoder → watchdog regressions and hosted
  screen/geometry controls now pass (10 focused native tests).
- Media: the original loop requested nine enables in roughly three seconds;
  the original endpoint completion requested recovery during browsing. Eight
  native tests now cover the actual runner, suspended negotiation, picture wait,
  nil-driver return and canceled-owner cleanup. Android tests drive the
  production runner and endpoint-repair seam, including stale-source repaints.
- Android admission replay originally lost the replacement keyframe. A second
  deterministic interleaving exposed an already-admitted callback crossing the
  epoch boundary. Both now pass; focused Android coverage totals 119 tests.
- Independent reviews of the core policy, iOS queue/warmup, Android admission
  and both media handoffs found no remaining blocking findings. The Android
  input fence covers AU/reference mutations; existing asynchronous size/parameter
  callbacks are not claimed to have gained the same fence.
- Hosted native CI exposed test setup races after the initial local pass. The
  rolling-picture fixture now requires nine actual presentation callbacks, not
  a fixed number of submissions. Inspector tests synchronize with worker and
  view lifecycle events, with finite failure bounds, and let their clock advance
  until initial work is admitted. Deterministic replays reproduce the old
  timeout/cancellation cascade and frozen-clock retry trap; they do not identify
  the precise scheduler delay in the hosted run. Production recovery budgets
  and the behavior assertions are unchanged.

Aggregate validation:

- `just check`: passed, including 1,003 portable Swift tests, hygiene, secret,
  notes, documentation and Sentry adapter checks.
- `just native-check`: passed; 704 iOS tests with one existing clip-dependent
  test skipped and zero failures, plus relay tests and iOS/Watch simulator builds.
- `just android-check`: passed; 926 JVM tests (815 app and 111 monitor UI),
  debug build, Vulkan synchronization test and lint. Lint has zero errors;
  warnings and hints remain, including two findings on unchanged lines in
  files touched by this correction.
- `just handbook-build`: 41 pages. Strict Swift formatting lint on changed
  files and `git diff --check` passed.

No reachable physical camera setup was available during the initial source
audit. A later Android pass exercised source `71a878a` and exposed additional
startup and loss-recovery defects; see the
[physical follow-up](2026-09-20-physical-connection-followup.md) for measured
cadence, failures and limits. Simulator and JVM tests cannot prove radio
stability, camera GOP response, sustained cadence or thermal performance. The
PR remains a draft until the required physical pass:

1. Cold-connect Pocket 3 and Pocket 4 / 4 Pro with identity output and with
   LUT/WAVE/HDR; verify first picture and retained image during recovery.
2. Run a steady take for at least five minutes, then repeat with normal FORMAT,
   COLOR, focus, zoom and stick changes; record packet/AU/output/present cadence.
3. Repeatedly open Media, play a proxy and return, including while a repair is
   active. Confirm one live start, no reconnect during intentional playback,
   fresh picture on return and bounded failure if the camera stops responding.
4. Cover/uncover Settings, rotate/resize, switch single-camera/Multiview hosts,
   and exercise background/foreground plus a brief Wi-Fi interruption.
5. Capture the first failure's diagnostic report and exact action/time; compare
   sustained performance with the [budgets](../PERFORMANCE.md). Do not close
   unresolved field groups based only on automated results.
