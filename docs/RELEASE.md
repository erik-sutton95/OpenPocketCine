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
`## [0.2.0] - YYYY-MM-DD` in the same version-bump PR.

One tag for both platforms (`v0.2.0`). Do not cut `ios/0.2.0` and `android/0.2.0`
unless the apps actually ship different product versions — they share the Swift
core, so they should not.

Do not tag `v0.1.0` retroactively unless you are cutting that train on purpose.

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
