#!/bin/bash
# Builds a drag-to-Applications disk image — the standard Mac install experience.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MeetingFlyby.app"
DMG="build/MeetingFlyby.dmg"
STAGE="build/dmg-stage"

[ -d "$APP" ] || { echo "Run ./build.sh first"; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

hdiutil create \
  -volname "Meeting Flyby" \
  -srcfolder "$STAGE" \
  -ov -format UDZO \
  "$DMG" >/dev/null

rm -rf "$STAGE"
echo "Built $DMG"
