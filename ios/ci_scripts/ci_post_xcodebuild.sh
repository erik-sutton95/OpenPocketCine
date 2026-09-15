#!/bin/sh
# Xcode Cloud: validate the reviewed TestFlight "What to Test" notes for distributed builds.
# Xcode Cloud picks up WhatToTest.<locale>.txt from the tracked TestFlight folder next to
# the ci_scripts folder (i.e. ios/TestFlight/).
set -eu

if [ -d "${CI_APP_STORE_SIGNED_APP_PATH:-}" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  ./scripts/ios-release-notes.sh
fi

# Every successful Cloud archive must support the automatic-reporting choice.
# Symbol uploads are optional; the app's reporting destination is not.
# Contract: docs/sentry-deployment.md
if [ "${CI_XCODEBUILD_ACTION:-}" = "archive" ] \
    && [ "${CI_XCODEBUILD_EXIT_CODE:-0}" = "0" ]; then
  cd "$CI_PRIMARY_REPOSITORY_PATH"
  app_plist="${CI_ARCHIVE_PATH}/Products/Applications/OpenPocketCine.app/Info.plist"
  python3 ./tools/sentry-verify-ios-dsn.py --plist "$app_plist" --require

  if [ "${SENTRY_UPLOAD_ENABLED:-}" = "true" ]; then
    install_dir="${CI_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}}/opc-sentry-cli"
    bash ./tools/sentry-install.sh --install-dir "$install_dir"
    PATH="${install_dir}:${PATH}"
    export PATH
    python3 ./tools/sentry-upload.py --platform ios
  fi
fi
