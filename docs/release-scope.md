# Companion expansion: implementation scope

This release implements the roadmap’s connected offline foundation: identity and adoption, original pixel art, editable appearances, care/activity economy, eight training tricks, three games, exploration, creative play, memories, traits, evolution requirements and postponement, home, dashboard, organization, focus, reminders, optional app awareness/calendar, creator packs, export/import and release automation.

## Deliberate boundaries

- Pixel art was explicitly selected by the owner. A low-poly source model and 3D renderer are not shipped.
- Animation uses 16 atlas poses, breathing, blinking and short transitions. Further dedicated gift/surprise/evolution frame sequences and new accessory artwork are content work, not a second renderer.
- Cosmetic choices currently include four palettes, plain/freckled markings, three body proportions, supported accessories and outfit presets. Independent eye, fin, and tail sprite variants are not yet drawn.
- The first three launch games are implemented. The document’s later game ideas (block stacking, adventure, word puzzles, daily puzzles) are future catalog additions.
- Creative tools include a local pixel canvas, a visual melody score, portraits and decorative keepsakes. Audio synthesis and a full scrapbook editor are future additions.
- Quick capture uses explicit structured dates. It does not guess natural-language deadlines. The island has a registered global Command-Shift-Space shortcut with a Command-Shift-M alternative; no general keyboard listener is installed.
- Tasks are built-in first. Calendar is read-only. Reminder notifications are scheduled in a bounded queue (up to 60 upcoming occurrences, up to 16 per recurring reminder) refreshed on edits and app launch. Delivery depends on macOS. Reopen Molt to replenish very long unattended recurrence schedules.
- App awareness records only public frontmost-app/session events and bounded intervals. It cannot prove productivity, detect all idle time, or reliably detect private browsing. Categories are user controlled, not inferred.
- Imported packs contain JSON and a bounded PNG atlas, never executable content. The editor offers name/decay forms plus JSON and a one-hour simulation preview.
- Launch-at-login is available through ServiceManagement for an installed app. Developer ID signing, notarization, auto-updates, screen/accessibility context, sync and an online directory remain future work. Optional Ollama and an app-managed local inference worker are implemented; hardware and clean-install qualification remain explicit release gates.

## Qualification still requiring hardware/user sessions

Cross-Space/full-screen behavior, multiple physical displays, VoiceOver usability, live permission denial/revocation flows, and an eight-hour real-time CPU/memory soak must be exercised on the supported macOS versions. The automated simulated soak does not claim those measurements. Native UI snapshots verify layout but do not replace interactive accessibility testing.

## Island and AI expansion

The island, local providers, supplied-text workflows, project memory, bounded filename search, typed proposals, reviewed tools, manual/scheduled review rituals, meeting and wrap-up context previews, and reversible file moves are implemented. See `local-ai.md` for exact qualification and limits. This does not claim every later content idea or unrestricted computer control is shipped.
