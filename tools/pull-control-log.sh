#!/usr/bin/env bash
# Pull OpenPocketCine's on-device control journal (Documents/control-live.log).
#
#   tools/pull-control-log.sh
#   DEVICE=es_iphone16 tools/pull-control-log.sh
#
# Uses `xcrun devicectl device copy from` with:
#   --device <name|CoreDevice-ID>
#   --domain-type appDataContainer
#   --domain-identifier com.opencapture.openpocketcine
#   --source Documents/control-live.log
#   --destination /tmp/opc-control-live.log
#
# Confirmed on this Mac (2026-08-14): copy-from works without sudo.
# Missing file → CoreDeviceError 7000 (file node). Xcode console
# (subsystem com.opencapture.openpocketcine / category session) is the live path
# until the app has written the journal.
#
# Device: es_iphone16  CoreDevice ID B1138BFC-5392-56A1-93F1-5B722F7BA10F

set -euo pipefail

DEVICE="${DEVICE:-es_iphone16}"
BUNDLE="com.opencapture.openpocketcine"
DEST="${DEST:-/tmp/opc-control-live.log}"
SOURCE="Documents/control-live.log"

rm -f "$DEST"

if ! xcrun devicectl device copy from \
    --device "$DEVICE" \
    --domain-type appDataContainer \
    --domain-identifier "$BUNDLE" \
    --source "$SOURCE" \
    --destination "$DEST" \
    --timeout 15
then
    echo "pull failed — journal not written yet, or $DEVICE not connected." >&2
    echo "Xcode console (com.opencapture.openpocketcine / session) is the live path until the file exists." >&2
    exit 1
fi

echo "---- last 30 ($DEST) ----"
tail -n 30 "$DEST"
