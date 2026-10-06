#!/usr/bin/env bash
# Shared steps live in the sibling OpenCine scripts. This file keeps the app path.
root=$(cd "$(dirname "$0")/.." && pwd)
shared="$root/../OpenCine/scripts/android-stage-swift-core.sh"
if [[ ! -f "$shared" ]]; then
  printf 'error: missing %s\n' "$shared" >&2
  exit 1
fi
cd "$root" || {
  printf 'error: cannot enter %s\n' "$root" >&2
  exit 1
}
exec "$shared" --product OpenPocketCineAndroid "$@"
