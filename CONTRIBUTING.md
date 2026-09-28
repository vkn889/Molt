# Contributing

Build with Swift 5.9+ on macOS 13+. Use full Xcode for tests. Run `swift test`, `python3 scripts/check-copy.py` and a release build before proposing changes. Format Swift with `swift-format format -i -r Sources Tests Package.swift` when available.

Keep simulation, eligibility, cooldowns, progression and game rules in MoltCore. Keep AppKit/SwiftUI and hardware access in the executable target. Add regression tests for persisted schema changes, timer arithmetic and reward delivery. Every schema change needs migration coverage and a preserved original save.

Species contributions must validate against the authoring guide. Packs contain only bounded local data/assets. Do not add executable scripts, remote assets, telemetry or mandatory network services. Preserve privacy separation between pet data and organization/activity data.

Use plain, readable copy. Project-authored text contains no em dashes. Preserve user-entered text and third-party license wording.

For UI changes, check keyboard access, VoiceOver labels, contrast, reduced motion, hidden-window animation, multiple displays and menu-bar recovery. Follow the manual qualification list in `docs/verification.md`. Do not claim performance measurements that were not taken.
