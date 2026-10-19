#!/bin/sh
# Xcode Cloud: every archive uploads to TestFlight, so it is a release. Fail before building
# when the tester notes break the caps or an earlier TestFlight build already carried them
# (docs/tester-notes.md). Xcode Cloud reports "<app> | TestFlight ..." commit statuses.
set -eu

if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  ./scripts/ios-release-notes-check.sh
  python3 ../OpenCine/scripts/tester-notes-release-check.py --repo erik-sutton95/OpenPocketCine \
    --released-by-status TestFlight --notes ios/TestFlight/WhatToTest.en-US.txt
fi
