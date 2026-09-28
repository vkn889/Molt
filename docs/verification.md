# Verification

## Automated

Run `swift test` with full Xcode selected, or prefix with `DEVELOPER_DIR=/Applications/Xcode.app/Contents/Developer`.

The suite exercises offline decay and clamping, daily integration independent of tick frequency, rolling evolution history, backward clocks, health cooldowns, corrupt saves, cyclic definitions, migration and original-file preservation, durable grouped cooldowns, low-needs recovery, exclusive activities, exactly-once rewards, early completion prevention, rest over elapsed time, reward caps, vacation, deterministic game completion, SQLite round trips, DST recurrence, focus pause gaps, task undo, app exclusions/retention, unsafe pack paths and symlinks, portable archives, invalid preferences, and an eight-hour simulated tick sequence.

`python3 scripts/check-copy.py` enforces the scoped em-dash rule in project-authored source, JSON and Markdown. Third-party font licensing and user data are excluded.

## Native layout snapshots

```sh
swift build
.build/debug/Molt --render-preview /tmp/molt-today.png
.build/debug/Molt --render-preview /tmp/molt-pet.png --pet
```

These render app-owned SwiftUI content with isolated temporary state. They do not capture the desktop, other apps or existing user data. They validate layout but do not prove interactive behavior, accessibility quality or permission delivery.

## Release checks

Build the universal `.app` and DMG with `scripts/package.sh`. Check the app’s Info.plist, included resource bundle, font/license, sprite atlas and architecture list. Render from the packaged executable to verify resource lookup without relying on SwiftPM’s build-folder fallback. CI tests and packages on tag pushes.

## Manual qualification

Before describing a release as fully qualified, exercise real restart/sleep/wake, notifications enabled/denied/revoked, selected-calendar access, full-screen Spaces, physical display removal, click-through recovery, keyboard-only workflows, VoiceOver, enlarged pet sizes and reduced motion. Measure CPU and resident memory over an actual eight-hour session with visible and hidden windows. The automated simulated soak is not a substitute for these measurements.

## Island and local AI checks

`InferenceTests` and `FileMovesTests` cover geometry, local/cloud capability boundaries, streaming failures, corrupt weights, durable job reconciliation, file collisions, stale previews, failed receipt writes, symlinks, and guarded undo. Live providers are opt-in via the environment variables documented in `local-ai.md`; ordinary CI never requires a model download or running Ollama.

The packaged app exposes `--verify-local-ai /path/to/model.gguf` for a readiness check using its own worker. A successful check under `sandbox-exec -p '(version 1)(allow default)(deny network*)'` confirms the tested text-generation path works with networking denied. This was exercised on the development Apple silicon Mac. It does not prove all hardware, installer, or permission flows.
