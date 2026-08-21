# Commit Hygiene (never leak into this public repo)

**Purpose:** This is an Apache-2.0 open-source repository. Anything committed is effectively
permanent and world-readable — even a later deletion leaves it in history, forks, clones, and
caches. This guide is the gate that keeps secrets, personal data, and non-distributable material
out of the repo in the first place.

**Golden rule:** If you are unsure whether something is safe to commit, do not commit it. Ask, or
leave it in a gitignored directory. Removing it after the fact requires a history rewrite and a
force-push (see the recovery section).

## Run this checklist before every commit and push

1. **Review the staged diff, not just file names.** Run `git diff --staged` and actually read it.
   Secrets hide in changed lines, fixtures, logs, and pasted error output.
2. **Run the secret scan.** `just secrets` (gitleaks). It also runs inside `just check`, the
   pre-commit hook, and CI — but run it yourself first.
3. **Confirm no local-only paths are staged.** Nothing under `captures/`, `Osmo LUTS/`, `vendor/`,
   `ref/`, or `.local/` should ever appear. Run `just hygiene` and review
   `git diff --staged --name-only`.
4. **Confirm the commit author is the public identity.** `git config user.email` should be the
   project's public personal email, never a company or employer address.
5. **Scan for accidental personal data and machine paths.** No home directory paths revealing
   identity, no camera Wi-Fi passwords, no private contact details.

If any check fails, unstage the offending content (`git restore --staged <path>`), fix it, and
re-run the checklist.

## What must never be committed

- **Credentials and secrets.** API keys, access tokens, OAuth client secrets, session cookies,
  passwords, connection strings, `.env` files, private keys (`*.pem`, `*.key`, `*.p12`, `*.pfx`),
  signing keystores (`*.keystore`, `*.jks`), Apple provisioning profiles and certs
  (`*.mobileprovision`, `*.cer`), and cloud service-account files (`google-services.json`,
  `GoogleService-Info.plist`, `*credentials*.json`). When a real key is needed, load it from the
  environment or a gitignored file and commit only an `.env.example` with placeholder values.
- **Camera Wi-Fi passwords.** Pairing dumps, Keychain exports, and packet captures can contain the
  SoftAP passphrase. Keep them under `captures/` (gitignored).
- **Personal information (PII).** Real email addresses (other than the project's public commit
  identity), legal names, home addresses, phone numbers, device identifiers, and account handles.
  Route contact through GitHub-native channels (Security Advisories, maintainer profiles).
- **Vendor / proprietary protocol material.** Any vendor SDK, specification PDF, header, binary, or
  network capture (`*.pcap`, `*.pcapng`). Protocol facts must be attributable to public sources in
  the [protocol handbook](https://openpocketcine.app/docs/)
  (`handbook/src/content/docs/`) and hardware observation — never pasted from proprietary
  DJI documentation.
- **Unofficial LUT dumps.** The bundled official Rec.709 cubes under
  `ios/OpenPocketCine/Resources/` are redistributable and tracked. Copies under `Osmo LUTS/`
  (duplicate names, vivid variants, files with spaces) stay local and gitignored.
- **Internal planning dumps.** `.planning/`, `STATUS.md`, and `OVERNIGHT.md` are local working
  notes. Public direction lives in [`ROADMAP.md`](ROADMAP.md).
- **Raw working media.** Layered design files, unreviewed captures, and full-resolution marketing
  sources stay under `.local/`. Only reviewed, optimized runtime exports belong in `site/`.

## Why a gitignore entry is not enough

`.gitignore` only stops *untracked* files from being added by accident. It does nothing for content
pasted *inside* a tracked file (a key in a source constant, a token in a test, a captured payload
in a comment). That class of leak is exactly what the secret scan and the staged-diff review catch.
Treat the three layers as complementary: gitignore (whole files), gitleaks (content), and human
review of the staged diff (judgment).

## Defense layers in this repo

- `.gitignore` — blocks whole categories of sensitive files (`captures/`, `Osmo LUTS/`, keys,
  certs, unofficial `*.cube` dumps, `.env`).
- `just hygiene` — rejects forbidden tracked paths, sensitive binary types, generated trees, and
  machine-specific home-directory paths. CI runs the same script.
- `.gitleaks.toml` + `just secrets` — content secret scanning, with an allowlist for known-safe
  values.
- `.githooks/pre-commit` — runs the staged form of the repository-hygiene guard and the secret
  scan. Enable it once per clone with `just setup` (it sets `core.hooksPath`). It also blocks a
  locally-forbidden author identity when `git config hooks.forbiddenEmailPattern` is set
  (per-clone, not committed).
- CI — runs the secret scan as a required check so nothing merges to `main` unscanned.

## If something sensitive was already committed

1. Stop. Do not just delete it in a new commit — the old content stays in history.
2. Rotate the exposed credential immediately (assume it is compromised the moment it is pushed).
3. Rewrite history to purge it from every commit (`git filter-repo`), prune `refs/original`, expire
   the reflog, and `git gc --prune=now`.
4. Verify with `git grep -i <token> $(git rev-list --all)` returning empty across every ref.
5. Force-push the rewritten branch and delete any branches/PRs that forked the tainted history.

OpenZCine published from a squashed initial commit rather than carrying private R&D history.
Prefer the same clean-slate publish if this repository still contains captures, device identifiers,
or personal email addresses in old commits.
