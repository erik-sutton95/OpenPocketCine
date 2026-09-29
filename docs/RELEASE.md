# Git and releases

Trunk-based GitHub Flow. One long-lived branch (`main`), short-lived PRs, annotated
**`v*`** tags for product trains. Not Git Flow: there is no `develop` branch, no
standing `release/*`, and no `git-flow` CLI.

This matches how the repo already ships: PRs into `main`, squash merge, linear
history, **CI gate**, TestFlight from `main`, Play closed testing from `main`
once `ANDROID_PLAY_UPLOAD` is on. See
[`repository-settings.md`](repository-settings.md),
[`testflight-ci.md`](testflight-ci.md), and
[`android-play-ci.md`](android-play-ci.md).

## Branches

| Branch | Lifetime | Purpose |
| --- | --- | --- |
| `main` | Forever | Only long-lived branch. Protected. Never commit here. |
| `feat/…`, `fix/…`, `docs/…`, `chore/…`, `ci/…`, `test/…` | One PR | Work. Name matches the Conventional Commit type. |
| `release/x.y` or `hotfix/x.y.z` | Until tagged | **Exception only** — see below. |

Open a PR into `main`. CI runs on the PR, not a second time on the branch push.
Squash merge. Delete the head branch (GitHub already does this).

Agents: same rules. Do not push `main`. Do not create tags (human gate).

## Version numbers

One **product** semver for iOS and Android. Two **store** counters.

| Field | Source | Example |
| --- | --- | --- |
| Product version | iOS `MARKETING_VERSION` in `ios/Config/Version.xcconfig` **and** Android `openpocketcine.versionName` in `Apps/Android/gradle.properties` | `0.1.0` |
| iOS build | Xcode Cloud counter (`CURRENT_PROJECT_VERSION` locally is not the cloud stamp) | `42` |
| Android build | Play workflow stamp (`ANDROID_VERSION_CODE_BASE` + `github.run_number`). Local `openpocketcine.versionCode` is the sideload floor. | `7` |

Keep `MARKETING_VERSION` and `openpocketcine.versionName` equal. Testers see
`0.1.0 (42)` on iOS and `0.1.0 (7)` on Android — same train, different builds.

Bump the product version only when starting a new train (`0.1.0` → `0.2.0`).
Daily TestFlight and Play closed-testing uploads stay on the current train. The
first external TestFlight build of a new marketing version needs TestFlight App
Review. The first closed Play release of the app sits in Play review.

iOS build numbers are the Xcode Cloud counter. Android Play `versionCode` is the
Actions stamp — do not bump `openpocketcine.versionCode` for every closed-testing
upload. Raise `ANDROID_VERSION_CODE_BASE` only to jump over a manual upload.

```bash
just ios-version
just android-version
```

## Tags

Tags mark **trains**, not every TestFlight or CI run. Annotated, from `main`:

```bash
git checkout main && git pull
git tag -a v0.2.0 -m "OpenPocketCine 0.2.0"
git push origin v0.2.0
```

Then a GitHub Release from that tag. Changelog: move `[Unreleased]` entries under
`## [0.2.0] - YYYY-MM-DD` in the same version-bump PR. TestFlight and Play tester
notes are a this-build window, not that changelog — [`tester-notes.md`](tester-notes.md).

One tag for both platforms (`v0.2.0`). Do not cut `ios/0.2.0` and `android/0.2.0`
unless the apps actually ship different product versions — they share the Swift
core, so they should not.

Do not tag `v0.1.0` retroactively unless you are cutting that train on purpose.

## Sideload APK

Every merge into `main` that changes the app (Android, iOS or the shared Swift
core) gets a new GitHub sideload APK, so Android users without Play stay on the
latest build. Docs-only and CI-only merges do not need one. Sideload tags are
`sideload-v<versionName>-<n>`, where `<n>` counts sideload builds on the train
(`sideload-v0.1.5-5` was `versionCode` 6).

1. **Bump.** One `chore(android)` PR raises `openpocketcine.versionCode` in
   `Apps/Android/gradle.properties` by one (Android refuses to install over an
   equal code) and points both README APK links at the next tag. Merge it.
2. **Build** from that `main` commit with the release keystore and the Android
   Sentry DSN (both local only, under `.local/android/`, never committed):

   ```bash
   export ANDROID_KEYSTORE_FILE=… ANDROID_KEYSTORE_PASSWORD=… \
     ANDROID_KEY_ALIAS=… ANDROID_KEY_PASSWORD=… SENTRY_DSN_ANDROID=…
   just android-core
   (cd Apps/Android && ./gradlew assembleRelease)
   ```

   Check `aapt2 dump badging` shows the new `versionCode`, and
   `apksigner verify --print-certs` the same certificate as the previous
   sideload APK.
3. **Publish** `app-release.apk` as `OpenPocketCine-<versionName>-<n>-sideload.apk`:

   ```bash
   gh release create sideload-v0.1.5-6 OpenPocketCine-0.1.5-6-sideload.apk \
     --target <main sha> --title "OpenPocketCine 0.1.5 (6)" --latest \
     --notes "<what changed, in user terms>

   Installs over any earlier OpenPocketCine 0.1.5 sideload build. One arm64 APK, Android 10 or newer. A Google Play copy is signed differently: remove it before installing."
   ```

   Keep earlier sideload releases unless they must be withdrawn.

## Hotfix / freeze (rare)

A `release/x.y` or `hotfix/x.y.z` branch exists only when **all** of these hold:

- Testers (or Play) are on `x.y` / `x.y.z`
- `main` already has work that must not ship on that train
- A fix must land on the shipped train anyway

Branch from the train tag (or from `main` if it still *is* that train). PR the
fix into the release branch **and** into `main`. Tag, then delete the branch.
This is not a standing `develop`.

## Contributors

When a second person gets write access, turn **admin enforcement** on for `main`
([`repository-settings.md`](repository-settings.md)). Required review then
applies to everyone, including the original maintainer.
