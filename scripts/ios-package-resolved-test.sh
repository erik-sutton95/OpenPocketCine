#!/usr/bin/env bash
# Regression tests for the committed iOS SPM lockfile copy.
set -euo pipefail

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
sync="${root}/ios/sync-package-resolved.sh"
check="${root}/scripts/ios-package-resolved-check.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fail() {
  printf 'ios-package-resolved-test failed: %s\n' "$1" >&2
  exit 1
}

chmod +x "$sync" "$check"

dst_rel="OpenPocketCine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved"

# Copies the lockfile into the generated workspace path.
ios_dir="${temp_dir}/ios"
mkdir -p "$ios_dir"
printf '{ "pins": [], "version": 3 }\n' > "${ios_dir}/Package.resolved"
sh "$sync" "$ios_dir"
[[ -f "${ios_dir}/${dst_rel}" ]] || fail "sync did not write ${dst_rel}"
cmp -s "${ios_dir}/Package.resolved" "${ios_dir}/${dst_rel}" || fail "copied lockfile differs from source"

# Missing source lockfile is a hard error.
empty_dir="${temp_dir}/empty"
mkdir -p "$empty_dir"
if sh "$sync" "$empty_dir" >/dev/null 2>&1; then
  fail "sync succeeded without Package.resolved"
fi

# Committed lockfile matches project.yml Sentry pin.
"$check"

printf 'ios-package-resolved-test: ok\n'
