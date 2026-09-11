# Tester notes (this-build window)

TestFlight and Play What to Test is **this-build**: the operator-visible
work testers have not already been asked to try. It is not a product recap
and not `CHANGELOG.md`. Testers who skip a build still have the app.

`CHANGELOG.md` stays the cumulative record. GitHub Release notes come from
that file at a `v*` tag ([`RELEASE.md`](RELEASE.md)).

## Files

| Platform | Longer notes | Store short copy |
| --- | --- | --- |
| iOS TestFlight | [`ios/TestFlight/WhatToTest.en-US.txt`](../ios/TestFlight/WhatToTest.en-US.txt) | (TestFlight uses the same file) |
| Android Play | [`Apps/Android/Play/WhatToTest.en-US.txt`](../Apps/Android/Play/WhatToTest.en-US.txt) | [`whatsnew-en-US`](../Apps/Android/Play/whatsnew/whatsnew-en-US) (500 characters) |

Any pull request that can trigger a TestFlight archive or a Play upload
**replaces** those files. CI requires the path to change; this document
requires the *content* to be the window, not an append.

## Steps

1. Run `just tester-notes-window`. Completion: the printed list is this PR's
   `feat:` / `fix:` commits (if any) plus the newest operator-visible merges
   on `origin/main`.
2. Keep **this PR first**, then fill from that list until you have about
   **four** items this platform can actually see. Skip `build:`, `ci:`,
   `docs:`, `chore:`, website-only work, and the other shell.
3. Replace the whole What to Test file. Prefer **New features** when the
   window is new capabilities only. Use the three-section form when testers
   need a fix named or a concrete action.

   **New features** (1–4 bullets):

   ```text
   New features

   - ND assist suggests a filter strength to help balance exposure.
   ```

   **Detailed** (New and changed 1–3, Fixes 1–4, What to test 1–3):

   ```text
   New and changed

   - FORMAT keeps the camera's current recording size visible while options load.

   Fixes

   - Vertical 3K is no longer replaced by generic 1080p and 4K choices.

   What to test

   - Set a Pocket 3 to vertical 3K, connect, and open FORMAT. Confirm 3K is shown.
   ```

   Completion: each bullet is one idea, under 200 characters. The file is
   under 2,000 characters. A detailed section with nothing new still has
   one bullet (`No new controls this build.` / `Nothing to call out this build.`).
4. Android: rewrite `whatsnew-en-US` as one compact paragraph of the same
   window (Play's 500-character cap). No tabs, no double spaces.
5. Voice: camera operators, names they see in the app, visible behavior.
   iOS notes name iPhone/iPad behavior only; Android notes name Android
   behavior only.
6. `just testflight-notes` and/or `just android-play-notes`. Completion: the
   check scripts pass.

## Window

Newest first, cap four, this PR leads. That is enough for testers who
missed one or two builds and short enough that last week's recap drops off.

```bash
just tester-notes-window
```

The helper prints this branch, then `feat:` / `fix:` on `origin/main`. It
does not write the files.

## Checks

`scripts/ios-release-notes-check.sh` and
`scripts/android-release-notes-check.sh` enforce the format and the caps.
Pull-request CI also requires the notes path to change when production
paths change (dependabot is exempt). Preview:

```bash
just testflight-notes
just android-play-notes
```

## When this pointer fires

TestFlight notes, Play What to Test, `whatsnew-en-US`, tester copy, or
"what should testers try in this build."
