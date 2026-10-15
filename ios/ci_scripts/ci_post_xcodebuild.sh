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
  # Validate the packaged value, including Xcode's generated Info.plist settings.
  # Linked OpenCineApple capture APIs require this even for wireless-only builds.
  python3 - "$app_plist" <<'PY'
import plistlib
import sys

with open(sys.argv[1], "rb") as source:
    info = plistlib.load(source)
purpose = info.get("NSCameraUsageDescription")
if not isinstance(purpose, str) or not purpose.strip():
    sys.exit("Archive is missing a non-empty NSCameraUsageDescription.")
print("Archive camera purpose string verified.")
PY
  python3 ../OpenCine/scripts/sentry/sentry-verify-ios-dsn.py --plist "$app_plist" --require

  if [ "${SENTRY_UPLOAD_ENABLED:-}" = "true" ]; then
    install_dir="${CI_DERIVED_DATA_PATH:-${TMPDIR:-/tmp}}/opc-sentry-cli"
    bash ../OpenCine/scripts/sentry/sentry-install.sh --install-dir "$install_dir"
    PATH="${install_dir}:${PATH}"
    export PATH
    python3 ../OpenCine/scripts/sentry/sentry-upload.py --platform ios --project openpocketcine-ios
  fi
fi
