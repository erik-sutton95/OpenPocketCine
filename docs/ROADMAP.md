# Roadmap

Direction and acceptance criteria, not promised dates. Feature requests belong in
[Ideas & Feature Requests](https://github.com/erik-sutton95/OpenPocketCine/discussions/categories/ideas-feature-requests);
public Issues are for bugs. This file owns engineering priorities; the
[shared-engine plan](SHARED-MONITOR-ENGINE.md) owns migration boundaries and
[parity](PARITY.md) owns platform exceptions and qualification evidence.

**Reviewed:** 2026-10-30 against app revision `35f51dc` and the dependency recorded
in [opencine-pins.txt](../opencine-pins.txt), `dd77b69e`. The review checked app
source, repository contracts and public Discussions. It did not build or
physically qualify that app/dependency combination; the sibling OpenCine checkout
was unavailable in the review environment.

## Current baseline

“Integrated” means the current source calls the feature. “Qualification pending”
means the claimed platform/body/build combination still needs evidence. Neither
a merged PR nor an older device pass qualifies a later combined build.

| Surface | Current evidence | Remaining work |
| --- | --- | --- |
| Connection, HEVC/AVC live view and camera controls | Both native shells exist; record, ISO, WB and focus are implemented. The current shared control binding is documented in [Architecture](ARCHITECTURE.md). | Qualify the current control/recovery paths on physical phones and each claimed body; do not schedule basic controls as a new implementation. |
| Shared monitor, assists and media delivery | iOS calls `MonitorClipDelivery`; Android uses `MonitorAssistState` and `MonitorOriginalDeliveryHost`. [Migration status](SHARED-MONITOR-ENGINE.md#11-migration-status-and-remaining-work) distinguishes adoption from completion. | Android original-file sharing does not provide iOS LUT bake, log conversion, Frame.io or watcher relay parity. |
| Distribution | Repository [Play documentation](android-play-ci.md) records a public open-testing entry; iOS has public TestFlight. The existing Play CI pipeline still targets closed testing. | Validate each release candidate and its intended track; do not describe Android as waiting for its first Play presence. |
| Support and diagnostics | Both shells have a native **Report a problem** form and separate opt-in automatic reporting. [Diagnostics](diagnostics.md) defines consent, redaction and deferred delivery. | Qualify release configuration and Android physical delivery. Manual text, optional email and selected images must not be described as anonymous. |
| Watch, Motion Control and Multiview | Apple Watch exists; Motion Control and Multiview have implementations and bounded verification records. | Retain experimental labels and the specific physical gaps in [parity](PARITY.md); Wear OS is separate future work. |

## Corrections to the previous plan

| Problem | Planning correction |
| --- | --- |
| The September roadmap lists existing controls, reporting and Play distribution as future work. | Separate implemented features from verification and rollout tasks using the baseline above. |
| “Parity later” allows new gaps to accumulate without an owner or exit condition. | Every operator-visible increment covers both shells or records its scoped exception in `PARITY.md` in the same change. |
| Early shared-engine phases still ask for code that has already moved. | Continue from current OpenCine adoption; qualify remaining adapters instead of repeating extraction or introducing a second backend API. |
| Features, screenshots, experiments and release gates share one undifferentiated list. | Put current-build reliability and footage preservation first, then bounded operator improvements. Screenshots follow the accepted UI and do not substitute for qualification. |
| Old discussion summaries conflict with current code and contracts. | Treat [discussion #29](https://github.com/erik-sutton95/OpenPocketCine/discussions/29) as historical context. In particular, its Play/reporting status is stale and its SoftAP multicast idea conflicts with the [one-client contract](../CONTEXT.md). |

## Now — P0: qualify the current foundation

These are the next release-readiness work packages, not claims of newly observed
bugs. Reproduce historical failures on the current app and OpenCine revisions
before changing code. Pick one package at a time; keep a named owner and evidence
link with its implementation change.

| Work package | Scope and dependency | Exit evidence |
| --- | --- | --- |
| P0.1 Reproducible combined baseline | Record app SHA, OpenCine SHA, build, phone/OS, camera/firmware and selected scenarios. Use the pinned dependency and existing [integration checklist](OPENCINE-INTEGRATION.md). | A clean pinned checkout builds; relevant automated gates pass for that combination. Each physical scenario is passed, failed or explicitly untested. Earlier candidate logs cannot silently close a current gap. |
| P0.2 Connection and control qualification | After P0.1: pairing, first picture, Media/Settings return, foreground return, Wi-Fi loss, camera power cycle and stale control cancellation on both shells. Start with Pocket 4/4 Pro, then Pocket 3 and Nano paths; qualify each model independently. | Recording follows camera-reported state, stale actions cannot reach a replacement camera, and recovery follows the bounded [reliability contract](connection-reliability.md). Use the [stress matrix](connection-stress-testing.md), record Android coverage gaps, and meet existing [performance budgets](PERFORMANCE.md) under the exercised load. |
| P0.3 Media and export integrity | After P0.1: catalogue pagination, original/proxy identity, sharing while the original is caching, cancellation/retry, low storage and switching cameras. Exercise the existing shared delivery owners. | No partial file is presented as a completed original; cancellation and retry preserve other consumers and cached footage; reported completion matches the delivered file. Verify physical iOS and Android download/share/return flows. Add regressions only for reproduced failures. |
| P0.4 Release and support readiness | After the relevant P0.2/P0.3 passes: verify manual reporting and automatic-report consent, internet gating and the actual release configuration. Keep public Play availability distinct from the CI upload track. | Reviewed reports reach the configured destination only under the existing consent/network rules; queued/failed states stay honest. Record the intended distribution track, current tester notes and outstanding device exceptions before release under [RELEASE.md](RELEASE.md). |

Multiview remains experimental while its matrix is incomplete. Existing two-camera
evidence does not establish four-camera thermal capacity, every hotspot/router
route, every body, or recovery after app switching. Expand qualification in bounded
steps and retain per-camera record results; do not promise frame-accurate sync.

## Next — P1: focused operator improvements

These are proposed increments, not implemented features or release commitments.
Confirm the remaining gap against the selected dependency before implementation.
Effort is relative scope, not a time estimate. Each item inherits the relevant P0
baseline, physical verification and parity requirements.

| Order | Recommendation and value | Smallest useful increment / acceptance | Owner boundary / effort |
| --- | --- | --- | --- |
| 1 | Orientation lock for mounted or inverted phones ([#564](https://github.com/erik-sutton95/OpenPocketCine/discussions/564)). | Explicitly lock/unlock the current monitor orientation with an accessible state indication. Rotation and unlock preserve controls, touch mapping and the active camera session on both shells. Keep this separate from locking camera controls. | Shared preference/presentation, native orientation policy / small |
| 2 | Accessible tracking target selection ([#491](https://github.com/erik-sutton95/OpenPocketCine/discussions/491)). | Expose currently detected targets through VoiceOver/TalkBack actions using position and selection state. Selection and Stop work without drawing a box; expired targets cannot initiate tracking. Reuse current detection and pacing rather than adding a second detector. | Shared target presentation, platform accessibility and existing tracking adapter / medium |
| 3 | Clear export choices and Android conversion parity ([#450](https://github.com/erik-sutton95/OpenPocketCine/discussions/450)). | First make original/proxy source, available look, destination and output format explicit. Preserve the original-copy path. Add Android LUT bake as a separate increment, then log conversion and capability-gated quality presets. Probe output codec, raster, frame rate, color tags and extension; deliver any offered metadata sidecar. Cancel/retry must retain the P0.3 guarantees. | OpenCine delivery/media plus native encoders; app wiring only / large, split into increments |
| 4 | Named gimbal position/move presets ([#424](https://github.com/erik-sutton95/OpenPocketCine/discussions/424)). | Extend existing A·B·C Motion Control with named saved position/zoom or move settings. Recall requires a current compatible body and valid pose/reference; changed mounting or reference requires recapture. Manual input and Stop cancel promptly. Rehearsal must establish repeatability before claiming precision. | OpenCineMotion and shared controls; DJI adapter for commands / medium–large |

## Later — P2: separate capability expansions

| Candidate | Dependency before promotion |
| --- | --- |
| Android watcher relay | Qualify single-camera recovery first; then implement host, discovery/join and control lease in bounded increments with existing relay wire tests and physical iOS↔Android interoperability. Keep one phone owning the camera session. |
| Android Frame.io | Reuse shared delivery/account policy after the export baseline. Qualify native sign-in, secure token storage, cancellation, internet hop and camera rejoin. This is separate from Android original sharing. |
| More cloud destinations | Choose one validated operator workflow after shared delivery is qualified. Drive, Dropbox and other “Coming soon” rows are previews, not working connectors; each needs its own credentials, retry and cancellation evidence. |
| RTMPS/live streaming ([#622](https://github.com/erik-sutton95/OpenPocketCine/discussions/622)) | Start with a bounded feasibility study of camera Wi-Fi plus internet routing, audio, encoder load, thermal budget and service access. Do not promise a platform integration from a requested endpoint alone. |
| Wear OS, desktop, USB/UVC and further camera bodies | Require hardware, a named adapter owner and a small capability/verification matrix. These do not block correctness of existing supported paths and must not trigger a shell rewrite. |
| Published OpenCine packages | Preserve exact pins and reproducible clean builds first. Move to versioned SPM/Maven distribution only with a verified consumer migration; a monorepo move is not a prerequisite for operator features. |

## How an item becomes complete

1. Name the surface and one owner, link the source of demand, and bound the change.
2. Record dependencies, platform/body coverage and measurable acceptance before editing.
3. Test behavior at the existing boundaries. Run `just check` and the applicable
   native gates together in one invocation; do not rerun unrelated gates mechanically.
4. Attach physical evidence for changed operator paths and performance evidence for
   live-path work. Unsupported or untested combinations remain visible in `PARITY.md`.
5. Update the relevant handbook page and this plan's status in the same change.
   Release or publish through the existing maintainer workflow, not as an automatic
   consequence of marking a roadmap row integrated.

Review this baseline when a release or shared dependency change alters capability
or qualification. Keep one source of truth per fact; dated integration notes and
discussion comments remain evidence for their recorded versions only.
