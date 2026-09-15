#!/usr/bin/env bash
# Run Sentry release-tooling regression checks. No network, no real uploads.
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
chmod +x \
  "${script_dir}/sentry-install.sh" \
  "${script_dir}/sentry-fake-uploader.sh" \
  "${script_dir}/sentry-upload.py" \
  "${script_dir}/sentry-dsn-xcconfig.py" \
  "${script_dir}/sentry-verify-ios-dsn.py" \
  "${script_dir}/sentry-require-android-dsn.sh" \
  "${script_dir}/sentry-install-test.sh" \
  "${script_dir}/sentry-upload-test.py" \
  "${script_dir}/sentry-dsn-test.py"

bash "${script_dir}/sentry-install-test.sh"
python3 "${script_dir}/sentry-upload-test.py"
python3 "${script_dir}/sentry-dsn-test.py"
python3 "${script_dir}/build-identity-test.py"
python3 "${script_dir}/ios-package-resolved-check.py"
bash "${script_dir}/../scripts/ios-package-resolved-test.sh"
printf 'sentry-test: ok\n'
