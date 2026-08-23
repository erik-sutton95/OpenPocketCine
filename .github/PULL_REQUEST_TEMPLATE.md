## What & why

<!-- What does this PR change, and why? Link any related issue. -->

## TestFlight notes

<!--
If this PR changes Sources/, Tests/, ios/, Package.swift, scripts/, or justfile, replace
ios/TestFlight/WhatToTest.en-US.txt:
- New and changed (1-6 bullets)
- Fixes (1-8 bullets)
- What to test (1-5 concrete actions)
Write for camera operators. For a build with no tester-facing app behavior, say that plainly.
-->

## Checklist

- [ ] `just check` passes.
- [ ] Native production changes: `just native-check` passes, or the relevant platform check is noted.
- [ ] Commits follow Conventional Commits.
- [ ] No captures, Wi-Fi passwords, unofficial LUT dumps, signing material, or other secrets.
- [ ] Docs/CHANGELOG updated if behavior or setup changed. Public handbook pages updated when protocol, app, or setup visitors read has changed.
- [ ] TestFlight-triggering changes include reviewed `ios/TestFlight/WhatToTest.en-US.txt` copy.
- [ ] iOS release PRs: bump `MARKETING_VERSION` in `ios/Config/Version.xcconfig` when starting a new version train.
