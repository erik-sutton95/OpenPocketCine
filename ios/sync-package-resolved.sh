#!/bin/sh
# Copy the committed SwiftPM lockfile into the generated Xcode workspace.
# Xcode Cloud builds with -disableAutomaticPackageResolution, so the file
# must exist at:
#   OpenPocketCine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm/Package.resolved
# The xcodeproj is gitignored; keep the lockfile at ios/Package.resolved.
set -eu

ios_dir="${1:-}"
if [ -z "$ios_dir" ]; then
  ios_dir="$(CDPATH= cd -- "$(dirname "$0")" && pwd)"
fi

src="${ios_dir}/Package.resolved"
dst_dir="${ios_dir}/OpenPocketCine.xcodeproj/project.xcworkspace/xcshareddata/swiftpm"
dst="${dst_dir}/Package.resolved"

if [ ! -f "$src" ]; then
  echo "error: missing committed SPM lockfile: ${src}" >&2
  echo "Run: just ios-resolve" >&2
  exit 1
fi

mkdir -p "$dst_dir"
cp "$src" "$dst"
