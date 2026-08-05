# Fastino — implementation notes

Status of the v1 build against `specification.md`. iOS 26 / Xcode 26.4, SwiftUI + SwiftData.

## What's implemented (builds, runs, tested)

The iOS app target is complete and verified in the simulator; the streak/stat
engine has an exhaustive unit-test suite (30 tests, all green).

**Core (pure, `[FastRecord]` + time zone — no SwiftData, §7)**
- `Model/FastingProtocol.swift` — the fixed protocol list (14:10 … OMAD 23:1)
- `Model/FastRecord.swift` — the Sendable value snapshot the engine operates on
- `Engine/FastingEngine.swift` — streaks (current/longest), goal days, 7-day
  strip, 30-day average & goal-completion rate, one-shot `summary`, and the
  between-fasts `EatingWindow` (`currentEatingWindow` — closes at the daily
  start-time anchor, 24h staleness cutoff, past-due guard)
- `Engine/FastValidation.swift` — `end>start`, 7-day cap, overlap (touching
  endpoints allowed), edit-excludes-self
- `FastinoTests/FastingEngineTests.swift` — midnight spans, DST, TZ shifts,
  edits, overlaps, rolling windows

**Persistence (§3)**
- `Model/Fast.swift`, `Model/AppSettings.swift` — SwiftData `@Model`s, all
  attributes defaulted (CloudKit-compatible schema, no unique constraints)
- `Store/AppContainer.swift` — the shared `ModelContainer`
- `Store/FastStore.swift` — the single write path (start/end/toggle/manual/edit/
  delete) shared by UI and intents; drives notifications + widget reloads

**UI (§4.1–4.3, §5)**
- Three tabs — Timer / Stats / Settings — each with its own `NavigationStack`
- Timer screen with progress ring (amber → mint bloom past goal, keeps counting
  over 100%), live SF-Rounded readout, "Ends 12:30" clock time under the goal
  (`TimeFormat.endLabel`, day-qualified when not today), inline start/end time
  adjustment, record banner, >48h gentle prompt, success haptic (Reduce-Motion
  aware)
- Between fasts the ring becomes the lilac **eating-window** countdown to the
  daily start-time anchor (time left → time since it closed), so a long fast
  shortens the window instead of moving tomorrow's start. Falls back to "Ready"
  before the first fast, once the last one is >24h old, and when a fast ran past
  both its goal and the anchor
- Stats screen: streak tiles, current/longest fast, 7-day strip, 30-day
  averages, link into history
- History (grouped by month, reverse-chron), edit/retro-entry/delete with
  validation messages, Settings (plan: protocol + "Start fast at" anchor;
  reminders; Back Tap tip card)
- `Design/Theme.swift` — the palette tokens (aubergine/cream, amber, mint)

**Notifications (§4.4)** — `Notifications/NotificationManager.swift`: goal-reached
(scheduled at start+goal, cancelled on end/edit) and the start reminder (on by
default at 20:00, suppressed while fasting, fired at the start-time anchor — one
repeating calendar trigger, since the anchor never moves). Permission is requested
lazily (on first start / when a reminder is enabled), not on launch. Scheduling
failures are logged; Settings surfaces an explicit "Notifications are turned
off" row when iOS won't present alerts; everything is re-armed on launch and on
foreground. Foreground alerts stay suppressed on purpose (no
`UNUserNotificationCenterDelegate`) — the app-open cue is the ring bloom (§5).

Verified in the simulator end-to-end: the goal alert is delivered when the app
is backgrounded, suppressed when it is open, and the blocked-permission row
appears after denying the prompt.

**App Intents / Shortcuts / Siri / Back Tap (§4.6)** —
`Intents/FastIntents.swift`: `StartFastIntent`, `EndFastIntent`,
`ToggleFastIntent` (state-aware confirmation) + `AppShortcutsProvider`. All write
through `FastStore` and reload widgets. Only Start/End are App Shortcuts; the
`INAlternativeAppNames` aliases in `Info.plist` make "Hey Siri, start fasting"
work. Toggle stays a Shortcuts-app action for Back Tap.

## Deferred (need additional Xcode targets — not added here)

These require new build targets in `project.pbxproj` (an App Extension and a
watchOS app), which can't be added reliably by editing the file by hand or
verified headlessly. The shared engine and App Intents are already structured
for reuse by them:

1. **Widget extension (§4.5)** — Lock Screen circular/rectangular + Home Screen
   widgets using `Text(timerInterval:)` and the interactive Start intent. Add a
   Widget Extension target, share the model/engine files + App Intents with it.
2. **watchOS app + complications (§4.7)** — mirror of the main screen; add a
   watchOS App target sharing the same store.
3. **CloudKit live sync (§3)** — the schema is already CloudKit-ready. To enable:
   set a real container id in `Fastino.entitlements`
   (`iCloud.com.balenet.fastino`) and flip `cloudKitDatabase: .none` →
   `.automatic` in `Store/AppContainer.swift`. Left local-only so the app runs
   without an iCloud container / provisioning.

Recommended next step is to extract `Model/` + `Engine/` into a shared Swift
package (as §7 envisions) so all four targets link one copy.

## Running

- App: `xcodebuild build -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17'`
- Tests: `xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FastinoTests`
- Demo data: launch with `-seedDemo 1` (DEBUG only) to populate a streak + an
  active fast for screenshots. `-seedEating` seeds the same streak but with the
  last fast closed 2h ago, so the timer shows the eating window instead.
