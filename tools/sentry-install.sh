#!/usr/bin/env bash
# Install the pinned sentry-cli binary. Never talks to Sentry APIs.
#
# Official install docs pin SENTRY_CLI_VERSION="3.7.0":
# https://docs.sentry.io/cli/installation/
# Checksums: https://release-registry.services.sentry.io/apps/sentry-cli/3.7.0
set -euo pipefail

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
version_file="${SENTRY_CLI_VERSION_FILE:-${script_dir}/sentry-cli-version}"
checksums_file="${SENTRY_CLI_CHECKSUMS:-${script_dir}/sentry-cli-checksums.txt}"
base_url="${SENTRY_CLI_BASE_URL:-https://downloads.sentry-cdn.com/sentry-cli}"
install_dir="${INSTALL_DIR:-}"
print_version=0

fail() {
  printf 'sentry-install: %s\n' "$*" >&2
  exit 1
}

usage() {
  cat <<'EOF'
Usage: tools/sentry-install.sh [--install-dir DIR] [--version VER] [--print-version]

Downloads the pinned sentry-cli build, verifies SHA-256, and writes
DIR/sentry-cli. Override the downloader with SENTRY_CLI_DOWNLOADER for tests.
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --install-dir)
      [[ $# -ge 2 ]] || fail "--install-dir needs a directory"
      install_dir="$2"
      shift 2
      ;;
    --version)
      [[ $# -ge 2 ]] || fail "--version needs a value"
      SENTRY_CLI_VERSION="$2"
      shift 2
      ;;
    --print-version)
      print_version=1
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown argument: $1"
      ;;
  esac
done

if [[ ! -f "$version_file" ]]; then
  fail "missing version pin at $version_file"
fi
pinned="$(tr -d '[:space:]' < "$version_file")"
[[ -n "$pinned" ]] || fail "empty version pin at $version_file"
version="${SENTRY_CLI_VERSION:-$pinned}"
if [[ "$print_version" -eq 1 ]]; then
  printf '%s\n' "$version"
  exit 0
fi

[[ -n "$install_dir" ]] || fail "pass --install-dir or set INSTALL_DIR"

uname_s="$(uname -s)"
uname_m="$(uname -m)"
if [[ -n "${SENTRY_CLI_DIST:-}" ]]; then
  dist="$SENTRY_CLI_DIST"
else
  case "${uname_s}-${uname_m}" in
    Darwin-arm64|Darwin-x86_64) dist="Darwin-universal" ;;
    Linux-x86_64|Linux-amd64) dist="Linux-x86_64" ;;
    Linux-aarch64|Linux-arm64) dist="Linux-aarch64" ;;
    Linux-armv7l) dist="Linux-armv7" ;;
    Linux-i686|Linux-i386) dist="Linux-i686" ;;
    *) fail "unsupported platform ${uname_s} ${uname_m}" ;;
  esac
fi

expected=""
if [[ ! -f "$checksums_file" ]]; then
  fail "missing checksums at $checksums_file"
fi
while read -r name hash _; do
  [[ -z "${name:-}" || "$name" == \#* ]] && continue
  if [[ "$name" == "$dist" ]]; then
    expected="$hash"
    break
  fi
done < "$checksums_file"
[[ -n "$expected" ]] || fail "no SHA-256 for dist $dist in $checksums_file"
[[ "$expected" =~ ^[0-9a-fA-F]{64}$ ]] || fail "checksum for $dist is not SHA-256"

mkdir -p "$install_dir"
dest="${install_dir}/sentry-cli"
url="${base_url}/${version}/sentry-cli-${dist}"

verify() {
  local file="$1"
  local digest=""
  if command -v sha256sum >/dev/null 2>&1; then
    digest="$(sha256sum "$file" | awk '{print $1}')"
  else
    digest="$(shasum -a 256 "$file" | awk '{print $1}')"
  fi
  [[ "$digest" == "$expected" ]]
}

if [[ -f "$dest" ]] && verify "$dest"; then
  printf 'sentry-install: reusing %s (%s %s)\n' "$dest" "$dist" "$version"
  exit 0
fi

tmp="$(mktemp "${install_dir}/sentry-cli.download.XXXXXX")"
cleanup() { rm -f "$tmp"; }
trap cleanup EXIT

if [[ -n "${SENTRY_CLI_DOWNLOADER:-}" ]]; then
  "${SENTRY_CLI_DOWNLOADER}" "$tmp" "$dist" "$version" "$url"
else
  curl -fsSL --retry 3 --retry-delay 2 -o "$tmp" "$url"
fi
[[ -s "$tmp" ]] || fail "download produced an empty file"
if ! verify "$tmp"; then
  fail "SHA-256 mismatch for $dist $version (refusing to install)"
fi
chmod 755 "$tmp"
mv "$tmp" "$dest"
trap - EXIT
printf 'sentry-install: installed %s (%s %s)\n' "$dest" "$dist" "$version"
