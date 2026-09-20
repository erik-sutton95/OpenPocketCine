# Sentry current-issue review — 2026-09-20

## Scope and release boundary

Reviewed the 90-day issue inventory for both OpenPocketCine projects: 46 error /
informational groups and six manual feedback reports, all in the iOS project.
The initial snapshot's newest event was September 20 at 13:51:39 UTC. All issue
event pages were read, including full native stacks. The separate Sentry Logs
query returned no records for either project. This does not establish Android
reliability: no Android reporting data was available in this inventory.

| TestFlight build | Feed incidents | Native events | Session summaries |
| --- | --- | --- | --- |
| 109 | 2 | 0 | 0 |
| 110 | 225 | 4 | 93 |
| 111 | 945 | 19 | 728 |
| 120 | 1 | 0 | 1 |

Counts come from the retrieved event pages, not issue lifetime totals or unique
operators. Development/verification events are excluded from this table.
Build 111's outcomes are 570 recovered, 191 interrupted, 165 suppressed and 19
exhausted. Recovery accounting is not proof that the initiating fault is fixed.

Build 111 reports source `3a3f858`; build 120 reports `753ee85`. The latter
contains the previous Sentry fixes from merged [PR #372](https://github.com/erik-sutton95/OpenPocketCine/pull/372)
at `4caa2da`, plus HDR display from #375. Build 120's only incident in this
snapshot is an interrupted connection later classified as suppressed, with
repeated inactive-scene breadcrumbs. Two total events cannot establish a
post-fix failure rate or successful physical qualification.

Downloaded and inspected all 82 typed feed attachments with occurrence times
after the previous follow-up cutoff, September 19 at 22:30 UTC. Also reviewed
all six manual reports, the supplied dropout diagnostic text, and the missing
display-control screenshot. Raw events, screenshots, contacts and attachments
remain in ignored local storage and were not published.

## Prior fixes removed from the active queue

Ten native groups were resolved **in commit `4caa2da`**, preserving their
history and identifying the merged fix. Resolution records and comments state
that physical qualification is still pending. No events were permanently deleted.

| Sentry group | Evidence / existing fix |
| --- | --- |
| [1H](https://opencapture.sentry.io/issues/148140657/) | Capture-tab index traps; labels and selection frozen with their options |
| [1S](https://opencapture.sentry.io/issues/148140673/) | Invalid playback seek; readiness, item identity and numeric-time guards |
| [1G](https://opencapture.sentry.io/issues/148140559/) | Main-thread proxy-buffer disposal; incremental file streaming |
| [1K](https://opencapture.sentry.io/issues/148140667/) | Native upscaler preparation moved to drawable worker |
| [1N](https://opencapture.sentry.io/issues/148140669/) | Media availability lookup moved to off-main snapshot |
| [1P](https://opencapture.sentry.io/issues/148140670/) | Media cache metadata lookup moved to off-main snapshot |
| [1R](https://opencapture.sentry.io/issues/148140672/) | Media `fileExists` lookup moved to off-main snapshot |
| [1Q](https://opencapture.sentry.io/issues/148140671/) | Recursive cache deletion moved off-main |
| [1V](https://opencapture.sentry.io/issues/148151124/) | Additional build 111 Media `libraryFiles → isAvailableOffline → existingFile → stat` hang; same snapshot fix |
| [1Y](https://opencapture.sentry.io/issues/148217562/) | Build 111 `cachePlaybackFile → writeAtomically → Data.write → fsync` hang; same incremental proxy streaming fix |

1V is a newly indexed historical occurrence from September 19 at 07:48 UTC.
1Y arrived during the review with an occurrence time of September 20 at
13:53:27 UTC, after the initial inventory/table cutoff. Both events report the
old build 111 source, not a regression in the build containing #372.

Four deliberately generated verification-only groups (1, 3, 5 and 6) were
resolved with comments identifying their probes. Informational session-summary
group [W](https://opencapture.sentry.io/issues/147424400/) was archived from the
issue inbox; its events remain available for exposure queries. Mixed production
and development groups, and development reports with unknown test origin, were
not suppressed as synthetic failures.

## Reproduced iOS ownership defect

The continuing fresh-input/stale-output family includes one trace with about
24 complete AUs/s, no native submissions/output and an IRAP hold for roughly
50 seconds. Another trace records a blocked `decoderNotReady` enable followed
by successful watchdog recovery. The attachments omit some repair readiness and
grace gates, so they do not establish why every watchdog tick stayed idle.

A native regression reproduced a concrete readiness defect at the actual view
boundary: construct a replacement `DisplayLayerView` with the same decoder
layer, lay it out at 640×360, then deliver a zero-size layout to the retired
host. Before the correction, the adopted layer became 0×0 and both
`isDisplayReady` and `isPresentationReady` became false. The layer remained
attached to the replacement; the old host was still writing its geometry.

Only the view currently containing that layer may now update geometry or
decoder bindings. Retired single-camera and Multiview updates cannot redirect
`processedFeed`, sample-bus or HDR state. Retired layout cannot issue readiness
callbacks; the current host still follows rotation and resizing. The retired
host's window callback cannot enable its renderer after ownership transfers.
No additional decoder, packet work, timer, enable request or watchdog threshold
was introduced.

Independent review caught the initially unguarded Multiview binding path; the
same ownership check and cross-host binding regressions were added there.
This is a reproduced shell bug. **No reported freeze has yet been causally
attributed to this defect.** Field incident groups remain open pending a matching
physical take.

## Current failures retained

- [1E](https://opencapture.sentry.io/issues/148140665/) and
  [1J](https://opencapture.sentry.io/issues/148140660/): iPad keyboard /
  AttributeGraph aborts. 1J also contains a Core Location memory fault.
  No matching device/OS reproduction or causal app change was established.
- [2](https://opencapture.sentry.io/issues/147029799/): includes a real build
  111 SDK-inferred termination, alongside development/verification events.
  No crash stack identifies its cause; the whole group cannot be dismissed
  as a test termination.
- [1M](https://opencapture.sentry.io/issues/148140668/): generic SwiftUI graph
  hang stack without the filesystem frames that justify resolving the other
  Media groups. Left open rather than inferring its cause from nearby events.
- Build 110 [V](https://opencapture.sentry.io/issues/148140651/) and
  [Y](https://opencapture.sentry.io/issues/148140647/): missing original app
  dSYM UUID `787AC52D-6AFF-3F70-86A4-AE6552F224EA`. Their framework stacks resemble
  later fixed families, but app-frame equivalence is unproven. A rebuild cannot
  replace that archive's symbols.
- Live packet, decoder and presentation failures remain open, including
  [E](https://opencapture.sentry.io/issues/147186544/) and
  [Q](https://opencapture.sentry.io/issues/147400866/). Fresh packets are not
  proof of decoded output; locally submitted ACKs do not prove camera receipt.
- New [1T](https://opencapture.sentry.io/issues/148145683/) has stale assist
  clocks with `outputObservable=false`. #372 corrects that classification,
  but the attachment's underlying reconnection outage is not thereby fixed.
- Manual [1A](https://opencapture.sentry.io/issues/147899518/) confirms repeated
  dropouts. Its final journal shows negotiated endpoint recovery and resumed
  roughly 25 fps, without identifying the initiating fault. Manual
  [18](https://opencapture.sentry.io/issues/147791842/) reports Pocket 3's first
  connection having working controls but no picture, on build 111, without a
  diagnostic attachment. Earlier first-picture fixes cannot justify closing it.

## Feedback and feature routing

| Manual feedback | Disposition |
| --- | --- |
| 1W: microphone receiver on phone, wireless audio to cameras | Created [Discussion #382](https://github.com/erik-sutton95/OpenPocketCine/discussions/382); resolved feedback with backlink |
| X: exposure consistency across 1× / 3× lenses | Created [Discussion #383](https://github.com/erik-sutton95/OpenPocketCine/discussions/383); resolved feedback with backlink |
| 15: connecting two cameras / app purpose | Added setup/discoverability context to [Discussion #238](https://github.com/erik-sutton95/OpenPocketCine/discussions/238#discussioncomment-18528085); resolved forwarded feedback; actual provisioning bug #365 remains open |
| 1X: missing “HSR” button in Display | Screenshot and metadata are build 111, before HDR display landed in #375. Added that evidence; kept open because “HSR” is ambiguous |
| 1A and 18 | Retained as unresolved dropout / first-picture reports |

Public summaries omit private contact details and attachments. The microphone
request's proposed drift explanation and wireless-audio feasibility remain
unverified; migration does not promise support.

Sixteen feature-planning issues already had product discussions. Their original
checklists were copied into those discussions with links to the issue history;
the duplicate issue entries were closed as **not planned in the bug tracker**,
not marked implemented. Current bug and hardware-qualification issues were kept.

| Closed planning issues | Existing discussion |
| --- | --- |
| #303 | #53 — phone relay exploration |
| #100 | #67 — white-balance presets |
| #99 | #66 — macOS product |
| #98 | #65 — iPad support |
| #96 | #63 — Sweet Spot LUT |
| #95 | #62 — live-view introduction |
| #94 | #61 — setup wizard |
| #92 | #59 — Lightroom export |
| #90 | #57 — Action support exploration |
| #89 | #56 — export grading |
| #88 | #55 — USB exploration |
| #87 | #54 — streaming backhaul |
| #85 | #52 — live denoise exploration |
| #82, #81 | #49 — shooting modes |
| #79 | #47 — gimbal settings |

## Verification and remaining device work

The ownership regression failed before the fix with 0×0 geometry and two false
readiness assertions, then passed after the fix. Its production test command is
`just ios-test -only-testing:OpenPocketCineTests/VideoDisplayOwnershipTests`.
Additional tests cover stale bindings in both single-camera/Multiview directions.

Validation passed:

- `just check`, including 995 Swift Testing tests, repository hygiene, secrets,
  notes and documentation checks.
- `just native-check`, including 692 iOS tests, relay tests and iOS/Watch
  simulator builds. The existing D-Log2 clip-distribution test was skipped
  because `OPV_SIM_FEED_CLIP` was not configured.
- `just handbook-build`: 41 pages.
- Strict Swift formatting lint on changed files and `git diff --check`.
- Independent read-only review of the revised ownership fix: no remaining
  blocking findings. Hosted status changes were retrieved again for verification.

Physical iPhone/iPad and Android devices were unavailable. Required follow-up: switch
between a Multiview tile and its single-camera monitor, rotate/resize with
assists and HDR on/off, cover/uncover Settings, and record live-rate/thermal
evidence and the first diagnostic failure if picture stops. Keep the original
build 110 archive if it becomes available. No merge or release is part of this review.

## Subsequent connection investigation

The [same-day connection regression audit](2026-09-20-connection-regressions.md)
refreshes the incident inventory and investigates the reported increase in
Waiting for live view since before UI 2.0. Its release boundaries, additional
reproductions and qualification status supplement this snapshot; the counts
and prior-fix resolutions above retain their original cutoff.
