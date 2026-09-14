# Sentry integration verification — 2026-09-14

## Scope

iOS shell reporting on a physical iPhone 16 Pro Max, iOS 26.6.2; portable
recorder and native regression tests; Android shell and release-tooling review.
No camera recording or media deletion. Development-only probes run in an isolated
screen without constructing the camera session UI. No store release was made.

## Problems corrected

- Starting on camera Wi-Fi previously prevented the Sentry SDK from starting,
  leaving local crash capture absent. The dedicated transport now gates uploads
  independently of SDK startup. The added XCTest failed before this fix and passed
  afterward.
- The DSN build setting was not present in the built app's explicit Info.plist.
  Physical verification reported SDK disabled despite local configuration. The
  explicit plist now substitutes the DSN, and release tooling checks the artifact.
- Delayed incidents now retain the original occurrence time, release/build and
  source revision. Native events retain bounded typed feed breadcrumb names;
  arbitrary UI text, requests, exception values and user identity are scrubbed.
- Server-side IP removal alone retained IP-derived geography. Recursive removal
  of `user.**` and `user.geo.**` was verified against a newly received event.

## Physical evidence

| Check | Observed result |
| --- | --- |
| Typed synthetic incident | SDK enabled; local receipt changed to confirmed after HTTP acceptance; event retrieved through the Sentry API with a 4,444-byte typed JSON attachment |
| Deliberate native crash | `EXC_BAD_ACCESS` received after relaunch; matching app and debug-dylib dSYMs uploaded; app functions symbolicated; no processing errors |
| Deliberate main-thread hang | Both five-second DEBUG probes produced native App Hang Fully Blocked events, retrieved through the API |
| Privacy after final server rule | Fresh received event had no populated identity, IP or geography fields and no processing errors |
| Upload gate | SDK enabled while the simulated camera-session gate was closed; remote event lookup returned 404. After the 31-second gate released, receipt confirmed and the event was retrieved with the expected decoded-output failure stage |

The gate check uses the production gate on a physical phone with a simulated
camera-session flag. It is not an RF impairment test or live-camera performance
qualification. HTTP acceptance and subsequent event retrieval are separate checks.

## Hosted configuration

The `opencapture` organization has separate `openpocketcine-ios` and
`openpocketcine-android` projects. The
[reliability dashboard](https://opencapture.sentry.io/dashboard/6020886/)
separates feed stages, recovery outcomes, native failures and reported sessions.
It excludes development and verification events. New/regressed error-level
alerts target the project team and exclude those environments and informational
session summaries. Notification delivery itself has not been tested.

Initial verification events predate the final recursive user-field rule.
An attempt to remove the initial synthetic issue returned HTTP 403 with the
current OAuth credentials; the rule does not retroactively scrub those events.
No production user event was involved.

## Rollout limits

Local physical iOS delivery does not configure release builders. Xcode Cloud and
Play CI still require their DSNs and a dedicated symbol-upload credential before
enablement. Do not use an expiring developer OAuth token as a CI secret.
Android physical delivery, crash symbolication and live-camera performance need
an Android device. See [deployment](../sentry-deployment.md) for exact configuration.

## Independent review and regression evidence

Review found the SDK overwrote queued incident `dist` with the current build.
A test using real `SentrySDK.capture` failed with build 1 instead of 107 before
the fix and passed afterward. The iOS suite passed 619 tests (one skipped).
Privacy operations and outstanding owner actions are recorded in
[privacy operations](../sentry-privacy-operations.md).

The normal app was restored on the iPhone after probes, with ordinary consent
preferences unchanged. Offline privacy copy and the new privacy row still need
a physical navigation review; no Android hardware was attached. Website changes
are prepared in the draft PR and are not yet published.

## Android and release transport review

Primary review replaced the initial Android enqueue-only transport wrapper and
then corrected native cached-envelope replay on idle flush. The final transport
uses cancellable HTTP, bounded cached replay, SDK retry/submission hints, and
Sentry rate-limit handling. HTTP acceptance alone confirms receipts. Mock-server
regressions prove cached delivery across transport restart after gate release,
rate-limit retention without repeated requests, and camera cancellation. These
are JVM transport tests, not physical Android qualification.

The release uploader is pinned and checksum verified. Validation against real
local DWARF files caught a mocked-test gap: the CLI rejects dSYM directories.
Enumeration now checks individual DWARF files and parses their actual debug IDs.
Existing-server files are accepted on repeat uploads. Source upload remains off.

Final repository checks passed: `just check` (949 core tests / 104 suites,
site validation, hygiene, secret scanning and release-tool tests), iOS XCTest
(619 tests, one skipped, zero failures), and `just android-check` (assembly,
unit tests, native synchronization test and lint). The Android cache regression
also verifies native disk-flush notification while HTTP is gated. Earlier
`just native-check` passed simulator and Watch builds as well.
