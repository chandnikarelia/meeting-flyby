# Meeting Flyby for Mac

_A macOS menu bar app. Universal (Apple Silicon + Intel), macOS 11 Big Sur or later._

A macOS menu bar app that flies a little pet across your screen before each meeting — **above
everything, including fullscreen video calls**. Built because system notifications get buried
behind a fullscreen Zoom/Meet window exactly when you need them.

<img width="420" alt="Preferences" src="docs/preferences.png">

## Install

> ⚠️ This app isn't signed with an Apple Developer certificate, so macOS blocks it on first
> launch. That's expected — the steps below get past it.

1. Download `MeetingFlyby-for-Mac.dmg` from the [latest release](../../releases/latest).
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

## ⚠️ Keep this repository private

`Sources/MeetingFlyby/BundledCredentials.swift` contains the Google OAuth client for the
`meeting-flyby` Cloud project so teammates can sign in without their own Cloud setup. The
consent screen is set to **Internal**, so only `mindtickle.com` accounts can complete sign-in
— but if this repo is ever made public, **rotate the secret first** (Cloud Console → Clients →
Meeting Flyby macOS → Add secret, then disable and delete the old one).
