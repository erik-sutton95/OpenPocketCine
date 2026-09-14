# Physical feed stress — 2026-09-14

Surface: iOS shell and Debug XCTest. Hardware: iPhone 16 Pro Max, iOS 26.6.2,
Pocket 4 Pro, Xcode 26.2. Recording and media deletion were disabled. Raw logs,
XCTest attachments and device identifiers remain local.

## Reproduction and fix

After on-device UI automation was approved, the camera connected and automated
interaction became possible. The first five-minute mixed run (seed `20260916`)
failed after background/foreground transitions. VideoToolbox returned
`kVTInvalidSessionErr` (`-12903`). Compressed video was initially still arriving.
The foreground check waited eight seconds for presentation while its presence
suppressed the keepalive/watchdog path, then forced a full reconnect. The largest
sampled decoder-output age reached 30.189 seconds.

The original lifecycle test incorrectly compared post-return counters with a
snapshot taken **before** Home. Frames arriving before the app went inactive
could make a failed return pass. Its baseline now starts after activation. The
isolated unchanged-app run (seed `20260917`, 120-second scenario budget) recorded
three lifecycle failures before the deadline, plus a final failure overlapping
the recorder deadline. Its largest sampled decoder age was 39.097 seconds.

The iOS fix releases the foreground check when the camera path/video are fresh
and native output is expected. That lets the existing watchdog own the decoder
rebuild and its one recovery enable. It does not add another PLI timer or remove
the GOP grace period. Logs show the invalid-session error, foreground handoff,
owned enable and fresh-picture completion without the former full reconnect.

The same focused seed then passed **11 consecutive lifecycle cycles**. Its
largest sampled decoder age was **6.447 seconds**, including deliberate time in
the background and existing GOP grace. This is bounded recovery, not seamless
video while backgrounded.

## Mixed regression

The repeated five-minute `20260916` run passed all **21 scenario checks**:

| Scenario | Passed checks |
| --- | ---: |
| Settings open/close (multiple transitions per check) | 3 |
| Assist toggles | 4 |
| Portrait/landscape rotation sequences | 3 |
| ISO controls | 4 |
| Bounded gimbal input | 4 |
| Background/foreground | 3 |

XCTest completed in 312.514 seconds including the final scenario and teardown.
There were 305 one-second samples and 7,335 successful native outputs. The
largest sampled decoder-output age was **2.866 seconds**, including deliberate
background transitions; largest presentation age was 2.856 seconds. Thermal state
was nominal in 132 samples and fair in 173; no serious/critical halt occurred.
This is one phone/camera combination, not a population reliability estimate.

## Injected faults

Each run required continuous fresh source/decode progress before arming. Each
fault was disarmed before the test required new decode/presentation progress.
Recording stayed zero in every sample.

| Fault | Seed | Injection evidence | Result |
| --- | --- | --- | --- |
| 2.5-second native-output suppression | `20260918` | 123 suppressed callbacks across two arms | Both recovery checks passed; both accompanying gimbal checks passed |
| 2% packet loss plus four-packet bursts every 100 packets | `20260919` | 136 dropped packets across two arms | Both recovery checks passed; both accompanying gimbal checks passed |

The packet run's largest sampled decoder age was 7.598 seconds. All 128 output
fault samples and all 141 packet fault samples reported fair thermal state, with
no serious/critical halt. Journal evidence shows watchdog decoder repair,
recovery enable and fresh-picture completion. Packet faults run after local ACK
observation and therefore do not reproduce camera-side ACK loss or RF behavior.
Sampled ages have one-second resolution and can miss the precise maximum gap.

The four passing runs contain 692 one-second samples, about 11.5 minutes of
instrumented time including startup, intentional interruptions and recovery.
They are short regression evidence, not an overnight endurance qualification.

## Harness corrections

- Focused core scenarios can be selected with `SCENARIOS`.
- Lifecycle progress is measured after activation.
- Every injection requires a continuous fresh source/decode baseline; elapsed
  run time alone cannot authorize a fault.
- The numeric recorder has a 60-second tail beyond the scenario budget so a
  final operation/teardown does not read frozen deadline counters.
- Reports are separated by run ID and repeated artifact pulls are deduplicated.
  Earlier failures must not be aggregated into a later passing run.

## Limits

The physical runs exercise one Pocket 4 Pro and one iPhone. They do not qualify
Android, other camera/codec combinations, RF interference, roaming, real ACK loss,
long takes, battery consumption or sustained frame-time budgets. Settings passed
in this run; the initiating cause of the originally supplied Settings incident
is still not proven. Cloud delivery and hosted alerting remain unconfigured.

## Verification and retained state

The source baseline was `3560dae`; passing device builds include the foreground
handoff patch described above. The focused red and green runs share seed
`20260917`; mixed red and green runs share `20260916`. The updated harness and
per-run numeric evidence distinguish these builds rather than relying on a
seed alone. `just check` passes 949 portable tests and repository gates.
`just native-check` passes 614 iOS tests (one skipped, zero failures), simulator
and Watch builds. No Android runtime code changed in this follow-up. The phone was returned to a normal app launch
with stress flags absent after artifact collection.
