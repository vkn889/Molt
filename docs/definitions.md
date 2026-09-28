# Authoring a species

Start with one of the examples in `Sources/Molt/Resources`. Definitions without `schemaVersion` are version 1; version 2 adds optional cooldown and progression fields while preserving the original model. Current app version: 0.2.0.

## Core fields

| Field | Meaning |
| --- | --- |
| `schemaVersion` | 1 or 2 |
| `id`, `name` | Stable species identity and display name; ID uses up to 64 letters, digits, underscores and hyphens |
| `author`, `minimumAppVersion` | Optional import-preview metadata and compatibility gate |
| `statDefinitions` | Unique ID, name, starting value from 0 to 100, nonnegative hourly decay |
| `evolutionTree` | Ordered stages; the first is the starting stage |
| `personality` | Dialogue dictionary and positive reaction speed |
| `interactions` | ID, name, SF Symbol, stat effects, optional `cooldownGroup` and `cooldownSeconds` |
| `systemHealthMappings` | Optional conditional effects and event triggers |
| `spriteAtlas` | Optional local PNG filename, no paths or URLs |

Larger stat values always mean healthier. The classic `hunger` ID is displayed as Nourishment. Actions can change any defined stat. `energy` and `hunger` enable the built-in resting, satiety and basic-recovery semantics. Keep these IDs when those behaviors are wanted.

Up to 10 stats, 100 stages and 40 actions are accepted. References, bounds, cycles, duplicate IDs, pack size and version requirements are validated. Unknown executable fields are never executed.

## Evolution

Stages require `id`, `displayName`, `sprite`, `minAgeDays`, `nextStages`. Optional gates: `requiredPreviousStage`, `minCareScore`, `minTraits` (0–1), `requiredSkills` (0–100) and `requiredInterests` (counts).

The brain checks candidates in the listed order. Put specific branches before fallbacks. Care is the elapsed-time-weighted average over the current and preceding six calendar days; actions never rewrite the past. Age excludes vacation duration. Traits and skill/interest gates must all pass. Cycles are rejected in linear graph traversal.

Eligible evolution is previewed in the discovery book. The user accepts when ready; previous forms remain recorded. The default Molt branches include exploration and training forms as well as care-based forms. All branches are valid companions.

## Activity economy

```json
{
  "id": "feed",
  "name": "Full meal",
  "symbol": "carrot.fill",
  "effects": { "hunger": 20 },
  "cooldownGroup": "meal",
  "cooldownSeconds": 1800
}
```

Cooldowns are persisted by group, not action title. Renaming an action or changing cosmetics cannot evade them. Explicit cooldowns may range from zero to seven days. Older definitions receive safe built-in defaults. Repetition diminishes positive need changes; negative costs are not discounted. Rewards share a daily 60-XP cap.

`rest` starts elapsed-time recovery; repeated starts do not instantly refill energy. `basic-care` restores nourishment only below 25, without progression credit, even while another activity or cooldown is active. Training uses a shared 20-minute group; games use a per-game group. Practice games do not award progression.

## Dialogue and health

Dialogue keys can be action IDs, health event IDs or moods. Interaction dialogue avoids the last few lines when alternatives exist. Moods include idle, happy, hungry, sleepy, sleeping, thinking, walking, eating, drinking, celebrating and sweating.

Health signals: `batteryLevel`, `isCharging` (0/1), `cpuLoad`, `memoryPressure`, `diskFreeRatio`, `thermalState`, `uptimeHours`. Use one `belowThreshold`, `aboveThreshold`, or thermal `atLeast` (`nominal`, `fair`, `serious`, `critical`). Effects are `affectsStat` with `delta`, `triggersEvent`, or both. Cooldown defaults to 60 minutes and must be at least one minute. Missing signals never match. Offline history is never fabricated.

## Sprite packs

Import either a JSON file or a folder containing `definition.json` and an optional PNG named by `spriteAtlas`. The image is a four-column, four-row atlas. Both dimensions must be divisible by four, between 64 and 4096 pixels. PNG size is capped at 8 MB, JSON at 256 KB. Symlinks, path traversal, remote URLs and incompatible versions are rejected.

Atlas cells, row-major: idle, blink, glance, sit, walk left, walk right, stretch, yawn, sleep, wake, eat, drink, play, think, celebrate, sweat. Every atlas needs the default idle pose. Unsupported/missing images fall back to the bundled creature. Overlay cosmetics use fixed anchors; arbitrary accessories are not supported.

Import previews metadata and starts a separate pet after confirmation. The outgoing pet is archived. Every save embeds its species definition so later imports cannot silently reinterpret that pet. Custom atlases are stored by pet UUID. Use portable pet export to include the atlas when moving to another Mac.

The Settings species editor has simple forms, JSON editing, validation and a one-hour sandbox preview. It never mutates the active pet. Export the draft and import it explicitly.
