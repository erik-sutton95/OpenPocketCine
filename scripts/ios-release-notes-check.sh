#!/usr/bin/env bash
# Shared steps live in the sibling OpenCine scripts. This file keeps the app path.
root=$(cd "$(dirname "$0")/.." && pwd)
shared="$root/../OpenCine/scripts/ios-release-notes-check.sh"
if [[ ! -f "$shared" ]]; then
  printf 'error: missing %s\n' "$shared" >&2
  exit 1
fi
exec "$shared" "$@"
