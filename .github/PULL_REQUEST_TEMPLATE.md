## What & why

<!-- What does this PR change, and why? Link any related issue. -->

## Tester notes

<!--
If this PR can trigger a TestFlight or Play build, replace WhatToTest (and
Android whatsnew) with the this-build window: this PR plus up to three other
newest operator-visible feat/fix items this platform can see.
Run `just tester-notes-window`. See docs/tester-notes.md.
- New features (1-4) for a capability-only window
- Or New and changed (1-3) / Fixes (1-4) / What to test (1-3)
CHANGELOG.md stays cumulative. For a build with no tester-facing behavior, say that.
-->

## Checklist

- [ ] `just check` passes.
- [ ] Native production changes: `just native-check` passes, or the relevant platform check is noted.
- [ ] Commits follow Conventional Commits.
- [ ] No captures, Wi-Fi passwords, unofficial LUT dumps, signing material, or other secrets.
- [ ] Docs/CHANGELOG updated if behavior or setup changed. Public handbook pages updated when protocol, app, or setup visitors read has changed.
- [ ] TestFlight- or Play-triggering changes replace WhatToTest with the this-build window (`docs/tester-notes.md`).
- [ ] iOS release PRs: bump `MARKETING_VERSION` in `ios/Config/Version.xcconfig` when starting a new version train.
