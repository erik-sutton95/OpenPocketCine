# Pocket connection and presentation audit — 2026-09-12

Surfaces: portable core, iOS shell, Android shell and operator documentation.
This dated audit records evidence and remaining qualification work. Current
contracts remain in [connection reliability](../connection-reliability.md),
[live session](../live-session.md), [performance](../PERFORMANCE.md) and
[parity](../PARITY.md).

## Reports and evidence

The primary motion-cadence report is
[#334](https://github.com/erik-sutton95/OpenPocketCine/issues/334): Pocket 4 Pro,
Redmi Note 14 Pro+ 5G, Android 16 / HyperOS 3, app build 37. Static shots look
acceptable while pans visibly lag or skip. Its journal reports many delivered
frames but contains no ACK, queue or presentation-gap measurements. Aggregate
FPS cannot establish smoothness or isolate the failing stage.

The maintainer also reproduces stutter on iPhone, control-triggered loss after
joining, AirPods-triggered loss, stuck RECOV and failure after leaving the app.
A directly retrieved iPhone journal from earlier on this date contains:

- Video and picture silence with fresh status, classified as encoder pause.
- Two UDP rebuilds one second apart: keepalive followed by foreground.
- 173 reported presentation-rate samples, median 25 FPS, including substantial
  dips; these older counters measure the existing present path, not scanout.
- One BLE drop beginning bounded recovery at the end of the available journal.

These are separate observations. Neither this log nor the Redmi report proves
that one decoder bug causes every reported failure. Raw journals and any footage
remain local, outside Git.

### iPhone capture after the maintainer returned

The maintainer tested commit `760a348` on a physical iPhone 16 Pro Max with a
Pocket 4 Pro, first over the existing installation and then after deleting and
reinstalling the app. USB journal snapshots, a camera-only RVI trace and a short
Time Profiler recording were retained locally.

- **Mode-change outage:** Direction Lock followed by Follow coincided with
  video stopping. The maintainer identified the action. The journal measured a
  21.862-second presentation gap; RVI measured 22.150 seconds between video
  packets. Camera status continued while video was absent. This event precedes
  decode; it is not evidence of decoder failure.
- **Unconfirmed endpoint migration:** the first recovery rebind changed the
  phone's UDP port while retaining the session. RVI showed camera packets still
  addressed to the retired port and ACKs leaving from the new port. The next
  handshake selected another endpoint; camera traffic and picture returned.
  Successful local ACK writes and a ready socket did not prove peer migration.
- **Motion stutter:** the earlier take contained receive/AU gaps up to 325 ms
  and a 353 ms presentation gap. During steady portions of the fresh-install
  take, presentation gaps reached 153–161 ms while GPU work remained at most
  15 ms. Some hitches followed upstream bursts or main-thread delivery waits;
  others need separate VT, assist and bake timing. No steady-state queue or
  incomplete-frame drops were logged. Startup logged 15 queued-AU drops.
- **AirPods startup:** permission was granted and Core Motion reported active,
  but no accepted motion appeared for almost two minutes. Toggling tracking
  preceded accepted samples and successful calibration. Repeated starts while
  permission was pending can advance the app's callback generation. The trace
  does not prove which Core Motion handler survived those repeated starts.
  The old “in your ears” message inferred wear state from missing motion data.
- **Active tracking:** after calibration, native target writes and roughly
  25 FPS presentation coexisted in the captured segment. This short run does
  not qualify all AirPods latency, takeover, recovery or thermal behavior.
- **Later smooth baseline:** the maintainer could no longer reproduce stutter.
  The final captured minute held a median 25 FPS, with a 60 ms maximum GPU
  presentation gap, 52 ms maximum AU gap, and no queue/incomplete-frame drops
  or failed presentations. No movement commands were sent in that minute.
  Earlier hitches occurred in the same installed revision; reinstalling also
  reset settings. This is useful baseline evidence, not causal attribution.

The initial long “Waiting for live view” interval was already trimmed from the
on-device journal before USB access returned. It is a reported reproduction,
not an attributed failure. Subsequent snapshots preserve overlapping history;
analysis must deduplicate it and exclude startup, intentional transitions and
profiler attachment from steady-state comparisons. RVI can batch timestamps;
short RVI gaps alone are not Wi-Fi airtime measurements.

## Corrected failure paths

| Area | Defect and resulting change | Evidence / limit |
| --- | --- | --- |
| Handshake | Previously seen unsolicited packets could retain a socket indefinitely, even after path loss. Path loss now wins; retained binds consume a finite open budget. | Core lost-path regression failed before the fix. iOS send-round limit and Android elapsed deadline are exercised automatically. |
| Android cancellation | `withContext(IO)` did not interrupt the blocking handshake; TCP setup also swallowed interruption and could publish a socket after close. | Blocking-open and TCP acquisition/settle regressions reproduced the lifetime failures. Interruptible waits, explicit interruption propagation and owned resource transfer now stop abandoned work. |
| Repair ownership | An old canceled task could clear the new repair task and its recovery state. | iOS source harness reproduced the ownership loss; lifecycle regressions cover replacement and cancellation. Kotlin finalizers likewise check job ownership. |
| Socket lifetime | Queued status/AU callbacks and queued writes could act after close or replacement. Old queued delivery suppressed the first new hop; reusing a driver could inherit an old socket or handshake ACK. | Callback epochs checked at execution. Retire and drain every retained socket before resetting handshake state. Assembler and actual-source stale-ACK probes failed before the fixes. |
| Endpoint migration | Rebinding to another local UDP port could leave the camera sending to the retired endpoint. | Physical RVI confirmed the mismatch. Rebuild negotiates a fresh handshake/register/subscribe before one caller-owned enable. A real UDP peer regression failed before the change; hardware retest remains required. |
| Android RX health | A permanent receive error could spin, then successful local sends could conceal a stopped receiver. | One current-epoch failure stops RX/ACK work; a separate receive-failure latch survives successful sends until a receiver is restarted. Failure → successful-send regression reproduced the misleading health. |
| Android TX | Background callers bypassed the supposedly serial TX executor; ACK payloads could retain obsolete cursors while queued. | All ordinary writes share TX; ACK work coalesces and reads windows at emission. Queued bind work has deadline/cancellation/epoch regressions. |
| iOS decoder lifetime | Successful old VT output and already queued assist results could repopulate a reset session and refresh source timestamps. | Two real iOS tests failed with seven stale-output assertions before generation fencing. Reset, rebuild and delayed-success paths now have regressions. |
| Presentation health | Android treated decoder output release as displayed picture; cached or unseen pre-background images could supply misleading health. | Separate output and source-presentation clocks; duplicate, older, previous-decoder and pre-resume source timestamps are rejected. GPU acceptance is still distinct from physical scanout. |
| Recovery presentation proof | An old in-flight GPU completion could combine with a newly decoded, not-yet-presented frame to claim recovery. | A real renderer/session regression reproduced all three incorrect observations. Recovery invalidates pending presentation ownership while retaining the held image and GPU resource reservation. |
| iOS GPU scheduling | Drawable acquisition ran on MainActor; GPU submission was counted as completed presentation. Bake callbacks lacked coherent source identity. | Injected blocked-acquire and failed/pending-GPU tests reproduced the defects. Acquisition moves off main, one reservation covers acquire through completion, and source/bake identity accompanies successful completion. |
| Foreground | Old subnet/socket state was trusted, fresh status could hide a frozen picture, and foreground could compete with keepalive rebuilding UDP. | Validate retained network; preserve healthy short returns; bounded presentation check, then saved-camera spine. No independent foreground enable loop. |
| Full reconnect | A warm iOS retry disconnected BLE without restoring GATT; failed attempts could retain their transports before the next scan. Both shells could dismiss recovery after handshake alone. | Full reconnect restores BLE → Wi-Fi → UDP and waits for fresh source/presentation. Failed-attempt teardown regression reproduced the retained driver; the held image survives cleanup. |
| Recovery budget | Stage deadlines could cut valid Wi-Fi/handshake waits, while increasing them alone would multiply into very long retries. | iOS per-stage limits and Android finite stage operations sit under a 180-second total full-session budget, including discovery and backoff. Advertisement scans have their own bound; they do not truncate the subsequent Wi-Fi wait. Eight attempts remains a second limit. Explicit Retry starts a fresh budget. |
| Active path loss | iOS missing-path guards could suppress every repair while BLE remained connected. | Eight-second reassociation grace sampled on the existing 1 Hz loop; sustained absent path and stale video transfer to full recovery. Tests cover transient loss, reset, competing owner and one-shot action. |
| Movement ownership | Manual control could start before first picture or survive scene inactivity; stale control owners could interfere with recovery. | Warmup/scene/recovery gates and teardown rest/cancellation in both shells. Wearer AirPods and physical movement qualification remain separate. |
| Retired control work | Pending SET retries, GET waiters and queued or active audio work could cross a same-driver session reset; fresh UI requests could enter negotiation. | Real iOS endpoint tests reproduced stale retries, retained waiters and audio continuation. Generation checks, waiter retirement and command admission fence negotiation. Mode/speed changes also require fresh live control eligibility. |
| AirPods startup | Repeated starts while permission was pending replaced the app callback generation; stopping only an active OS stream left pending requests alive. | Real bridge tests with a controlled Core Motion manager reproduced duplicate starts, rejected first-handler samples and a missing stop. One owned request spans permission, cancellation fences old callbacks, and a silent authorized stream offers explicit Calibrate retry. Physical capture established the symptom; exact OS handler ownership remains unknown. |
| Scope placement | Enabling Head Lock added a bottom exclusion area that moved scopes away from the control. | Scopes may extend beneath the button in both iOS orientations; the button remains above them. Android has no Head Lock control. Physical layout verification remains required. |
| Android radio ownership | Late GATT, Wi-Fi request, cancellation and timeout callbacks could clear a replacement connection. | Attempt/resource fences protect queued platform work; four regressions failed before the ownership check. Failed process binding rejects the join. Real radio callback ordering remains a hardware check. |
| Operator recovery | Stages were opaque; terminal Android failure still displayed an activity indicator. | Stage-specific progress, truthful held-picture state and persistent Retry/menu actions. |
| Diagnostics | Existing logs could not separate input cadence, compressed backlog, decoder delay and present delay. | Low-rate stage counters, timing gaps including silence, queue pressure and a local summary command. GPU logs retain maximum wait/completion delay across the journal window; no per-packet logging added. |

## Native Android GPU synchronization

The audit also found indefinite fence/acquire waits and ignored presentation
results in the Vulkan live path. The rendering submit/present pair lacked an
explicit semaphore dependency. Same-queue ordering alone does not meet Vulkan's
presentation synchronization requirement.

The native correction uses bounded frame waits and per-swapchain-image completion
semaphores connecting submit to present. Both rendering paths share the tested
submission/presentation construction. A failed presentation cannot report a new
picture. Acquired-image and in-flight-resource ownership must survive timeouts;
GPU resources are not freed merely because a CPU deadline expired. Native build
and fault-injection checks are distinct from physical GPU/driver qualification.

The primary contracts used here are the Khronos references for
[acquisition](https://docs.vulkan.org/refpages/latest/refpages/source/vkAcquireNextImageKHR.html),
[presentation](https://docs.vulkan.org/refpages/latest/refpages/source/vkQueuePresentKHR.html)
and [fence waits](https://docs.vulkan.org/refpages/latest/refpages/source/vkWaitForFences.html).
For platform lifecycle behavior, the audit checked Apple's
[current Wi-Fi API](https://developer.apple.com/documentation/networkextension/nehotspotnetwork/fetchcurrent(completionhandler:)),
Android's [network callbacks](https://developer.android.com/develop/connectivity/network-ops/reading-network-state),
and Kotlin's [interruptible blocking work](https://kotlinlang.org/api/kotlinx.coroutines/kotlinx-coroutines-core/kotlinx.coroutines/run-interruptible.html).

## Remaining work and qualification

| Priority | Finding / next proof |
| --- | --- |
| P1 | **Physical #334 cadence remains unqualified.** Compare packet/AU/output/presentation gaps during motion on the reported Redmi and on iPhone. The corrected defects are not a measured root-cause attribution for that report. |
| P1 | **Compressed backlog needs a codec-aware overload policy.** Android's AU executor can accumulate work, and iOS's queue cannot safely discard arbitrary inter frames. Record queue depth/wait and input misses first; test reference continuity and IDR recovery before changing overflow behavior. |
| P2 | **Radio callback qualification.** Android attempt/resource fences have queue-level regressions, but real GATT and network cancellation timing still needs repeated Cancel/retry hardware runs. iOS CoreBluetooth callbacks identify a peripheral, not a connection attempt; same-body delayed-disconnect ordering remains unproven. |
| P1 | **Mid-session decoder stalls with live transport require physical classification.** `LinkDiagnoser` remains observe-only. Do not wire a second PLI/rebuild owner from an ambiguous present hitch. |
| P1 | **Initial picture completion needs a finite bound.** Initial handshake success can enter first-picture recovery, where fresh packets without a usable picture can keep the policy waiting after its second enable. Endpoint repair and warm rejoin now have fresh-picture deadlines, but they do not cover every initial entry. Test the actual initial lifecycle handoff before closing this gap. |
| P1 | **GPU teardown under a hung vendor driver remains a limit.** Native resize/destruction still uses device-idle waits; freeing pending AHB/swapchain resources on a timeout would be unsafe. Validate Android driver failure and lifecycle with Vulkan validation and device traces. |
| P2 | **Same-subnet camera identity while continuously foregrounded.** iOS checks interface loss continuously and SSID on foreground return; silently roaming to another camera on the same subnet is not continuously identity-verified. Android retains the camera-specific requested Network and validates process binding. |
| P2 | **Watcher/Watch scheduling.** Concurrent wrist JPEG jobs can complete out of order, and wrist ACK occurs before main-thread ingestion. These are separate preview ordering/backlog concerns; no evidence currently attributes Pocket phone stutter to them. |
| P2 | **Radio and thermal matrix.** Long app suspension, camera power cycles, weak/interfered Wi-Fi, multiple assists, recording, alternate firmware, Redmi/Samsung hardware and long thermal soak still require matched physical runs. |

## Physical feedback loop

Use the normal saved-camera connection and mounted monitor, retaining existing
operator settings. Do not change recording state as part of a connection probe.

1. Capture 30 seconds static, then slow pans with assists off and with the
   operator's LUT/scopes. Compare maximum frame gaps as well as average rate.
   Repeat with Watch preview or Sharing enabled if normally used.
2. Test joystick immediately after first picture, then sustained movement.
   Test AirPods separately, including rest, Stop and manual takeover.
3. Leave the app for 15 and 60 seconds. Test both retained camera Wi-Fi and an
   actual network change. A direct lifecycle method call is not OS suspension.
4. Exercise a full saved-camera reconnect and camera power cycle. Recovery must
   show the failing stage, retain the picture and end in new video or operator
   action within the relevant budgets. No stale source can count as success.
5. Run at least a five-minute live take with pan/tilt, LUT/scopes and recording,
   then a longer thermal run appropriate to set use.

Use `just live-log-summary /tmp/camera-control.log` for local timing summaries.
If AU delivery is smooth but output/presentation is uneven, trace the decoder and
GPU. If packet/AU gaps appear first, compare transport timing and ACK windows with
Mimo under the same camera settings and RF conditions. Captures remain local.

## Verification record

The audit reproduced specific failures before fixing them; pure tests and
simulator checks do not replace camera qualification. Final check counts are
recorded in the associated draft PR, alongside the remaining physical matrix.
The repository quality gate, public handbook build, native simulator checks and
development-signed iPhone build passed during integration. The maintainer then
installed that build and performed the physical captures above. They establish
specific failures and one successful automatic rejoin; they are not a complete
hardware qualification or proof that issue #334 is resolved. Follow-up changes
need a new physical run against the installed revision.

The separate [merged-issue audit](2026-09-12-merged-issue-audit.md) covers the true
last twenty merges and all fifty issues that were open at its start. Only #101
and #80 were closed; connection/cadence issues remain open.
