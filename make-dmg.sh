#!/bin/bash
# Builds a drag-to-Applications disk image — the standard Mac install experience.
set -euo pipefail
cd "$(dirname "$0")"

APP="build/MeetingFlyby.app"
DMG="build/MeetingFlyby-for-Mac.dmg"
STAGE="build/dmg-stage"

[ -d "$APP" ] || { echo "Run ./build.sh first"; exit 1; }

rm -rf "$STAGE" "$DMG"
mkdir -p "$STAGE"
cp -R "$APP" "$STAGE/"
ln -s /Applications "$STAGE/Applications"

# Instructions live inside the disk image, because macOS will block an unsigned app on
# first launch and people otherwise assume the download is broken. Leading space in the
# filename sorts it first in the DMG window.
cat > "$STAGE/ READ ME FIRST — how to open.txt" <<'TXT'
MEETING FLYBY FOR MAC — HOW TO INSTALL
======================================

STEP 1  Drag "MeetingFlyby" onto the "Applications" folder in this window.

STEP 2  Open Applications and double-click MeetingFlyby.
        macOS will say: "Apple could not verify MeetingFlyby is free of malware."
        >>> Click "Done".  DO NOT click "Move to Bin" / "Move to Trash" <<<
        (That message is expected. This app isn't signed with a paid Apple
         certificate, so macOS asks you to approve it once, by hand.)

STEP 3  Open  System Settings > Privacy & Security
        Scroll down to the "Security" section.
        You'll see: "MeetingFlyby was blocked to protect your Mac"
        Click "Open Anyway", then confirm with Touch ID or your password.

STEP 4  The app opens. A setup window appears:
        choose "Sign in with Google" and sign in with your work account.
        Nothing else to configure.

That's it. Steps 2 and 3 happen only once, ever.

Optional: add it to System Settings > General > Login Items so it starts
automatically when you log in.


IF "OPEN ANYWAY" ISN'T THERE
----------------------------
Open Terminal (Applications > Utilities > Terminal), paste this, press Return:

    xattr -cr /Applications/MeetingFlyby.app

Then double-click the app normally.


WHAT IT DOES
------------
Before each meeting on your calendar, a little pet flies across your screen
towing a banner with the meeting name — on top of everything, including
fullscreen video calls. Set your character, heads-up time and see your synced
meetings from the menu bar icon > Preferences.

Requires macOS 11 (Big Sur) or later. Works on Intel and Apple Silicon Macs.
TXT

# hdiutil intermittently fails with "Resource busy" when it's been run repeatedly, so
# retry rather than leaving the build randomly broken.
for attempt in 1 2 3 4 5 6; do
  if hdiutil create -volname "Meeting Flyby" -srcfolder "$STAGE" -ov -format UDZO "$DMG" >/dev/null 2>&1; then
    break
  fi
  if [ "$attempt" -eq 6 ]; then
    echo "hdiutil failed after 6 attempts" >&2
    exit 1
  fi
  echo "  hdiutil busy, retrying ($attempt)…"
  sleep 3
done

rm -rf "$STAGE"
echo "Built $DMG"
