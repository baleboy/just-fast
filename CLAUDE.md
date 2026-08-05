# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Just Fast** — a free, minimal iOS intermittent-fasting tracker. SwiftUI + SwiftData, iOS 26.4 minimum, Xcode 26.x. Bundle id `com.balenet.JustFast`.

Two documents drive the work and are the source of truth; keep them current:
- `specification.md` — product & technical spec. Source files reference its sections (`§2`, `§4.6`, …) in their header comments; keep those references accurate when editing.
- `IMPLEMENTATION.md` — what's built vs. deferred (widget extension, watchOS app, CloudKit sync are all deferred pending new Xcode targets).

## Commands

```bash
# Build
xcodebuild build -scheme JustFast -destination 'platform=iOS Simulator,name=iPhone 17'

# Unit tests (swift-testing)
xcodebuild test -scheme JustFast -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:JustFastTests

# A single suite or test (swift-testing names, not XCTest)
xcodebuild test -scheme JustFast -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:JustFastTests/CurrentStreakTests
xcodebuild test -scheme JustFast -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:JustFastTests/CurrentStreakTests/threeConsecutiveDaysEndingToday
```

Launch with `-seedDemo` (DEBUG only) to populate a streak plus an active fast for screenshots; `-seedEating` seeds the between-fasts state instead.

Only the iOS 26.5 simulator runtime satisfies the 26.4 deployment target — installing on the iOS 26.1 devices fails.

The Xcode project uses **file-system-synchronized groups** — new `.swift` files under `JustFast/` are picked up automatically; no `project.pbxproj` edits needed.

## Keep the README screenshot current

`docs/screenshot.png` is the timer tab mid-fast, in **dark mode**, and it is embedded at the top of `README.md`. **Whenever a change alters what that screen looks like** — the ring, the centre text block, the tab bar, the palette — regenerate it as part of the same piece of work, don't leave it for later:

```bash
DEV=$(xcrun simctl list devices available | grep -A20 "iOS 26.5" | grep "iPhone 17 (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$DEV"; xcrun simctl ui "$DEV" appearance dark
# build, install, then:
xcrun simctl launch "$DEV" com.balenet.JustFast -seedDemo   # 10h into a 16h fast
xcrun simctl io "$DEV" screenshot /tmp/hero.png
sips -Z 620 /tmp/hero.png --out docs/screenshot.png          # keeps it ~45KB
```

Always look at the result before committing it — a screenshot that silently captured the wrong tab, light mode, or a half-loaded view is worse than a stale one.

## Architecture

Three layers, deliberately separated so the logic is testable and reusable by the deferred widget/watch targets:

**1. Pure core — no SwiftData, no globals, no I/O**
- `Model/FastRecord.swift` — `Sendable` value snapshot of a fast (id/start/end/goalHours). Everything analytical operates on `[FastRecord]`, never on `@Model` objects.
- `Engine/FastingEngine.swift` — streaks, goal days, 7-day strip, 30-day averages. Every function is a pure function of `[FastRecord]` + `now` + `TimeZone`.
- `Engine/FastValidation.swift` — `end > start`, 7-day cap, overlap (touching endpoints allowed, open fast extends to `.distantFuture`), `excludingID` for edits.

Keep this layer pure. New stat/validation logic goes here and gets unit tests in `JustFastTests/FastingEngineTests.swift` (swift-testing `@Suite`/`@Test`, ~35 tests).

**2. Persistence + the single write path**
- `Model/Fast.swift`, `Model/AppSettings.swift` — SwiftData `@Model`s. **Every attribute must have a default and there are no unique constraints** — this keeps the schema CloudKit-compatible. Preserve that when adding fields.
- `Store/AppContainer.swift` — the shared `ModelContainer` (plus `inMemory()` for previews/tests). `cloudKitDatabase` is `.none`; flipping it to `.automatic` + setting a real container id in `JustFast.entitlements` enables sync.
- `Store/FastStore.swift` — **the only place fasts are mutated.** UI, App Intents, and the future widget/watch targets all go through `startFast`/`endFast`/`toggle`/`addManual`/`update`/`delete`. Each method validates, saves, reconciles notifications, and calls `WidgetCenter.reloadAllTimelines()`. Never write to a `Fast` from a view or an intent directly — add a method here instead.
  - `endFast` returns a `FastActionResult` carrying the celebration facts (goal met, new longest fast/streak, current streak) so the UI can decide what to animate.

**3. Surfaces**
- `Views/` — `RootView` is a three-tab `TabView` (Timer / Stats / Settings), each tab wrapping its own `NavigationStack` so `StatsView` → `HistoryView` pushes stay within the Stats tab. Plus `TimerView` (home, ring + start/end), `EditFastView`, `AdjustTimeSheet`.
- `Intents/FastIntents.swift` — `Start`/`End`/`ToggleFastIntent` + `AppShortcutsProvider`. Only Start/End are App Shortcuts; Siri phrases rely on the `INAlternativeAppNames` aliases in `Info.plist` ("Fasting", "Fast") so `"Start \(.applicationName)"` reads as "start fasting". `ToggleFastIntent` is deliberately *not* an App Shortcut — it stays a Shortcuts-app action and requests confirmation (it's the Back Tap target).
- `Notifications/NotificationManager.swift` — goal-reached notification (scheduled at start+goal, cancelled on end/edit) and the start reminder (on by default, suppressed while fasting). Permission is requested lazily, never on launch.
  - The start reminder fires at the user's **start-time anchor** (`startReminderHour`/`Minute`, 20:00 by default) — the same instant the eating window closes. Since the anchor never moves it's a single repeating calendar trigger; `FastStore.reconcileNotifications` only has to arm/cancel it (it's suppressed while a fast runs).
  - **No `UNUserNotificationCenterDelegate`, on purpose** — that's what makes iOS suppress alerts while the app is open, leaving the ring bloom + haptic as the app-open cue (§5). Adding one silently changes product behavior.
  - `add()` fails silently when permission is denied, so failures are logged and Settings shows a "Notifications are turned off" row; `JustFastApp` re-arms everything on launch and on foreground.

## Domain rules that are easy to get wrong

- **Streaks are derived, never stored.** Any edit/delete recomputes from `[FastRecord]`.
- **A goal day is the day a completed fast *ended***, in the current device time zone. A fast spanning midnight credits the end day only. Multiple completed fasts ending the same day count once.
- **Strict streaks** — no freezes, no rest days; one calendar day with no completed fast resets to zero. `currentStreak` anchors on today, or yesterday if today isn't a goal day yet.
- **Day arithmetic goes through `FastingEngine.dayNumber(of:timeZone:)`** (calendar-day counting from the epoch), never 86 400-second math — durations stay absolute so DST can't distort them.
- **`goalHours`/`protocolID` are snapshotted at start.** Changing the protocol in Settings never applies retroactively, not even to the open fast.
- **The eating window closes at the daily start-time anchor, not at `lastEnd + eatingHours`.** That's what stops the schedule drifting: fasting past goal shortens today's eating window instead of pushing tomorrow's start later. `eatingHours` is descriptive only and never sets the window's length, so a protocol change doesn't resize it. Two guards return `nil` (plain "Ready"): the last fast ended >24h ago, or it ran past both its goal and the anchor — the past-due case, which would otherwise count down nearly a full day.

## Design tokens

`Design/Theme.swift` holds the palette (§5): aubergine dark / cream light background, amber for the active ring, **mint is reserved exclusively for success states**. Use the tokens, not literal colors, and don't introduce system blue. Celebration cues are ≤1.5s, non-blocking, and fall back to a color fade under Reduce Motion.
