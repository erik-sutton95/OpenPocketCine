#!/usr/bin/env bash
# Copy numeric feed-stress artifacts off the iPhone. No footage, no journal dump.
#
#   DEVICE=<name-or-id> tools/feed-stress-pull.sh
#   DEST=/tmp/opc-feed-stress DEVICE=... tools/feed-stress-pull.sh
#
# Uses the same CoreDevice copy path as tools/pull-control-log.sh.

set -euo pipefail

DEVICE="${DEVICE:-}"
BUNDLE="com.opencapture.openpocketcine"
DEST="${DEST:-/tmp/opc-feed-stress}"
SOURCE="Documents/feed-stress"

if [[ -z "$DEVICE" ]]; then
    echo "DEVICE is required (xcrun devicectl list devices)." >&2
    exit 2
fi

# Preserve earlier runs and never recursively remove a caller-supplied path.
DEST="${DEST%/}/pull-$(date -u +%Y%m%dT%H%M%SZ)-$$"
mkdir -p "$DEST"

if ! xcrun devicectl device copy from \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" \
    --source "$SOURCE" \
    --destination "$DEST" \
    --timeout 30
then
    echo "pull failed — no Documents/feed-stress yet, or $DEVICE not connected." >&2
    echo "The app writes that folder only in Debug with OPV_FEED_STRESS=1 after installIfRequested()." >&2
    exit 1
fi

echo "pulled $SOURCE -> $DEST"
find "$DEST" -type f | sort
