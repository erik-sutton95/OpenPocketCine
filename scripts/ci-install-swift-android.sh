#!/usr/bin/env bash
# Install the official Swift 6.3.3 Android SDK on a GitHub-hosted Ubuntu runner.
#
# skiptools/swift-android-action cannot be used here: it references
# actions/cache@v5 and reactivecircus/android-emulator-runner@v2, and repository
# SHA pinning rejects those nested tags even when the emulator steps are skipped.
set -euo pipefail

readonly SWIFT_VERSION="6.3.3"
readonly SDK_ID="swift-6.3.3-RELEASE_android"
readonly SDK_URL="https://download.swift.org/swift-6.3.3-release/android-sdk/swift-6.3.3-RELEASE/swift-6.3.3-RELEASE_android.artifactbundle.tar.gz"
readonly SDK_CHECKSUM="d160cc3206dd1886dae3fef2337af5e25ec034692cd0ec225721c56cc69da7f5"
readonly TARGET="aarch64-unknown-linux-android29"

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

swift_bin="$(command -v swift || true)"
[[ -n "$swift_bin" && -x "$swift_bin" ]] || fail "swift is not on PATH"
# GitHub Ubuntu images extract the toolchain to /usr/share/swift and only
# symlink swift/swiftc into /usr/local/bin. llvm-objcopy and llvm-objdump stay
# in the real usr/bin. Follow the binary; `pwd -P` on its directory is not enough.
swift_bin="$(readlink -f "$swift_bin")"
[[ -x "$swift_bin" ]] || fail "could not resolve the swift executable"
swift_version="$("$swift_bin" --version)"
[[ "$swift_version" == *"${SWIFT_VERSION}"* ]] || fail \
  "Swift ${SWIFT_VERSION} is required; found: ${swift_version%%$'\n'*}"

toolchain_bin="$(dirname "$swift_bin")"
[[ -x "$toolchain_bin/llvm-objcopy" ]] || fail "llvm-objcopy is missing beside $swift_bin"
[[ -x "$toolchain_bin/llvm-objdump" ]] || fail "llvm-objdump is missing beside $swift_bin"

if ! "$swift_bin" sdk list 2>/dev/null | grep -Fxq "$SDK_ID"; then
  "$swift_bin" sdk install "$SDK_URL" --checksum "$SDK_CHECKSUM"
fi

sdk_home=""
candidates=(
  "${HOME}/.swiftpm/swift-sdks/${SDK_ID}.artifactbundle/swift-android"
  "${HOME}/.config/swiftpm/swift-sdks/${SDK_ID}.artifactbundle/swift-android"
)
if [[ -n "${XDG_CONFIG_HOME:-}" ]]; then
  candidates+=("${XDG_CONFIG_HOME}/swiftpm/swift-sdks/${SDK_ID}.artifactbundle/swift-android")
fi
for candidate in "${candidates[@]}"; do
  if [[ -x "${candidate}/scripts/setup-android-sdk.sh" ]]; then
    sdk_home="$candidate"
    break
  fi
done
[[ -n "$sdk_home" ]] || fail "setup-android-sdk.sh is missing after installing $SDK_ID"

: "${ANDROID_NDK_HOME:?ANDROID_NDK_HOME must point at NDK 27}"
# GitHub-hosted Ubuntu sets ANDROID_NDK_ROOT. Swift 6.1+ Android SDKs treat that
# as an NDK override and then fail to find Swift runtime libraries.
# https://github.com/finagolfin/swift-android-sdk/issues/207
unset ANDROID_NDK_ROOT
(cd "$sdk_home" && ./scripts/setup-android-sdk.sh)

"$swift_bin" sdk configure --show-configuration "$SDK_ID" "$TARGET" >/dev/null \
  || fail "Swift Android SDK $SDK_ID is not configured for $TARGET"

if [[ -n "${GITHUB_ENV:-}" ]]; then
  {
    echo "SWIFT_ANDROID_SDK_ID=${SDK_ID}"
    echo "SWIFT_INSTALLATION=${toolchain_bin%/bin}"
    echo "ANDROID_NDK_ROOT="
  } >> "$GITHUB_ENV"
fi
