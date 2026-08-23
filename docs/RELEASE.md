# Git and releases

Trunk-based GitHub Flow. One long-lived branch (`main`), short-lived PRs, annotated
**`v*`** tags for product trains. Not Git Flow: there is no `develop` branch, no
standing `release/*`, and no `git-flow` CLI.

This matches how the repo already ships: PRs into `main`, squash merge, linear
history, **CI gate**, TestFlight from `main`. See
[`repository-settings.md`](repository-settings.md) and
[`testflight-ci.md`](testflight-ci.md).

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
| Android build | `openpocketcine.versionCode` in `Apps/Android/gradle.properties` | `7` |

Keep `MARKETING_VERSION` and `openpocketcine.versionName` equal. Testers see
`0.1.0 (42)` on iOS and `0.1.0 (7)` on Android — same train, different builds.

Bump the product version only when starting a new train (`0.1.0` → `0.2.0`).
Daily TestFlight uploads stay on the current train. The first external TestFlight
build of a new marketing version needs TestFlight App Review.

Bump `versionCode` when shipping an Android artifact that must exceed a previous
install (Play / internal testing). iOS build numbers are the cloud counter.

```bash
just ios-version
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
