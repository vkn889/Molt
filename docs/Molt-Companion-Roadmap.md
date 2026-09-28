# Molt : Living Desktop Companion Roadmap

**Status:** Proposed product and engineering plan; not a claim that these features are implemented.  
**Date:** September 28, 2026  
**Purpose:** Expand the original native macOS pet into an expressive, customizable companion that helps users care for their computer, organize their day, and enjoy time at their desk.  
**Scope:** Future development after the original offline foundation. This document supplements the original PRD/SRD; implementation phases below deliberately expand its scope.

## 1. Product vision

Molt is a small creature with a name, a personality, a home, and a shared history with its person. It lives on the desktop, responds to the computer's condition, joins work sessions, learns tricks, plays games, and helps keep daily commitments manageable.

Molt should feel alive when nothing is being clicked. It should also be useful without requiring the user to maintain a perfect virtual pet. Its personality and progression connect the experience; they do not obstruct access to tasks, notes, reminders, or computer information.

### Five pillars

1. **A recognizable creature:** original art, consistent anatomy, expressive motion, preferences, routines, and believable autonomous behavior.
2. **A personal relationship:** naming, gradual personality development, training, memories, and care-driven evolution.
3. **Meaningful play:** varied games and activities, cooldowns, diminishing rewards, and long-term discovery.
4. **Practical companionship:** focus, tasks, notes, reminders, daily planning, and understandable activity summaries.
5. **User ownership:** local-first storage, clear permissions, customization, portable saves, and no account required for the core experience.

### Product rules

- The pet never dies, permanently loses earned progress, or shames the user for taking a break.
- Useful tools remain available when the pet is asleep, tired, or on cooldown.
- Computer activity is context, not proof of productivity, wellbeing, or character.
- Observing something never implies permission to send messages, edit files, or control applications.
- No loot boxes, paid energy, gambling, advertising, or engagement streak penalties.
- AI is optional and later. Core behavior, organization, and games work offline.

## 2. Creative direction: a real creature with a retro identity

### Interpretation of “64-bit themed”

Use a Nintendo 64–era visual direction: low-poly forms, small textured surfaces, chunky silhouettes, restrained shading, and tactile game-like menus. This is an aesthetic proposal, not a requirement for a particular CPU architecture. If the intended look is pixel art instead, confirm before producing the final art pipeline; the behavioral systems remain the same.

### Typography: Oxanium

Use **[Oxanium](https://fonts.google.com/specimen/Oxanium)** as Molt's signature display font. Its angular, game-interface character fits the proposed retro creature world. Source: [upstream font project](https://github.com/sevmeyer/oxanium).

- Oxanium SemiBold (600): section titles, creature name, game headings, and primary navigation.
- Oxanium Bold (700): wordmark treatments and major milestone titles, used sparingly.
- Native macOS system font: tasks, notes, descriptions, settings, and longer dialogue for comfortable reading.
- Native monospaced digits: countdowns, cooldowns, and changing numerical statistics to prevent layout movement.
- Suggested starting scale: 28–32 pt display titles, 18–22 pt section titles, and 13–15 pt body text, respecting user text preferences and available space.
- Bundle the required font assets locally, include their license, and register them during app startup. No runtime font downloads.
- Provide a native-font fallback and check unsupported characters, localization, and accessibility sizing.
- Avoid all-caps paragraphs, excessive letter spacing, and decorative fonts for dense utility content.

### Editorial requirement: remove all em dashes

**Remove all em dashes from existing project-authored user-facing copy and documentation, and do not introduce new ones.** This applies to interface strings, pet dialogue, onboarding, notifications, README files, release notes, and planning documents. Replace them with a period, comma, colon, parentheses, or a rewritten sentence according to meaning. Do not substitute doubled hyphens as punctuation.

Implement this cleanup as a scoped copy pass, preserving user-entered content, third-party licenses, attributed quotations, and program syntax. Add a lightweight check for the U+2014 character in project-authored copy resources and documentation. This roadmap already follows the rule; the broader repository cleanup is a future implementation task.

### Creature concept

Start with one original species: a rounded, soft-bodied creature with tiny feet, expressive eyes, flexible ear-like fins, and a tail or shell that becomes more distinctive as it evolves. Give it a recognizable silhouette even at desktop-widget size. Avoid making the shipped identity an emoji or a generic floating ball.

Early forms should resemble the adult enough that evolution feels like growth. Personality should be visible through posture and movement, not only text labels.

### Art implementation strategy

- Prototype the low-poly creature in a short technical spike.
- For the first polished release, prefer pre-rendered transparent animation atlases from the low-poly source model. This provides the retro appearance with predictable desktop cost.
- Design a renderer boundary so a real-time 3D implementation can be evaluated later.
- Do not ship both renderers initially. Choose using visual quality, customization requirements, battery impact, and maintenance cost.
- Layer supported cosmetic attachments over predefined anchor points; arbitrary accessories are not automatically compatible.
- Keep UI text sharp and readable. Use retro typography for titles sparingly and native accessible text for utility screens.

### Initial animation set

Idle breathing, blinking, looking around, walking, turning, sitting, stretching, yawning, sleeping, waking, eating, drinking, playing, thinking, celebrating, sulking briefly, sweating, being surprised, accepting a gift, and evolving.

Animations need transition rules so the pet does not snap between unrelated poses. Reduced-motion mode substitutes still poses or gentle fades. Pause animation while hidden and reduce motion when the computer is under load.

### Sound

Optional short creature chirps, soft interaction sounds, and game audio. Sound starts off or is explicitly chosen during onboarding. Never play unexpected speech or sounds during quiet hours. Every audio cue must have a visual equivalent.

**Acceptance:** A user can recognize the creature and its basic mood at normal widget size without opening a stats panel. The pet never falls back to missing-texture graphics; every skin includes a default pose.

## 3. Personalization and identity

### Name and profile

- Name and rename Molt at any time without resetting progress.
- Record birthday, adoption date, chosen nickname, and a short user-authored profile.
- Use the chosen name throughout menus, journal entries, reminders, and celebrations.
- Offer a small adoption sequence: choose appearance, name the creature, meet it, and perform one optional interaction.
- Preview choices before confirming. No permission prompts are necessary to adopt a pet.

### Appearance

- Base color, accent color, markings, eye style, ear/fin style, tail variation, and supported body variants.
- Hats, scarves, glasses, backpacks, seasonal decorations, and small handheld props.
- Separate cosmetic appearance from evolution bonuses. A user can keep a favorite look while retaining earned development.
- Named outfit presets and a shuffle-preview button.
- A cosmetic catalog showing how items are earned; no opaque random purchases.
- High-contrast outlines and a few color-vision-friendly palettes.

### Behavior and desktop preferences

- Pet size, animation intensity, talkativeness, sound, wandering area, preferred display, and resting position.
- Companion modes: quiet coworker, playful friend, focus partner, or custom settings.
- Stationary, bounded wandering, and hide modes; walking across the entire screen is opt-in.
- Optional cursor curiosity, limited to the app's available pointer context and never blocking clicks.
- Click-through mode with an always-available menu bar control to restore interaction.
- Preserve a reachable location after display changes or resolution changes.

### Tiny home

An optional nest/terrarium opens from the pet or dashboard. Place a bed, lamp, plant, toy box, trophy shelf, and decorations. Objects have small interactions: Molt sleeps in its bed, examines a new item, or waters a plant alongside the user.

Home decoration is local and cosmetic. Furnishing should not become a second mandatory maintenance chore.

## 4. Life simulation and relationship

### Needs and traits

Keep three to five visible needs, rather than exposing dozens of bars. Suggested needs: nourishment, energy, connection, stimulation, and comfort. “Nourishment” makes it clear that a higher value is better.

Under the surface, track slowly changing preferences and tendencies:

- Curious ↔ cautious.
- Energetic ↔ mellow.
- Social ↔ independent.
- Routine-loving ↔ novelty-seeking.

Traits influence animation, activity preferences, dialogue, and evolution possibilities. They do not make the pet demand constant interaction. A user may disable adaptive personality or choose a stable personality preset.

### Relationship depth

- Familiarity grows through varied, spaced interaction, rather than click count.
- Discover favorite foods, games, toys, and routines through repeated experiences.
- Unlock affectionate animations and cooperative activities over time.
- Mark firsts: first trick, first completed focus session, first exploration, first evolution.
- Make dialogue contextual and varied with deterministic templates and recent-message suppression.

### Daily rhythm

- User-configured sleep hours and quiet hours.
- Small greeting when the user returns, without guilt-inducing absence messages.
- Optional morning check-in and evening wind-down.
- Vacation mode freezes care decay while preserving birth date and history; record paused duration separately for evolution eligibility.
- Long absence catch-up is bounded in presentation: one welcoming summary, not a backlog of alerts.
- Evolution uses active care history and configured age rules. Time spent paused must not count as evidence of good care.

### Evolution and life story

- Branching forms based on sustained care, traits, training, and discovered interests.
- A discovery book with silhouettes and broad hints; exact formulas can be shown in an optional advanced view.
- Different branches are equally valid personalities, not “good pet” versus “failed pet.”
- Preview an impending evolution and let the user postpone its visual transition.
- Preserve unlocked forms in an appearance archive; do not erase the pet's identity.
- Journal explanations use real recorded causes: “A week of exploring brought out your curiosity.”

## 5. Cooldowns and a meaningful activity economy

The goal is to make choices matter and prevent repetitive farming. It is not to make the companion difficult to access.

### Proposed starting balance : tune through playtesting

| Activity | Initial cooldown | Cost / limitation | Reward behavior |
|---|---:|---|---|
| Full meal | 30 minutes | Satiety limits repeated meals | Restores nourishment; favorite-meal discovery |
| Snack | 10 minutes | Smaller restoration; diminishing repeated benefit | Small need recovery |
| Pet / reassure | 15 seconds for rewarded response | Affection animation remains available | Relationship credit capped across repeated interactions |
| Toy play | 10 minutes | Small energy cost | Stimulation and toy familiarity |
| Trick lesson | 20 minutes | Requires enough energy | Skill experience with diminishing repetition |
| Rewarded mini-game | 15 minutes per game | Moderate energy cost | Daily soft cap on collectibles/experience |
| Practice mini-game | None | No progression rewards | Always available for fun |
| Exploration | 2 hours after return | Pet commits to a 5–15 minute activity | Predictable discovery category, capped rewards |
| Creative activity | 30 minutes | Low energy cost | Journal artifact or decorative unlock progress |
| Focus companionship | None | User chooses duration; can stop freely | Reward only actual completed duration, with a daily cap |
| Rest | None | Recovery scales with elapsed time | No instant full refill from repeated starts |

These numbers are balancing hypotheses, not hard requirements.

### Required mechanics

- Store cooldown end times durably and show time remaining before an action is selected.
- Prevent repeated starts, duplicate completion rewards, and overlapping exclusive activities.
- Explain disabled actions and offer a useful alternative: practice, quiet companionship, notes, or a different activity.
- Use separate cooldown groups so renaming an activity or switching cosmetics cannot bypass limits.
- Apply diminishing returns to repeated activities; reward variety and spacing modestly.
- Persist reward ledgers and activity IDs so restarting cannot claim a reward twice.
- Use monotonic elapsed time while running and persisted wall-clock timestamps across restarts. Handle clock rollback conservatively and explain corrected timers; fully preventing clock manipulation is not a goal for an offline personal app.
- Accessibility settings and difficulty choices must not reduce cosmetic access.
- Essential nourishment recovery cannot be trapped behind a cooldown: offer a low-reward basic-care option if a pet is in a low-needs state.

### No cooldowns on utility

Tasks, reminders, notes, search, activity summaries, export, settings, dismissing interruptions, and stopping a focus timer are always available. A tired pet can present a sleepy animation while those tools remain fully functional.

**Acceptance:** Closing and reopening the app cannot bypass a cooldown or duplicate a reward. Every blocked activity displays a reason and a next available time. A pet can always recover without waiting through a punitive chain of locks.

## 6. Activity catalog beyond eating, playing, and resting

### Care and connection

Groom, brush, offer water, tell a short story, give a collected gift, decorate together, comfort, stretch together, celebrate a completed task, and take a pet portrait. Keep these lightweight; not every action needs a new stat.

### Training

- Teach sit, spin, wave, fetch, hide, pose, carry a tiny object, and settle for focus.
- Skills progress through introduction, practice, familiarity, and mastery.
- Mini-lessons involve a short timing or matching interaction, not repeated button presses.
- Learned tricks remain learned. Missed days do not erase them.
- A training book shows progress and hints; mastered tricks can be performed on request without earning repeated XP.
- Later, allow predefined trick sequences with cosmetic rewards. Do not expose arbitrary automation scripts as “tricks.”

### Exploration

Send Molt to imaginary locations such as the circuit garden, moonlit cache, or desktop meadow. These are fictional adventures, not permission to inspect user files. Choose a location, see the duration and likely discoveries, then receive one compact return summary.

A user may recall Molt early with partial or no rewards clearly disclosed. The utility dashboard stays available while the creature is away.

### Creative activities

Create a small abstract drawing with Molt, arrange a melody from preset notes, grow a decorative plant, pose for a local screenshot, or assemble a scrapbook page from earned stickers. Save outputs only when requested, in a user-chosen location.

## 7. Mini-games

### First release: three reusable game systems

1. **Memory Meadow:** match symbol pairs together. Adjustable board size, no timer required, keyboard accessible.
2. **Molt Fetch:** aim a toy and help Molt retrieve it through a short obstacle course. Include a slower mode and an alternative to precision timing.
3. **Rhythm Steps:** copy a short sequence of directions, colors, or sounds. Visual-only and untimed modes available.

### Later games

- A compact garden puzzle with move-based play.
- Cooperative block stacking.
- Hide-and-seek inside a dedicated game scene, not behind arbitrary user windows.
- A short turn-based adventure with collectible story pages.
- Word or arithmetic puzzles with adjustable difficulty and no claims of cognitive diagnosis.
- A daily locally generated puzzle; previous puzzles remain playable.

### Game rules

Games open in their own window and never capture system-wide keyboard input. Pause safely on loss of focus. Practice is unlimited; progression rewards are limited. No online leaderboard or multiplayer dependency in the initial expansion.

**Acceptance:** Each launch game supports keyboard operation, paused/resumed sessions where practical, clear exits, and completion without audio. Reward calculation is independently testable.

## 8. Notch-attached companion dashboard and command palette

The primary app interface is a notch-attached, expandable island. Command–Shift–Space toggles it, subject to shortcut availability. The small companion popup remains a lightweight surface; the full dashboard, chat, and tools live in the expanded island. See sections 21–25 for the revised design and delivery order.

### Dashboard tabs

- **Today:** next commitment, top three priorities, active focus session, and a small check-in.
- **Activity:** current available context, app-time summary, focus sessions, and computer health.
- **Molt:** needs, personality, skills, memories, evolution, and wardrobe.
- **Home:** decoration and collected items.
- **Library:** notes, saved links, tasks, and search.

The default Today view should answer “What is next?” within a few seconds. Avoid filling it with every available measurement.

### Quick capture

A menu bar entry and configurable shortcut open a small input field. Support typed task creation, note capture, and reminder creation with a confirmation preview for interpreted dates. Plain structured controls remain available when a sentence cannot be parsed confidently.

A command palette supports actions such as “start focus,” “show today,” “feed Molt,” and “open journal.” Prefer explicit commands over pretending to understand everything.

## 9. Practical organization tools

### Tasks and projects

- Inbox, Today, Upcoming, and completed views.
- Due date, optional time, priority, estimate, tags, project, checklist, and recurring rules.
- Choose up to three daily priorities; do not force every task onto Today.
- Break a task into steps manually or through reusable templates.
- Carry unfinished work forward by explicit user choice, not silent deadline changes.
- Complete, postpone, and undo without losing history.

### Reminders

One-time and recurring reminders with snooze, dismiss, completion, and a clear next occurrence. Handle time zones and daylight-saving transitions deliberately. Explain that delivery depends on macOS notification permissions and system behavior.

### Notes and personal knowledge

Fast plain-text or Markdown notes, tags, pinned notes, local full-text search, and links to tasks. A scratchpad is one click away. Save selected links explicitly; no automatic browser-history collection.

### Routines and habits

User-created morning, work-start, break, and evening routines. Habits use weekly targets and gentle summaries rather than brittle streaks. Missing a habit never harms Molt. Reward engagement without making the pet's wellbeing depend on personal productivity.

### Focus and breaks

- Flexible timer, Pomodoro preset, and count-up mode.
- Select a task before starting, optionally.
- Pause, stop, extend, and resume without judgment.
- Molt settles down during focus and gives one quiet completion cue.
- Optional stretch, water, or look-away reminders, described as user preferences rather than medical guidance.
- After a session, offer one-tap completion or a short note.

### Daily planning and review

A morning card offers the user's priorities and available calendar events. An evening card summarizes completed tasks, recorded focus time, and one pet memory. Neither opens automatically over full-screen work unless the user chooses that behavior.

## 10. Current activity and computer awareness

“All current activity” must mean the signals the user explicitly enables and the platform actually exposes. Molt cannot reliably know every document, browser tab, or intention from an app name.

### Activity levels

| Level | Information | Default and access boundary |
|---|---|---|
| Core | Molt interactions, tasks, focus sessions, app-owned history | Local and available without activity tracking |
| System health | Battery/charging where available, thermal state, CPU load, memory pressure, free disk, uptime | Separately switchable; missing signals are shown as unavailable |
| App awareness | Frontmost application and elapsed active intervals | Off until chosen; use available public app lifecycle APIs |
| Calendar | Selected calendars and upcoming events | Separate system authorization; start read-only |
| Rich context | Selected browser tab or document context | Future explicit integration; not inferred from app awareness |

### Activity dashboard

- “Current app” with timestamp and an explanation of what is observed.
- App-time timeline with user-editable categories such as work, creativity, communication, and leisure.
- Focus sessions and breaks as separate first-party records.
- System-health cards showing unavailable states honestly.
- Optional comparison to the user's own goals; never a universal productivity score.
- Pause tracking from the menu bar and show a visible paused indicator.
- Exclude chosen apps, private sessions where reliably detectable, or specific time ranges. Do not promise automatic private-mode detection without integration support.
- Reset the baseline on sleep, lock, and tracking pause. Do not count those gaps as active use.
- If reliable idle detection needs additional capability, keep it a separate engineering and consent decision; disclose limitations of app-time estimates.

### Useful contextual behavior

- Low battery: offer a quiet “time to plug in?” message, subject to cooldown.
- High thermal pressure: pet looks warm and reduces its own animations.
- Low storage: show a factual card with a shortcut to the relevant system settings; never delete files automatically.
- Long user-recorded focus session: suggest the user's preferred break.
- Upcoming authorized calendar event: show its configured reminder.
- Return after sleep: reconcile timers and offer one compact status update.

System pressure affects creature expression more strongly than permanent development. A demanding app should not punish the user by ruining their pet.

## 11. Permission and privacy design

- Request a permission only when the user enables the corresponding feature, with a plain-language reason.
- Activity tracking off by default. Suggested retention: 7 days of raw app intervals, 30 days of optional daily aggregates, with off/delete controls.
- Treat excluded applications before persistence, not just as hidden chart rows.
- Do not record keystrokes, clipboard history, screenshots, window titles, document contents, browser history, or audio in the proposed baseline.
- Notification, calendar, launch-at-login, and future integrations each have independent controls.
- “Forget activity history” must not erase the pet. “Export pet” must not silently include task, calendar, or activity data.
- Explain what each export includes before writing it.
- Keep raw system readings transient unless the user explicitly enables a diagnostic history.
- No external messages, file rearrangement, purchases, or destructive actions without an explicit user action and a reviewable preview where relevant.

The default AI path is local and requires no provider credential. Model installation is explicit. Any future cloud provider is a separate opt-in with consent for transmitted context, secure credential storage where required, and a clear cost model. Never silently fall back from local inference to a cloud service.

## 12. Desktop behavior and quality of life

- Menu bar controls, floating creature, and dashboard share one source of truth.
- Dragging, persistent placement, multi-display recovery, and a “bring Molt back” action.
- Respect quiet hours, user-selected presentation mode, and available system state without claiming universal detection of meetings or screen sharing.
- Stay visible across Spaces where supported; provide a setting for full-screen behavior and validate it on target macOS versions.
- Optional launch at login through supported platform mechanisms.
- Keyboard shortcuts with conflict handling.
- VoiceOver labels, keyboard navigation, reduced motion, readable contrast, scalable text, and non-audio alternatives.
- Optional seasonal local themes; use the configured calendar/time zone and allow disabling them.
- A gentle onboarding tour with every optional step skippable.

## 13. Custom definitions and creator ecosystem

### Versioned species packs

A pack can describe stats, action effects, cooldowns, activity requirements, personality dialogue, evolution rules, supported cosmetics, animation keys, and system-health mappings. Extend the existing definition format through explicit schema versions and migrations.

- Provide two or three example species with different behavior, such as a study companion, garden creature, and classic pet.
- An import preview displays name, author-supplied metadata, required app version, and supported assets.
- Validate references, bounds, cycles, asset sizes, and paths before activation.
- Packs are data and assets only. No executable scripts, shell commands, arbitrary network URLs, or native plugins in the initial ecosystem.
- Provide a definition editor with forms, validation messages, and a sandbox preview after the format stabilizes.
- Switching species must explicitly choose a separate save or a supported migration. Never reinterpret an existing pet silently.

### Sharing

Export a cosmetic preset, species pack, or selected portrait independently of private history. A public online marketplace and social network are outside this roadmap's first implementation sequence.

## 14. Engineering architecture

Preserve native macOS, Swift Package Manager, AppKit window management, and SwiftUI utility views. Do not make the floating pet depend on a web service.

### Proposed modules and responsibilities

| Component | Responsibility |
|---|---|
| Simulation core | Time-based needs, personality changes, care history, and evolution |
| Behavior planner | Priority-based autonomous activities, interruption rules, dialogue selection |
| Activity engine | Eligibility, costs, cooldowns, ongoing activities, and exactly-once rewards |
| Training and games | Skill progression and pure game-state/reward logic |
| Companion renderer | Poses, animation transitions, cosmetic anchors, reduced motion |
| Organization store | Tasks, notes, routines, reminders, and focus sessions |
| Context adapters | Optional system-health, application-activity, and calendar inputs |
| Presentation coordinator | Chooses whether a cue is silent, on-pet, dashboard-only, or a notification |
| Persistence and migration | Versioned saves, atomic commits, backup, recovery, export/import |

### Model additions

- `PetIdentity`: name, adoption date, appearance preset, species identifier.
- `PersonalityProfile`: trait values, preferences, confidence, and provenance for significant changes.
- `ActivityDefinition`: duration, costs, cooldown group, prerequisites, reward rules, animation key.
- `ActivityInstance`: unique ID, start/end, status, cancellation rule, completion/reward record.
- `CooldownLedger`: scoped end times and last reliable clock observation.
- `SkillProgress`: learned tricks, mastery, and spaced training history.
- `MemoryEvent`: type, timestamp, related IDs, and safe display data.
- `CosmeticInventory` and `HomeLayout`: owned items and supported placements.
- `Task`, `Note`, `Routine`, `Reminder`, and `FocusSession`: independent of pet health.
- `ActivityInterval`: optional app identifier, time range, category, and retention metadata.
- `ConsentPreferences`: enabled capabilities, exclusions, retention, and notification preferences.

### Behavior priorities

Explicit user action → user-requested activity → scheduled pet routine → contextual reaction → autonomous idle behavior. Urgent user reminders use the notification policy independently and do not require interrupting the pet animation.

Provide interruption and cancellation rules for every long-running activity. A game or training session must not unexpectedly end because a routine idle animation was selected.

### Timing and performance

- Keep coarse simulation and system sampling on the existing low-frequency cadence.
- Use event-driven app/sleep/wake observation instead of high-frequency polling.
- Render only when visible; target a deliberately modest animation frame rate initially.
- Separate animation updates from persistence and simulation ticks.
- Batch app-activity writes and prune retained records.
- Proposed budgets for a reference Apple silicon Mac: under 1% average CPU while stationary, under 150 MB memory for the basic pet, and no unbounded growth during an eight-hour session. Treat these as measurement targets, not current results; dashboard/game peaks are measured separately.

### Persistence strategy

Keep the pet snapshot compact and atomically written. Before organization and activity history grow, evaluate SQLite for indexed records and transactional task/reminder/activity updates. Do not place an unbounded lifetime event log in the existing pet JSON.

Every schema change requires migration tests and a pre-migration backup. Failed loads must offer recovery without overwriting the damaged original. Resetting a pet, deleting organization data, and deleting activity history are separate operations.

## 15. Delivery sequence and dependencies

Each phase ends with a usable release. These are scope gates, not calendar promises.

### Phase 0 : Protect the foundation

- Verify original v1 requirements: persistence, offline decay, care history, evolution, definition validation, system-health toggles, menu bar, and packaging.
- Add save schema versioning, backup/recovery, controllable clocks, and deterministic simulation tests.
- Establish accessibility and performance baselines.

**Exit:** Restart, sleep/wake, malformed saves, long absences, and disabled health monitoring behave predictably. Existing pets survive an upgrade.

### Phase 1 : Give Molt its identity

- Finalize one creature silhouette and retro art pipeline.
- Add name/profile, adoption flow, essential animations, color presets, and basic accessories.
- Add needs panel, quiet settings, placement recovery, and reduced-motion behavior.
- Replace placeholder identity art throughout the experience.

**Exit:** The creature is expressive and recognizable; naming and appearance persist. Art and animation work at small size and on Retina displays.

### Phase 2 : Make care and play meaningful

- Activity engine, cooldown ledger, ongoing activities, recovery option, and reward caps.
- Grooming, toys, preferences, introductory training, and one complete mini-game.
- Daily rhythm, vacation mode, welcoming return, and contextual dialogue suppression.

**Exit:** Cooldowns and rewards survive restart; utilities remain accessible; repetitive clicking cannot farm unlimited progress.

### Phase 3 : Build a shared history

- Personality development, memories/journal, discovery book, and richer evolution conditions.
- Tiny home, cosmetic inventory, exploration, and remaining two launch games.
- Export selected portraits and memories.

**Exit:** Two different care histories visibly produce different preferences or evolution outcomes, with an understandable journal trail and no irreversible punishment.

### Phase 4 : Become useful every day

- Dashboard, quick capture, tasks, notes, local search, reminders, and focus sessions.
- Morning/evening routines and optional habit tracking.
- Persistent reminder scheduling and explicit permission onboarding.

**Exit:** A user can capture work, plan Today, focus, and receive a reminder without needing to interact with pet-care mechanics.

### Phase 5 : Understand the computer responsibly

- Opt-in frontmost-app activity, estimated timeline, exclusions, retention, and pause control.
- Clear system-health dashboard and contextual reactions.
- Optional selected-calendar integration, beginning read-only.
- Activity summaries with visible provenance and unavailable states.

**Exit:** Excluded data never reaches storage, sleep/lock gaps are handled, denial of every optional permission leaves the core app usable, and activity summaries state their limits.

### Phase 6 : Open up customization

- Stable pack schema, example species, safe importer, outfit sharing, and authoring documentation.
- Definition editor only after pack compatibility is tested.
- Broader cosmetics, home objects, games, and training lessons as content updates.

**Exit:** A creator can produce and import a working species without editing Swift, and incompatible packs fail without affecting the active pet.

### Later extensions

Cross-device sync, broader integrations, signed/notarized distribution improvements, and an online creator directory need separate designs. Local AI and bounded agent actions are now explicit roadmap scope, introduced according to section 25. Sync must not be added casually to a single-device timer/reward model.

## 16. First implementation backlog

| Priority | Deliverable | Depends on | Definition of done |
|---|---|---|---|
| P0 | Save versioning and recovery | Existing persistence | Upgrade and recovery fixtures pass; original damaged file is preserved |
| P0 | Unified clock and activity transactions | Simulation core | Restart, rollback, and duplicate-completion tests pass |
| P0 | Name/profile and customization model | Save migration | Rename and outfit survive restart without resetting progress |
| P0 | Creature art/rendering spike | Visual direction | One animated creature measured at widget size; renderer chosen |
| P1 | Essential animation state machine | Rendering spike | Smooth transitions, interruption rules, hidden/reduced-motion behavior |
| P1 | Cooldowns and action eligibility | Activity transactions | Clear wait times; practice and recovery paths available |
| P1 | Three additional care actions | Activity engine | Distinct effects/dialogue with accessible controls |
| P1 | Introductory training | Activity engine | Three tricks with persistent mastery and capped rewards |
| P1 | First mini-game | Reward ledger | Keyboard access, practice mode, deterministic scoring |
| P1 | Journal and milestone memories | Versioned event storage | Accurate firsts; no duplicate entries after catch-up |
| P2 | Personality and evolution expansion | History and validation | Changes explainable from sustained behavior |
| P2 | Today dashboard and quick capture | Organization storage decision | Tasks and notes independent of pet state |
| P2 | Focus and reminders | Timing and notifications | Restart/sleep reconciliation and permission-denied paths |
| P3 | Activity dashboard | Consent and retention design | Estimates labeled; exclusions applied before persistence |
| P3 | Creator packs | Stable schema and assets | Safe validation and compatibility tests |

## 17. Verification plan

### Simulation and progression

Test long offline intervals, daily boundaries, time-zone changes, leap days, daylight-saving transitions, vacation pauses, stat limits, branch ordering, history windows, and missing context. Feeding immediately before an evolution check must not rewrite historical care.

### Activities and games

Test insufficient energy, cooldown overlap, cancellation, restart midway, duplicate completion, reward caps, practice mode, clock rollback, and concurrent menu/dashboard actions. Persist completion and rewards transactionally.

### Organization

Test recurrence rules, snooze, edits, deletion, permission denial, notification scheduling failures, app restart, and sleep/wake. Distinguish a scheduled notification from a guaranteed user-visible delivery.

### Privacy

Test tracking off, pause, exclusions, retention cleanup, separate exports, revoked calendar access, and no raw readings in pet history. Inspect outbound traffic during core workflows to verify the offline claim.

### Desktop and accessibility

Test multiple displays, display removal, Spaces, full-screen behavior, click-through recovery, drag interactions, keyboard navigation, VoiceOver, scaling, and reduced motion. Validate both supported processor architectures if release artifacts claim universal support.

### Reliability and performance

Run an eight-hour idle soak, repeated sleep/wake cycles, migration fixtures, interrupted saves, full-disk write failures, and corrupt pack imports. Measure visible idle, hidden idle, open dashboard, and each game separately.

## 18. Success criteria

Use opt-in interviews and voluntary issue reports; do not add telemetry by default.

- Users can describe Molt's personality and remember a shared milestone.
- Users find at least one organization feature useful without opening another app.
- Cooldowns encourage variety without making the app frustrating.
- The pet remains enjoyable after a week away.
- Users understand exactly what activity is being tracked and can disable it immediately.
- The app causes no lost pets, lost tasks, unrecoverable migrations, or unexplained background load.
- New species packs demonstrate real behavioral variation, not just recoloring.

## 19. Decisions to settle before the relevant phase

1. Confirm low-poly N64-era art versus pixel art before commissioning or generating final assets.
2. Pick the first species silhouette and a manageable accessory attachment system.
3. Tune cooldowns and reward caps with hands-on testing; avoid committing to the sample numbers blindly.
4. Decide whether the first organization release uses only built-in tasks or also imports from system services. Built-in first is the recommended default.
5. Define precisely which app-activity signals are supported on each target macOS version before promising rich context.
6. Choose storage for growing organization/history records before building migration-heavy features.
7. Decide which features are visible in compact mode so the companion does not become an intrusive dashboard.

## 20. Recommended next release boundary

The revised next release should first establish the **notch-attached app shell, named customizable creature, and shortcut interaction**. Follow with durable cooldowns, training, one mini-game, and memories. Introduce local AI and bounded computer tools through the revised delivery sequence in section 25.

The eventual destination is one connected loop: plan something with Molt, work alongside it, take a playful break, teach it something, and watch your shared history shape its life. Every phase should strengthen that loop while keeping the computer and the user's attention under the user's control.


## 21. Revised product direction: Molt Island

**This section supersedes earlier assumptions about a standalone dashboard window.** The entire primary app experience becomes a Mac notch-attached island, inspired by the expanding interaction model of a Dynamic Island. Preserve Molt's original visual identity rather than copying Apple's branding or assets.

The creature lives at the island's edge and appears to emerge from it. The physical camera notch has no usable display pixels; Molt renders beside and below the hardware cutout, never inside it. On a display without a notch, use a top-center island with identical capabilities.

### Surface states

| State | Purpose and contents | Behavior |
|---|---|---|
| Resting | Tiny creature pose and optional single status cue | No keyboard focus, minimal movement, no large permanent panel |
| Glance | Timer, next reminder, or current agent task | Brief, non-interactive cue unless explicitly opened; obey quiet mode |
| Expanded | Full app with navigation, chat, tasks, games, creature, and settings | Opened deliberately; accepts keyboard input |
| Working | Compact progress and cancel control | Long work continues after collapse, when safe |
| Needs review | A factual indicator that a concrete action awaits review | Never steals focus or executes just because time passes |

Keep the small companion popup distinct from the expanded application. This redesign does not require removing its existing lightweight interactions. It should open the island for complex work instead of spawning a competing dashboard.

### Primary interaction

- Requested default shortcut: **Command–Shift–Space**. Toggle the expanded island and focus its command/chat input.
- Register a scoped global shortcut rather than recording all keystrokes. Check registration results, expose remapping, and provide menu bar and clickable-island alternatives.
- Apple documents system uses for shortcuts that vary by OS and configuration. Do not silently override a system binding. Explain conflicts and let the user choose another shortcut.
- Escape first dismisses a transient picker, then collapses the island. Never discards unsaved edits or silently cancels an active action.
- Clicking outside collapses ordinary browsing views. Preserve drafts; a required review can remain pending without executing.
- Opening by keyboard intentionally takes focus. Passive cues never do. Restore the previous app's focus when appropriate on collapse.
- Dragging a file onto the island opens a drop preview with available actions; dropping alone never authorizes moving, deleting, or uploading it.
- Hover expansion is optional and defaults off to reduce accidental activation near menu bar controls.

### Expanded layout

A black or near-black rounded surface grows downward from the notch, with subtle creature-colored accents, Oxanium headings, and readable native body text. Use clear boundaries in light and dark wallpapers. Do not rely on translucency for legibility.

1. Header: creature, chosen name, active workspace, and current activity indicator.
2. Command/chat field: explicit text input, attachments, and a visible local-AI status.
3. Navigation: Today, Ask Molt, Activity, Play & Train, My Molt, and Library. Home and wardrobe live under My Molt; settings remain accessible from the header.
4. Main pane: one focused feature at a time, with scrolling and optional detail navigation.
5. Action strip: progress, cancel, undo when available, or an action-review button.

Start with an expanded width around 640–760 points, clamped to the screen and text size. Height is content-dependent and capped to available display space. These are prototype dimensions, not fixed requirements. On small screens, switch to a single-column layout. Long documents and games use a larger expanded panel mode attached to the same anchor, not a tiny tooltip.

### Geometry and platform behavior

- Derive layout from the selected `NSScreen` frame, `safeAreaInsets`, and auxiliary top-area rectangles; never hardcode a notch size or assume screen coordinates begin at zero.
- Use an AppKit panel/window coordinator with SwiftUI content. Separate focusable expanded state from non-focus-stealing resting state.
- Avoid covering menu bar controls and respect the hardware exclusion region. Recompute after display changes, scaling changes, and wake.
- Default to the built-in notched display when available. Allow a selected display or active-display preference, with exactly one interactive island at a time.
- Test full-screen apps, menu bar auto-hide, Spaces, Mission Control, and presentation mode. Do not promise visibility above system-secure surfaces.
- On external monitors or notchless Macs, retain the top-center anchor and menu bar fallback.
- Reduce or disable expansion motion when requested. Support VoiceOver, complete keyboard navigation, and large text without clipping.

**Acceptance:** All primary app features are reachable from the island. The requested shortcut works when available, conflicts are explained, no controls lie beneath the physical notch, and passive updates do not interrupt typing in another application.

## 22. Computer companion and agent capabilities

All capabilities below are planned, not already operational. Prefer explicit APIs and integrations; use permissioned accessibility automation only when necessary and reliable. An app name alone is not evidence of a document's contents or the user's intent.

| Capability | User experience | Action and permission boundary |
|---|---|---|
| Workspace rituals | “Let's code” opens a saved project, editor, links, and focus timer | Preview routine setup; execute only saved steps within the approved scope |
| Resume checkpoints | Save selected file links, app links, task, and a short next-step note | User-chosen context; do not promise restoration of unsaved third-party state |
| Drag-and-drop assistance | Drop a document or log for a summary, explanation, or task extraction | File access limited to supplied items; ask before persisting extracted information |
| Downloads organizer | Propose folders, names, and selected file moves | Concrete before/after preview, collision checks, no deletion by default, undo records |
| Universal action palette | Open projects, capture tasks, search notes, and run routines | Distinguish deterministic commands from model interpretation; confirm ambiguity |
| Selected-text actions | Explain, rewrite, translate, save, or create a task | Explicit user handoff; no continuous text capture or automatic replacement |
| Screen help on demand | Explain a shared error dialog or selected screen image | Separate screen permission; one-shot capture; vision-capable model required for visual understanding |
| Project memory | Recall approved goals, folders, decisions, and next steps | Separate projects; inspect, edit, delete, and disable memory at any time |
| Meeting preparation | Assemble agenda from selected notes and authorized calendar entries | Read-only initially; no implicit recording or transcription |
| Meeting follow-up | Turn supplied notes into proposed tasks and draft messages | Task creation reviewed; sending messages requires explicit authorization |
| Routine automation | Named trigger/action sequences such as a work-start routine | Narrow saved scopes, visible history, pause and delete controls |
| Computer care | Explain battery, disk, thermal, and process information where available | Report measurements and uncertainty; no automatic cleanup or process termination |
| Command assistance | Explain and optionally execute a command in a selected project | Show command, working directory, expected effects, and output; consequential commands require review |
| Local search | Find files and optionally search indexed contents | User-selected folders, bounded indexing, exclusions, and source links |
| Clipboard handoff | Clean copied text, extract links, or save a supplied snippet | Read only when invoked; no background clipboard history |
| Daily wrap-up | Draft a summary of completed work and a next-step note | Use enabled sources only; save on request or within an explicitly configured routine |

### Make the work visible through Molt

Use a folder-carrying pose for organization, glasses for reading, a tiny desk for focus, and a backpack for saved items. A result card appears when real work completes. Learned named routines appear as tricks in the creature interface, but use the same explicit automation permissions as any other tool.

Clicking Molt's activity cue shows the current operation, inputs, progress, required decision, and stop control. Animation must reflect actual execution state: a “thinking” loop cannot substitute for honest progress or an error message.

### Initial limits

Do not implement an unrestricted “control my entire computer” loop. Ship a small, tested tool catalog before general UI automation. Apps differ in scripting and accessibility support; unsupported actions should fail clearly without repeated blind clicks.

## 23. Keyless local intelligence

### What is feasible

Molt can be a fully functional **local AI application powered by an existing language model**, without an API key, account, or per-request provider fee. Creating and training a new foundation model called Molt is a different undertaking and is not required for this product.

Local inference still consumes RAM, disk space, battery, and compute. Initial model acquisition normally requires a download, or a user can import a compatible model file. After installation, supported text workflows can run offline. Internet browsing, model updates, and external service integrations still require connectivity and may require their own authentication.

### Default architecture

- Place inference behind `LocalModelRuntime`, separate from deterministic simulation and tool execution.
- Start with a `llama.cpp` integration spike using a pinned, reviewed version and supported model format. Its upstream project supports local inference and Apple silicon acceleration through Metal.
- Prefer an app-managed isolated worker with bounded IPC over an exposed HTTP server. A runtime crash must not crash the pet or corrupt a save.
- Validate runtime packaging, deployment target, code-signing implications, cancellation, and architecture support before selecting the shipping integration.
- Offer a curated, versioned model manifest with file hashes, download size, license, compatibility, and measured resource requirements. Choose the actual model after evaluating quality and redistribution terms; do not claim every open-weight model is freely redistributable.
- No prerequisite Ollama installation, terminal setup, or third-party account for the standard experience. Optional advanced model imports can be added after the managed path works.
- Never bundle an API credential or secretly route requests to a paid provider.

### Hardware-aware setup

Detect available memory, processor architecture, free storage, and runtime compatibility. Offer a small model first, with stronger options only when benchmarked on that hardware class. Do not promise model quality or speed from parameter count alone.

Proposed evaluation categories: compact models for classification and rewriting, medium models for conversation and planning, and optional vision models for screen help. Context length and quantization affect memory substantially. Determine supported combinations experimentally, including Intel support; the non-AI companion remains usable on the baseline OS even where a selected runtime is unavailable.

Show download progress, cancel/retry, disk requirements, and uninstall controls. Lazy-load the model on first use, support manual unload, and release idle model memory according to preferences. Do not continuously run the model to animate the creature.

### First AI functions

- Conversational help grounded in approved personal context.
- Summarize a supplied note or document.
- Rewrite selected text and propose task breakdowns.
- Explain an explicitly supplied error log.
- Turn natural-language requests into validated proposals for the small tool catalog.
- Generate short optional creature dialogue while deterministic rules maintain needs, cooldowns, and evolution.

### Grounding and memory

Use local search and explicit source references for personal answers. Start with keyword/full-text retrieval before adding local embeddings. Keep durable user facts separate from generated guesses and conversation transcripts. Offer “remember this” explicitly; do not silently retain every attached document.

A model may be wrong or produce invalid tool requests. Schema validation, permission checks, and real tool results determine what happens. Never claim an action succeeded because the model wrote a success sentence.

**Acceptance:** A fresh installation can enable AI without entering an API key; after model installation, a network-disabled test can complete supported text workflows. Cancellation works, model failure leaves the pet usable, and no tool executes from unvalidated generated text.

## 24. Agent execution, review, and recovery

### Three user-facing modes

1. **Observe:** read specifically enabled context.
2. **Suggest:** produce a concrete proposal without changing external state.
3. **Act:** execute an explicit request or a narrowly approved saved routine.

The user can always see which mode applies. Model installation is not permission to observe the screen or manipulate files.

### Execution pipeline

User request → select permitted context → model or deterministic planner → typed tool proposal → validate arguments and capability scope → preview/review when required → execute → verify actual result → record outcome → offer undo when possible.

Suggested first tools: `openWorkspace`, `createTask`, `saveNote`, `searchApprovedFiles`, `startFocus`, and `proposeFileMoves`. Add command execution and screen/accessibility control only after scope enforcement and recovery tests pass.

### Required controls

- A visible job list with queued, running, awaiting review, completed, canceled, and failed states.
- Per-job cancellation, timeouts, maximum steps, and no infinite autonomous retry loop.
- Project/folder scopes and an explicit allowlist of executable tool types.
- Never treat text inside files, web pages, emails, or tool output as permission or new user instructions.
- Preview exact file paths, collisions, destinations, and counts before a batch mutation.
- Revalidate before executing if files or context changed after review.
- Record reversible operations with stable identifiers. Undo must detect intervening edits instead of overwriting them.
- Never imply full rollback for external messages, shell commands, or other irreversible side effects.
- Persist completion records so restart cannot repeat a mutation or send the same operation twice.
- Show a factual failure and partial results when only part of an operation succeeds.
- Keep audit details local, apply retention controls, and avoid storing secrets or unnecessary file contents.

### Automation builder

Start with explicit manual triggers and scheduled routines, then add well-defined app lifecycle triggers. Each routine displays its trigger, permitted inputs, actions, scopes, and review points. Include a master pause switch and quiet hours. No autonomous messaging, deletion, installation, or purchases merely because a model recommends them.

## 25. Revised implementation sequence and acceptance gates

This order supersedes the sequence where it deferred all AI indefinitely or assumed a separate dashboard. Existing creature, organization, games, and creator-pack requirements remain part of the roadmap.

1. **Foundation and island shell:** preserve saves; implement screen geometry, expanded/collapsed states, shortcut registration/remapping, focus behavior, menu bar recovery, and notchless fallback. Move existing app features into the island without duplicating state.
2. **Creature and interaction depth:** deliver identity, art, animation, customization, cooldowns, training, one game, and journal. Keep low-cost deterministic behavior independent of AI.
3. **Practical island tools:** Today, tasks, notes, reminders, focus, workspace rituals, explicit file/text handoff, and local project search. These should work before natural-language interpretation is added.
4. **Local AI release:** model installer, isolated runtime, local chat, grounded document summaries, project memory, and typed proposals. Measure supported hardware and publish honest limits.
5. **Bounded agent actions:** a small validated tool catalog, review cards, real execution status, cancellation, durable action records, and undo where safe. Add file organization only after recovery tests pass.
6. **Richer context:** opt-in activity summaries, calendar, screen help, and carefully scoped accessibility integration. Gate each independently and test denied/revoked permissions.
7. **Expanded world and ecosystem:** additional games, home, personality/evolution, creator packs, routines, and optional stronger local models.

### Additional verification

- Geometry fixtures and manual testing on notched, notchless, scaled, and multiple displays.
- Shortcut conflicts, keyboard layouts, menu bar auto-hide, focus restoration, and unsaved draft preservation.
- Network-disabled local inference tests after installation; cancel during download and generation.
- Model checksum mismatch, insufficient disk/RAM, worker crashes, malformed output, and unsupported architecture.
- Tool proposal tests for path traversal, unapproved folders, stale previews, malicious document instructions, duplicate requests, and partial failure.
- Profile resting pet separately from active AI. The earlier lightweight idle budget does not describe loaded-model memory or inference CPU/GPU use.
- Ensure sleep and wake do not resume a consequential agent action without reconciling its state.

### Technical references

- [Apple NSScreen documentation](https://developer.apple.com/documentation/appkit/nsscreen): display geometry and safe-area APIs.
- [Apple auxiliaryTopLeftArea](https://developer.apple.com/documentation/appkit/nsscreen/auxiliarytopleftarea): visible area next to the camera housing.
- [Apple keyboard guidance](https://developer.apple.com/design/human-interface-guidelines/keyboards): shortcut conventions and system conflicts.
- [llama.cpp upstream](https://github.com/ggml-org/llama.cpp): local inference runtime and supported acceleration. Verify the pinned release during implementation.


## 26. Confirmed AI delivery plan: Ollama during development, managed runtime in production

**Decision:** Use the developer's existing Ollama installation to build and test Molt's AI features. Ordinary users of the released application must not need to install Ollama, run terminal commands, create an account, or supply an API key for local AI. This is an implementation requirement, not a capability already shipped.

### Development path

- Implement an `OllamaProvider` behind a shared `InferenceProvider` protocol.
- Connect to the local Ollama service, list installed models, and let the developer select a compatible local model.
- Support streamed responses, cancellation, timeouts, unavailable-service errors, and model capability checks.
- Keep local and cloud-backed models clearly distinguished. Development testing of the offline promise must use a genuinely local model.
- Use this provider to develop chat, personality prompts, retrieval, structured tool proposals, and agent review interfaces.
- Do not hardcode one developer's installed model name or filesystem paths into release behavior.
- Reference: [Ollama local API documentation](https://docs.ollama.com/api/introduction).

### Production path

- Implement a `ManagedLocalProvider` behind the same protocol, using the app-managed runtime selected and verified in section 23.
- Package the runtime or isolated worker with Molt. Installing Molt must not install or depend on a separate Ollama application or service.
- Download model weights separately after the user chooses Enable AI. The default application installer remains usable without them.
- Keep model storage, lifecycle, updates, compatibility, and removal under Molt's own settings.
- Retain Ollama as an optional advanced provider for people who already use it; never make it the default prerequisite.
- Sharing a provider interface does not guarantee identical model behavior. Validate prompts, streaming, context limits, and tool-output handling independently for each supported provider/model combination.

### First-run experience for released Molt

1. Install and open Molt. The creature, organization tools, and deterministic activities work immediately.
2. Offer an optional Enable AI step with a plain explanation of local processing and resource use.
3. Check runtime support, available memory, and free storage. Show a tested compatible model option, download size, and license information.
4. Let the user start, postpone, or cancel the download. Support recovery from interrupted downloads.
5. Verify model integrity, load it, and run a small readiness check.
6. Show Local AI ready in the island. All supported inference stays on the Mac without an API key.
7. If setup fails or the hardware is unsupported, preserve the fully usable non-AI companion and explain the limitation. Do not silently switch to cloud inference.

### Model management

Provide installed size, selected model, compatibility status, download progress, retry, update, switch, unload, and uninstall controls. Deleting a model must not delete the pet, tasks, notes, or memories. Updates should preserve the previous working installation until the new version is verified, subject to sufficient disk space.

A model download is normally required once per installation. Additional downloads occur only for explicit model changes or updates. Importing a compatible local model may provide an advanced offline setup path. Local AI uses the user's hardware and power; no provider fee does not mean zero resource cost.

### Provider-neutral application design

The companion controller, chat interface, retrieval system, and tool executor must not depend directly on Ollama request types. Normalize messages, streaming events, model capabilities, errors, and typed proposals at the provider boundary.

Keep the permission and execution layer outside the language model. Switching providers must never broaden folder access, bypass an action review, or alter the cooldown/reward system. The deterministic simulation remains authoritative for creature state.

### Required work before releasing local AI

- Package and test the managed runtime on every supported release architecture and OS combination.
- Verify runtime and model distribution licenses, notices, and integrity checks.
- Add the production model installer, compatibility checks, lifecycle controls, and isolated-worker recovery.
- Test on a clean Mac or clean user environment without Ollama, developer tooling, or preexisting model caches.
- Complete setup without Terminal, account creation, or API keys.
- After model installation, disable network access and verify supported chat, supplied-document assistance, and bounded local tools.
- Test low disk space, memory pressure, interrupted downloads, invalid model files, cancellation, restart, and runtime crashes.
- Measure active AI separately from idle companion performance and document tested hardware limits.

**Release gate:** Do not advertise effortless keyless AI for ordinary users until the managed runtime and clean-install flow pass these checks. A working Ollama development integration alone does not satisfy this requirement.
