# iPhone connection stress follow-up — 2026-09-22

Surface: iOS Debug instrumentation, physical XCTest and host tooling. Follow-up
to [the two-platform campaign](2026-09-22-connection-stress-campaign.md) and
[#401](https://github.com/erik-sutton95/OpenPocketCine/issues/401).

## Device and evidence

Physical iPhone 16 Pro Max, iOS 27.0, Pocket 4 Pro, USB, Xcode 26.2. Recording
remained disabled. Raw journals, numeric samples, XCTest bundles and screenshots
are private under ignored `.local/iphone-priority/`; no camera credentials,
device identifiers, footage or user feedback are committed.

The earlier wireless destination failure is retained. After USB connection,
three normal XCTest app launches failed with CoreDevice error 10004. Direct
CoreDevice launches worked. A test-only attachment path then ran real XCTest
input against a freshly identified recorder and accepted the Wi-Fi Join prompt.
The prior join error 8 is a separate startup failure; these observations do not
prove an Xcode/iOS version incompatibility or a production launch crash.

The first two runs used the installed `cc219a6c4622` application with the new
attachment test. Later runs used `42729a958f79` plus the recorded uncommitted test
instrumentation changes, built with `SWIFT_OPTIMIZATION_LEVEL=-O` and
`GCC_OPTIMIZATION_LEVEL=s`. These remain Debug diagnostic builds, not shipping
Release performance measurements. Subsequent build manifests preserve the
application/test binary hashes and stamped build identity.

## Completed runs

| Run | Evidence | Verdict and limits |
| --- | --- | --- |
| 9401, uninterrupted feed | Full five-minute identity-enqueue/native-output proof; 299 interior one-second samples had maximum source/decode/enqueue ages of 32/40/31 ms | Passed. Interior ACK writes stayed 40 Hz, maximum ACK gap 26 ms; maximum AU/native-output gap 82 ms; no queue drops. Temperature nominal/fair. |
| 9402, requested ten-minute mixed UI/control run | 25 scenario passes; two foreground returns missed the 16-second picture check while temperature was fair; a later lifecycle case stopped for serious thermal state | Failed and stopped after about 439 recorder seconds. It is not ten minutes of qualified exposure. Both slow returns later recovered. |
| 9403, combined local loss overlapping joystick | 17 packet drops and 17 suppressed outputs; failed two-fresh-window recovery check; picture returned during passive aftermath observation | Failed original deadline, retained after later recovery. Nominal temperature. Other selected actions were not reached. |
| 9404, combined loss followed by Media return | Five cycles, 417 packet drops and 26 suppressed outputs; fresh AU/native output/identity enqueue after every catalog return | Passed this targeted test. Pre-Media samples show picture stale for about five seconds with fresh packets. Media and automatic repair can both run in this interval; no claim that Media alone caused recovery. |
| 9405, stronger controls and Xcode-condition attempts | Eight gimbal cycles (96 large throws), seven successful Media returns; eight settings precondition failures before mutation | Failed; thermal stop at recorder 283.4 s. Requested 600 s was not completed. Settings setup was corrected to fetch the lazy ISO ceiling and respect modes without Auto ISO. Xcode activation did not establish network impairment. |
| 9406, corrected settings and gimbal workloads | Three complete ISO/WB sweeps (48 drum swipes), two gimbal cycles (24 large throws), fresh post-action picture progress; journal confirms 24/24 ISO and 12/12 sweep WB success replies | Passed, XCTest exit 0 and host evidence checks passed. Requested 180 s plus the final in-flight sweep; host elapsed 241.69 s. Temperature nominal/fair. ISO returned to its original value; teardown WB command was accepted. Ceiling coverage and independent WB restore readback remain unproven. |
| 9418, matched automatic recovery | One combined-fault cycle, 57 packet drops and 19 suppressed outputs; first sampled fresh source/native output/identity enqueue at 18.3 s after disarm | Failed the original 16-second check; later passive recovery retained. Native-output gap 22.114 s. All 129 samples nominal; host elapsed 139.01 s, not the requested 180 s. |
| 9418, matched Media return, separate run | Same application/test binaries, seed and fault plan; three cycles, 246 packet drops and 22 suppressed outputs; first fresh samples 7.9/7.8/7.5 s after disarm | Passed, XCTest exit 0 and host checks passed; nominal/fair. Host elapsed 214.71 s includes the final in-flight cycle. This is a comparison under one configuration, not a universal Media repair guarantee. |
| 9419, focused lifecycle on optimized Debug | Twelve background/foreground cycles; every post-activation fresh-picture check passed; no injected faults | Passed, XCTest exit 0 and host checks passed. All 125 samples fair; host elapsed 133.05 s for requested 120 s plus final in-flight cycle. This does not erase run 9402's slower returns. |

The local gate observes ACK windows before dropping received video. Output
suppression deliberately hides callbacks; it does not reproduce a native decoder
error. Neither mechanism measures RF strength, range, shared-channel contention
or camera-side receipt of ACKs.

The run-9406 reply audit excludes older journal entries. Six ISO sequences
went 1600 → 3200 → 200 → 100, with successful `0x02/0x2A` replies for all 24
SETs. The initial exposure report and the final post-SET report both show ISO
100. Six WB sequences went 5600K → Auto, with 12 successful `0x02/0x2C`
replies. Teardown's additional Auto/tint-13 command received a successful
reply at 18:22:07 UTC. Original WB/tint is inferred from the captured-baseline
restore path; neither an independent original-value record nor a subsequent WB
readback exists. No ISO-ceiling GET or SET occurred. Baseline readiness can
legitimately omit the ceiling when the mode does not offer Auto ISO.

## Foreground delay: different from the Android loss hold

In run 9402, at 17:41:57 UTC a native submit returned `-12903`, classified by the
repository as an invalid decoder session. At 17:41:59, foreground recovery saw a
video packet younger than two seconds and handed native-output recovery to the
watchdog. That recent timestamp did not establish continued packet delivery.

The same second, UDP Flip reported `notReady`. ACK/video/AU rates then became
zero. Delivered packet/AU counters stayed at 7,637/514 until endpoint replacement.
BLE fallback continued to receive Flip replies. Apparent control responsiveness
therefore does not prove that the video endpoint or arbitrary SET commands were
working. This differs from Android's earlier fresh-complete-AU/silent-submit hold.

The decoder owner exhausted its 16-second picture deadline at 17:42:15. Endpoint
replacement restored picture at 17:42:16, with a native-output gap near 18.9 s.
This follows the implemented recovery ladder; the test's 16-second foreground
threshold can fail before that second stage succeeds. It is a reproduced latency
failure, not a permanently wedged decoder or proof of gimbal causation.

Evidence-backed follow-ups:

1. Reassess transport state during the existing serialized decoder-repair wait.
   Capture endpoint generation/state with freshness at admission and during the
   wait. Preserve transient waiting connections that still deliver packets; do
   not add a competing recovery owner or increase enable traffic.
2. Make live-enable submission outcomes observable. The current Boolean can
   report success after an optional void-returning send, while failed/cancelled
   sockets discard untracked writes and waiting sockets allow them without a
   completion result. A journal line saying `sent` is not camera receipt proof.
3. Extend existing ownership and watchdog regressions with transport deterioration
   during decoder repair. Test ready/waiting/failed/cancelled/missing endpoints
   before changing admission or recovery budgets.
4. Compare automatic recovery with the same fault followed by Media. Catalog
   return advances picture ownership, exits playback and sends a captured live
   start through the existing slot. Those multiple changes need isolation before
   attributing users' workaround to a decoder reset.

## Matched automatic versus Media recovery

Both 9418 runs used `loss:0.10,burst:8:40,outputSilenceMs:2500`, the same
optimized Debug build and seed, a fresh healthy baseline, and the same
native-output/identity-enqueue proof. The automatic case performs no UI action
after disarm. Its first-picture budget begins at confirmed disarm, including
attachment-capture time; three further advancing windows confirm persistence.
Media keeps its own 16-second check after catalog return, so compare the
recorded disarm-to-picture intervals rather than just those two verdicts.

Automatic injection armed at recorder t=99.6 s and disarmed at 104.1 s. The
watchdog requested reference-loss decoder repair at 19:21:36 UTC, while
injection was active, and logged one local enable. Its picture deadline expired
at 19:21:52. Endpoint recovery reported fresh picture at 19:21:57. The first
fresh one-second sample is t=122.4 s, or 18.3 s after disarm; the cadence log
measured a 22.114-second native-output gap. The failed-deadline attachment was
captured after picture had returned; it must not be mistaken for an exact
deadline-time snapshot. XCTest failure remains authoritative.

Between t=104.4 and 116.4, observed packets advanced from 4,466 to 5,066 and
assembled observed AUs from 2,178 to 2,478. Delivered AUs stayed at 1,969,
native submissions at 1,968 and outputs at 1,949. The delivery log reports
roughly 25 observed AUs and 25 queue drops per second. This localizes the hold
before native submission; it is not evidence that fresh AUs reached a wedged
VideoToolbox decoder. Packet counters also stopped during the later endpoint
recovery. Preserve this admission/reference-loss boundary in the next regression.

All three Media cycles had picture about five seconds stale immediately after
disarm, then fresh samples at 7.9, 7.8 and 7.5 seconds after disarm. They also
passed the post-return persistence check. These samples support faster observed
recovery with Media in this configuration. They do not identify which part of
Media's ownership/playback-exit/live-start sequence caused it, or prove that
the earlier repair keyframe was lost. Equal seeds do not produce equal physical
packet schedules: packet-drop and output-suppression counts differed. Fresh
picture times have approximately one-second sampling resolution and measure
pipeline progress, not physical scanout. No production recovery policy changed.

The first Media cycle was nominal and injected 56 drops/19 suppressed outputs,
close to the automatic case's 57/19. Later Media cycles injected 97/3 and 93/0;
the run reached fair temperature. Native-output gaps were 11.712, 11.593 and
11.789 seconds. Picture remained stale at each catalog-entry snapshot, and
decoder repair had already started. Thus Media overlapped an existing repair
owner rather than testing a decoder that had received no automatic repair.

Focused lifecycle run 9419 still logged twelve native-submit `-12903` errors
and twelve foreground handoffs to the watchdog, yet all twelve picture checks
passed. It recorded no decoder-repair request/deadline exhaustion or session
drop, but all twelve cycles completed endpoint recovery. The gaps began during
backgrounding and extended into foreground recovery within the picture checks.
This shows that the numeric error alone does not predict the slow return seen in run 9402.
The changed workload and thermal history prevent attributing the difference
solely to compiler optimization.

## Qualification limits

Xcode's network-condition UI must be checked against actual camera traffic.
In the initial mixed system-condition attempt, a short gap overlapped Media,
which itself can pause live delivery; a subsequent 100% loss selection left
camera traffic advancing at 25 fps. Neither is qualified as a measured network
outage. Keep condition activation/restoration records separate from the
transport-effect evidence.

The resumed isolated attempts also remain unqualified. Direct recorder 9407
collected about 302 seconds including startup, but the condition activated after
that recorder had stopped. Coordinated recorder 9417 reached a continuous
30-second healthy baseline, then refused activation because the returned Xcode
snapshot showed the project window rather than the expected Devices controls.
The actual pulse was verified stopped, and both owned recorder processes were
stopped. Neither attempt is an XCTest pass or evidence of camera-route loss.
Further repetitions of this conditioning approach were stopped. An isolated
iPhone Wi-Fi interruption and actual bandwidth/congestion tests remain gaps.

Fresh Sentry retrieval remains blocked by sign-in. The historical September 21
Sentry audit and GitHub feedback review are described in the parent campaign.
Matching a failure family does not prove it is the same incident or root cause.
Recording endurance, playback/download, Multiview, real RF range and weak-signal
measurements remain outside these completed runs. No production recovery policy
has been changed on the strength of these traces alone.

## Checkpoint and verification

The campaign resumed after the account-switch handoff at run 9406. Settings
reply auditing, the matched automatic-versus-Media comparison and focused
optimized lifecycle replay are complete at the limits above. Xcode conditioning
did not qualify route impairment. Private artifacts and resume state remain
under `.local/iphone-priority/`; no raw journals or images are committed.

`just check` passed: 56 Python stress-host tests, 1,025 Swift Testing cases plus
3 XCTest cases, and the repository documentation/hygiene gates. The 15 attach
host regressions include stale/mismatched evidence, interruption and malformed
cleanup responses. Changed Swift files passed strict format lint; the optimized
physical test build and both device installs passed. These checks validate the
test tooling; they do not resolve the reproduced production recovery delays.
The resumed native simulator suite completed 721 tests with one skipped and
zero failures. Fresh-context review verified the reply counts, matched timing,
deadline accounting and requested-scenario coverage. Owned phone processes
were absent at cleanup; a subsequently launched app session was preserved.
