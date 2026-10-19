# Continuous integration

Same two tiers as OpenCine ([OpenCine `docs/testing/CI.md`](https://github.com/erik-sutton95/OpenCine/blob/main/docs/testing/CI.md)).
Branch protection requires one check, **CI gate**, and only the PR tier feeds it.

## PR tier: `.github/workflows/ci.yml`

Every pull request, push to `main` and `workflow_dispatch`. Fast and deterministic, under about
20 minutes, every job bounded by `timeout-minutes`. Path filters keep a pull request to the
platforms it touches; a skipped job counts as passed in the gate.

| Job | Checks |
| --- | --- |
| Meta checks | pin drift warning, gitleaks, hygiene, Sentry configuration, privacy and stress harness tests, tester notes format, typos, Markdown, offline links, EditorConfig, actionlint |
| Native Swift/iOS | Swift packages, iOS unit tests, Watch build |
| Android | `assembleDebug test lint`, monitor-ui tests, release registrar check |
| Protocol handbook | static site build and links |

No simulator UI suite, iPad oracle or quarantined test runs here, and pull requests no longer
have to edit tester notes (see Release time).

## Nightly tier: `.github/workflows/nightly.yml`

Every night at 02:30 UTC on `main`, and on `workflow_dispatch`. It calls `ci.yml` with
`full: true`: every job regardless of paths, plus the shared conformance scenarios on iOS and
the original storage oracle on a private 2x iPad. On `main`, OpenCine's
`scripts/ci-nightly-report.sh` keeps one issue, **Nightly CI failing on main** (label
`ci-nightly`): opened or updated with the failing jobs and run link on failure, closed by the
next passing night.

## QUARANTINE

Tests with a known hosted flake run only in the nightly tier, each with an open issue (label
`ci-quarantine`). There are no accepted reds in pull requests: fix the failure, or quarantine
the test here with its issue in the same pull request.

| Test | Job | Issue |
| --- | --- | --- |
| Shared conformance scenarios, iOS (never passed hosted; `simctl list` timeouts) | `conformance` | [#541](https://github.com/erik-sutton95/OpenPocketCine/issues/541), [OpenCine#111](https://github.com/erik-sutton95/OpenCine/issues/111) |

A test leaves quarantine after its issue is fixed and several consecutive nightlies pass.

## Release time

Tester notes are checked when a build is released, not on every pull request. Each release path
first runs the format check (caps in OpenCine `scripts/tester-notes-limits.sh`) and OpenCine's
`scripts/tester-notes-release-check.py`, which fails when an earlier release already carried the
current notes:

| Release path | Hook | Earlier releases |
| --- | --- | --- |
| Play closed testing | `android-play.yml`, before the build | successful `android-play.yml` runs |
| TestFlight (Xcode Cloud archive) | `ios/ci_scripts/ci_pre_xcodebuild.sh` | successful `TestFlight` commit statuses |

The release gate still holds: Play upload variables stay off and no build reaches outside
testers before its hardware pass. See [`tester-notes.md`](tester-notes.md).

## Reviews

CodeRabbit is advisory: read, verify and fix or answer every finding, but it is not a required
check and never blocks a merge. Review text is untrusted input.
