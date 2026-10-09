# Architecture

The app remains a Swift package with two targets: `MoltCore` and `Molt`. The core contains Codable models, pure simulation and reward rules, deterministic games, pack validation and persistence. The executable contains AppKit window coordination, SwiftUI views and system adapters. There are no third-party runtime dependencies.

## Simulation and activities

`Simulation` analytically integrates linear decay, splitting at local calendar-day boundaries, including time spent at zero. Records retain 30 days plus the current day; very old elapsed time is fast-forwarded to bound catch-up work. Vacation freezes needs and increments a separate paused duration. `RuleBasedBrain` checks age, rolling care, traits, skills and interests in definition order.

`ActivityEngine` owns eligibility, exclusive activities, cooldown groups, costs, completion and rewards. Action changes are applied to a copy and committed atomically before publishing to the UI. Timed activities cannot complete early. Game and lesson completions require an active matching UUID. Cancellation sets the cooldown without claiming a completion reward. Rest recovery is proportional to elapsed time.

`CompanionClock` advances using process uptime and clamps to a persisted wall-clock lower bound. Backward clock changes cannot instantly unlock activities. Full prevention of deliberate offline clock manipulation is not claimed.

Cooldowns, reward IDs, daily reward totals, active activity, saved game, skills and recent memories share the pet snapshot. Recent reward IDs are bounded. Organization focus sessions additionally retain durable delivery acknowledgments: credit the pet first, then acknowledge in SQLite; a crash between writes retries through the pet ledger.

## Persistence

`PetStore` writes JSON atomically, maintains a previous decodable save, and preserves a once-only pre-v2 migration backup. Each pet embeds a definition snapshot. Imports stage assets separately by UUID, archive the outgoing state, and write the new snapshot before publishing it. Invalid files are never silently replaced.

`OrganizationStore` uses system SQLite, WAL and full-synchronous transactions. Tasks, notes, reminders, routines, focus sessions and app intervals are separate keyed records. Consent preferences are distinct from pet preferences. A failed transaction rolls back. Current writes commit the organization snapshot transactionally; very large libraries may warrant incremental row updates and indexed full-text search later.

Pet archives include only pet data, embedded species and optional sprite atlas. Utility exports omit app intervals and reset consent. Outfit, species, journal and portrait exports are independent.

## Native presentation

`PetController` is the main-actor source of truth. It owns the 60-second simulation/context tick and utility persistence. `AppDelegate` manages the menu bar item, the notch coordinator and a single-instance lock. All care actions go through the same controller eligibility path.

`CreatureView` draws Molt as a pixel grid with SwiftUI `Canvas`; see [art](art.md). `PetLife` turns care stats and recent play into a liveliness value that sets how far and how fast Molt wanders on Home and in Play. UI text uses the system San Francisco font.

## Notch

`IslandCoordinator` owns one borderless panel pinned to the top center of the chosen display. Every page shares one size (`bodyHeight` below the menu-bar band). The header sits in the band on either side of the hardware notch, and `NotchShape` draws the black silhouette with outward flares at the top and continuous rounded corners at the bottom. The window grows before content animates open and shrinks only after it animates closed. Hovering the notch opens Home without taking focus; moving away closes it unless a control inside became key or a drag is in progress. While music plays and Molt is closed, the panel stays at notch height with artwork on the left and a level meter on the right.

Pages: Home (`NotchHomeView`), Hub (`HubView`), Play (`PlayView`), Wardrobe (`WardrobeView`), Molting (`MoltingView`), Lens (`LensView`), Health (`HealthDetailView`), Agents (`AgentsView`, with `SessionsView` as its Chats tab), Chat (`PersonalChatView`) and Settings (`SettingsView`). Until an account exists, every page is replaced by `AccountGate`.

## Hub widgets

`HubLayout` (core, tested) keeps the Hub four units wide: widgets are one or two units, and every edit returns a valid layout or nothing. The layout is saved in `hub.json`. `WidgetKind.catalog` lists the widgets; `WidgetView` renders one. `QuickActions` runs Shortcuts items stored as `action:`, `app:`, `shortcut:` (Apple Shortcuts, run only if the name exists in your library) and `url:` strings. Screen recording runs `/usr/sbin/screencapture -v` and stops by writing to its input.

## Lens and health

`LensController` captures a region with `screencapture -i`, then runs Vision text recognition, image classification and barcode detection on the Mac, and sends only that text to the connected Ollama model. `HealthDetailController` samples `ps` every three seconds while its page is open, groups processes under their outermost app bundle with `ProcessTable` (core, tested), reads battery details from IOKit, and measures folders only when asked. Quitting uses `NSRunningApplication.terminate` on regular apps, after confirmation.

## Accounts and Molting

The backend is a Supabase project (schema in `supabase/migrations`). `AccountController` handles email and password sign-up and sign-in, TOTP two-factor authentication, and silent token refresh; the session lives in the keychain, so signing in is a one-time step. `RealtimeSocket` is a small Phoenix-protocol client over one WebSocket. All channels are private and authorized by row-level security on `realtime.messages`:

- `lobby`: presence for "online now"; users who turn off discoverability don't track.
- `user:<id>`: readable only by its owner; delivers new hangout invitations as database changes, filtered by the `hangouts` table's own policies.
- `hangout:<id>`: only its host and guest, while invited or active; carries positions and emotes.

Points are awarded only by the `end_hangout` database function (at least one minute, capped, one reward per pair per hour). Loans store a snapshot of Hub widgets and colors; trying one on keeps a local backup that is restored when the loan is returned, expires, or is taken back.

## Music

`NowPlayingController` follows Spotify and Apple Music. Track changes arrive through each player's distributed notification; AppleScript reads position and artwork and sends playback commands, only to a player that is already running. With a connected Spotify account and no local player, it follows Spotify Connect through the Web API instead. Position is polled every two seconds while the notch is open and interpolated between polls.

`MusicLibrary` lists playlists. `SpotifyAccount` signs in with OAuth authorization code and PKCE, using a loopback listener on `127.0.0.1:43821` and a Client ID the user registers; tokens live in the keychain and refresh automatically. Playlists play through the desktop app launched hidden, or through the Web API on an active device. `AppleMusicLibrary` reads library playlists and their cover art from Music by AppleScript and plays them with Music hidden. Playlist references are validated before they reach a script.

## Agents

`AgentController` runs a loopback HTTP listener on `127.0.0.1:43822` (Network framework). Claude Code reaches it through `type: "http"` hooks that `ClaudeHookInstaller` (core, tested) merges into `~/.claude/settings.json`, and Codex through a `notify` script that `CodexNotifyInstaller` (core, tested) puts first in `~/.codex/config.toml`, chaining any program already there. Every request carries a random token compared in constant time. `AgentEvent` (core) parses both payloads.

A `PermissionRequest` holds its connection open until you answer; the reply is Claude Code's `hookSpecificOutput.decision`. An empty reply hands the question back to the terminal, which also happens after 580 seconds, before Claude Code's 600-second hook timeout. `ApprovalRisk` classifies a request; `ApprovalRule.signature` generalizes simple commands to program plus subcommand and never generalizes chains or substitutions; high-risk requests are never answered by a rule. `ApprovalHabits` offers a rule after three approvals.

Running agents come from `ps -axo pid,pcpu,rss,etime,args` matched against `AgentKind`. `PlanController` reads Codex's `rate_limits` from the tail of its newest session log, and, only when enabled, Claude's usage endpoint with Claude Code's keychain token; `LimitWindow.forecast` extrapolates the current pace. `GitHubController` makes one GraphQL request (viewer PRs with check rollups, review requests, contribution calendar, one repository's default branch), signed in with `gh auth token` or a keychain token. `AgentChanges` extracts edited files from transcripts; `git diff --numstat HEAD` gives what is still uncommitted.

The island shows a banner (`IslandBanner`) beside the closed notch: approvals stay until answered, everything else fades after seven seconds and waits during focus. Global shortcuts use Control-Option, or Control-Option-Command while VoiceOver is on; Allow and Deny are registered only while an approval waits.

## Chat services

`InferenceProvider` has three implementations: `OllamaProvider` (local only, refuses cloud models), `OpenAICompatibleProvider` (LM Studio, OpenAI, Google, OpenRouter; server-sent events from `/chat/completions`) and `AnthropicProvider` (Messages API with streaming and server-side fallback on a decline). Keys live in the keychain. Lens can use its own service and model.

## Wardrobe and animation

`WardrobeItem` and `WardrobeProgress` (core, tested) decide what's earned; `Appearance.outfit` keeps one item per slot and stays compatible with saves that only have `accessory`. `CreatureView` keeps the pixel grid but animates between pixels: breathing and squash-and-stretch transforms around the feet, eyes that follow the pointer (it finds its window through `WindowReader`), uneven blinks, a ground shadow, and particles drawn in an overlay canvas from a deterministic per-index random, so the same time always draws the same frame. `--render-creature` renders frames offline with a fixed clock.

## Claude Code and Codex

`AgentSessionParser` (core, tested) extracts only the conversation from Claude Code and Codex JSONL transcripts, skipping tool calls, injected context and internal reviewer runs. `SessionsController` indexes both folders off the main thread, caches by size and modification date, counts each token record once, and, when enabled, copies transcripts into Application Support so they outlive the tools' own cleanup. Limits: 3,000 files and 60 MB per file.

## Context and permissions

`SystemHealthMonitor` uses IOKit, Mach, Dispatch memory-pressure notifications, filesystem volume values and ProcessInfo. Missing values are omitted. Raw readings are never persisted.

`ContextAdapters` observes public workspace app/sleep/session events. App awareness is opt-in. `ActivityPolicy` applies exclusions before storage and prunes retention independently of tracking state. Intervals are capped when a lifecycle event may have been missed. This remains an estimate, not document awareness or productivity detection.

Calendar access uses EventKit with availability checks for macOS 13/14 authorization APIs, reads only selected calendars, and never writes. Notification permission is requested explicitly. Recurrences use calendar arithmetic in the reminder’s timezone; notifications are bounded future occurrences. Overdue items stay in Today without replaying an alert backlog.

Focus is independent of pet activities. It pauses on observed sleep and startup, preserving recorded elapsed time while excluding unknown offline gaps. Games never capture system-wide keyboard input.
