#!/usr/bin/env bash
# Require the committed iOS SPM lockfile to pin every remote package in
# ios/project.yml. Xcode Cloud cannot resolve packages without it.
set -euo pipefail
root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
exec python3 "${root}/tools/ios-package-resolved-check.py"
