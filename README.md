# Meeting Flyby for Mac

_A macOS menu bar app. Universal (Apple Silicon + Intel), macOS 11 Big Sur or later._

A macOS menu bar app that flies a little pet across your screen before each meeting — **above
everything, including fullscreen video calls**. Built because system notifications get buried
behind a fullscreen Zoom/Meet window exactly when you need them.

<img width="420" alt="Preferences" src="docs/preferences.png">

## Install

> ⚠️ This app isn't signed with an Apple Developer certificate, so macOS blocks it on first
> launch. That's expected — the steps below get past it.

1. Get `MeetingFlyby-for-Mac.dmg` from your team (Mindtickle: ask Chandni), or build it
   yourself with `./build.sh && ./make-dmg.sh`.
2. Double-click the DMG, then drag **MeetingFlyby** onto the **Applications** shortcut.
3. Double-click it. macOS will say it "cannot verify the developer" — click **Done**.
4. Open **System Settings → Privacy & Security**, scroll down, click **Open Anyway**, confirm.
5. A setup window appears → choose **Sign in with Google** → sign in with your Mindtickle
   account. Nothing else to configure.
6. Optional: add it to **System Settings → General → Login Items** so it starts on login.

You may see a one-time macOS **keychain** prompt after signing in — that's the OS asking
permission to store your Google sign-in securely. It wants your normal Mac login password;
choose **Always Allow** and it won't ask again.

## Using it

Everything lives in the menu bar icon → **Preferences…**

- **Character** — dog, cat, pig or bunny. Each has its own accent color and sound.
- **Heads-up time** — 2, 5 or 10 minutes before the meeting.
- **Test flyby** — fires one immediately so you can see it.
- **Upcoming meetings** — the next 72 hours as actually fetched, so you can confirm the right
  calendar is synced.
- **Manage connections** — add or remove Google accounts (multiple accounts are merged).

## Calendar options

| Option | Setup needed | Notes |
|---|---|---|
| **Sign in with Google** | None | Recommended. Works with Mindtickle Workspace accounts. |
| **macOS Calendar** | Account added in System Settings → Internet Accounts | Reads whatever Calendar.app already syncs. |
| **Paste a calendar link** | An ICS/iCal URL | Usually unavailable on Workspace accounts, which don't expose a secret iCal address. |

## Privacy

- Calendar data is read **only** from Google's API (or your local Calendar) and kept in memory.
- No analytics, no telemetry, no crash reporting, no backend. Nothing is sent anywhere else.
- Google sign-in uses the system browser (your password never touches this app) with OAuth 2.0
  + PKCE, and refresh tokens are stored in the macOS Keychain.
- Requests read-only calendar scope.

**Note:** the banner displays real meeting titles over everything, including during screen
shares. Be aware of that before presenting.

## Building from source

Requires the Xcode Command Line Tools.

```bash
./build.sh          # compiles and signs into build/MeetingFlyby.app
./make-dmg.sh       # packages build/MeetingFlyby-for-Mac.dmg
open build/MeetingFlyby.app
```

`build.sh` invokes `swiftc` directly rather than Swift Package Manager — SPM's manifest
compilation was broken on the machine this was written on.

## Google sign-in credentials

This repository contains **no** OAuth credentials. `build.sh` generates
`Sources/MeetingFlyby/BundledCredentials.swift` at build time from a local, gitignored
`credentials.env` — so the client never enters git history, and repo visibility can't leak it.

To build with Google sign-in enabled:

```bash
cp credentials.env.example credentials.env
# fill in GOOGLE_CLIENT_ID / GOOGLE_CLIENT_SECRET from your own Cloud Console
# (APIs & Services → Credentials → OAuth client ID, type "Desktop app")
./build.sh
```

Build without it and the app still works — users pick **macOS Calendar** (no Google Cloud
setup needed) or paste their own Client ID on the Advanced page.

Prebuilt Mindtickle-internal builds are shared directly with the team rather than attached
to public releases, since a bundled client secret is recoverable from any distributed binary.
