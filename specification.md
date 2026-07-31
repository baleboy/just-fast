# Just Fast — Minimal Fasting Tracker for iOS
*Product & technical specification, v0.1 — 2026-07-29*

## 1. Purpose

A free, minimal iOS app for tracking intermittent fasting. Logging must be nearly invisible — one tap from the Lock Screen or wrist — while statistics remain comprehensive and available on demand. The app rewards consistency with subtle, delightful cues rather than gamification noise.

**Non-goals:** social features, meal/calorie logging, coaching content, HealthKit integration (no native fasting sample type exists; revisit only if Apple adds one), subscriptions or any monetization, Android/web.

## 2. Core concepts

**Protocol.** The user selects exactly one active fasting protocol from a fixed list: 14:10, 16:8, 18:6, 20:4, OMAD (23:1). The first number is the fasting goal in hours. The protocol can be changed at any time in Settings; the change applies to fasts started afterward, never retroactively.

**Fast.** A single fasting session with a `start` and an optional `end` timestamp (open = in progress). At most one fast may be open at a time. A fast whose duration ≥ the protocol goal at the time it was started is a **completed** fast; shorter ones are kept and shown in history, marked as under goal.

**Streak.** Count of consecutive *goal days* — **strict, by decision**: no freezes, no rest days; one day without a completed fast resets the streak to zero. A goal day is a calendar day (in the user's current local time zone) on which a completed fast **ended**. Multiple completed fasts ending on the same day still count as one goal day. The streak breaks when a calendar day passes with no completed fast ending on it. Retroactive edits recompute the streak from scratch — the streak is always derived from stored fasts, never stored independently.

> Rationale for "credit the end day": a 16-hour fast typically spans midnight (e.g. 20:00 → 12:00). Crediting the end day means every successful daily fast credits exactly one day, in order, with no double counting.

## 3. Data model

Storage: **SwiftData** with **CloudKit private database sync** (iPhone ⇄ Watch ⇄ future iPad). Local-first; sync is transparent and requires no account beyond iCloud.

```
Fast
  id: UUID
  start: Date            // stored as absolute time (UTC instant)
  end: Date?             // nil while in progress
  goalHours: Int         // snapshot of protocol goal at start
  protocolID: String     // e.g. "16:8", snapshot at start
  note: String?          // optional, single free-text field
  createdVia: enum { app, lockScreenWidget, homeWidget, watch, manual }

Settings (single object)
  activeProtocolID: String
  startReminderEnabled: Bool
  startReminderTime: DateComponents   // local wall-clock time
  goalNotificationEnabled: Bool
```

Derived (never stored): current streak, longest streak, longest fast, averages, goal-completion rate.

## 4. Features

### 4.1 Timer & logging
- The app is three tabs — **Timer** (home), **Stats**, **Settings** — each with its own navigation stack, so History pushes inside the Stats tab and the tab bar stays put.
- Main screen is dominated by a single state element: a progress ring with elapsed time, goal time, and one primary button — **Start fast** / **End fast**.
- Starting a fast defaults `start` to *now*, but the confirmation affordance allows adjusting the start time inline (e.g. "actually started at 21:30 yesterday") without leaving the flow.
- Ending a fast likewise allows adjusting the end time inline.
- Progress ring keeps counting past 100% (goal exceeded is a positive state, visually distinct — see §5).
- The ring centre reads as a single block: a quiet heading naming the window ("16h fast" / "8h eating window"), the large rounded readout, then the end time. The heading also carries the count's *direction* — the fast's elapsed time only ever rises, while the eating window counts down to its close and up again afterwards ("8h window closed").
- Below the readout, a quiet line gives the **clock time the current window ends** ("Ends 12:30") — the ring says how far along you are, this says when to act. It's the user's own 12/24h convention, and carries a day qualifier ("12:30 tomorrow", "Fri 12:30") whenever the end isn't today, which is the norm for an evening-started fast. Once the window is behind you the line is replaced by the status ("Goal reached 🎉" / "Ready when you are") rather than stacking on top of it, since a past end time is no longer useful.

**Eating window.** Between fasts the same ring tracks the *eating window* — the stretch from the end of the last fast to when the next one is due — so the whole cycle is visible on one screen:
- The window opens when a fast ends and lasts the current protocol's eating hours (24 − goal; e.g. 8h on 16:8). It is forward-looking — it says when the *next* fast is due — so changing protocol mid-window resizes it. Stored fasts are never touched (§6).
- The readout counts *down* the time left; once the window is over it counts *up* the time since it closed, with neutral copy ("since your 8h window closed" / "Ready when you are"). Being late is not a failure — no red, no shaming (§5).
- The ring is lilac, distinct from the amber fasting ring. It does **not** bloom to mint (success-only) and has no overshoot arc — running past the eating window isn't an achievement.
- **Before the first fast ever**, and once the last fast ended more than 24h ago (the daily cadence is broken), the screen shows the plain "Ready" state instead.
- No notification when the window closes in v1.

### 4.2 Editing & retroactive entry
- Any fast in history can be edited (start, end, note) or deleted.
- A completely missed fast can be added manually with arbitrary start/end.
- Validation: `end > start`; fasts may not overlap an existing fast (edit is rejected with a clear message identifying the conflicting fast); duration capped at 7 days (sanity guard against typos).
- Every edit triggers recomputation of streak and stats.

### 4.3 Statistics (essentials only)
One dedicated Stats screen, its own tab (§4.1):
- **Current streak** and **longest streak** (days)
- **Current fast** (live) and **longest fast ever** (duration)
- Last-7-days strip: one dot/bar per day, filled when it was a goal day
- Average fast duration and goal-completion rate over the last 30 days
- **History list**: reverse-chronological fasts with duration, goal met/missed badge; tap to edit. Infinite scroll, grouped by month.

No charts beyond the 7-day strip in v1. The data model loses nothing, so richer charts can be added later without migration.

### 4.4 Notifications (local only)
- **Goal reached**: scheduled at `start + goalHours` when a fast starts; cancelled if the fast is ended or edited before firing. Copy is celebratory, not clinical ("16 hours — goal reached 🎉 Keep going or break your fast whenever you're ready").
- **Start reminder**: "Time to start your fast?", **on by default** at a user-chosen wall-clock time (20:00). Suppressed automatically if a fast is already running. It follows the eating window (§4.1) rather than the clock alone:
  - The next reminder fires when the eating window closes, if that lands **before** the chosen time — the window knows when the next fast is actually due.
  - If the window would push it **later** than the chosen time, the chosen time wins and the window reminder is dropped. The chosen time is a ceiling, and a day never gets two nudges.
  - With no eating window (before the first fast, or once the last one is >24h old) it's simply the chosen daily time.
  - Implemented as a rolling week of one-shots re-armed on launch, on foreground and after every write — a single repeating trigger can't move its next occurrence, and one lone one-shot would stop reminding anyone who never reopens the app.
- No other notifications. No badges.
- **Foreground behaviour is deliberate**: no `UNUserNotificationCenterDelegate` is installed, so iOS suppresses alerts that fire while the app is open. The app-open goal celebration is the mint ring bloom + success haptic (§5) — a banner on top of it would be redundant.
- Permission is requested lazily (first fast start, or when a reminder is switched on), never on launch. Because `UNUserNotificationCenter.add` fails silently when permission is denied, Settings shows an explicit "Notifications are turned off" row with a link into iOS Settings whenever iOS won't present alerts — otherwise the toggles look functional while nothing can fire.
- Pending notifications are re-armed on launch and on every foreground, so a schedule lost to a denied permission recovers as soon as permission is granted.

### 4.5 Lock Screen & Home Screen widgets
No Live Activities — by decision: the system ends a Live Activity after 8 hours, shorter than any supported fasting window, and restarting from the background would require APNs push-to-start (a server; out of scope). Widgets cover the need without the cap:
- **Lock Screen accessory widgets** (circular + rectangular) are the persistent glanceable surface. They use WidgetKit timer text (`Text(timerInterval:)`) for a continuously counting elapsed/remaining display — no timeline refreshes needed, no duration cap. When idle, the circular widget is a one-tap **Start fast** button (interactive widget via App Intents); during a fast it shows progress and deep-links into the app.
- **Home Screen widget** (small): same state + start/end toggle.

### 4.6 Shortcuts, Siri & Back Tap
- App Intents shipped in v1: `StartFastIntent`, `EndFastIntent`, and a **`ToggleFastIntent`** that starts a fast if none is open and ends the open one otherwise.
- `ToggleFastIntent` **requests confirmation** before acting, with state-aware copy: "Start fasting now?" / "End fast? 15h 42m elapsed — goal reached ✓". Confirmation is what makes it safe to bind to accidental-prone triggers.
- All intents are exposed as App Shortcuts (zero-setup, Siri-invocable: "start my fast").
- **Back Tap flow** (the headline use case): the user binds the Toggle Fast shortcut to double-tap in Settings → Accessibility → Touch → Back Tap. The app can't configure this programmatically, so Settings includes a short "Set up Back Tap" tip card with the exact steps.
- Intents write through the same shared store + validation as the app; widgets reload after every intent run.

### 4.7 Apple Watch
- Independent watchOS app (SwiftUI, shared SwiftData/CloudKit store): mirror of the main screen — ring, elapsed time, start/end button, current streak. No stats screen on watch.
- **Complications / Smart Stack widget**: progress ring with elapsed time; tappable to open the watch app. Corner and circular families at minimum.
- Start/end actions on the watch sync to iPhone via CloudKit; iPhone widgets reflect the change on next reload (`WidgetCenter.reloadAllTimelines` triggered by the sync handler).

## 5. Design direction

**Distinctive, calm, warm.** No default system blue, no clinical white dashboard.

- **Palette**: deep aubergine background (#2B1B33) with warm amber/apricot accents (#FFB25E) for the active fast ring; mint (#7FE0C3) reserved exclusively for success states (goal reached, streak up). Light mode variant: cream paper (#FAF3E8) with the same accents. Colors are tokens — final values tuned during design.
- **Typography**: rounded numerals for the timer (SF Rounded), generous size; everything else quiet.
- **Celebration cues** — small, fast, never blocking:
  - Goal reached while app/watch is open: ring blooms into mint with a soft particle shimmer + success haptic (`.success` on iPhone, `.notification(.success)` on watch).
  - Streak increment: streak number does a single tick-up roll animation with a spring, tinted mint for ~1s.
  - New longest fast / longest streak: one-line inline banner ("New record — 19h 12m"), no modal.
  - All cues are ≤1.5s, no sounds by default, and respect Reduce Motion (fall back to a color fade).
- **Tone of copy**: encouraging, dry, never moralizing. Missing a goal is neutral ("14h 20m — logged"), never shaming.

## 6. Rules & edge cases

- **Midnight spans**: handled by the end-day streak rule (§2).
- **Time zone changes**: timestamps are absolute instants; calendar-day attribution uses the *current* device time zone at computation time. A Helsinki→Italy trip (1h shift) may in rare cases move a fast's end across midnight and change a historical goal day — accepted trade-off for simplicity; streak recomputation keeps everything self-consistent.
- **Clock changes / DST**: durations are computed from absolute instants, so DST never distorts a fast's length.
- **Protocol change mid-fast**: the open fast keeps its snapshotted `goalHours`; the new protocol applies from the next fast.
- **Very long open fast**: if a fast is open > 48h, the app shows a gentle prompt on next open: "Still fasting? You can adjust the end time if you forgot to stop the timer."
- **Deleting a fast** that anchored the streak recomputes and may shorten the streak; the UI shows the new value without ceremony (no negative animation).
- **Widget/Watch offline**: actions queue locally in the shared store and reconcile via CloudKit; last-writer-wins on the single open fast, with overlap validation on merge (later start wins, other record closed at that instant).

## 7. Architecture notes

- SwiftUI throughout; iOS 26 / watchOS 26 minimum (free app, no legacy-support pressure; adopt current widget & Live Activity APIs without fallbacks).
- Targets: iOS app, watchOS app, Widget extension, shared Swift package for model + streak/stat engine.
- The streak/stat engine is a pure function of `[Fast]` + time zone — unit-test it exhaustively (midnight spans, TZ shifts, overlaps, edits).
- App Intents expose `StartFastIntent` / `EndFastIntent` / `ToggleFastIntent` (§4.6) — one implementation reused by widgets, watch, Shortcuts, Siri, and Back Tap.
- No backend, no analytics SDK. Zero telemetry — by decision, consistent with the app's no-accounts, no-backend stance.

## 8. Resolved decisions

All open decisions from v0.1 have been resolved (see §7 for the resulting architecture notes: no backend, no analytics SDK, zero telemetry by decision).

## 9. v1 milestone slice

1. Model + streak engine + unit tests
2. iPhone app: timer, edit/retro-entry, stats, notifications
3. Lock Screen + Home Screen widgets
4. watchOS app + complications
5. Design polish pass: palette, celebrations, haptics
6. TestFlight (self + family), App Store submission
