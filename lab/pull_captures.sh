#!/usr/bin/env bash
# Copy Lab Captures from a USB-connected iPhone into lab/data/.
#   ./pull_captures.sh                 # first connected iPhone
#   ./pull_captures.sh <device-udid>
set -euo pipefail
cd "$(dirname "$0")"
DEVICE="${1:-$(xcrun devicectl list devices 2>/dev/null | awk '/connected/ && /physical/ {for (i=1;i<=NF;i++) if ($i ~ /^[0-9A-F]{8}-[0-9A-F]{16}$/ || $i ~ /^[0-9A-F]{8}-[0-9A-F]{4}-/) {print $i; exit}}')}"
[ -n "$DEVICE" ] || { echo "No connected iPhone found."; exit 1; }
mkdir -p data
xcrun devicectl device copy from --device "$DEVICE" \
  --domain-type appDataContainer --domain-identifier vn.kanax.depthkit \
  --source Documents/LabCaptures --destination data
ls data
