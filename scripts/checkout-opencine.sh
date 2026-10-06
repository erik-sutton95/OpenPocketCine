#!/bin/sh
# Check out each repository named in opencine-pins.txt next to this app
# (../<Name>) at its exact commit, then verify the commit. Never follows a branch.
# Usage: scripts/checkout-opencine.sh [base-url]   (default https://github.com/erik-sutton95)
#
# This file is the bootstrap, so the app keeps its own copy: it runs before the
# pin exists. Keep it identical to OpenCine/scripts/checkout-opencine.sh.
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
canon="$root/../OpenCine/scripts/checkout-opencine.sh"
if [ -f "$canon" ]; then
  me=$(cd "$(dirname "$0")" && pwd)/$(basename "$0")
  if [ "$me" != "$canon" ] && ! cmp -s "$me" "$canon"; then
    echo "error: scripts/checkout-opencine.sh differs from ../OpenCine/scripts/checkout-opencine.sh" >&2
    exit 1
  fi
fi
base=${1:-https://github.com/erik-sutton95}
grep -v '^#' "$root/opencine-pins.txt" | while read -r name sha; do
  [ -n "$name" ] || continue
  dest="$root/../$name"
  if [ -e "$dest/.git" ] && [ -z "${CI:-}" ]; then
    # A developer's own sibling checkout: report, never move it.
    actual=$(git -C "$dest" rev-parse HEAD)
    [ "$actual" = "$sha" ] || echo "warning: ../$name is at $actual, pinned $sha" >&2
    continue
  fi
  if [ ! -d "$dest/.git" ]; then
    git init -q "$dest"
    git -C "$dest" remote add origin "$base/$name.git"
  fi
  git -C "$dest" fetch -q --depth 1 origin "$sha"
  git -C "$dest" -c advice.detachedHead=false checkout -q --detach FETCH_HEAD
  actual=$(git -C "$dest" rev-parse HEAD)
  if [ "$actual" != "$sha" ]; then
    echo "error: $name is at $actual, pinned $sha" >&2
    exit 1
  fi
  echo "$name $sha"
done
