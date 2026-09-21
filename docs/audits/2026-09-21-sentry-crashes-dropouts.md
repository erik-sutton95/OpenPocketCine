# Sentry crashes and dropouts — 2026-09-21

## Coverage and counting

Reviewed both OpenPocketCine Sentry projects across the available 90-day window,
including unresolved, resolved and ignored groups, all manual feedback statuses,
full event pages, and the separate Sentry Logs dataset. Inventory captured on
September 21 around 13:20 UTC. Reports after that cutoff are outside this snapshot.

The iOS inventory contains 55 error/informational groups and seven feedback
groups: 2,885 event rows, representing 2,777 distinct event IDs. Repeated event
IDs occur in the API itself; a second direct API retrieval confirmed them.
That pass also added one late-indexed build 130 session summary with a
September 21 08:46 UTC occurrence; the counts include it.
Counts below show rows and distinct IDs rather than treating either as people
or independent outages. Android returned no issues, feedback or logs. Separate
Sentry Logs returned zero records on iOS too; diagnostic breadcrumbs and typed
attachments are still present on error events. Absence of Android telemetry is
not evidence of reliability.

Downloaded all 1,743 attachment files listed for the 1,677 distinct non-summary
events: 1,740 JSON files, one manual diagnostic text and two screenshots. All
sizes were verified against Sentry metadata; eleven empty initial downloads were
retried successfully. The JSON files cover 1,612 distinct typed incidents;
multiple attachments can describe the same incident. Parsed every incident,
reviewed all native exception stacks and manual report text, and inspected both
manual screenshots. Raw exports, contacts, screenshots, incident payloads and
local phone logs remain in ignored storage, outside this public audit.

| TestFlight build | Feed rows / distinct IDs | Native events | Summary rows / distinct IDs |
| --- | --- | --- | --- |
| 109 | 2 / 2 | 0 | 0 / 0 |
| 110 | 236 / 215 | 4 | 99 / 91 |
| 111 | 1,292 / 1,245 | 29 | 923 / 891 |
| 120 | 56 / 56 | 0 | 39 / 39 |
| 127 | 46 / 46 | 0 | 45 / 45 |
| 130 | 10 / 10 | 0 | 19 / 19 |

Development and verification events and the seven manual feedback events are
excluded from this release table. Build 111 reports source `3a3f858`, build 120
`753ee85`, build 127 `3b53dbc`, and build 130 `6823cf3`. Build 130 therefore
contains the previous connection correction, but continues to report feed
incidents. No native crash/hang events from builds 120–130 were present at this
cutoff. The small, opted-in population cannot establish a crash-free release or
a comparable per-user failure rate.

## Priority findings

1. **Preview reliability remains open.** Newer builds still report transport,
   reference-loss and presentation incidents. Build 130 has eight recovered,
   one interrupted and one suppressed incident. Recovered means the telemetry
   recorded renewed progress; it does not mean a take was uninterrupted.
2. **Discovery now has two current reports.** Sentry 27 describes a Pocket 4 Pro
   on firmware 01.01.7131 never appearing on an iPhone 12 Pro Max. The supplied
   TestFlight build 130 note independently reports repeated discovery failure.
   Neither has a scan diagnostic attachment, and the TestFlight note omits the
   camera model. Bluetooth authorization, advertising and scan lifecycle cannot
   be distinguished from these reports. Do not prescribe a decoder or Wi-Fi fix
   for a camera that has not been discovered.
3. **Remaining native failures need targeted reproductions.** New groups 23 and
   24 are historical build 111 hangs from September 19, not build 130 crashes.
   Their stacks sample observation/font resolution after `endZoomPinch` and
   `LiveZoomChip`/`CameraModel.activeZoomStops`. Sampling those frames does not
   prove that string matching or font construction caused the hang. Groups 1M,
   1E/1J and 2 retain the unresolved graph hang, keyboard/Core Location and
   stackless watchdog-termination limitations described in the previous audit.
4. **Known fixed native families still receive older-build events.** Later
   occurrences in 1K, 1P and 1Y still identify build 111, before the fixes in
   [PR #372](https://github.com/erik-sutton95/OpenPocketCine/pull/372). They do not
   establish a regression in the corrected code. Original build 110 symbols
   remain necessary for V/Y.

No Sentry issue was resolved, archived, deleted or otherwise changed during this
review. Existing dispositions are preserved.

## Reproduced missing-format recovery defect

The current production policy could remain idle indefinitely when an established
native-output path lost its format while complete compressed access units kept
arriving. The watchdog required `hasFormat` before allowing the decoder repair
that requests a replacement random-access frame and parameter sets.

The native regression exercises `HevcDecoder`: present a synthetic HEVC keyframe,
activate native output, call the same `flushForRecovery` used by a failed display
path, then deliver an inter-frame without parameter sets. The last image,
output intent and display readiness survive, but format does not. Feeding those
actual decoder properties into `FeedWatchdog` returned `none` before the fix.
The core test also showed no escalation after 16 seconds.

Red commands:

- `just swift-test --filter FeedWatchdogTests/establishedDecoderWithoutFormatStillOwnsOneBoundedRepair`
- `just ios-test -only-testing:OpenPocketCineTests/ConnectionLifecycleRegressionTests/testLostFormatWithFreshPFramesCannotStrandAnEstablishedDecoder`

The corrected policy permits the existing decoder repair without requiring the
format it must restore. Both the shared Swift policy and Android's JVM fallback
use the same rule. Established picture and native-output intent remain required.
Readiness, camera path, motion, command/GOP grace, one repair attempt and the
16-second escalation deadline are unchanged. Startup, fresh native output and
packet-only assembly stalls retain their separate behavior. The change adds no
ACK work, timers or independent enable sender.

This is a reproduced source defect, **not a proven cause of every Sentry freeze**.
The regression invokes the real format-reset boundary; it does not reproduce the
OS/hardware event that originally caused a field reset. Physical camera
qualification remains outstanding.

## Build 130 trace limits

One fresh-input/stale-output trace shows complete AUs near 25 Hz, ACK submission
near 40 Hz, no native submission/output, missing references and an approximately
six-second gap. Its existing reference-loss repair restores output. That is
recovery evidence, not proof of the packet-loss cause or camera receipt of ACKs.

Three unexpected-disconnect presentation incidents retain native status `-12903`
and gaps around 18, 111 and 130 seconds. Their timelines include scene transitions
and sparse snapshots across inactivity/reconnection; these durations must not be
reported as continuous foreground freezes. A format-less snapshot during a
reconnect is not enough to attribute an entire incident to the defect above.
No retrieved build 127/130 snapshot combined missing format, active presentation,
stale output and a sustained fresh AU rate matching the synthetic regression.
The two Osmo 360 incidents are a short presentation stall and transport gap;
they do not establish general support or qualification for that camera.

The supplied manual dropout diagnostic (1A) remains build 111. It records repeated
repairs and a final negotiated endpoint recovery with resumed picture. Its
screenshot shows Reconnecting / Waiting for live view with camera controls
present. It supports the reported symptom without identifying its initiating
fault. The previous [September 20 audit](2026-09-20-sentry-current-issues.md)
contains the earlier repair and symbolication history.

## All user reports

| Source | Report | Evidence and disposition |
| --- | --- | --- |
| TestFlight feedback 16, September 18, build 111 | Preview repeatedly drops while buttons still work; sometimes needs app restart | Matches the live-preview failure class. No attached journal or camera model; not evidence against later fixes. |
| TestFlight feedback 15, September 21, build 130 | Camera never found despite retries, reset and update | Current discovery failure. Camera model and BLE diagnostics missing. |
| [27](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A148409819&project=4512086563356752) | Pocket 4 Pro never appears during scan | Current build 130 source; firmware and phone model supplied, no attachments. |
| [1A](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147899518&project=4512086563356752) | Repeated video dropouts/reconnects | Build 111 diagnostic and screenshot reviewed; live root cause remains open. |
| [18](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147791842&project=4512086563356752) | Pocket 3 controls work but first picture is black until restart | No diagnostic attachment; first-picture failure remains open. |
| [1X](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A148205841&project=4512086563356752) | Missing HSR display button | Screenshot reviewed: older Display page, before HDR; wording remains ambiguous. Existing issue status preserved. |
| [1W](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A148191434&project=4512086563356752) | Wireless microphone routing request | Existing feature routing in Discussion #382; no new product commitment. |
| [X](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147543818&project=4512086563356752) | Exposure differs between 1× and 3× lenses | Existing feature routing in Discussion #383. |
| [15](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147627577&project=4512086563356752) | Unclear how to connect two cameras / app purpose | Existing setup/discoverability routing in Discussion #238. |

## Complete Sentry group inventory

Issue labels use the `OPENPOCKETCINE-IOS-` prefix. Event rows include all
environments. Status is the existing Sentry status at collection time.

| Group | Rows | Distinct event IDs | Status | Family |
| --- | --- | --- | --- | --- |
| [2](https://opencapture.sentry.io/issues/147029799/) | 26 | 26 | unresolved | WatchdogTermination |
| [1E](https://opencapture.sentry.io/issues/148140665/) | 1 | 1 | unresolved | SIGABRT |
| [1J](https://opencapture.sentry.io/issues/148140660/) | 3 | 3 | unresolved | SIGABRT |
| [24](https://opencapture.sentry.io/issues/148274719/) | 1 | 1 | unresolved | App Hang Non Fully Blocked |
| [23](https://opencapture.sentry.io/issues/148274714/) | 1 | 1 | unresolved | App Hang Non Fully Blocked |
| [V](https://opencapture.sentry.io/issues/148140651/) | 3 | 3 | unresolved | App Hang Fully Blocked |
| [1M](https://opencapture.sentry.io/issues/148140668/) | 2 | 2 | unresolved | App Hang Non Fully Blocked |
| [Y](https://opencapture.sentry.io/issues/148140647/) | 1 | 1 | unresolved | EXC_BREAKPOINT |
| [E](https://opencapture.sentry.io/issues/147186544/) | 239 | 235 | unresolved | freshInputStaleOutput / decodedOutput |
| [N](https://opencapture.sentry.io/issues/147317662/) | 393 | 378 | unresolved | unexpectedDisconnect / packet |
| [1Z](https://opencapture.sentry.io/issues/148267697/) | 19 | 19 | unresolved | unexpectedDisconnect / presentation |
| [21](https://opencapture.sentry.io/issues/148274579/) | 16 | 16 | unresolved | transportStall / presentation |
| [M](https://opencapture.sentry.io/issues/147315395/) | 149 | 140 | unresolved | transportStall / decodedOutput |
| [20](https://opencapture.sentry.io/issues/148271814/) | 1 | 1 | unresolved | transportStall / presentation |
| [Q](https://opencapture.sentry.io/issues/147400866/) | 159 | 155 | unresolved | decoderError / decodedOutput |
| [F](https://opencapture.sentry.io/issues/147195912/) | 275 | 264 | unresolved | transportStall / assistOutput |
| [26](https://opencapture.sentry.io/issues/148310307/) | 3 | 3 | unresolved | freshInputStaleOutput / presentation |
| [K](https://opencapture.sentry.io/issues/147315390/) | 25 | 22 | unresolved | presentStalled / presentation |
| [25](https://opencapture.sentry.io/issues/148293807/) | 1 | 1 | unresolved | assistStalled / decodedOutput |
| [P](https://opencapture.sentry.io/issues/147317671/) | 135 | 127 | unresolved | unexpectedDisconnect / assistOutput |
| [16](https://opencapture.sentry.io/issues/147632945/) | 5 | 5 | unresolved | decoderError / decodeAccept |
| [22](https://opencapture.sentry.io/issues/148274584/) | 2 | 2 | unresolved | decoderError / presentation |
| [G](https://opencapture.sentry.io/issues/147195916/) | 145 | 134 | unresolved | unexpectedDisconnect / assistOutput |
| [J](https://opencapture.sentry.io/issues/147302199/) | 17 | 17 | unresolved | freshInputStaleOutput / assistOutput |
| [1T](https://opencapture.sentry.io/issues/148145683/) | 3 | 3 | unresolved | assistStalled / assistOutput |
| [19](https://opencapture.sentry.io/issues/147796349/) | 8 | 6 | unresolved | unexpectedDisconnect / presentation |
| [R](https://opencapture.sentry.io/issues/147404310/) | 43 | 43 | unresolved | decoderError / assistOutput |
| [T](https://opencapture.sentry.io/issues/147419172/) | 6 | 6 | unresolved | freshInputStaleOutput / decodeAccept |
| [1C](https://opencapture.sentry.io/issues/148006668/) | 7 | 6 | unresolved | freshInputStaleOutput / assistOutput |
| [1F](https://opencapture.sentry.io/issues/148059969/) | 1 | 1 | unresolved | presentStalled / assistOutput |
| [4](https://opencapture.sentry.io/issues/147031028/) | 7 | 7 | unresolved | freshInputStaleOutput, transportStall / decodedOutput |
| [11](https://opencapture.sentry.io/issues/147606503/) | 2 | 2 | unresolved | assistStalled / assistOutput |
| [17](https://opencapture.sentry.io/issues/147696754/) | 2 | 2 | unresolved | unexpectedDisconnect / packet |
| [12](https://opencapture.sentry.io/issues/147608154/) | 3 | 3 | unresolved | transportStall / assistOutput |
| [14](https://opencapture.sentry.io/issues/147623998/) | 1 | 1 | unresolved | assistStalled / decodedOutput |
| [A](https://opencapture.sentry.io/issues/147035689/) | 5 | 5 | unresolved | unexpectedDisconnect / assistOutput |
| [8](https://opencapture.sentry.io/issues/147035685/) | 3 | 3 | unresolved | decoderError / decodeAccept |
| [S](https://opencapture.sentry.io/issues/147407024/) | 1 | 1 | unresolved | freshInputStaleOutput / packet |
| [7](https://opencapture.sentry.io/issues/147035683/) | 1 | 1 | unresolved | decoderError / decodedOutput |
| [B](https://opencapture.sentry.io/issues/147035690/) | 1 | 1 | unresolved | unexpectedDisconnect / packet |
| [1Y](https://opencapture.sentry.io/issues/148217562/) | 2 | 2 | resolved | App Hang Fully Blocked |
| [1P](https://opencapture.sentry.io/issues/148140670/) | 3 | 3 | resolved | App Hang Non Fully Blocked |
| [1K](https://opencapture.sentry.io/issues/148140667/) | 3 | 3 | resolved | App Hang Fully Blocked |
| [3](https://opencapture.sentry.io/issues/147029846/) | 1 | 1 | resolved | EXC_BAD_ACCESS |
| [1H](https://opencapture.sentry.io/issues/148140657/) | 2 | 2 | resolved | EXC_BREAKPOINT |
| [1S](https://opencapture.sentry.io/issues/148140673/) | 2 | 2 | resolved | NSInvalidArgumentException |
| [1V](https://opencapture.sentry.io/issues/148151124/) | 1 | 1 | resolved | App Hang Non Fully Blocked |
| [6](https://opencapture.sentry.io/issues/147032063/) | 1 | 1 | resolved | App Hang Fully Blocked |
| [5](https://opencapture.sentry.io/issues/147031607/) | 1 | 1 | resolved | App Hang Fully Blocked |
| [1G](https://opencapture.sentry.io/issues/148140559/) | 1 | 1 | resolved | App Hang Fully Blocked |
| [1R](https://opencapture.sentry.io/issues/148140672/) | 1 | 1 | resolved | App Hang Non Fully Blocked |
| [1Q](https://opencapture.sentry.io/issues/148140671/) | 1 | 1 | resolved | App Hang Fully Blocked |
| [1N](https://opencapture.sentry.io/issues/148140669/) | 1 | 1 | resolved | App Hang Non Fully Blocked |
| [1](https://opencapture.sentry.io/issues/147029645/) | 2 | 2 | resolved | freshInputStaleOutput / decodeAccept |
| [W](https://opencapture.sentry.io/issues/147424400/) | 1140 | 1100 | ignored | Feed session summary |
| [27](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A148409819&project=4512086563356752) | 1 | 1 | unresolved | Manual feedback |
| [1X](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A148205841&project=4512086563356752) | 1 | 1 | unresolved | Manual feedback |
| [1W](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A148191434&project=4512086563356752) | 1 | 1 | resolved | Manual feedback |
| [1A](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147899518&project=4512086563356752) | 1 | 1 | unresolved | Manual feedback |
| [18](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147791842&project=4512086563356752) | 1 | 1 | unresolved | Manual feedback |
| [15](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147627577&project=4512086563356752) | 1 | 1 | resolved | Manual feedback |
| [X](https://opencapture.sentry.io/feedback/?feedbackSlug=openpocketcine-ios%3A147543818&project=4512086563356752) | 1 | 1 | resolved | Manual feedback |

## Validation and next evidence

The core, native decoder integration and Android fallback regressions failed
before the correction and pass after it. Validation on the corrected tree:

- `just check`: passed, including 1,023 Swift tests, repository hygiene and
  handbook validation (97 pages, no broken links).
- `just native-check`: passed, including the simulator and Watch builds and
  711 iOS tests with one existing clip-dependent test skipped.
- `just android-check` with `ANDROID_HOME` pointing to the local SDK: passed,
  including the Swift Android core, APK build, JVM tests and lint against the
  existing baseline.
- An independent read-only review found no remaining material findings in the
  correction, regressions or redacted evidence inventory.

A paired iPhone and an Android phone are available, but an active camera/test
setup has not been confirmed for this session. The Android phone was not on a
named camera Wi-Fi network when inspected. The retrieved iPhone journal predates
this change and cannot qualify it. The iPad devices required by the keyboard failures are
unavailable. Physical iPhone/Pocket and Android/Pocket tests must cover retained
picture, missing-format recovery, foreground return, first connection and
five-minute cadence/thermal behavior before release qualification.

For discovery, capture the report from Connection setup → Share Diagnostics or
include reviewed technical details in Report a problem, plus the camera model,
firmware and whether it is visible in DJI Mimo. Bluetooth permission/state and
an advertisement/scan trace are needed to build a failing reproduction. No
speculative discovery filter or additional live-enable loop was introduced.
