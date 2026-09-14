#!/usr/bin/env bash
# Fail closed before Android bundleRelease when symbol upload is enabled
# but SENTRY_DSN_ANDROID is missing. Does not print the DSN. Shape/invalid
# values are Gradle/SDK concerns (Apps/Android).
set -euo pipefail

if [[ "${SENTRY_UPLOAD_ENABLED:-}" != "true" ]]; then
  printf 'sentry-require-android-dsn: skipped (SENTRY_UPLOAD_ENABLED is not true)\n'
  exit 0
fi
if [[ -z "${SENTRY_DSN_ANDROID:-}" ]]; then
  printf 'sentry-require-android-dsn: SENTRY_UPLOAD_ENABLED=true requires SENTRY_DSN_ANDROID before bundleRelease\n' >&2
  exit 2
fi
printf 'sentry-require-android-dsn: SENTRY_DSN_ANDROID is set\n'
