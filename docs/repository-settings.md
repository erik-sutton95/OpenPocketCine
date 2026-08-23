# Repository settings

Target GitHub configuration for the public OpenPocketCine repository. Apply
changes through the API or
[`scripts/go-public.sh`](../scripts/go-public.sh); do not weaken these by hand.

## Branch `main`

- Pull request required. One approving review. Stale reviews dismissed.
- Conversation resolution required. Linear history. Squash merge only. Delete
  the head branch on merge.
- Required status check: **CI gate** (must be up to date with `main`).
- No force pushes. No branch deletion.
- Admin enforcement is off so the solo maintainer can merge their own PRs
  after CI. Do not give anyone else write access without turning admin
  enforcement on.
- No `develop` branch. Feature work is PRs into `main`; product trains are
  annotated `v*` tags. See [`RELEASE.md`](RELEASE.md).

## Actions

- Actions on. Default `GITHUB_TOKEN` is read-only. SHA-1 pinning required.
- Workflows may not create or approve pull requests.
- First-time contributors' fork workflows need approval (set at publish).
- No repository secrets. Optional Pages variable: `TESTFLIGHT_URL`.
- Hosted runners only. Do not add a self-hosted runner — CI executes pull
  request code.

CI (`.github/workflows/ci.yml`) runs **once** per pull request (`pull_request`
into `main`) and once per merge (`push` to `main`). Feature-branch pushes do
not start a second suite: that duplicated every job on the PR checks list.
Re-run a branch without a PR with **Run workflow**. Meta checks always run and
include gitleaks. Native iOS, Android, and the protocol handbook run only when
their paths change (and native/Android also skip while the repository is
private so they do not burn paid macOS minutes). Skipped jobs are success.
The **CI gate** job is the only required check — do not require Native,
Android, or handbook by name, or a docs PR stays blocked waiting for a check
that never reports. The Android job installs the official Swift 6.3.3 Android
SDK with `scripts/ci-install-swift-android.sh` — do not switch back to
`skiptools/swift-android-action`; that composite references `actions/cache@v5`
and `reactivecircus/android-emulator-runner@v2`, which SHA pinning rejects.

The Pages workflow deploys `site/` (landing) plus the Starlight handbook at
`/docs/`. Engineering notes in `docs/` are never uploaded. The PR labeler
uses `pull_request_target` and does **not** check out pull-request code.

## Security

- [`SECURITY.md`](../SECURITY.md) sends reports to private advisories.
- Dependabot alerts and security updates on. Weekly Dependabot for GitHub
  Actions and `Apps/Android` Gradle.
- Secret scanning and push protection: unavailable on this private repo;
  enable them immediately after making the repository public.
- Private vulnerability reporting: enable after public.
- `just secrets` / gitleaks and `.githooks/pre-commit` still scan locally.

## History at publish

gitleaks and `just hygiene` were clean. Commit authors include GitHub noreply
and a personal Gmail. History was not rewritten. A later deletion does not
remove those commits from forks or clones.

## Do not

- Disable the CI workflow (`disabled_manually` previously stopped all checks).
- Allow force pushes to `main`.
- Add secrets to `pull_request` workflows (forks would see them).
- Point CI at a self-hosted runner.
