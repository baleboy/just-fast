# Fastino — Minimal Fasting Tracker for iOS
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
  startReminderTime: DateComponents   // local wall-clock time; also the schedule
                                      // anchor the eating window closes at (§4.1)
  goalNotificationEnabled: Bool
  milestoneNotificationsEnabled: Bool        // fat-burn / ketosis nudges (§4.4)
  appearance: enum { system, light, dark }   // UI mode override (§5)
```

Derived (never stored): current streak, longest streak, longest fast, averages, goal-completion rate.

## 4. Features

### 4.1 Timer & logging
- The app is three tabs — **Timer** (home), **Stats**, **Settings** — each with its own navigation stack, so History pushes inside the Stats tab and the tab bar stays put.
- Main screen is dominated by a single state element: a progress ring with elapsed time, goal time, and one primary button — **Start fast** / **End fast**.
- Starting a fast defaults `start` to *now*, but the confirmation affordance allows adjusting the start time inline (e.g. "actually started at 21:30 yesterday") without leaving the flow.
- Ending a fast likewise allows adjusting the end time inline.
- **The ring encodes the metabolic zones as colour bands** (§5): gold 0–12h "Burning", orange 12–14h "Fat burn", pink 14h+ "Ketosis". Inside a band the colour ramps; at a boundary it jumps. The part still ahead of you is that zone's colour as a pale preview, and a white dot with a 4pt ring in the active zone's colour rides the fill edge. Zone boundaries are **absolute hours into the fast, not fractions of the goal**: fat burn opens 12h in whether the plan is 16:8 or 20:4. A goal that stops before a boundary simply never reaches that band (14:10 can't reach ketosis), and the corresponding bead is shown as unreachable.
- Under the ring, **three zone beads** double as its legend and its progress readout: passed zones are ticked ("Burning ✓"), the current one is on the peach surface with an exclamation ("Fat burn!"), the rest are quiet at 55%.
- Progress past the goal keeps the ring fully lit rather than wrapping a second time (goal exceeded is a positive state — see §5).
- The ring centre reads as a single block: the mascot, the large readout, and one quiet line under it ("16h fast · ends 12.34"). Between fasts a heading is added above the readout, because there the count's *direction* needs saying — the fast's elapsed time only ever rises, while the eating window counts down to its close and up again afterwards ("EATING WINDOW" → "WINDOW CLOSED"). That heading carries no hour count, because the window's length isn't fixed (below).
- Below the readout, a quiet line gives the **clock time the current window ends** ("Ends 12:30" while fasting, "Next fast at 20:00" between fasts) — the ring says how far along you are, this says when to act. It's the user's own 12/24h convention, and carries a day qualifier ("12:30 tomorrow", "Fri 12:30") whenever the end isn't today, which is the norm for an evening-started fast. Once the window is behind you the line is replaced by the status ("Goal reached 🎉" / "Ready when you are") rather than stacking on top of it, since a past end time is no longer useful.

**Eating window.** Between fasts the same ring tracks the *eating window* — the stretch from the end of the last fast to when the next one is due — so the whole cycle is visible on one screen:
- The window opens when a fast ends and closes at the user's **start-time anchor**: the daily wall-clock time they start fasting (`startReminderTime`, 20:00 by default). It is *not* `end + eating hours`.
- **The anchor never moves, so the schedule never drifts.** Fasting past goal costs eating time — break at 14:00 against a 20:00 anchor and the window is 6h, not 8h — rather than pushing tomorrow's start later, where the drift would compound day after day. Breaking early buys the time back. The protocol's eating hours (24 − goal) describe the shape of an on-plan day; they never set this window's length, so changing protocol mid-window doesn't resize it. Stored fasts are never touched (§6).
- **If a fast runs past its goal *and* past the anchor**, the user is already due: the screen goes straight to the past-due "Ready when you are" state rather than counting down almost a full day to the next anchor. Starting a fast a few minutes either side of the anchor is the on-plan case and never counts as a missed one.
- The readout counts *down* the time left; once the window is over it counts *up* the time since it closed, with neutral copy ("Window closed" / "Ready when you are"). Being late is not a failure — no red, no shaming (§5).
- The ring becomes a **waiting ring**: a dashed circle, no fill and no dot, with the pilot-light mascot inside. Under it sits a **last-fast recap** card ("16h 4m · goal met") with the current streak as a green chip. The fire only burns during a fast, and running past your eating window isn't an achievement.
- **Before the first fast ever**, and once the last fast ended more than 24h ago (the daily cadence is broken), the screen shows the plain "Ready" state instead.
- No notification when the window closes in v1.

### 4.2 Editing & retroactive entry
- Any fast in history can be edited (start, end, note) or deleted.
- A completely missed fast can be added manually with arbitrary start/end.
- Validation: `end > start`; fasts may not overlap an existing fast (edit is rejected with a clear message identifying the conflicting fast); duration capped at 7 days (sanity guard against typos).
- Every edit triggers recomputation of streak and stats.

### 4.3 Statistics (essentials only)
One dedicated Stats screen, its own tab (§4.1), laid out as a 2×2 bento plus the week strip:
- **Current fast** (live, highlighted while one is running) and **longest fast ever**
- **Streak**: current, with the best alongside it
- **Goal rate** over the last 30 days, with the average duration as its caption
- **Last-7-days strip**: a bar histogram — seven bars on a 64pt track, height proportional to that day's longest fast against the goal. A goal day is a solid warm gradient (glowing in dark); a day with nothing logged is a neutral stub; **today, still fasting, is the same gradient at half strength with a 2pt dashed accent border**, and fills in solid the moment the goal is met.
- **History list**: reverse-chronological fasts with duration, goal met/missed badge; tap to edit. Infinite scroll, grouped by month.
- **Export data** (Settings → General): every fast as a CSV — start, end, goal hours, duration, goal met — shared through the system share sheet.

No charts beyond the 7-day strip in v1. The data model loses nothing, so richer charts can be added later without migration.

### 4.4 Notifications (local only)
- **Goal reached**: scheduled at `start + goalHours` when a fast starts; cancelled if the fast is ended or edited before firing. Copy is celebratory, not clinical ("16 hours — goal reached 🎉 Keep going or break your fast whenever you're ready").
- **Start reminder**: "Time to start your fast?", **on by default**, fired at the start-time anchor (20:00 by default) — the same instant the eating window closes (§4.1). Suppressed automatically if a fast is already running. Because the anchor never moves, this is a single repeating calendar trigger on wall-clock components, so it keeps its local time across DST and keeps firing whether or not the app is ever reopened.
  - The anchor is presented in Settings as a plan setting ("Start fast at"), not a notification preference, and stays visible when the reminder is switched off — it still governs the eating window.
- **Milestones**: "Fat burn zone" at 12h and "Ketosis zone" at 14h — the same boundaries the ring changes colour at (§4.1), so the notification and the screen always agree. On by default, one switch for the pair. A milestone landing at or after the goal is skipped, so a 14:10 fast doesn't fire "ketosis" and "goal reached" for the same instant.
- No other notifications. No badges.
- **Foreground behaviour is deliberate**: no `UNUserNotificationCenterDelegate` is installed, so iOS suppresses alerts that fire while the app is open. The app-open goal celebration is the ember burst + green CTA + success haptic (§5) — a banner on top of it would be redundant.
- Permission is requested lazily (first fast start, or when a reminder is switched on), never on launch. Because `UNUserNotificationCenter.add` fails silently when permission is denied, Settings shows an explicit "Notifications are turned off" row with a link into iOS Settings whenever iOS won't present alerts — otherwise the toggles look functional while nothing can fire.
- Pending notifications are re-armed on launch and on every foreground, so a schedule lost to a denied permission recovers as soon as permission is granted.

### 4.5 Lock Screen & Home Screen widgets
No Live Activities — by decision: the system ends a Live Activity after 8 hours, shorter than any supported fasting window, and restarting from the background would require APNs push-to-start (a server; out of scope). Widgets cover the need without the cap:
- **Lock Screen accessory widgets** (circular + rectangular) are the persistent glanceable surface. They use WidgetKit timer text (`Text(timerInterval:)`) for a continuously counting elapsed/remaining display — no timeline refreshes needed, no duration cap. When idle, the circular widget is a one-tap **Start fast** button (interactive widget via App Intents); during a fast it shows progress and deep-links into the app.
- **Home Screen widget** (small): same state + start/end toggle.

### 4.6 Shortcuts, Siri & Back Tap
- App Intents shipped in v1: `StartFastIntent`, `EndFastIntent`, and a **`ToggleFastIntent`** that starts a fast if none is open and ends the open one otherwise.
- `ToggleFastIntent` **requests confirmation** before acting, with state-aware copy: "Start fasting now?" / "End fast? 15h 42m elapsed — goal reached ✓". Confirmation is what makes it safe to bind to accidental-prone triggers.
- **Start and End are exposed as App Shortcuts** (zero-setup, Siri-invocable). App Intents requires every phrase to contain the app name, so `Info.plist` declares `INAlternativeAppNames` aliases — **"Fasting"**, "Fast" — which turn `"Start \(.applicationName)"` into the natural "Hey Siri, start fasting" / "stop fasting" alongside "start Fastino".
- **Toggle is not an App Shortcut.** Siri offers only the unambiguous start/end pair; `ToggleFastIntent` remains available as an action in the Shortcuts app, which is all Back Tap needs.
- **Back Tap flow** (the headline use case): the user wraps the Toggle Fast action in a Shortcuts-app shortcut, then binds it to double-tap in Settings → Accessibility → Touch → Back Tap. Because Toggle is no longer an App Shortcut it doesn't show up in the Back Tap picker on its own, so the "Set up Back Tap" tip card in Settings spells out that first step.
- Intents write through the same shared store + validation as the app; widgets reload after every intent run.

### 4.7 Apple Watch
- Independent watchOS app (SwiftUI, shared SwiftData/CloudKit store): ring, elapsed time, start/end button. "Independent" means it talks to CloudKit itself rather than proxying through the phone — starting and ending a fast works with the phone out of range.
- **Installable on its own**, without the iPhone app — while still shipping *with* it: one App Store listing, and a user who installs Fastino on their iPhone gets the watch app on their paired watch automatically, as they always did. Standalone installation is an addition, not a replacement. But it makes the watch the only surface some users ever see, so it carries the settings a plan needs to work at all: the protocol, the start-reminder time, and the goal/milestone alert toggles. Appearance is not among them — there is no light appearance on watchOS.
- **Three pages, timer in the middle**: `[Progress] ← [Timer] → [Settings]`. Progress is the current streak, the seven-day strip, and the fast in progress above the ten most recent finished ones. Tapping any of them opens a detail screen where either time can be corrected, or the fast discarded. Correcting the **start of a running fast** is the one that matters most: tap Start late and every zone boundary and the goal alert are wrong from then on. Editing covers hour and minute; a different *day* is a phone-sized edit.
- **Only one device schedules notifications.** iOS forwards the phone's alerts to a paired watch and there is no API to dedupe them, so the watch schedules only when there is no iPhone app to defer to. Cancelling stays live on both.
- **Complications / Smart Stack widget**: progress ring with elapsed time; tappable to open the watch app. Corner and circular families at minimum.
- Start/end actions on the watch sync to iPhone via CloudKit; iPhone widgets reflect the change on next reload (`WidgetCenter.reloadAllTimelines` triggered by the sync handler).

## 5. Design direction

**"Flame Friend" — warm, cute, encouraging.** The fast is a little flame you keep alive, and it lives inside the ring. No default system blue, no clinical white dashboard.

- **The mascot** is the centre of the system. A teardrop flame with a face, drawn from shapes (never a raster asset), whose **colour and expression follow the metabolic zone**: gold and plainly happy while burning, deep orange and determined in fat burn, pink and proud in ketosis. Between fasts it shrinks to a pale "pilot light" with its eyes closed. It appears again at three smaller sizes: one per plan card (growing and hardening with the plan's intensity), one per goal day in the week strip, and one in the corner of the longest-fast card. It idles with a slow bob (3s fasting, 4.5s resting) and holds still under Reduce Motion. The mascot never speaks — copy stays matter-of-fact.
- **Palette**: peach paper (#FFF3E4 → #FFE8D1; the eating window uses a calmer #FFF8EF → #FDEEDE). Ink #4A2A1E, muted #B07A5A, accent #C9502E, lowercase wordmark #C96F4A. The zone scale — gold #FFD88A→#FFB36B, deep orange #FF9068→#FF7D52, pink #F78AA8 — drives the ring, the mascot and the beads together. Green (#2A8A6B on #E3F5EC) is reserved exclusively for success. Colours live in `Design/Theme.swift` as tokens; nothing hard-codes a hex.
- **Surfaces**: white cards, 24pt radius (22 rows, 20 small), warm soft shadow. A selected card takes the peach accent surface and a 2.5pt border instead of a shadow. Grouped rows are split by **2pt dashed** dividers, not hairlines.
- **The primary button is chunky and physical**: a gradient pill with a *hard* 3D shadow (a solid colour offset 6pt down, no blur). Pressing moves the cap 3pt down and shrinks the shadow to match.
- **Chrome**: the system tab bar is replaced by a floating white pill (Timer / Stats / Settings) with the active item on a peach chip. The three main screens carry no navigation bar.
- **Dark scheme — "cozy campfire night"**: #2B1A12 → #211107, cream ink #FFF3E4, muted #C99A7D, accent text #FFB98A. Cards become translucent warm film (`rgba(255,220,180,.07)`) with **no drop shadow**, and everything lit earns a glow the light scheme doesn't have: the mascot and the selected plan flame get a halo, the ring gains a blurred copy of its burned arc, the histogram's goal-day bars glow, and the progress dot inverts to a dark disc ringed in fire. The zone colours themselves are unchanged — the flame is the same flame at night.
- **Appearance setting**: the app follows the device's light/dark setting by default, and Settings offers an explicit Light/Dark override, cycling through both designed token sets.
- **Typography**: **Baloo 2** (bundled, OFL, weights 600/700/800, subset to Latin). Everything is rounded and chunky: the live timer is 40pt/800, screen titles 26/800, stat values 32/800, section labels 12–13/800 uppercase, row titles 16/800, captions 12.5–14/600–700.
- **Motion** — ported from the handoff's live demo:
  - **Launch fill**: the ring sweeps 0 → current over 1.8s, ease-out.
  - **Ignite**: starting a fast plays an expanding ring flash, ~0.9s, and the fill grows with it.
  - **Zone crossing**: a flash in the new zone's colour plus a soft haptic; the mascot, the beads and the dot all hand over at 12h and 14h.
  - **Completion**: a flare and a stagger of rising embers (~2s), and the CTA turns green and flips from "End fast" to "Log this fast".
- **Celebration cues** — small, fast, never blocking:
  - Goal reached while app/watch is open: success haptic (`.success` on iPhone, `.notification(.success)` on watch), the ember burst, and the green CTA.
  - Streak increment: the streak number rolls up once with a spring, tinted the success green for ~1s.
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

- **Portrait only**, iPhone and iPad. The screens are one tall column each — a ring stack, a bento, a settings list — and the design was drawn at 402×874; nothing here gains from a landscape variant.
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
