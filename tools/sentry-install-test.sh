#!/usr/bin/env bash
# Regression checks for tools/sentry-install.sh (no network).
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
installer="${script_dir}/sentry-install.sh"
temp_dir="$(mktemp -d)"
trap 'rm -rf "$temp_dir"' EXIT

fail() {
  printf 'sentry-install-test: %s\n' "$*" >&2
  exit 1
}

chmod +x "$installer"

version="$("$installer" --print-version)"
[[ "$version" == "3.7.0" ]] || fail "expected pin 3.7.0, got $version"
file_pin="$(tr -d '[:space:]' < "${script_dir}/sentry-cli-version")"
[[ "$file_pin" == "3.7.0" ]] || fail "tools/sentry-cli-version must be 3.7.0"

payload="opc-fake-sentry-cli"
if command -v sha256sum >/dev/null 2>&1; then
  digest="$(printf '%s' "$payload" | sha256sum | awk '{print $1}')"
else
  digest="$(printf '%s' "$payload" | shasum -a 256 | awk '{print $1}')"
fi

checksums="${temp_dir}/checksums.txt"
printf 'test-dist %s\n' "$digest" > "$checksums"

download_log="${temp_dir}/download.log"
downloader="${temp_dir}/downloader.sh"
cat > "$downloader" <<EOF
#!/bin/sh
set -eu
dest=\$1
printf 'opc-fake-sentry-cli' > "\$dest"
printf '%s %s %s\\n' "\$2" "\$3" "\$4" >> "${download_log}"
EOF
chmod +x "$downloader"

install_dir="${temp_dir}/bin"
SENTRY_CLI_DOWNLOADER="$downloader" \
  SENTRY_CLI_CHECKSUMS="$checksums" \
  SENTRY_CLI_DIST="test-dist" \
  "$installer" --install-dir "$install_dir" --version "3.7.0"

[[ -x "${install_dir}/sentry-cli" ]] || fail "binary was not installed"
[[ "$(cat "${install_dir}/sentry-cli")" == "$payload" ]] || fail "payload mismatch"
requested="$(cat "$download_log")"
[[ "$requested" == "test-dist 3.7.0 https://downloads.sentry-cdn.com/sentry-cli/3.7.0/sentry-cli-test-dist" ]] \
  || fail "unexpected downloader request: $requested"

# Reuse when checksum matches — downloader must not run again.
SENTRY_CLI_DOWNLOADER="$downloader" \
  SENTRY_CLI_CHECKSUMS="$checksums" \
  SENTRY_CLI_DIST="test-dist" \
  "$installer" --install-dir "$install_dir" --version "3.7.0"
[[ "$(wc -l < "$download_log" | tr -d ' ')" == "1" ]] || fail "reused binary still invoked the downloader"

# Checksum mismatch must refuse to install.
bad="${temp_dir}/bad"
printf 'wrong-dist deadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeefdeadbeef\n' > "${temp_dir}/bad-checksums.txt"
if SENTRY_CLI_DOWNLOADER="$downloader" \
  SENTRY_CLI_CHECKSUMS="${temp_dir}/bad-checksums.txt" \
  SENTRY_CLI_DIST="wrong-dist" \
  "$installer" --install-dir "$bad" --version "3.7.0" 2>"${temp_dir}/mismatch.err"; then
  fail "expected checksum mismatch to fail"
fi
grep -q 'SHA-256 mismatch' "${temp_dir}/mismatch.err" || fail "mismatch error missing"
[[ ! -f "${bad}/sentry-cli" ]] || fail "mismatched binary was installed"

# Missing dist in the checksum table.
if SENTRY_CLI_DOWNLOADER="$downloader" \
  SENTRY_CLI_CHECKSUMS="$checksums" \
  SENTRY_CLI_DIST="nope" \
  "$installer" --install-dir "${temp_dir}/missing-dist" --version "3.7.0" 2>"${temp_dir}/dist.err"; then
  fail "expected missing dist to fail"
fi
grep -q 'no SHA-256 for dist nope' "${temp_dir}/dist.err" || fail "missing-dist error missing"

printf 'sentry-install-test: ok\n'
