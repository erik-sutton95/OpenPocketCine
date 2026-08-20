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

## Actions

- Actions on. Default `GITHUB_TOKEN` is read-only. SHA-1 pinning required.
- Workflows may not create or approve pull requests.
- First-time contributors' fork workflows need approval (set at publish).
- No repository secrets. Optional Pages variable: `TESTFLIGHT_URL`.
- Hosted runners only. Do not add a self-hosted runner — CI executes pull
  request code.

CI (`.github/workflows/ci.yml`): meta checks and gitleaks always run. Native
iOS and Android jobs skip while the repository is private (paid macOS minutes)
and run once it is public. The **CI gate** job is the merge gate even when
those jobs are skipped.

The landing-page workflow deploys only `site/` to GitHub Pages. The PR labeler
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
