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

`PetController` is the main-actor source of truth. It owns the 60-second simulation/context tick and utility persistence. `AppDelegate` manages the floating panel, menu bar, dashboard, quick capture, game window, position recovery and a single-instance lock. All action surfaces call the same controller eligibility path.

`CreatureView` uses cached atlas frames and modest animation cadence. Animation stops for hidden/occluded surfaces, reduced motion and elevated thermal pressure. Pose choice is driven by explicit actions, active activities, sleep routine, context, then idle behavior. UI text uses local Oxanium headings and native body fonts.

## Context and permissions

`SystemHealthMonitor` uses IOKit, Mach, Dispatch memory-pressure notifications, filesystem volume values and ProcessInfo. Missing values are omitted. Raw readings are never persisted.

`ContextAdapters` observes public workspace app/sleep/session events. App awareness is opt-in. `ActivityPolicy` applies exclusions before storage and prunes retention independently of tracking state. Intervals are capped when a lifecycle event may have been missed. This remains an estimate, not document awareness or productivity detection.

Calendar access uses EventKit with availability checks for macOS 13/14 authorization APIs, reads only selected calendars, and never writes. Notification permission is requested explicitly. Recurrences use calendar arithmetic in the reminder’s timezone; notifications are bounded future occurrences. Overdue items stay in Today without replaying an alert backlog.

Focus is independent of pet activities. It pauses on observed sleep and startup, preserving recorded elapsed time while excluding unknown offline gaps. Games never capture system-wide keyboard input.
