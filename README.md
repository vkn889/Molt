# Molt

A little companion. Your whole Mac, a little closer.

Molt is a native macOS notch companion with a clean, Apple-style interface, a pixel-art creature, and practical everyday controls. See what's playing, glance at your week and your Mac's health, arrange your hub, check the weather, settle into a focus session, and chat with a local helper.

![Molt notch home](docs/screenshots/notch-home.png)

## Open the notch

Hover over the notch, or press **Command-Shift-Enter**, and Molt expands from it. Move the pointer away (or press the shortcut again) to close it. Escape closes the menu first, then Molt. Hover-to-open can be turned off from the **•••** menu.

The panel is pure black and meets the top of the screen with small outward flares, like the notch itself; the lower corners are continuously rounded. Home and Hub tabs sit left of the notch; Chat, Search, Capture and the menu sit to its right. Text uses San Francisco, and reduced-motion preferences disable interface movement. The companion remains pixel art.

**Home** shows:

- **Now playing** from Spotify or Apple Music, detected automatically: artwork, title, album, artist, a draggable progress bar and playback controls. While music plays and Molt is closed, the artwork and a level meter sit either side of the notch.
- **Your week:** a five-day strip with today highlighted, dots on days with events, and today's events or priorities.
- **Mac health:** battery, CPU, memory, storage and your companion's care level.

## A companion and a control center

- **Companion:** care, moods, tricks, short games, outfits, colors, accessories, and home customization. Click the creature to customize its home and wardrobe.
- **Today:** your next priority, selected calendar events, reminders, and focus controls.
- **Music:** Home follows whichever of Spotify or Apple Music is playing. macOS asks once for Automation permission. Molt never launches a player itself. Spotify artwork is loaded from Spotify's image servers. The Hub's **Playlists & volume** card keeps system volume and favorite playlist links; autoplay depends on the service.
- **Weather:** search for a city, choose the correct result, and fetch current modeled conditions. Powered by [Open-Meteo](https://open-meteo.com/) under CC BY 4.0. Only your search and selected coordinates go to the weather service.
- **My Mac:** save wallpaper favorites, apply one to current desktops, and restore the prior wallpaper during the session. Change Dock position, auto-hide, and icon size. Dock controls apply immediately and restart the Dock; they do not install custom skins.
- **Scenes:** save a combination of selected apps, a favorite playlist, wallpaper, and focus duration. Review the exact actions before running a scene. Existing focus sessions are preserved. App and playlist opening cannot guarantee playback or restore prior app state.
- **Arrange:** show, hide, and reorder Hub cards.

## Local helper

Start with **Connect to Ollama**. Molt connects to Ollama on this Mac and automatically uses an available compatible local installation. There is no provider or model-selection interface. Inference uses loopback requests and has no cloud fallback.

Use chat for everyday questions, explanations, writing help, planning, and reviewed task proposals. Explicitly shared screen images or extracted text can provide context. Capture requires macOS Screen Recording permission and macOS 14+; screenshot attachment is available on macOS 13. Image support depends on the connected service.

Molting offers explicit web search and reviewed public-page reading. Memories are saved only when approved and can be edited, paused, or forgotten. Recent actions and memory controls live under Settings. Older project and creator data is preserved even where its tools are no longer prominent in navigation.

## Usage and morning postcards

Usage tracking is **opt-in** in the Usage card.

- **Foreground app time:** local observation while Molt is running, including Codex and Claude desktop apps when they are foreground. Sleep gaps and idle time beyond two minutes are excluded conservatively. This is an estimate, not access to Apple's Screen Time database.
- **CLI process time:** samples whether Claude Code and Codex CLI executables are running. Background time can overlap with foreground time; it is not attention or billable duration. Terminal sessions cannot always be attributed exactly.
- **Tokens:** explicitly imports numeric records from standard `~/.claude/projects` and `~/.codex/sessions` JSONL files. Prompts are not retained or uploaded. Missing folders, oversized files, custom storage paths, and scan limits can make totals incomplete. Imports are limited to 500 files, 8 MB per file, and 64 MB per scan.
- **Cost:** displays reported costs when present, or estimates using rates you enter per million tokens. These are approximate blended rates, not subscription charges or provider invoices. Cache creation is treated as input. Without rates or recorded cost, cost is unavailable.
- **Morning postcard:** after 7 AM, summarizes the previous day's observed activity and available token records. Appears in the hub while Molt runs or on its next launch. No background daemon is installed. Up to 30 reports and 30 days of CLI intervals are retained.
- **Control:** pause imports, configure foreground tracking exclusions, or forget Molt's AI usage and reports. Forgetting does not delete the tools' original session files.

## Run and package

Requires macOS 13+, Swift 5.9+, and full Xcode for universal builds and XCTest.

```sh
swift run Molt
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer swift test --scratch-path .build-xcode
DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer ./scripts/package.sh 0.6.0
open dist/Molt.app
```

The package script produces `dist/Molt-0.6.0.dmg` and an ad-hoc signed universal app. Ad-hoc signing is not Apple notarization. Set `MOLT_UNIVERSAL=0` for a host-only development build.

## Privacy and permissions

No background screen capture, clipboard collection, or keystroke recording. Calendar, notifications, screen capture, app observation, and local AI usage imports have separate controls. Media automation requests macOS permission the first time Molt reads Spotify or Apple Music, and only for a player that is already running. Weather and web search contact their respective services when requested. Local chat and imported usage stay on the Mac.

## Development references

- [Architecture](docs/architecture.md)
- [Companion definitions](docs/definitions.md)
- [Release scope](docs/release-scope.md)
- [0.6.0 release notes](docs/releases/0.6.0.md)

Historical model/runtime tooling remains in the repository for compatibility and development, outside the current user interface.
