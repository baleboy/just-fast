# Fastino

A minimal iOS intermittent-fasting tracker. Logging a fast should be nearly invisible — one tap, or a double-tap on the back of the phone — while the statistics stay comprehensive and out of the way until you ask for them.

No accounts, no backend, no analytics, no subscriptions. Your data stays on your device.

<p align="center">
  <img src="docs/screenshot.png" alt="The Fastino timer part-way through a 16-hour fast: the flame mascot inside the zone-banded progress ring, with the elapsed time and the clock time the fast ends" width="285">
</p>

## Features

**Timer.** A little flame lives inside the ring, and it's the fast made visible. It changes colour and expression as you cross the metabolic zones — gold and happy up to 12 hours, deep orange and determined through fat burn, pink and proud into ketosis — while the ring fills in the same colours and three beads underneath name the zones. Between fasts the flame settles into a pale pilot light, the ring goes dashed, and a countdown runs to your next start.

**Your schedule doesn't drift.** You pick the time you start fasting, and the eating window closes at that time every day. Fast two hours longer than planned and you've spent two hours of today's eating window — you haven't pushed tomorrow's start two hours later.

**Protocols.** 14:10, 16:8, 18:6, 20:4 and OMAD (23:1). The goal is snapshotted when a fast starts, so changing protocol never rewrites history.

**Streaks and stats.** Current and longest streak, current and longest fast, a seven-day strip, and 30-day average duration and goal-completion rate. Everything is derived from stored fasts — nothing is cached, so edits recompute cleanly.

Streaks are strict by design: no freezes, no rest days. A goal day is a calendar day on which a completed fast *ended*, which means a fast spanning midnight credits exactly one day.

**History and editing.** Reverse-chronological, grouped by month. Edit start, end or note; add a fast you forgot to log; delete. Validated against overlaps, backwards times and implausible durations.

**Notifications.** A celebratory alert when you hit your goal, optional milestone nudges as you cross into fat burn and ketosis, and a daily start reminder at your chosen start time — the same moment your eating window closes. Suppressed automatically while a fast is already running.

**Shortcuts, Siri and Back Tap.** "Hey Siri, start fasting" / "stop fasting" — Start and End ship as App Shortcuts, with app-name aliases so the phrase reads naturally. A state-aware `Toggle` intent lives in the Shortcuts app and asks for confirmation, which is what makes it safe to bind to a Back Tap double-tap — the app's headline interaction.

**Export.** Every fast as a CSV — start, end, goal, duration, goal met — through the share sheet. It's your data.

**Warm by default.** The "Flame Friend" look: peach paper rather than a clinical white dashboard, Baloo 2 throughout, chunky buttons that press like real ones, and celebrations — an ignite, a zone-crossing flash, a burst of embers at the goal — that last under two seconds and respect Reduce Motion. Missing a goal is reported neutrally, never with shame.

## Requirements

- iOS 26.4 or later (iPhone and iPad)
- Xcode 26.x

## Building

```bash
# Run in the simulator
xcodebuild build -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17'

# Tests
xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FastinoTests

# A single suite
xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FastinoTests/CurrentStreakTests
```

Or just open `Fastino.xcodeproj` and hit Run.

Debug-only launch arguments help with screenshots: `-seedDemo` (a streak plus an active fast), `-seedEating` (the between-fasts state), and `-tab stats` / `-tab settings` to open on another tab.

## Architecture

SwiftUI and SwiftData throughout, in three layers:

**A pure core** — `Model/FastRecord.swift`, `Engine/FastingEngine.swift`, `Engine/FastValidation.swift`. Every streak, statistic and validation rule is a pure function of `[FastRecord]` plus a reference time and time zone. No SwiftData, no globals, no I/O. This is the layer with the exhaustive test suite: midnight spans, DST, time-zone shifts, overlaps and retroactive edits.

**Persistence and a single write path** — `Store/FastStore.swift` is the only place a fast is ever mutated. The UI and the App Intents all go through it, so validation, notification scheduling and widget reloads happen identically no matter where a fast was started from. The SwiftData models keep every attribute defaulted and avoid unique constraints, which keeps the schema CloudKit-compatible.

**Surfaces** — three tabs (Timer, Stats, Settings), plus the App Intents.

Tests use swift-testing (`@Suite` / `@Test`): 59 tests across 9 suites, all against the pure core.

### Not built yet

The engine and intents are structured for reuse by these, but each needs an additional Xcode target:

- Lock Screen and Home Screen widgets
- watchOS app and complications
- CloudKit sync — the schema is already compatible; enabling it means setting a real container identifier in `Fastino.entitlements` and flipping `cloudKitDatabase` to `.automatic` in `Store/AppContainer.swift`

## Documentation

- [`specification.md`](specification.md) — the product and technical specification, and the source of truth. Source files reference its sections (`§2`, `§4.6`) in their headers.
- [`IMPLEMENTATION.md`](IMPLEMENTATION.md) — what is built versus deferred.
- [`CLAUDE.md`](CLAUDE.md) — orientation for AI coding agents.
- [`design_handoff_fastino_flame_friend/`](design_handoff_fastino_flame_friend) — the design handoff the current screens were built from.

## Privacy

There is no backend, no telemetry and no analytics SDK. Fasts are stored locally via SwiftData. Notifications are scheduled on-device and permission is requested lazily — the first time it would actually be useful, not on launch.

## License

[MIT](LICENSE) © 2026 Francesco Balestrieri

The bundled [Baloo 2](https://github.com/EkType/Baloo2) typeface is used under the SIL Open Font License — see [`Fastino/Resources/Fonts/OFL-Baloo2.txt`](Fastino/Resources/Fonts/OFL-Baloo2.txt).
