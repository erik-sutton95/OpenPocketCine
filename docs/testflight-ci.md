# TestFlight (Xcode Cloud)

Xcode Cloud is the TestFlight path: Apple-managed signing, a build counter, and a native
upload after archive. There is no GitHub Actions TestFlight workflow.

Public join link: <https://testflight.apple.com/join/1tmt3aEB>

## What the cloud workflow does

| Step | Where it lives |
| --- | --- |
| Generate `ios/OpenPocketCine.xcodeproj` | [`ios/ci_scripts/ci_post_clone.sh`](../ios/ci_scripts/ci_post_clone.sh) (`xcodegen`) |
| Frame.io xcconfig injection | same script + optional Xcode Cloud environment variables |
| Archive + TestFlight upload | Xcode Cloud Archive action, deployment **TestFlight and App Store** |
| Build number | Xcode Cloud's own counter (stamped automatically) |
| Marketing version | [`ios/Config/Version.xcconfig`](../ios/Config/Version.xcconfig) |
| Tester notes | [`ios/TestFlight/WhatToTest.en-US.txt`](../ios/TestFlight/WhatToTest.en-US.txt) |

`ios/ci_scripts/` sits next to the generated `OpenPocketCine.xcodeproj`, which is how Xcode Cloud
finds the hooks.

One-time App Store Connect / Xcode setup is the wizard:

```bash
./scripts/setup-xcode-cloud.sh
```

That walkthrough reuses the App Store Connect record for `com.opencapture.openpocketcine`,
connects this GitHub repo, and defines the `main` Archive workflow.

## Watch companion signing

Register both explicit bundle IDs in **Certificates, Identifiers & Profiles** on
the Apple Developer team used by the workflow:

- iPhone app: `com.opencapture.openpocketcine`
- Watch companion: `com.opencapture.openpocketcine.watch`

Xcode Cloud cannot register a new Watch bundle ID during export. A successful
simulator build or unsigned archive does not prove this prerequisite is met.
Local Xcode automatic signing can register the identifier and create its
provisioning profile when the signed-in account has permission. See Apple's
[Xcode Cloud setup guidance](https://developer.apple.com/documentation/xcode/configuring-your-first-xcode-cloud-workflow).

If all distribution exports fail after adding a target, download the build's
**Logs** artifact from Xcode Cloud → Archive → **Artifacts**. Read
`app-store-export-archive-logs/xcodebuild-export-archive.log`; the summary's exit
code 70 and `IDEDistribution.critical.log` may omit the actionable provisioning
error. For `Automatic signing cannot register bundle identifier` followed by
`No profiles ... were found`, verify the named identifier is registered on the
workflow's team; register it if missing. If it already exists, check that the
target and workflow use the same team and that Cloud can access the required
provisioning profiles, then rebuild. Keep downloaded logs and provisioning
profiles outside git.

## After the workflow exists

- **Merges to `main`** that touch `Sources/`, `Tests/`, `ios/`, `Package.swift`, `scripts/`, or
  `justfile` should start an Archive. Restrict the workflow's **Files and Folders** start
  condition to those paths so docs-only commits do not burn the monthly hours.
- **Environment**: latest released Xcode and macOS. Optional **secret** environment variables
  `FRAMEIO_CLIENT_ID`, `FRAMEIO_REDIRECT_URI`, `FRAMEIO_URL_SCHEME` (omit to ship with Frame.io
  login disabled).
- **Post-actions**: TestFlight Internal Testing for the first smoke; External Testing once a
  version has passed TestFlight App Review. External groups cannot install an
  internal-testing-only archive.
- **Next build number**: set it above any existing TestFlight build for this bundle ID. If this
  App ID already has private R&D uploads, start above that high-water mark.

## Tester-facing release notes

**this-build** window by default. A maintainer-named open-beta baseline instead
uses the cumulative release window: [`tester-notes.md`](tester-notes.md).
For routine internal builds, a pull request that can trigger a TestFlight build replaces
`ios/TestFlight/WhatToTest.en-US.txt` with this PR plus up to three other
newest operator-visible `feat:` / `fix:` items iPhone testers can see.
**New features** (1–4) for a capability-only window; three-section form when
testers need a named fix or a concrete action.

```bash
just tester-notes-window
just testflight-notes
```

`scripts/ios-release-notes-check.sh` enforces the format. Pull-request CI also verifies that the
notes file changed when iOS production paths changed.

TestFlight screenshot feedback cannot carry an attached file (Apple has no
API for that). The app copies a redacted compact report to the pasteboard
when the tester screenshots; they paste it into the feedback comment.
Crashes still go to App Store Connect automatically. Full report:
Connection setup **Share Diagnostics**, or Operator Setup → System →
Share Diagnostics. Contract: [`diagnostics.md`](diagnostics.md).

## Version numbers

| Field | Source | Example |
| --- | --- | --- |
| **Marketing version** (TestFlight “Version”) | `MARKETING_VERSION` in `ios/Config/Version.xcconfig` | `0.1.0` |
| **Build number** (TestFlight “Build”) | Xcode Cloud counter | `1`, `2`, … |

Keep the marketing version stable so uploads stay in the same TestFlight version train. Bump
`MARKETING_VERSION` only when starting a new train (`0.1.0` → `0.2.0`), and keep Android
`openpocketcine.versionName` equal. Product tags are `v0.2.0` on `main`, not a tag per
cloud build. See [`RELEASE.md`](RELEASE.md). The first external build
of a version needs [TestFlight App Review](https://developer.apple.com/help/glossary/testflight-app-review/);
later builds of that version often do not.

```bash
just ios-version
```

## Crash reports

Apple's TestFlight pipeline is the crash source. Testers share crash reports with the developer;
Xcode uses the archive dSYMs to symbolicate. Review them in Xcode Organizer under **Crashes**, or
in App Store Connect.

See Apple's [crash reports](https://developer.apple.com/documentation/xcode/acquiring-crash-reports-and-diagnostic-logs)
and [debugging information](https://developer.apple.com/documentation/xcode/building-your-app-to-include-debugging-information)
notes. `ITSAppUsesNonExemptEncryption` is `NO` so TestFlight does not stall on the export-compliance
prompt (the app only uses Apple ATS/HTTPS).

## Troubleshooting

| Symptom | Likely cause |
| --- | --- |
| Cloud build cannot open `OpenPocketCine.xcodeproj` | `ci_post_clone.sh` did not run or `xcodegen` failed |
| Export cannot register the Watch bundle ID and finds no profiles | Check identifier registration, team alignment and provisioning access; see [Watch companion signing](#watch-companion-signing) |
| Frame.io login missing in the build | Add the three `FRAMEIO_*` environment variables on the workflow |
| “Build number already used” | Raise the workflow's next build number above the App Store Connect high-water mark |
| Archive succeeds but testers see nothing | Wait for processing; first external build of a version sits in TestFlight App Review |
| Export compliance questionnaire | Confirm `ITSAppUsesNonExemptEncryption` is in the built Info.plist |
