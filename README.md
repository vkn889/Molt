# Molt

A little companion that lives in your MacBook's notch.

Molt is a native macOS notch app. Hover over the notch and it opens into a black panel that looks like part of the hardware: your music, your week, your Mac's health, your own widgets, and Molt, a small pixel creature that runs around when you look after it and hangs out with your friends' Molts.

![Molt notch home](docs/screenshots/notch-home.png)

## Getting started

Open Molt and create your account once: email, password and a @username. You stay signed in on that Mac. Turn on two-factor authentication in Settings; until you do, Molt sends a gentle weekly reminder.

Hover over the notch, or press **⌘⇧↩**, to open Molt. **⌘⇧L** asks about anything on your screen. Every page is the same size. Home, Hub, Play and Molting sit left of the notch; Lens, Claude Code & Codex, Chat and Settings are icons on the right.

## Pages

- **Home:** now playing, a five-day calendar strip with today's events or tasks, and Mac health. Click the health column to see what's using your Mac. Molt scurries along the bottom, or sleeps.
- **Hub:** four slots of widgets you choose, like a Home Screen. See [Widgets](#widgets).
- **Play:** a tamagotchi. Drag a meal, snack, water, ball, nap, brush, pat or story onto Molt, or click it. The more you care for Molt, the livelier it gets.
- **Molting:** friends, hangouts and lending your setup. See [Molting](#molting).
- **Lens:** select part of your screen and ask about it.
- **Claude Code & Codex:** your conversations from both tools with token usage, plus private copies that survive the tools' cleanup.
- **Chat:** talk to Molt through Ollama on this Mac.
- **Settings:** your account and 2FA, Molt's name and color, accent, hover, display, and every connection.

![Hub](docs/screenshots/notch-hub.png)

## Widgets

Click the pencil in the header, or hold any widget, to edit the Hub. Widgets jiggle; drag to reorder, **–** removes, the arrows switch between small and wide, and **+** adds from the catalog.

| Widget | Sizes | What it does |
| --- | --- | --- |
| Shortcuts | small, wide | 4 or 8 one-click actions you pick: record screen, screenshot, ask about screen, pick a color, keep awake, dark mode, mute, sleep screen, Downloads, empty Trash, focus, System Settings, any app, any Apple Shortcut, or any link |
| Screen recorder | small | Records the screen with one click; saves to Movies. While recording, a red dot and timer sit beside the notch; click them to stop |
| Lens | small | Ask about your screen |
| Focus, Tasks, Weather | small (Tasks also wide) | Focus timer, today's to-dos, your city's weather |
| Top apps | small, wide | Your most-used apps today, with their icons |
| Molt | small | Molt's needs at a glance |
| Agent usage | small | Today's Claude Code and Codex tokens |
| Up next | small, wide | Your next events with a countdown |
| Mac health | small | Opens the health drill-down |
| Now playing, Playlists | small/wide, wide | Music controls and playlist covers |
| Clock, Downloads, Quick note, Web search | various | Time, latest downloads, a scratchpad, and search across Google, YouTube, Wikipedia and Maps |

## Lens

Press **⌘⇧L** (or the viewfinder icon) and drag over text, an image, an error or a QR code. macOS's built-in Vision reads the text, recognizes objects and scans codes on your Mac; your Ollama model answers questions using that. There's no vision model to download and nothing is uploaded. Quick actions: What is this?, Explain it, Summarize, Translate, Copy text, Search web.

## Mac health

Click the health column on Home, or the Mac health widget:

- **CPU / Memory:** the apps using the most, with helper processes grouped under their app. Quit a background app after a confirmation. System processes, Finder and Molt can't be quit from here.
- **Battery:** health, cycle count, temperature, power source and time remaining.
- **Storage:** measures Trash, Downloads, Desktop, Documents, Movies, app caches, Xcode build data and simulators.
- **Molt's advice:** one suggestion at a time, like quitting the background app eating memory, emptying a large Trash, or clearing Xcode build data (moved to the Trash, so it's recoverable). **Low-impact Molt** stops Molt's own animations.

## Molting

- **Friends:** add people by @username, or from **Online now**. Accept or decline requests.
- **Hangouts:** invite an online friend. Both Molts appear in a little playground; click to walk, and send waves, hearts, dances and laughs. When you leave, you both earn points (10 plus 2 per minute, up to 50) and your social status goes up, after at least a minute together and once an hour per friend.
- **Lending:** lend your Hub widgets, accent color and Molt's color to a friend for a day, a week, or until they give it back. They can try it on; their own setup comes back when the loan ends.
- Turn off **Show me in Online now** in your account to stay invisible to strangers.

![Molting](docs/screenshots/notch-molting.png)

## Music

Home follows whichever of Spotify or Apple Music is playing, with artwork, a draggable progress bar and playback controls. Click the artwork to browse your playlists; clicking one plays it in the background without opening the app.

- **Apple Music:** choose **Connect Apple Music** to read the playlists in your library.
- **Spotify:** create a free app at [developer.spotify.com/dashboard](https://developer.spotify.com/dashboard), add `http://127.0.0.1:43821/callback` as its redirect URI, paste its Client ID into Molt and choose **Connect**. With Spotify connected, Home also follows and controls Spotify playing on other devices (needs Premium).

## Run and package

Requires macOS 13+, Swift 5.9+, and full Xcode for universal builds and XCTest.

```sh
swift run Molt
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path .build-xcode
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/package.sh 0.8.0
open dist/Molt.app
```

The package script produces `dist/Molt-0.8.0.dmg` and an ad-hoc signed universal app. Ad-hoc signing is not Apple notarization.

The backend is a Supabase project; its schema and security rules are in [`supabase/migrations`](supabase/migrations). The app ships only the publishable key; row-level security decides what each signed-in user can read and write.

## Privacy and permissions

- **Account:** your email, @username, Molt's name and color, points and friends are stored on Molt's server. Other signed-in users can see your @username, Molt and points. Your session is kept in the macOS keychain.
- **Hangouts** send only your Molt's position and emotes, live, to the friend you're with. Nothing from a hangout is stored except its start, end and points.
- **Lens and screen recording** need Screen Recording permission. Lens reads only the area you select, on your Mac. Recordings are saved to Movies and go nowhere else.
- Calendar, app usage, Mac health, and Claude Code & Codex reading are each off until you turn them on. Chat copies stay in `~/Library/Application Support/Molt/Sessions`.
- Weather sends only your city search to [Open-Meteo](https://open-meteo.com/) (CC BY 4.0). Spotify tokens stay in the keychain.
- No keystroke recording, clipboard collection or background screen capture.

## Development references

- [Architecture](docs/architecture.md)
- [Companion definitions](docs/definitions.md)
- [0.8.0 release notes](docs/releases/0.8.0.md)
