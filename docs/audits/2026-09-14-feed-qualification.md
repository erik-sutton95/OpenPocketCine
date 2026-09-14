# Feed reliability implementation and qualification — 2026-09-14

Surfaces: portable core, iOS shell, Android shell, diagnostics and Debug XCTest.
This records implementation after the [incident audit](2026-09-14-feed-incidents.md).
This records the earlier blocked attempt. The later operator-assisted
[physical stress results](2026-09-14-physical-feed-stress.md) reproduce and fix an
iOS foreground recovery defect and include passing focused/mixed runs. Full
release qualification remains incomplete.

## Implemented

- Fresh compressed packets no longer hide silent native decoder output from the
  watchdog. A bounded decoder rebuild uses the existing repair owner, readiness
  gates and one recovery enable, then escalates if fresh picture does not return.
- Fresh UDP without complete AUs can enter the bounded transport repair ladder.
  A temporarily blocked enable does not spend a retry budget. Existing SET/GOP
  grace periods and enable-once behavior remain in force.
- Both shells discard broken compressed reference chains and wait for random
  access. Android admission is bounded to eight AUs / 4 MiB; iOS assembly retains
  at most eight protocol-bounded AUs. Decoder errors are generation-scoped.
- Both shells retain typed local incident timelines and recovery outcomes. iOS
  records Settings/scene context, native submit acceptance and actual output.
  iOS healthy session summaries survive relaunch separately from incidents.
- iOS has an optional, default-off Sentry adapter. Upload is gated by consent,
  camera session and camera IPv4 path; raw journals and footage are not attached.
  No DSN, production project, alerts or confirmed remote delivery were configured.
- A seeded Debug XCTest harness exercises Settings, assists, orientation, camera
  settings, short gimbal input and app lifecycle. Explicitly armed packet loss,
  burst loss and callback suppression require a healthy baseline. Recording is
  off unless explicitly enabled. These are software faults, not RF interference.

## Physical attempt

Hardware: iPhone 16 Pro Max, iOS 26.6.2, Xcode 26.2; saved Pocket 4 Pro.
Device identifiers, Wi-Fi identity and raw artifacts remain outside Git.

1. USB pairing, Developer Mode, installation and launch were established. An
   earlier UI test could issue taps, but its live case had no connected camera.
2. Two later XCTest starts failed before initialization with
   `Timed out while enabling automation mode`. No stress scenarios executed.
3. A newly installed Debug app was launched directly with seed `20260914`, a
   300-second deadline and recording disabled. Bluetooth connected. Camera Wi-Fi
   join timed out, then returned `NEHotspotConfigurationErrorDomain` code 8
   (`internal error`). The connection attempt ended at Joining camera Wi-Fi.
4. Source, decoded output and presentation counters stayed **zero**. Healthy
   live exposure was **zero**. No gimbal, recording or injected-fault scenario ran.
5. This run exposed a harness bug: its sample timer continued after the deadline.
   The timer is now cancelled and the idle-timer setting restored on completion.
   The phone was returned to an ordinary app launch without stress flags.

The Wi-Fi error is observed evidence, not a proven explanation for the supplied
Settings freeze. That report had continuing AUs with silent decoder output.

## Remaining qualification

Restore a successful camera Wi-Fi join and XCTest automation while the operator
is present, then follow [the stress procedure](../feed-stress-testing.md): a
healthy baseline, repeated Settings/lifecycle run, and separately armed faults.
Compare ACK cadence, AU latency, decode/present gaps, memory and thermal state
against [the performance budget](../PERFORMANCE.md). A compile or synthetic test
cannot establish physical camera recovery or on-set reliability.

Android physical recovery and performance remain untested. Android has no cloud
reporting adapter; see [parity](../PARITY.md). Renderer-only local repair remains
follow-up work: fresh decoded output with stalled presentation must not trigger
blind camera PLIs. Actual RF degradation, interface migration, long takes and
all supported camera/codec combinations need separate hardware coverage.

## Automated verification

- `just check`: 949 portable tests across 104 suites passed, plus repository
  hygiene, secret scanning, site, Markdown, links and configuration checks.
- `just native-check`: 614 iOS XCTest cases, one skipped, zero failures, with
  simulator and Watch builds. The skipped case is not physical camera evidence.
- `just android-check`: Debug assembly, lint and 770 unit tests, zero failures.
- Independent Grok 4.6 / xhigh reviews covered recovery and SDK transport/privacy;
  integration addressed blocked-retry accounting, unobservable exposure,
  compressed-envelope parsing, consent revocation and session attribution.

These checks validate policy, queues, storage and build integration. They do
not satisfy the hardware and performance requirements above.
