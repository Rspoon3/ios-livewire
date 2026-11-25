#!/usr/bin/env bash
# Copies the app's log files from a simulator or a connected iPhone into ./logs/<timestamp>/.
#
#   scripts/pull-logs.sh sim                 # the booted simulator
#   scripts/pull-logs.sh device <device-id>  # a connected iPhone (see: xcrun devicectl list devices)
#
# The ./logs folder is git-ignored: the files contain your VIN, bike location and rides.
set -euo pipefail

BUNDLE_ID="${BUNDLE_ID:-com.rspoon3.ios-livewire}"
DEST="logs/$(date +%Y%m%d-%H%M%S)"
mkdir -p "$DEST"

case "${1:-}" in
  sim)
    CONTAINER=$(xcrun simctl get_app_container booted "$BUNDLE_ID" data)
    cp -R "$CONTAINER/Documents/Logs/." "$DEST/"
    ;;
  device)
    DEVICE="${2:?usage: pull-logs.sh device <device-id>}"
    xcrun devicectl device copy from \
      --device "$DEVICE" \
      --domain-type appDataContainer \
      --domain-identifier "$BUNDLE_ID" \
      --source Documents/Logs \
      --destination "$DEST"
    ;;
  *)
    sed -n '2,8p' "$0" | sed 's/^# \{0,1\}//'
    exit 2
    ;;
esac

echo "Copied to $DEST"
find "$DEST" -name '*.log' | sort
