#!/bin/sh
# Xcode Cloud: every archive uploads to TestFlight. Fail before building when the tester notes
# break the caps, or, outside TestFlight Internal, when an earlier TestFlight build already
# carried them (docs/ci.md, Release time). Xcode Cloud reports "<app> | TestFlight ..."
# commit statuses.
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  ./scripts/ios-release-notes-check.sh
  # TestFlight Internal archives every merge to main and keeps the version's notes; any other
  # archive workflow reaches testers and needs notes no earlier TestFlight build carried.
  if [ "${CI_WORKFLOW:-}" != "TestFlight Internal" ]; then
    python3 ../OpenCine/scripts/tester-notes-release-check.py --repo erik-sutton95/OpenPocketCine \
      --released-by-status TestFlight --notes ios/TestFlight/WhatToTest.en-US.txt
  fi
fi
