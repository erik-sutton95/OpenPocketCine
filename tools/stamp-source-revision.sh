#!/usr/bin/env bash
# Stamp the built application, before signing, with its source identity.
set -euo pipefail

repo_root="${SRCROOT:?}/.."
built_plist="${TARGET_BUILD_DIR:?}/${INFOPLIST_PATH:?}"
revision="$(git -C "$repo_root" rev-parse HEAD)"
if ! git -C "$repo_root" diff --quiet HEAD -- Sources ios tools Package.swift Package.resolved; then
    revision="${revision}-dirty"
elif [ -n "$(git -C "$repo_root" ls-files --others --exclude-standard -- Sources ios tools)" ]; then
    revision="${revision}-dirty"
fi
/usr/libexec/PlistBuddy -c "Set :OPCSourceRevision $revision" "$built_plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :OPCSourceRevision string $revision" "$built_plist"

# Stable for identical inputs; distinguishes uncommitted edits that share HEAD-dirty.
build_identity="$(python3 "$repo_root/tools/build-identity.py" --root "$repo_root" \
    --platform ios --configuration "${CONFIGURATION:-unknown}-${PLATFORM_NAME:-unknown}-${ARCHS:-unknown}-${SDK_VERSION:-unknown}-${XCODE_VERSION_ACTUAL:-unknown}")"
/usr/libexec/PlistBuddy -c "Set :OPCBuildIdentity $build_identity" "$built_plist" 2>/dev/null \
    || /usr/libexec/PlistBuddy -c "Add :OPCBuildIdentity string $build_identity" "$built_plist"
