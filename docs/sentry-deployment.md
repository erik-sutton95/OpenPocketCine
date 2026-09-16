# Sentry release symbol upload

Release-time debug-file upload for iOS archives and Android Play bundles, plus
Xcode Cloud DSN injection for the Cocoa SDK. Every successful Xcode Cloud
archive requires a valid reporting destination, independently of symbol uploads.
Symbol uploads and Android Play DSN enforcement remain opt-in through
`SENTRY_UPLOAD_ENABLED=true`.

The iOS shell pins Sentry Cocoa **9.24.0** in `ios/project.yml` and
[`ios/Package.resolved`](../ios/Package.resolved). Xcode Cloud requires that
lockfile in the generated workspace; see [TestFlight CI](testflight-ci.md).
Operator-visible reporting, consent, and camera-path gating stay in
[`diagnostics.md`](diagnostics.md). This document is the release/CI contract.

Hosted organization: **opencapture**. Projects:

| Platform | Slug |
| --- | --- |
| iOS | `openpocketcine-ios` |
| Android | `openpocketcine-android` |

## Two CLIs

| Tool | Version | Role |
| --- | --- | --- |
| `sentry-cli` (this repo) | **3.7.0** (pinned) | CI `debug-files check` / `debug-files upload --wait` |
| `sentry` at `~/.local/bin/sentry` | 0.45.0 (OAuth) | Maintainer hosted setup only. Not used by CI. |

Official install docs pin CI to a version rather than fetching latest:

```bash
curl -sL https://sentry.io/get-cli/ | SENTRY_CLI_VERSION="3.7.0" sh
```

Sources (checked 2026-09-14):

- [Installation](https://docs.sentry.io/cli/installation/) — example pin `3.7.0`
- [Debug information files](https://docs.sentry.io/cli/dif/) — `debug-files check` and `debug-files upload --wait`
- [Configuration](https://docs.sentry.io/cli/configuration/) — `SENTRY_AUTH_TOKEN`, `SENTRY_ORG`, `SENTRY_PROJECT`
- [Apple dSYMs](https://docs.sentry.io/platforms/apple/dsym/)
- Release registry: [sentry-cli 3.7.0](https://release-registry.services.sentry.io/apps/sentry-cli/3.7.0)

CI does **not** run the unpinned installer and does **not** use the OAuth
`sentry` binary. `tools/sentry-install.sh` downloads 3.7.0 from
`downloads.sentry-cdn.com` and checks SHA-256 in `tools/sentry-cli-checksums.txt`.
This worker must not perform live uploads.

```bash
sentry-cli debug-files check <path>
sentry-cli debug-files upload --wait --org <org> --project <project> <usable-paths>
```

Auth for CI is `SENTRY_AUTH_TOKEN` in the environment (organization token).
Never pass `--auth-token`. Never print the token or DSN. Do not set
`SENTRY_ALLOW_FAILURE`. Source context (`--include-sources`) is **never** passed.

## Enablement

| Variable | Where | Role |
| --- | --- | --- |
| `SENTRY_UPLOAD_ENABLED` | Xcode Cloud env / GitHub Actions variable | Exactly `true` to upload and require Android DSNs. iOS archives always require a DSN. |
| `SENTRY_ORG` | same | Defaults to `opencapture`. |
| `SENTRY_PROJECT` | same | Defaults to `openpocketcine-ios` or `openpocketcine-android`. |
| `SENTRY_AUTH_TOKEN` | Xcode Cloud secret / `play-closed` secret | Required when upload is enabled. |
| `SENTRY_DSN_IOS` or `SENTRY_DSN` | Xcode Cloud secret | Public https DSN for the Cocoa SDK. Injected in `ci_post_clone.sh`. |
| `SENTRY_DSN_ANDROID` | `play-closed` secret | Public https DSN for the Android SDK. Passed into `bundleRelease`. |
| `SENTRY_PROGUARD_UUID` | future Android CI | Required **if** `mapping.txt` exists. Unset + mapping is a hard fail. |

Optional: `SENTRY_URL` (self-hosted).

## iOS (Xcode Cloud)

`ios/ci_scripts/ci_post_clone.sh` writes gitignored
`Reliability.local.xcconfig` from `SENTRY_DSN_IOS` or `SENTRY_DSN`. The DSN is
encoded as `https:/$()/…` so xcconfig does not treat `//` as a comment.
`INFOPLIST_KEY_SentryDSN` alone does not reach an explicit Info.plist; the
app plist uses `SentryDSN = $(SENTRY_DSN)` (app owner). When upload is
enabled, clone **fails** without a valid https DSN.

`ios/ci_scripts/ci_post_xcodebuild.sh` after a successful **archive**, in order:

1. **Verify DSN first**, even when symbol uploads are disabled: archived app `Info.plist` must contain a substituted
   https `SentryDSN` (not empty, not `$(SENTRY_DSN)`, not the xcconfig `/$()/` form).
2. When `SENTRY_UPLOAD_ENABLED=true`, install pinned `sentry-cli` into derived data.
3. With uploads enabled, `debug-files check` on each `.dSYM` (empty bundles are not usable).
4. With uploads enabled, `debug-files upload --wait` of files that produced debug IDs. Fail if the
   wait output does not accept those IDs.

Test / build actions do not upload. Missing DSN configuration fails an archive
before symbol tooling runs. With uploads disabled, a configured archive passes
without an upload token or `sentry-cli`.

SDK release naming (app owner): `com.opencapture.openpocketcine@version+build`
with event `dist` = build number. `sourceRevision` is a separate tag, not the
Sentry dist.

SDK `environment` is **not** a user-promoted gate in the app:

| Build | `environment` |
| --- | --- |
| Ordinary Debug | `development` |
| iOS Release (TestFlight) | `testflight` |
| Android Release (Play) | `production` |
| DEBUG explicit probe only | `verification` |

Do not describe current traffic as waiting on a human to “promote” the app
environment.

## Android (Play workflow)

`.github/workflows/android-play.yml`:

1. **Before** `bundleRelease`, `tools/sentry-require-android-dsn.sh` fails if
   upload is enabled and secret `SENTRY_DSN_ANDROID` is missing. Unset DSN is
   acceptable when upload is off. Invalid DSN **shape** is handled in
   `Apps/Android` (Gradle `BuildConfig` + SDK `validated()`), not this script.
2. `bundleRelease` receives `SENTRY_DSN_ANDROID` in the environment.
3. After the signed AAB is attached and **before** Play API upload: DSN
   verification, `debug-files check`, then `debug-files upload --wait`. A
   failed enabled Sentry step stops Play upload.

Paths scanned after `bundleRelease` are **candidates** only. Suffix or an empty
`.dSYM`/`.so` is not enough; `sentry-cli debug-files check` must report
`Usable: yes` and a non-zero debug ID.

R8 `mapping.txt`: minify is **off**. If a mapping file appears anyway,
upload **fails** unless `SENTRY_PROGUARD_UUID` matches an
`io.sentry.proguard-uuid` the Android app actually ships. Uploading mappings
without that UUID cannot deobfuscate. Android Gradle owns UUID injection; this
CI does not invent one.

GitHub: variable `SENTRY_UPLOAD_ENABLED=true`, optional `SENTRY_ORG` /
`SENTRY_PROJECT`, `play-closed` secrets `SENTRY_AUTH_TOKEN` and
`SENTRY_DSN_ANDROID`. Missing Sentry secrets do **not** fail Play unless
upload is enabled.

### Local Android builds

Set `SENTRY_DSN_ANDROID` in the build environment, or put the same key in
`.local/reliability.properties` at the repository root. The non-empty environment
value takes precedence. The local file is ignored by Git and is read by both
Android Studio and the `just android-build` / `just android-install` recipes.
Use the Android project's public HTTPS DSN, never an upload token.

A build without a valid destination cannot offer automatic reporting. It leaves
consent undecided, so installing a configured update can offer the prompt without
clearing app data. Confirm the destination is configured in the generated
BuildConfig without printing its value, then check the prompt on the device.

## Server privacy (mandatory)

`scrubIP` is not enough: Sentry can still infer geo from the request. A
parent `user` application does **not** cover nested fields. Projects must keep
this relay PII config with **recursive** applications:

```json
{
  "rules": {
    "removeUser": {
      "type": "anything",
      "redaction": { "method": "remove" }
    }
  },
  "applications": {
    "user.**": ["removeUser"],
    "user.geo.**": ["removeUser"]
  }
}
```

A physical phone **fresh** event after that recursive rule verified `user` and
`user.geo` absent. The first synthetic issue/crash still has inferred geo
because the original parent `user` rule failed to match. Event DELETE returned
**403**; do not claim those historical events were retroactively scrubbed.

Hosted dashboard `6020886` (feed stage / recovery / native / session) and
alerts `824917` / `824918` are maintainer configuration. They exclude
verification/development and levels below error.

### Internal testing

The separate [Internal Testing dashboard](https://opencapture.sentry.io/dashboard/6027232/)
includes development and verification traffic. It separates manual testing,
automation, activated fault injection, verification probes and legacy/unknown
origins. Its eight queries were verified against hosted events on 2026-09-15.
Existing production dashboard and alert filters remain unchanged.

`buildIdentity` identifies source/build inputs, including dirty and untracked
source files, independently of the marketing version and build number. It is a
platform-prefixed content hash generated by `tools/build-identity.py`; it is not
a hash of the compiled binary or a replacement for a debug UUID. Ignored local
configuration and unrelated documentation are excluded. Identical selected
inputs and configuration retain the same identity. iOS stamps `OPCBuildIdentity`
into the built plist; Android generates `BuildConfig.BUILD_IDENTITY` per variant.

Ordinary iOS Debug builds generate dSYMs. Local builds still require a deliberate
symbol upload; release archives retain the existing CI upload path. Keep the
matching dSYM before cleaning build products. Two historical verification events
were missing their original debug-dylib symbols during the 2026-09-15 audit;
neither original UUID was found in local dSYMs or binaries. A rebuild cannot
repair those historical events because it produces different debug IDs.

WatchdogTermination events are SDK inferences about an unexpected prior exit.
An automated test termination can satisfy that inference. Compare test origin,
build identity and session evidence before treating a group count as confirmed
foreground hangs. Reporting remains enabled for these events.

## Local checks

No network, no real Sentry API, no device:

```bash
just sentry-test
```

`just check` already runs that recipe. Covers install checksums, upload skip /
config-error / missing or unusable symbols / `--wait` accept-none / mapping
without UUID / success (fake uploader, token and DSN redaction), DSN xcconfig
encoding, Info.plist substitution, and Android pre-bundle DSN presence.

## Remaining hosted / app work

Not owned by this CI-tooling change:

1. Keep organization token and DSNs in Xcode Cloud / `play-closed` only.
   Maintainer OAuth `sentry` 0.45.0 is for hosted setup, not CI.
2. Set `SENTRY_UPLOAD_ENABLED=true` on the Archive workflow and as a GitHub
   variable only when DSN + token are in those stores.
3. Android minify / `io.sentry.proguard-uuid` + `SENTRY_PROGUARD_UUID` if R8
   mappings become a release artifact (Android Gradle owner). Until then a
   mapping.txt in CI is a fail.
4. Store privacy disclosures if opted-in reporting is offered to testers.
5. Historical events with inferred geo cannot be deleted (API 403).

## Privacy readiness

Before production enablement, complete the [privacy operating record](sentry-privacy-operations.md), including DPA acceptance, access controls, retention and deletion verification, and store disclosures. SDK delivery tests do not establish GDPR compliance.

A 2026-09-15 simulator incident was confirmed by the SDK receipt and hosted event:
`testSource=verification` and a complete `ios-` build identity survived ingestion.
This validates event metadata delivery, not physical watchdog capture. Physical
verification of the new native breadcrumb context remains pending.
