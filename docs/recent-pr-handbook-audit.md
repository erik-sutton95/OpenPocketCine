# Recent PR and Pocket 3 handbook audit

Audit date: 2026-09-11. Surface: **docs**. This is a dated coverage audit,
not a new protocol or architecture contract.

Correction status: the documentation changes identified in items 1–4 and 6–7
below are applied in this worktree, including Multiview navigation and the stale
engineering paragraphs. Item 5 now has a separate
[Pocket 3 survey reference](../handbook/src/content/docs/protocol/pocket3.md),
linked from navigation and the command catalog. Its UI, accepted-request,
status and inspected-file evidence are explicitly distinguished. The
[reference result map](pocket3-reference-checklist.md) records the remaining
body/accessory and physical-qualification gaps.

The numbered findings below retain the **pre-correction audit baseline**.
These documentation corrections did not add app behavior. The 2.7K zoom
implementation discrepancy, failed cold-boot capture and broader app acceptance
remain open. The survey branch was integrated with fetched main before review;
publication still depends on merging the documentation PR.

Subsequent operator update, 2026-09-11: the cold-boot stall appears gone and
cannot currently be reproduced. Its cause remains unconfirmed; the historical
failure and conditional follow-up remain in the [startup investigation](pocket3-startup-investigation.md).

## Answer

The handbook has been updated: **all seven product changes in the latest twenty
merged PRs changed public handbook source**, as did the two documentation PRs
in that window that affected protocol or contribution guidance. Eleven landing
page, dependency or CI changes did not need app/protocol documentation.
The main remaining problems are contradictory older paragraphs, missing
navigation, and incomplete model-specific qualification.

GitHub reported a successful [Pages deployment](https://github.com/erik-sutton95/OpenPocketCine/actions/runs/34542103628)
at the original audit head `40a89d5`. This verifies that deployment's completion,
not a browser review of every page or publication of this worktree's new survey.
The [deployment containing Convert log](https://github.com/erik-sutton95/OpenPocketCine/actions/runs/34541862566)
also succeeded. Publication at the newer fetched head has not been independently
verified by this audit.

## Scope and evidence

The current window is the latest twenty merged PRs at fetched `origin/main`
**`2bf5611` (#327)**, ordered by merge time and ending **2026-09-11 00:11:19 UTC**.
The earliest included merge is #315 at 2026-09-10 21:08:59 UTC. GitHub's PR list
order alone is not merge-time order; the API results were explicitly sorted and
bounded to this fetched head's merge timestamp. Evidence comes from GitHub PR bodies and changed-file lists,
Git history, current source, handbook Markdown and engineering contracts.

The working checkout was `ab8be20`, which predates merged #321, #323 and #324.
The main-branch iOS handbook was initially read through the GitHub contents API
to verify #321. A later fetch advanced `origin/main` to `2bf5611` (#327), and its
handbook delta was read locally. **That fetched main was integrated in merge
commit `859f4d0`.** Both app pages retain the upstream Convert log documentation
alongside these corrections. Its absence from the older checkout was not a
missing-upstream-docs finding.
PR test claims below are attributed to the PR, not independently rerun here.
No device operation was part of this PR audit. The later survey summary links
separately produced evidence; the PR table does not claim to reverify it.

## Fetched-main integration

This refresh moves #325–#327 into the twenty-row table and moves #286, #277
and #274 into supplementary context below. Their older source evidence remains
relevant to the numbered findings; they are no longer counted in the current
window. Each newly included PR was checked through Git history and the GitHub
changed-file API.

The fetched handbook delta from `ab8be20` contains #321's iOS Convert log
description and Android's iOS-only exception. Both survived main integration.
No new app/protocol handbook change appears in #325–#327.

Evidence labels:

- **Physical:** a PR or maintained contract records a specific hardware check.
- **Automated:** tests, replay, rendering or builds; these do not prove camera
  behavior or wireless capacity.
- **Pending:** the source explicitly leaves that hardware check outstanding.
- **Source:** implemented behavior; hardware acceptance is not inferred.

## Latest twenty merged PRs

| PR | Change | Public coverage | Evidence and remaining qualification |
| --- | --- | --- | --- |
| [#327](https://github.com/erik-sutton95/OpenPocketCine/pull/327) | Final landing-button alignment | Landing CSS and HTML only; handbook update unnecessary | No camera behavior change. |
| [#326](https://github.com/erik-sutton95/OpenPocketCine/pull/326) | Homepage cache refresh and site checks | Landing assets documentation and HTML only; handbook update unnecessary | No camera behavior change. |
| [#325](https://github.com/erik-sutton95/OpenPocketCine/pull/325) | Coffee button centering/animation | Landing CSS, JS and HTML only; handbook update unnecessary | No camera behavior change. |
| [#324](https://github.com/erik-sutton95/OpenPocketCine/pull/324) | Coffee embed content policy | Landing page only; handbook update unnecessary | Browser check and repository checks recorded in PR. |
| [#321](https://github.com/erik-sutton95/OpenPocketCine/pull/321) | Convert log export | Current-main iOS and Android app pages updated | Automated MOV pixel/metadata/original-preservation tests. Physical destination picker plus real take through an NLE pending. D-Log M explicitly excluded; Android shares originals. |
| [#323](https://github.com/erik-sutton95/OpenPocketCine/pull/323) | Coffee embed script | Landing page only; handbook update unnecessary | No camera behavior change. |
| [#322](https://github.com/erik-sutton95/OpenPocketCine/pull/322) | Coffee support button | Landing page only; handbook update unnecessary | No camera behavior change. |
| [#319](https://github.com/erik-sutton95/OpenPocketCine/pull/319) | Movable ND chip and units | Both app pages cover hold-drag and Stops / ND32 / ND 0.3 | Physical iPhone chip/drag/unit check. Physical Android pending. D-Log M estimate caveat should accompany the ND description. |
| [#320](https://github.com/erik-sutton95/OpenPocketCine/pull/320) | Recent-feature release notes | [Keeping docs current](../handbook/src/content/docs/contribute/documentation.md) updated | Documentation and note-validator tests; no app behavior change. |
| [#316](https://github.com/erik-sutton95/OpenPocketCine/pull/316) | Multiview, live decoding, D-Log M scopes, Pocket 3 FORMAT fallback | Both app pages, Multiview guide, BLE, commands and live-view pages updated | Physical three-camera iPhone preview/record, five Pocket 3 reconnects and D-Log M scope routing recorded. Pocket 3 2.7K record/reconnect, AP restoration, saved stages, hotspot, full borrowed controls and Android physical checks pending. Several old statements conflict with these additions; see below. |
| [#308](https://github.com/erik-sutton95/OpenPocketCine/pull/308) | Native Motion Control and AirPods tracking | Both app pages and command catalog updated | Physical Pocket 4 Pro/iPhone motion and pause/resume checks. Pocket 3, Android, optical repeatability and end-to-end AirPods wearer qualification pending. |
| [#306](https://github.com/erik-sutton95/OpenPocketCine/pull/306) | Shared-Wi-Fi watcher relay and controls | iOS page and live-view transport updated | Automated real-socket, recovery and load tests. Earlier one-iPad smoothness report is physical evidence for that earlier configuration. Final QR/passcode/recovery build and multiple wireless watchers remain pending. |
| [#305](https://github.com/erik-sutton95/OpenPocketCine/pull/305) | CineStop, six-zone IRE and EL Zone | Both app pages updated | PR records physical iPhone installation/check with the scales and automated iOS/Android tests. Does not calibrate Pocket 3 scene exposure. |
| [#304](https://github.com/erik-sutton95/OpenPocketCine/pull/304) | ND recommendation | Both app pages updated; #319 supersedes placement/unit details | Physical Pocket 4 Pro/iPhone assist check. Android physical pending. |
| [#318](https://github.com/erik-sutton95/OpenPocketCine/pull/318) | js-yaml update | Handbook dependency lockfile only | No operator/protocol change. |
| [#302](https://github.com/erik-sutton95/OpenPocketCine/pull/302) | SoftAP unicast evidence | DUML transport, iOS protocol, live-view and Wi-Fi pages updated | Existing single-client captures; second-client handshake behavior explicitly untested. No proof that the camera can never support a second client. |
| [#310](https://github.com/erik-sutton95/OpenPocketCine/pull/310) | svgo update | Handbook dependency files only | No operator/protocol change. |
| [#313](https://github.com/erik-sutton95/OpenPocketCine/pull/313) | Astro update | Handbook dependency files only | No operator/protocol change. |
| [#314](https://github.com/erik-sutton95/OpenPocketCine/pull/314) | deploy-pages action update | CI only | No operator/protocol change. |
| [#315](https://github.com/erik-sutton95/OpenPocketCine/pull/315) | typos action update | CI only | No operator/protocol change. |

## Supplementary older context

These PRs were in the earlier twenty-PR snapshot ending at #324, but fall
outside the refreshed window. They remain useful evidence for model-specific
claims and the FORMAT corrections; their physical claims remain attributed.

| PR | Change | Public coverage | Evidence and remaining qualification |
| --- | --- | --- | --- |
| [#286](https://github.com/erik-sutton95/OpenPocketCine/pull/286) | Android first picture, rendering, peaking and face AF | Android app page updated | Physical Galaxy S25/Pocket 4 Pro recorded. This does not prove Pocket 3 Android behavior. |
| [#277](https://github.com/erik-sutton95/OpenPocketCine/pull/277) | Advertised FORMAT choices and confirmed selection | Both app pages and command catalog updated | Physical Nano/iPhone FORMAT/no-bounce check. Pocket 3 format matrix was not physically qualified by this PR. Engineering format reference still contains obsolete pre-change descriptions. |
| [#274](https://github.com/erik-sutton95/OpenPocketCine/pull/274) | Nano COLOR bytes | Command catalog updated | Hardware-derived mapping described; new-build physical selection check explicitly pending. Swift and Android tests passed. |

## Precise handbook work

### 1. Correct the Pocket 3 codec table and obsolete qualification text

Priority: high. [Live view](../handbook/src/content/docs/protocol/live-view.md)
says all “Pocket” previews are HEVC, and later says “Nano sends AVC while Pocket
sends HEVC.” The same page now describes captured **Pocket 3 AVC** startup.
The iOS feature list mentions AVC only for Nano. This can cause a contributor to
choose the wrong decoder or diagnose a valid Pocket 3 AVC stream as malformed.

Update the codec table to distinguish Pocket 4 / 4 Pro HEVC from **observed
Pocket 3 AVC** and Nano AVC. Do not claim the Pocket 3 can never produce another
codec without model/firmware/mode evidence. Update codec-aware queue prose to
follow the detected stream codec. Add Pocket 3 to the iOS codec summary and use
codec-neutral wording where the Android description refers to all supported
feeds as HEVC.

Replace the page's repeated “repeated joins remain in progress” with the recorded
five successful Pocket 3/iPhone normal-monitor reconnects and their limited
scope. Preserve the outstanding cold-boot and broader firmware qualification.
The existing successful-join evidence does not resolve a later report where
controls stall before video.

Sources: [PR #316](https://github.com/erik-sutton95/OpenPocketCine/pull/316),
[live-session evidence](live-session.md#pocket-3-first-picture-random-access),
[decoder parity](PARITY.md#first-picture-random-access-gate).

### 2. Make Multiview discoverable and state its observed recovery limit

Priority: high. [Multiview guide](../handbook/src/content/docs/guides/multiview-prototype.md)
is detailed, but [sidebar configuration](../handbook/astro.config.mjs),
[overview](../handbook/src/content/docs/index.mdx) and
[iOS page](../handbook/src/content/docs/apps/ios.md) provide no Multiview entry.
A published page that visitors cannot find does not adequately announce a major
new feature.

Add a sidebar/overview guide link and an iOS feature summary: experimental local
Wi-Fi stage, independent previews and controls, group recording without
frame-accurate synchronization, and iOS-only status. Keep the existing guide as
the detailed home. Link the guide from Android's exceptions or explicitly state
Multiview is unavailable there.

In “Reconnecting a camera,” add the observed limitation: all three cameras
recovered after an app switch, but Pocket 3 required a full rejoin and roughly a
minute. Current prose explains automatic recovery without that concrete limit.
Retain pending AP restoration, hotspot, borrowed-control and four-camera checks.

Sources: [PR #316](https://github.com/erik-sutton95/OpenPocketCine/pull/316),
[foreground recovery evidence](live-session.md#multiview-foreground-picture-freshness),
[Multiview parity](PARITY.md#multiview-foreground-recovery-and-reconnect).

### 3. Surface Pocket 3's capability fallback and mode qualification

Priority: high. Both app pages describe FORMAT as camera-advertised choices
only. [Command catalog](../handbook/src/content/docs/protocol/commands.md#pocket-3-format-choices-without-a-capability-table)
correctly documents the Pocket 3 normal-Video fallback when the camera rejects
the capability request. Link that section from both app pages and explain that
reported capabilities take precedence, selection waits for camera confirmation,
and the fallback is not a SlowMo or unknown-mode allow-list.

Add a focused Pocket 3 modes/format reference or subsection with separate columns
for official specification, observed Mimo/body choice, captured command/status,
and OpenPocketCine physical acceptance. Do not publish the entire engineering
matrix as device-tested support. At this audit baseline, PR #316 explicitly left
2.7K selection, recording and reconnect unverified. An overnight UI visit alone
does not establish the recorded file's dimensions, frame rate or bit depth.

Implementation evidence: [Swift picker policy](../Sources/OpenPocketViewCore/CamCap.swift),
[iOS picker](../ios/OpenPocketCine/CaptureControlSheets.swift),
[Android picker policy](../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/session/VideoFormat.kt).
PRs: [#277](https://github.com/erik-sutton95/OpenPocketCine/pull/277),
[#316](https://github.com/erik-sutton95/OpenPocketCine/pull/316).

### 4. Extend the D-Log M accuracy caveat to the affected controls

Priority: high. Both app pages correctly distinguish normalized signal scopes
from estimated EL Zone/gray values. They do not mention the separate engineering
qualification that **LUT exposure compensation, baked exposure and Face Priority
EV still use the pre-existing D-Log approximation for D-Log M**. Add this short
limitation beside LUT/exposure descriptions and link the curve investigation.
Do not suggest that the recent scope fix calibrated those operations.

ND also derives stops from the selected transfer through
`NDFilterRecommendation.pictureStops` → `LiveColorScience.stops`. Therefore its
D-Log M stop/filter recommendation inherits the empirical Pocket 3 curve's
uncertainty. This is a **source-derived implication**, not an additional physical
measurement. State that D-Log M ND readings are estimates and that a measured
signal value does not identify sensor clipping.

Sources: [curve investigation](pocket3-dlogm-curve.md),
[ND recommendation](../Sources/OpenPocketViewCore/NDFilterRecommendation.swift),
[transfer implementation](../Sources/OpenPocketViewCore/LiveColorScience.swift),
[Android Face Priority exposure](../Apps/Android/app/src/main/kotlin/com/opencapture/openpocketcine/feed/FacePriorityExposure.kt),
[PR #316](https://github.com/erik-sutton95/OpenPocketCine/pull/316).

### 5. Publish a Pocket 3 evidence index, not a universal mode dictionary

Priority: medium. The command catalog's shooting-mode row says only “sparse enum.”
The [source enum](../Sources/OpenPocketViewCore/CameraControl.swift) names modes,
but its comments already distinguish Pocket 4 photo from Nano photo and omit
unconfirmed panorama values. That does not prove Pocket 3's mode mapping.

For each newly captured Mimo mode, record the visible label, device firmware,
preconditions, request/reply/status observation, resulting original-file
properties, return-to-Video behavior and confidence. Include rejected or
uncaptured cases explicitly. Cross-link this index from commands and the
Pocket 3 guide. Confirm mode-specific audio, exposure/color options, zoom and
recording duration using both UI and files where available. Keep unknown values
unknown; do not infer Pocket 3 bytes from another body's enum.

Sources: [shooting mode source](../Sources/OpenPocketViewCore/CameraControl.swift),
[format investigation](osmo-recording-formats.md),
[capture guide](capture-guide.md). No claim of newly observed hardware behavior
is made by this audit.

### 6. Keep pending proof visible beside experimental features

Priority: medium. Motion Control is already marked experimental on both app
pages. Add a short link to [model qualification](programmed-moves.md#evidence-and-qualification)
so Pocket 3 users do not mistake Pocket 4 Pro results for Pocket 3 proof. The
watcher description should distinguish earlier one-watcher smoothness from the
final QR/passcode/recovery build's pending physical acceptance. Preserve the
existing statement that simulated nine-watcher loads do not establish wireless
capacity.

Sources: [PR #308](https://github.com/erik-sutton95/OpenPocketCine/pull/308),
[PR #306](https://github.com/erik-sutton95/OpenPocketCine/pull/306),
[watcher contract](watcher-relay.md).

### 7. Correct the Android install link description

Priority: low. The [overview](../handbook/src/content/docs/index.mdx) calls
Android “not on Play yet.” The [Android page](../handbook/src/content/docs/apps/android.md)
describes Google Play closed testing and links to the landing page. Replace the
overview label with “Google Play closed testing” to match the current install
guidance. Do not imply a public production-store release.

## Engineering references that need cleanup before reuse

These should be corrected with the handbook work so they do not reintroduce
obsolete facts in future implementations.

| File | Stale or inconsistent statement | Required correction |
| --- | --- | --- |
| [Recording formats](osmo-recording-formats.md), “Capability table” and “What the FORMAT sheet does today” | Says unknown codes are dropped, only 1080/4K exist, tests prohibit 2.7K, and Nano's extra choices never reach the picker | Replace with #277's preserving/labelling behavior and #316's Pocket 3 normal-Video fallback. Its later “App work” section partly describes the newer implementation, so editing only one paragraph is insufficient. |
| [Recording formats](osmo-recording-formats.md), opening sentence | Calls all Pocket previews HEVC | Qualify Pocket 3's observed AVC separately. |
| [Recording formats](osmo-recording-formats.md), Pocket 3 zoom / “App work” | Says 2.7K zoom is 3× per the cited specification, while the source clamps only `.p4K` and otherwise exposes 4× | Capture the Mimo 2.7K limit and camera confirmation; then reconcile [CameraModel](../Sources/OpenPocketViewCore/CameraModel.swift), both shells and handbook. This audit establishes the inconsistency, not a newly verified 3× wire limit. |
| [Live session](live-session.md), first-picture section | Older “repeated joins remain in progress” survives beside five successful joins later | Consolidate the existing evidence while preserving unresolved cold-boot and broader model qualification. |
| [Protocol notes](protocol-notes.md), “Phone relay and dual-interface” | Says “If a watcher exists later” after describing implemented Sharing above | Describe the implemented shared-camera-Wi-Fi relay and leave alternate-interface research separately qualified. |

## Physical evidence to prioritize before returning Pocket 3

The survey now supplies a substantial part of the original evidence queue.
The [public reference](https://openpocketcine.app/docs/protocol/pocket3/) and
[result map](pocket3-reference-checklist.md) distinguish completed observations
from remaining checks; they do not claim an exhaustive sweep or prove OPC parity.

| Priority | Current evidence | Remaining work |
| --- | --- | --- |
| Startup | Earlier iOS journal shows control timeouts before video loss; warm reconnect and app relaunch later succeeded. | Capture a failed physical camera power cycle from before handshake and discriminate the startup ordering risks. [Investigation](pocket3-startup-investigation.md). |
| RAW and media preservation | Twenty Mimo imports match complete camera HTTP originals by SHA-256; a genuine full-resolution Photo DNG is preserved. A full five-minute Timelapse's status/frame count matches its downloaded video. | Preserve Panorama RAW components and Timelapse still companions; qualify processed Glamour exports separately from the preserved originals. |
| Modes/formats | All shooting families were visited; selected requests/status and files are documented. Video 2.7K rate choices and its 3× UI zoom endpoint were observed. | Portrait Video entry/output, complete mode/color/rate dependencies and the OPC 2.7K zoom clamp. Mimo evidence does not finish OPC recording/reconnect acceptance. |
| D-Log M | Color selections and several downloaded file properties are established; existing scope qualifications remain. | Simultaneous original/ungraded preview with neutral exposure steps, dark floor and highlight plateau. Ordinary room footage is not a calibrated chart measurement. |
| Body/accessories | General and gimbal menus, corrected Photo/Glamour controls and help inspected; Wi-Fi 2.4/5.8GHz choices retained after reconnect in Mimo. | Optical focus/tracking, handle-motion response, body-only candidate paths, external microphones, webcam/USB and timecode hardware branches. |
| OPC regression/Multiview | Earlier model-specific app checks remain recorded in their contracts. | AP return, saved-stage reopen, borrowed controls, recording continuity and physical Motion Control; Android qualification remains separate. |

Earlier relevant [COLOR #268](https://github.com/erik-sutton95/OpenPocketCine/pull/268)
and [media #263](https://github.com/erik-sutton95/OpenPocketCine/pull/263) are outside
the current twenty-PR window and left new-build physical proof pending. A Mimo
COLOR or album result does not close those OPC implementation checks.

Raw pcaps, BLE dumps, originals and live UI images remain local under ignored
storage. Publish sanitized protocol facts, evidence limits and reproducible
synthetic tests. A firmware version is useful provenance; camera serial numbers,
device identifiers, network credentials and private scene images are not public
documentation.
