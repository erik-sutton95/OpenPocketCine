# Tester notes

TestFlight and Play What to Test is **this-build**: the operator-visible
work testers have not already been asked to try. It is not a product recap
and not `CHANGELOG.md`. Testers who skip a build still have the app.

When the maintainer names a previous open-beta build, use the cumulative window
below instead. Internal uploads do not reset that public-beta baseline.

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

## Cumulative open-beta window

For a named baseline, include every operator-visible addition and fix since that
build, grouped by behavior and written for each platform. Locate the baseline in
build history or earlier release notes; do not substitute a count of commits or
the most recent four changes. If its source commit cannot be retrieved, retain
the named build, disclose that limit in the PR, and review the full candidate
history rather than claiming an exact commit diff. Describe the final behavior, combining repeated fixes to
the same feature. Keep experimental labels and platform limitations.

Start both longer files with `Since open beta build N`, where `N` is the previous
public-beta build number. It identifies the shared release window; it does not
change Android's version code. Follow it with the usual **New and changed**,
**Fixes**, and **What to test** sections. This explicit marker allows up to
16 new/changed bullets, 20 fixes, and 5 test actions, with a 4,000-character file
cap. Each bullet still stays within 200 characters. Routine notes without the
marker retain their smaller limits.

Publish the full platform lists together in the handbook's release notes and
link them from Play's 500-character short summary. Keep the cumulative
`CHANGELOG.md` accurate too. Record the baseline build and target beta build
with the public release notes so the next update has a clear starting point.

Return to the short format only when preparing a routine internal build or
when the maintainer selects a new release window.

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
