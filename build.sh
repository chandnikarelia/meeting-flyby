#!/bin/bash
set -euo pipefail
cd "$(dirname "$0")"

APP=build/MeetingFlyby.app
rm -rf "$APP"
mkdir -p "$APP/Contents/MacOS" "$APP/Contents/Resources"

swiftc -O -o "$APP/Contents/MacOS/MeetingFlyby" \
  Sources/MeetingFlyby/*.swift \
  -framework Cocoa -framework EventKit -framework AVFoundation -framework Network -framework CryptoKit

cp Info.plist "$APP/Contents/Info.plist"
cp Sounds/*.wav "$APP/Contents/Resources/"
codesign --force --deep -s - "$APP"

echo "Built $APP"
echo "Run:  open '$APP'"
