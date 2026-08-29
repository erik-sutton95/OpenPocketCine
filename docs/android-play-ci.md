# Play closed testing (GitHub Actions)

GitHub Actions is the Android analog of Xcode Cloud → TestFlight: a signed
App Bundle, a monotonic `versionCode`, and an upload onto Play **closed
testing**. There is no Play equivalent of Apple-managed signing, so the upload
keystore and the Play service account live in the **play-closed** GitHub
Environment.

Join URL (once the first release is live):
<https://play.google.com/apps/testing/com.opencapture.openpocketcine>

One-time Play Console / signing / secrets:

```bash
./scripts/setup-android-play.sh
```

## Why closed testing

| Track | Cap | Review | Use |
| --- | --- | --- | --- |
| Internal testing | 100 testers | None | Maintainer smoke |
| **Closed testing (`alpha`)** | Large email lists | First release of a version | Waitlist (300+) |
| Open testing | Anyone with the link | Yes | Not yet |

Internal testing cannot hold the waitlist. Firebase App Distribution would skip
Play review, but the waitlist copy and privacy policy already promise Play
Console. Closed testing is the TestFlight-shaped path: opt-in URL, email list,
Play-delivered updates.

## What the workflow does

| Step | Where it lives |
| --- | --- |
| Swift core + JNI `.so` | [`scripts/ci-install-swift-android.sh`](../scripts/ci-install-swift-android.sh) + `:app:stageSwiftCore` |
| Signed AAB | `./gradlew bundleRelease` with `ANDROID_KEYSTORE_*` |
| `versionName` | [`Apps/Android/gradle.properties`](../Apps/Android/gradle.properties) `openpocketcine.versionName` (keep equal to iOS `MARKETING_VERSION`) |
| `versionCode` | CI stamp: `ANDROID_VERSION_CODE_BASE` + `github.run_number` (local `openpocketcine.versionCode` is the sideload floor) |
| Tester notes | [`Apps/Android/Play/WhatToTest.en-US.txt`](../Apps/Android/Play/WhatToTest.en-US.txt) |
| Play "what's new" (500 chars) | [`Apps/Android/Play/whatsnew/whatsnew-en-US`](../Apps/Android/Play/whatsnew/whatsnew-en-US) |
| Upload | `.github/workflows/android-play.yml` → track `alpha` |

The workflow **never** runs on `pull_request`. Forks must not see the keystore
or the service account. Auto-upload on `main` is off until you set the
repository variable `ANDROID_PLAY_UPLOAD=true` (the wizard asks). Until then,
**Run workflow** on **Android Play**.

The first AAB of a new package must go through the Play Console UI so the
package name exists. After that, Actions can upload.

## After the workflow exists

- **Merges to `main`** that touch `Apps/Android/`, the Swift core, the JNI
  facade, `Package.swift`, the Android scripts, or `Apps/Android/Play/` upload
  once `ANDROID_PLAY_UPLOAD` is true. Docs-only commits do not.
- **Dispatch inputs**: `alpha` (closed) or `internal` (smoke); `completed` or
  `draft`; `changes_not_sent_for_review` while the listing is still incomplete.
- **Next versionCode**: the stamp is monotonic because `github.run_number` only
  increases. Raise `ANDROID_VERSION_CODE_BASE` if you ever need to jump over a
  manual upload.

Local signed bundle (same keystore as CI):

```bash
just android-bundle
```

## Tester-facing release notes

Play listing "what's new" is 500 characters. The longer What to Test file is
operator copy for GitHub / email, same shape as TestFlight.

Any pull request that can trigger a Play upload must replace
`Apps/Android/Play/WhatToTest.en-US.txt` **and** the 500-character
`whatsnew-en-US`. Required What to Test format:

```text
New and changed

- Pair over Bluetooth, join the camera's Wi-Fi, and watch a live view with waveform and assists.

Fixes

- Nothing to call out yet — this is the first closed-beta build.

What to test

- Pair an Osmo Pocket 4 Pro, join its Wi-Fi, and confirm live view fills the monitor.
```

Write for camera operators:

- Include only behavior visible in the Android app.
- Say what changed for the tester, not how it was implemented.
- Use the names testers see in the app.
- Keep **New and changed** to 1-6 bullets, **Fixes** to 1-8, **What to test** to 1-5 concrete actions.
- Exclude iPhone, TestFlight, website, CI, architecture, identifiers, issue numbers, and source-file details.

`scripts/android-release-notes-check.sh` enforces the format. Pull-request CI
also verifies that the notes files changed when Android production paths
changed.

Preview locally:

```bash
just android-play-notes
```

## Version numbers

| Field | Source | Example |
| --- | --- | --- |
| **Product version** (Play "Version") | `openpocketcine.versionName` | `0.1.0` |
| **versionCode** (Play "Build") | CI stamp | `1`, `2`, … |

Keep `openpocketcine.versionName` equal to iOS `MARKETING_VERSION`. Bump the
product version only when starting a new train. Daily closed-testing uploads
stay on the current train. See [`RELEASE.md`](RELEASE.md). The first closed
release of the app sits in Play review; later builds of that version are often
faster.

```bash
just android-version
```

## Store listing copy

Short description (80 characters):

```text
Open-source field monitor for DJI Osmo. Live view, scopes, camera control.
```

Full description (paste into Play Console):

```text
OpenPocketCine is a free, open-source field monitor for DJI Osmo.

Pair over Bluetooth, join the camera's Wi-Fi, and watch a live view with
waveform, parade, histogram, and vectorscope. False colour, zebras, peaking,
and LUTs sit on the picture. Record, ISO, white balance, zoom, and gimbal
from the phone.

This closed beta is arm64 only (64-bit phones, Android 10+). It is tested on
Osmo Pocket 4 Pro. Pocket 4 and Pocket 3 are untested. There is no account
in the app.

Source: https://github.com/erik-sutton95/OpenPocketCine
Docs: https://openpocketcine.app/docs/
Privacy: https://openpocketcine.app/privacy/
```

Privacy policy URL: <https://openpocketcine.app/privacy/>
Support URL: <https://openpocketcine.app/support/>

Phone screenshots must be **Android** captures. Do not reuse iPhone marketing
frames on the Play listing.

## Testers

1. Export the Tally waitlist (CSV). Keep it out of git.
2. `python3 scripts/prepare-android-testers.py ~/Downloads/tally.csv`
3. Play Console → Closed testing → Testers → upload `.local/play-testers.csv`

Play also emails testers when they are added.

## Crash reports

Play Console Vitals is the crash source once testers install from Play. There
is no third-party crash SDK. Native Swift `.so` frames are easier to read if
you keep a matching AAB from the Actions run.

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Workflow skipped on `main` | `ANDROID_PLAY_UPLOAD` is not `true`; dispatch it once by hand |
| `ANDROID_KEYSTORE_BASE64 is empty` | Environment **play-closed** secrets missing; re-run the wizard |
| Insufficient permissions | Service account invited in Play Console, but wait 15–60 minutes |
| Package not found | First AAB has not been uploaded in the Console yet |
| Testers see nothing | Closed release still in review; or they have not tapped Become a tester |
| "Device not compatible" | 32-bit phone, or Android older than 10 |
| versionCode collision | Raise `ANDROID_VERSION_CODE_BASE` above the Play high-water mark |
