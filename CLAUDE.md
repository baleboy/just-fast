# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Fastino** — a free, minimal iOS intermittent-fasting tracker. SwiftUI + SwiftData, iOS 26.4 minimum, Xcode 26.x. Bundle id `com.balenet.fastino`.

Two documents drive the work and are the source of truth; keep them current:
- `specification.md` — product & technical spec. Source files reference its sections (`§2`, `§4.6`, …) in their header comments; keep those references accurate when editing.
- `IMPLEMENTATION.md` — what's built vs. deferred (widget extension, watchOS app, CloudKit sync are all deferred pending new Xcode targets).

## Commands

```bash
# Build
xcodebuild build -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17'

# Unit tests (swift-testing)
xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FastinoTests

# A single suite or test (swift-testing names, not XCTest)
xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FastinoTests/CurrentStreakTests
xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' \
  -only-testing:FastinoTests/CurrentStreakTests/threeConsecutiveDaysEndingToday
```

Launch with `-seedDemo` (DEBUG only) to populate a streak plus an active fast for screenshots; `-seedEating` seeds the between-fasts state instead. `-tab stats` / `-tab settings` (DEBUG only) opens straight onto another tab — the custom tab bar can't be tapped from `simctl`, so this is how the other screens get screenshotted.

Only the iOS 26.5 simulator runtime satisfies the 26.4 deployment target — installing on the iOS 26.1 devices fails.

The Xcode project uses **file-system-synchronized groups** — new `.swift` files are picked up automatically; no `project.pbxproj` edits needed. **Which folder you put a file in decides which platforms build it**: `Shared/` compiles into the iOS app *and* the watch app, `Fastino/` is iOS-only. Put anything that touches UIKit, the tab bar, or a full-size screen in `Fastino/`; put model/engine/store/design code in `Shared/`. The split is by folder rather than by membership exceptions precisely so the default for a new file is correct.

## Keep the README screenshot current

`docs/screenshot.png` is the timer tab mid-fast, in **light mode** (both schemes are designed; light is the one the direction leads with), and it is embedded at the top of `README.md`. **Whenever a change alters what that screen looks like** — the ring, the centre text block, the tab bar, the palette — regenerate it as part of the same piece of work, don't leave it for later:

```bash
DEV=$(xcrun simctl list devices available | grep -A20 "iOS 26.5" | grep "iPhone 17 (" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$DEV"; xcrun simctl ui "$DEV" appearance light
# build, install, then:
xcrun simctl launch "$DEV" com.balenet.fastino -seedDemo   # 10h into a 16h fast
xcrun simctl io "$DEV" screenshot /tmp/hero.png
sips -Z 620 /tmp/hero.png --out docs/screenshot.png
```

Always look at the result before committing it — a screenshot that silently captured the wrong tab, the wrong appearance, or a half-loaded view is worse than a stale one.

## Architecture

Three layers, deliberately separated so the logic is testable and reusable by the deferred widget/watch targets:

Paths below are relative to `Shared/` unless they start with `Fastino/`.

**1. Pure core — no SwiftData, no globals, no I/O**
- `Model/FastRecord.swift` — `Sendable` value snapshot of a fast (id/start/end/goalHours). Everything analytical operates on `[FastRecord]`, never on `@Model` objects.
- `Engine/FastingEngine.swift` — streaks, goal days, 7-day strip, 30-day averages. Every function is a pure function of `[FastRecord]` + `now` + `TimeZone`.
- `Engine/FastValidation.swift` — `end > start`, 7-day cap, overlap (touching endpoints allowed, open fast extends to `.distantFuture`), `excludingID` for edits.

Keep this layer pure. New stat/validation logic goes here and gets unit tests in `FastinoTests/FastingEngineTests.swift` (swift-testing `@Suite`/`@Test`, ~35 tests).

**2. Persistence + the single write path**
- `Model/Fast.swift`, `Model/AppSettings.swift` — SwiftData `@Model`s. **Every attribute must have a default and there are no unique constraints** — this keeps the schema CloudKit-compatible. Preserve that when adding fields.
- `Store/AppContainer.swift` — the shared `ModelContainer` (plus `inMemory()` for previews/tests). Mirrors to the CloudKit private database, naming `iCloud.com.balenet.fastino` explicitly rather than using `.automatic` — see `Sync/` below and IMPLEMENTATION.md.
- `Sync/` — the two rules CloudKit forces on us: `OpenFastMerge` (two devices each start a fast offline) and `SettingsElection` in `Model/AppSettings.swift` (duplicate settings rows). Both pure and unit-tested; `SyncReconciler` applies the merge, `CloudSyncStatus` reports whether sync actually works.
- `Store/FastStore.swift` — **the only place fasts are mutated.** UI, App Intents, and the future widget/watch targets all go through `startFast`/`endFast`/`toggle`/`addManual`/`update`/`delete`. Each method validates, saves, reconciles notifications, and calls `WidgetCenter.reloadAllTimelines()`. Never write to a `Fast` from a view or an intent directly — add a method here instead.
  - `endFast` returns a `FastActionResult` carrying the celebration facts (goal met, new longest fast/streak, current streak) so the UI can decide what to animate.

**3. Surfaces**
- `Fastino/Views/` — `RootView` is the three-tab shell (Timer / Stats / Settings) with the custom `FlameTabBar`; all three tabs stay mounted behind each other so switching away doesn't pop `StatsView` → `HistoryView`. Plus `TimerView` (home: `FlameRing` + mascot + zone beads + start/end), `StatsView`, `SettingsView`, `HistoryView`, `EditFastView`, `AdjustTimeSheet`.
- `Fastino Watch App/WatchTimerView.swift` — the entire watch app (§4.7): ring, mascot, elapsed time, zone, one button. No stats, no settings — the watch *reads* the plan and never writes it. It reuses `FlameRing`/`FlameMascot` by passing a smaller size rather than reimplementing them, and uses `Text(timerInterval:)` for the digits so Always-On stays correct without a per-second timeline.
- `Fastino/Intents/FastIntents.swift` — `Start`/`End`/`ToggleFastIntent` + `AppShortcutsProvider`. Only Start/End are App Shortcuts; Siri phrases rely on the `INAlternativeAppNames` aliases in `Info.plist` ("Fasting", "Fast") so `"Start \(.applicationName)"` reads as "start fasting". `ToggleFastIntent` is deliberately *not* an App Shortcut — it stays a Shortcuts-app action and requests confirmation (it's the Back Tap target).
- `Notifications/NotificationManager.swift` — goal-reached notification (scheduled at start+goal, cancelled on end/edit), the fat-burn/ketosis milestones (12h and 14h, skipped when they'd land at or after the goal), and the start reminder (on by default, suppressed while fasting). Permission is requested lazily, never on launch.
  - The start reminder fires at the user's **start-time anchor** (`startReminderHour`/`Minute`, 20:00 by default) — the same instant the eating window closes. Since the anchor never moves it's a single repeating calendar trigger; `FastStore.reconcileNotifications` only has to arm/cancel it (it's suppressed while a fast runs).
  - **The watch schedules nothing** — `add()` is a no-op there. iOS forwards the phone's notifications to the watch and there's no API to opt a local notification out of forwarding (identifiers are per-device, so matching ids don't dedupe), so scheduling on both would simply double every alert. Cancelling stays live on both. `FastinoApp` re-arms on launch and foreground, so a watch-started fast gets its notifications when the phone is next opened; the accepted gap is a phone left away right through the goal.
  - **No `UNUserNotificationCenterDelegate`, on purpose** — that's what makes iOS suppress alerts while the app is open, leaving the ember burst + green "Log this fast" CTA + haptic as the app-open cue (§5). Adding one silently changes product behavior.
  - `add()` fails silently when permission is denied, so failures are logged and Settings shows a "Notifications are turned off" row; `FastinoApp` re-arms everything on launch and on foreground.

## Domain rules that are easy to get wrong

- **Streaks are derived, never stored.** Any edit/delete recomputes from `[FastRecord]`.
- **A goal day is the day a completed fast *ended***, in the current device time zone. A fast spanning midnight credits the end day only. Multiple completed fasts ending the same day count once.
- **Strict streaks** — no freezes, no rest days; one calendar day with no completed fast resets to zero. `currentStreak` anchors on today, or yesterday if today isn't a goal day yet.
- **Day arithmetic goes through `FastingEngine.dayNumber(of:timeZone:)`** (calendar-day counting from the epoch), never 86 400-second math — durations stay absolute so DST can't distort them.
- **`goalHours`/`protocolID` are snapshotted at start.** Changing the protocol in Settings never applies retroactively, not even to the open fast.
- **The eating window closes at the daily start-time anchor, not at `lastEnd + eatingHours`.** That's what stops the schedule drifting: fasting past goal shortens today's eating window instead of pushing tomorrow's start later. `eatingHours` is descriptive only and never sets the window's length, so a protocol change doesn't resize it. Two guards return `nil` (plain "Ready"): the last fast ended >24h ago, or it ran past both its goal and the anchor — the past-due case, which would otherwise count down nearly a full day.

## Design tokens

The UI is the **"Flame Friend"** design system — the fast as a little flame you keep alive. `design_handoff_fastino_flame_friend/` is the handoff it was built from; the approved screens are `4a` (timer), `6a` (eating window), `5a` (stats), `5b` (settings) in light, `7a`/`7b`/`7c` in dark ("cozy campfire night"), plus `3a` for the motion specs. The dark eating window wasn't drawn — it reuses the dark tokens over 6a's layout. Everything else in that file is rejected exploration. Apple Health was deliberately skipped — there's no HealthKit integration (§1 non-goals).

- `Design/FlameMascot.swift` — **the mascot, and the heart of the direction.** `BlobShape` reimplements CSS elliptical-corner `border-radius` so the silhouette matches the mock exactly rather than approximately; `FlameExpression` is the face. Colour and expression come from context (zone while fasting, intensity on a plan card), never from the mascot itself — including the face ink, which is `palette.flameInk` (warm dark in *both* schemes, because it sits on the flame, not on the page) rather than `palette.ink`. The ready-made constructors — `.inZone`, `.pilotLight`, `.lit`, `.unlit` — are how every other screen should reach for it.
- `Design/Theme.swift` — the palette (§5), twice over: dynamic `Color`s for ordinary view code, and numeric `RGBA`/`FlamePalette` values for the ring and mascot, which interpolate between zone colours and so can't use an opaque dynamic Color. **Both schemes come from the handoff.** Dark is not a tint of light: cards become translucent warm film with no drop shadow, and everything lit — mascot, ring, bars, progress dot — earns a `glow` it doesn't have in daylight (`palette.glow` is clear in light, which is how the views branch). Peach paper, ink #4A2A1E, accent #C9502E; the gold→orange→pink zone scale drives ring, mascot and beads together; **green is reserved exclusively for success states**. Use tokens, never literal hexes, and don't introduce system blue.
- `Design/FlameChrome.swift` — `FlameBackground` (with the calmer `resting:` variant), `.flameCard()`, `FlamePrimaryButton` + `HardShadowButtonStyle` (the 3D press: cap moves down 3pt, shadow shrinks by the same, so the two always sum to the same height), `FlameToggleStyle`, `SuccessChip`.
- `Design/Typography.swift` + `Fastino/Resources/Fonts` — Baloo 2 at 600/700/800, bundled under OFL, subset to Latin, registered via `UIAppFonts` in `Info.plist`. Reach for `.flame(_:_:relativeTo:)` (scales with Dynamic Type) or `.flameFixed(_:_:)` where growth would break the layout. 800 is the default for anything that matters; nothing is lighter than 600.
- `Model/MetabolicZone.swift` — the three bands. Boundaries are **absolute hours (12h, 14h), not fractions of the goal**; a goal that stops short leaves a zone unreachable rather than squeezing it. The ring, the beads, the mascot's face and the milestone notifications all read from here, so they can't drift apart.
- `RootView` owns a **custom floating tab bar**, so the three main screens hide their navigation bar and every scroll view pads its bottom with `.flameTabBarClearance()`.
- **The Stats week strip is a bar histogram, not a row of mascots.** It was flames briefly and the design moved back: bar height carries a quantity (fast length against goal), and the mascot is for mood. Don't re-cute it.
- **Haptics go through `Support/Haptics.swift`**, never `UIImpactFeedbackGenerator` directly — the watch needs `WKInterfaceDevice`. Watch haptics only play when the app is frontmost and on-wrist, so never make a cue the user needs depend on one landing.
- **`Theme.dynamic` resolves statically to the dark palette on watchOS** — there's no light appearance and no `UITraitCollection` there. Appearance in Settings is iOS-only by the same logic; don't "fix" it.
- **Motion lives in `TimerView.ActiveFastContent`** (§5): launch fill 1.8s, ignite 0.9s (triggered by the fast being <2s old on appear), a flash + soft haptic at each zone crossing, and the ember burst plus green "Log this fast" CTA at the goal. All of it is skipped under Reduce Motion.

Celebration cues are ≤1.5s, non-blocking, and fall back to a color fade under Reduce Motion.
