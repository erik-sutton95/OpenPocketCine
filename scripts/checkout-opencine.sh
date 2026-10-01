#!/bin/sh
# Check out each shared OpenCine package pinned in opencine-pins.txt next to this
# repository (../<Name>) at its exact commit, then verify the commit. Never follows a branch.
# Usage: scripts/checkout-opencine.sh [base-url]   (default https://github.com/erik-sutton95)
set -eu
root=$(cd "$(dirname "$0")/.." && pwd)
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
