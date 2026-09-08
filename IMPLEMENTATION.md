# Fastino — implementation notes

Status of the v1 build against `specification.md`. iOS 26 / Xcode 26.4, SwiftUI + SwiftData.

## What's implemented (builds, runs, tested)

The iOS app target is complete and verified in the simulator; the streak/stat
engine has an exhaustive unit-test suite (59 tests, all green). The UI implements
the "Flame Friend" design system — see `design_handoff_fastino_flame_friend/`
for the handoff the screens were built from (approved: 4a, 6a, 5a, 5b light;
7a, 7b, 7c dark; 3a for motion).

**Core (pure, `[FastRecord]` + time zone — no SwiftData, §7)**
- `Model/FastingProtocol.swift` — the fixed protocol list (14:10 … OMAD 23:1)
- `Model/MetabolicZone.swift` — the three ring bands (burning / fat burn /
  ketosis) at absolute hour boundaries, shared by the ring, the zone cards and
  the milestone notifications
- `Model/FastRecord.swift` — the Sendable value snapshot the engine operates on
- `Engine/FastingEngine.swift` — streaks (current/longest), goal days, 7-day
  strip, per-day `DayBar`s for the Stats bars, 30-day average &
  goal-completion rate, one-shot `summary`, and the
  between-fasts `EatingWindow` (`currentEatingWindow` — closes at the daily
  start-time anchor, 24h staleness cutoff, past-due guard)
- `Engine/FastValidation.swift` — `end>start`, 7-day cap, overlap (touching
  endpoints allowed), edit-excludes-self
- `FastinoTests/FastingEngineTests.swift` — midnight spans, DST, TZ shifts,
  edits, overlaps, rolling windows, day bars
- `FastinoTests/MetabolicZoneTests.swift` — zone boundaries, unreachable zones
  on short goals, spans tiling the goal

**Persistence (§3)**
- `Model/Fast.swift`, `Model/AppSettings.swift` — SwiftData `@Model`s, all
  attributes defaulted (CloudKit-compatible schema, no unique constraints)
- `Store/AppContainer.swift` — the shared `ModelContainer`
- `Store/FastStore.swift` — the single write path (start/end/toggle/manual/edit/
  delete) shared by UI and intents; drives notifications + widget reloads

**UI (§4.1–4.3, §5)**
- Four tabs — Timer / Stats / History / Settings — each with its own
  `NavigationStack`, behind a custom floating pill tab bar of SF Symbols
  (`RootView`), whose flame is lit while a fast runs; no tab screen carries a
  navigation bar
- The end-fast sheet takes a note alongside the time, seeded from the fast's
  existing one. `FastStore.endFast(at:note:createdVia:)` reads `nil` as "leave
  the note alone" (the intents and the watch, neither of which offers anywhere
  to type one) and a non-`nil` string as the user's intent — blank included, so
  clearing the field clears the note. Covered by `EndFastNoteTests`. Not on the
  watch, per §4.7's subset rule.
- Timer screen with the **flame mascot** inside the **zone ring**
  (`Design/FlameMascot.swift`, `Views/FlameRing.swift`): gold/orange/pink bands,
  a pale preview of what's still ahead, and a white progress dot on the fill
  edge. The mascot's colour and expression follow the zone. Three zone beads act
  as the legend, plus the live readout and "16h fast · ends 12.30"
  (`TimeFormat.endLabel`, day-qualified when not today), inline start/end time
  adjustment, record banner, >48h gentle prompt
- Motion per the handoff's turn 3: launch fill (1.8s), ignite (0.9s), a flash +
  soft haptic at each zone crossing, and at the goal an ember burst plus the CTA
  turning green and flipping to "Log this fast". All Reduce-Motion aware
- Between fasts the ring goes **dashed**, the mascot becomes a pilot light, and
  a last-fast recap card (with the streak as a green chip) appears below. It
  counts down the eating window to the daily start-time anchor (time left → time
  since it closed), so a long fast shortens the window instead of moving
  tomorrow's start. Falls back to "Ready" before the first fast, once the last
  one is >24h old, and when a fast ran past both its goal and the anchor
- Stats screen ("Your journey"): 2×2 bento (current fast in accent, longest fast
  with a mascot in the corner, streak + best, goal rate on the peach surface),
  the week as a **bar histogram** — height ∝ fast length against goal, solid for
  a goal day, a neutral stub for a missed one, half-strength and dashed for
  today — and a link into history
- History (grouped by month, reverse-chron), a note's first line under the
  end time (elided, single-line, so the row keeps its height),
  edit/retro-entry/delete with
  validation messages, Settings (plan cards, each a flame that grows and hardens
  with the plan's intensity; "Start fast at" anchor; the three notification
  toggles; appearance cycle; CSV export; Back Tap tip card)
- `Design/Theme.swift` — the Flame Friend palette, as dynamic `Color`s and as
  numeric `RGBA`/`FlamePalette` values the ring and mascot interpolate between.
  **Both schemes are from the handoff**; dark ("cozy campfire night") swaps
  cards for translucent film and adds the `glow` token that lights the mascot,
  the ring, the bars and the progress dot
- `Design/Typography.swift` + `Resources/Fonts` — Baloo 2 at 600/700/800 (OFL,
  Latin subset), registered through `UIAppFonts`
- `Design/FlameChrome.swift` — screen gradient (with the calmer resting
  variant), card treatment, the hard-3D-shadow button, pill toggle, success chip
- `Support/FastExport.swift` — the CSV the Settings "Export data" row shares
- `Model/Appearance.swift` + `RootView.preferredColorScheme` — the UI-mode
  override, applied above the TabView so both palettes and the window
  background follow it

**Notifications (§4.4)** — `Notifications/NotificationManager.swift`: goal-reached
(scheduled at start+goal, cancelled on end/edit), the fat-burn/ketosis
**milestones** at 12h and 14h (skipped when they'd land at or after the goal),
and the start reminder (on by
default at 20:00, suppressed while fasting, fired at the start-time anchor — one
repeating calendar trigger, since the anchor never moves). Permission is requested
lazily (on first start / when a reminder is enabled), not on launch. Scheduling
failures are logged; Settings surfaces an explicit "Notifications are turned
off" row when iOS won't present alerts; everything is re-armed on launch and on
foreground, and a fast started on the watch re-arms them through
`CompanionRelay` rather than waiting for the phone to be opened (see the watch
section). Foreground alerts stay suppressed on purpose (no
`UNUserNotificationCenterDelegate`) — the app-open cue is the in-ring "Goal
reached" line + success haptic (§5).

Verified in the simulator end-to-end: the goal alert is delivered when the app
is backgrounded, suppressed when it is open, and the blocked-permission row
appears after denying the prompt.

**App Intents / Shortcuts / Siri / Back Tap (§4.6)** —
`Intents/FastIntents.swift`: `StartFastIntent`, `EndFastIntent`,
`ToggleFastIntent` (state-aware confirmation) + `AppShortcutsProvider`. All write
through `FastStore` and reload widgets. Only Start/End are App Shortcuts; the
`INAlternativeAppNames` aliases in `Info.plist` make "Hey Siri, start fasting"
work. Toggle stays a Shortcuts-app action for Back Tap.

## Built: Apple Health (§4.8)

Read-only, iOS-only. `HealthPanels` sits at the foot of `StatsView`, under the
week strip and the History row — in line rather than behind a link of its own,
because a screen you have to go looking for is one most people never see. Two
dual-axis panels — weight over fasting hours, and the eating stop over hours
asleep — on one shared 30-day date axis. The only Swift Charts in the app,
styled entirely from `Theme`.

The fasting/weight panel is by the calendar week: `FastingEngine.weeklyAverageHours`
for the bars (`WeeklyFastAverageTests`) and `WeightSeries.weeklyMean` for the
line (`WeightSeriesTests.swift`), both bucketed by `FastingEngine.weekStart` —
the one locale-aware date function in the engine, since the first day of the
week is the user's own convention. Day-to-day weight is mostly water and one
fast can't have moved a week's average. The shared date domain is snapped out to
whole weeks so the weekly bars and both panels' grid lines land on real week
boundaries.

Both panels follow one contract: bars are that panel's hours against the
trailing axis, the overlaid line or dots go against the leading one, and only
the hours axis draws grid lines. Each chart is drawn in its bars' scale with
the second series projected into it and every label converted back
(`project`/`clock(at:)`, `project`/`mass(at:)`, labelled through
`overlayAxis`).

The night panel is the one the section is built around: `FastingEngine.eatingStops`
(our own data, not Health's) as dots on a clock axis in signed hours from
midnight, over bars of each night's total time asleep. Covered by
`EatingStopTests` in `FastingEngineTests.swift`: the signed-hours scale staying
continuous across midnight, the longest-fast-per-day rule matching `lastDays`,
the open fast landing on today, DST, and time-zone bucketing.

## Cut: the Patterns scatter plots

A Trends sub-screen once sat behind a link on Stats, with two scatter plots
under the timelines (eating stop vs hours asleep, weekly average fast vs weekly
weight change), a fitted line, and a generated headline. It was cut as more
machinery than a fasting app's stats page wants — along with
`Shared/Engine/Correlation.swift`, `Shared/Health/HealthCorrelation.swift`,
`CorrelationTests.swift`, and the separate 90-day `weightDays` window on
`HealthProvider.series` that only the weight pairing needed. The panels moved to
Stats. Nothing in the app computes a correlation any more, by design: the panels
show what happened and the user does the interpreting.

`-seedHistory` seeds three months of fasts; its stop times deliberately track
the same wobble `FixtureHealthProvider` uses, so the panels line up rather than
looking like two unrelated series. Both sides are invented data — making them
agree is what makes the section reviewable at all.

`DemoSeeder`'s completed fasts now end at noon rather than at whatever time the
seed runs, so the seeded schedule reads like a real 16:8 (stop just before 20:00,
break at midday) instead of starting in the small hours. Calendar days — and so
the streak and the week strip — are unchanged.

The pure half lives in `Shared/Health/` (`HealthSample`, `SleepAggregator`,
`WeightSeries`, `HealthProvider` + `FixtureHealthProvider`) and is covered by
`FastinoTests/SleepAggregatorTests.swift` — overlapping multi-source samples,
`inBed`/`awake` exclusion, naps, DST, and time-zone bucketing. The one file that
imports HealthKit is `Fastino/Health/HealthKitProvider.swift`.

Settings has an **Apple Health** row (`healthCard` in `SettingsView`), added
because the integration otherwise existed only as a one-shot permission sheet on
Stats: refuse it and nothing anywhere in the app mentioned Health again. It
branches on `hasBeenAsked()`, the one authorization fact HealthKit discloses
about reads — before, it asks; after, it opens the Health app (`x-apple-health://`,
falling back to `openSettingsURLString`), since a refusal can only be reversed
there and re-requesting presents nothing. It never claims Health is *on*. The
row takes its provider from `DebugLaunch.healthProvider`, so `-fixtureHealth`
drives it too. `HealthPanels` also re-loads on `scenePhase == .active` while
visible, so access granted in the Health app lands on the way back.

Wiring: `com.apple.developer.healthkit` in `Fastino/Fastino.entitlements` and
`NSHealthShareUsageDescription` in `Fastino/Info.plist` (the project's first
privacy usage string). **Device builds also need the HealthKit capability
enabled on the App ID in the developer portal** — a manual step outside the
repo. Simulator builds work as-is.

Not done, deliberately:

- **Writing fasts to Health.** There is no fasting sample type in the SDK
  (checked against `iPhoneOS26.5.sdk`); Mindful Minutes is the only thing other
  apps use and it's a meditation type. Still a non-goal (§1).
- **Background delivery / `HKObserverQuery`.** The panels fetch when Stats
  appears, which is enough for a tab you visit.
- **Watch.** No health data on the wrist (§4.7 — phone-sized screens stay on the
  phone).

Verified on the iPhone 17 simulator via `-tab stats -fixtureHealth` (populated,
light and dark) and `-noHealthData` (empty states). **The real HealthKit query
path is not verifiable headlessly**: a simulator's Health store is empty and its
permission sheet can't be tapped by `simctl`, so `-fixtureHealth` uses
`FixtureHealthProvider`. The panels sit below the fold and `simctl` can't
scroll, so seeing all of them means temporarily hoisting `HealthPanels` to the
top of `StatsView.content`. `HealthKitProvider` itself needs a device or a manual
simulator session with sample data. The Settings row's two states were both
looked at on the simulator (`-tab settings`, with and without `-fixtureHealth`,
the "ask" state after an uninstall) by temporarily hoisting the group above
`YOUR FAST PLAN` — it sits below the fold too.

## Built: the splash (§5)

`Fastino/Views/SplashView.swift` — the mascot igniting over the wordmark, with
the Baleware lockup at the foot; ~1.4s, then a 0.45s crossfade into the app.

- It lives **inside `RootView`'s stack**, not above `RootView` in `FastinoApp`.
  The appearance override (`.preferredColorScheme`) is applied in `RootView`, so
  a splash mounted outside it would follow the *system* scheme and flash the
  wrong palette on a device whose owner picked the other one. Being a sibling of
  the tab bar rather than a parent is also what lets the app finish laying out
  behind it, so the crossfade reveals a settled screen.
- It comes down on a timer, not on any work: the store opens synchronously and
  there is nothing to wait for. It is staging, not a progress indicator — so
  the duration is a design value, and nothing may be made to block on it.
- **The Baleware wordmark is not set in Baloo 2** — it's the publisher's
  identity, not the app's. baleware.com declares
  `"American Typewriter", "Courier New", Courier, monospace`, and iOS resolves
  that chain differently from a Mac: asking `Font.custom` for a face that isn't
  resident yields the *system* font silently, with no way to detect it at the
  call site. `BalewareLockup` therefore probes `UIFont(name:)` down the brand's
  own list and takes the first face that exists, so the fallback is Baleware's
  choice rather than Apple's.
- The rainbow is fixed in both schemes — six equal stripes, green through blue,
  from the site's favicon. It's someone else's mark, so it is not re-tinted by
  the palette the way the app's own colours are.

## Deferred

Not blocked on anything structural any more — the iOS widget extension exists
(see below), so these are a view file and a `supportedFamilies` line each.

1. **Lock Screen rectangular widget (§4.5)** — the layout already exists as the
   complication's `.accessoryRectangular` family; it is a port, not a design.
2. **Home Screen small widget (§4.5)** — not a port. §4.5 specifies it with a
   start/end *toggle*, which means an interactive `Button(intent:)` and so a
   second write-from-extension path to verify. It also raises a question this
   change didn't have to answer: whether a Home Screen toggle confirms, given
   the Control Center one doesn't.

## Built: the iOS widget extension + Control Center control (§4.5)

Target `Fastino WidgetsExtension` in `Fastino Widgets/`, bundle
`com.baleware.fastino.Fastino-Widgets`, iOS 26.4, `TARGETED_DEVICE_FAMILY = 1`,
entitlements at the repo root (app group only). Embedded in the app. Two
surfaces: the Lock Screen `.accessoryCircular` widget, and the Control Center
toggle.

The bundle id is the wizard's dashed default rather than a tidied
`…fastino.widgets`, matching `com.baleware.fastino.watchkitapp.Fastino-Watch-Widgets`
on the sibling extension. It is invisible to users and a prefix-extension of the
app id, which is all that's required — **not worth renaming once provisioned.**

**Almost nothing lives in the extension.** The entry, the store read, the
timeline instants, the colour/rendering-mode rules and the circular gauge are all
in `Shared/Widgets/` and `Shared/Design/FlatFlameMascot.swift`, shared with the
watch complication (§4.7) — the two surfaces show the same fact from the same
store at the same size, and one of them quietly disagreeing with the other is
exactly what sharing them prevents. The complication went from 314 lines to 112
in the process, and the duplicated smile shape it carried is gone.

### Three container entry points, and which process uses which

- `AppContainer.shared` — the app (and the watch app). Mirrored to CloudKit.
- `AppContainer.readOnly()` — extensions that only *display*: the complication,
  the Lock Screen widget, the control's value provider.
- `AppContainer.writableShared()` — **new**, and used by exactly one thing: the
  Control Center toggle's `SetFastingIntent`, which runs in the extension
  process and has to act rather than display.

`writableShared()` does not mirror, so the "one CloudKit mirror, in the app"
invariant is unchanged. The write is not stranded: Core Data records it in
persistent history and the app's mirrored container exports it the next time the
app runs. The alternatives were worse — `openAppWhenRun = true` launches the app
on every tap, which is not a toggle; and queueing the intent for the app to apply
later would mean a fast started from Control Center **does not exist** (no row,
no notification, no sync, no history) until the app is next opened.

### Two things that had to change in the app to make it correct

- **`RemoteChangeRefresher` now watches `.NSPersistentStoreRemoteChange` too**,
  and calls `mainContext.rollback()` before reconciling. A cross-process write is
  not a CloudKit import, so the existing observer never saw it; and without the
  refault, the context keeps the snapshot its objects were faulted with, so
  `TimerView` shows the state from before the control was tapped right up until
  relaunch. The cross-process half is deliberately **not** gated on
  `isCloudKitConfigured` — a local-only fallback store still has an extension
  writing to it.
- **`FastStore.reloadWidgets()` now also calls
  `ControlCenter.shared.reloadControls(ofKind:)`** (iOS only — `FastStore`
  compiles into the watch app). A control is not a timeline, so `WidgetCenter`
  never touches it; without this, starting a fast *in the app* leaves the Control
  Center toggle reading "off" until the system next happens to poll. The kind
  strings live in `Shared/Widgets/FastinoWidgetKind.swift` because they are
  agreed between processes and a typo doesn't error, it just means the surface
  never refreshes. **They are also stored by the system against every widget and
  control the user has placed, so changing one loses those placements.**

Reconciling notifications from the extension is safe and necessary:
`NotificationOwnership.schedulesLocally` is unconditionally `true` off watchOS
(the `WCSession`/`CompanionProbe` path is inside `#if os(watchOS)`), so no
WatchConnectivity is reachable, and `FastStore` does the reconcile on every write
anyway. Skipping it would leave a control-started fast with no goal alert armed
until the app was opened — the same bug this file records for the watch.

### The rest

`SetFastingIntent` is `isDiscoverable = false`: `ToggleFastIntent` (§4.6) is the
Shortcuts and Back Tap action, and two near-identical entries would make the
Shortcuts library worse. Its branches guard on `store.openFast()` rather than
trusting the control's `value`, so a stale snapshot is a no-op instead of an
`AppError` thrown into Control Center.

A control's label is SF Symbols and text only, so the mascot can't appear there.
`flame.fill`/`flame` is not a compromise: it's the same status-light vocabulary
`FlameTab.symbol(fasting:)` uses in the tab bar.

**The `fastino://` URL scheme is new** (`CFBundleURLTypes` in `Fastino/Info.plist`),
and `FastinoURL` is the only thing that may build one. It exists solely so the
Lock Screen widget lands on the timer: an accessory widget with no `widgetURL`
opens the app wherever it was last left, which for a widget about the fast can be
Settings. `RootView.onOpenURL` is the only external driver of its `@State`
`selection`.

**What a headless pass does prove.** More than expected, via the simulator's
logs after an install:

- `chronod` registers both surfaces —
  `CHSWidgetDescriptor; kind: FastingLockScreen; supportedFamilies: (accessoryCircular)`
  and `CHSControlDescriptor; kind: com.baleware.fastino.control.fasting;
  action: appintent:SetFastingIntent`. So the control **is** bound to its intent
  in the system's database, which is the wiring most likely to be silently wrong.
- The extension process launches and renders the circular view:
  `Request ended for FastingLockScreen:accessoryCircular - success`.
- `Fastino.store` is in the app group container, and **nothing** is logged on the
  `com.baleware.fastino` subsystem — no "App group unavailable", no "Could not
  open the shared store", which are the two silent-failure modes.
- The `fastino://` scheme resolves to Fastino.

**What it can't prove, and why.** WidgetKit only requests a *timeline* for a
widget that has actually been placed, and `simctl` cannot tap — so it can
neither add a Lock Screen widget nor open Control Center. iOS also always
confirms a custom-scheme open from `simctl openurl` with an untappable alert, so
the deep link's final hop is covered by unit tests over `FastinoURL` and
`FlameTab.named` rather than by a device. Needs a hand pass: the widget in `.vibrant` on a real Lock Screen; the toggle in
both states; a control tap with the app backgrounded, then foregrounding it to
confirm `TimerView` has healed (the `rollback()` regression); starting a fast in
the app and confirming the control follows; and — on hardware, two devices — a
control-started fast reaching the watch, which is the persistent-history export
and cannot be simulated for the same reason watch⇄phone sync can't.

## Built: the watchOS app (§4.7)

Target `Fastino Watch App Watch App` (doubled name courtesy of the wizard;
display name and bundle id are correct), watchOS 26.5, sharing `Shared/` with
the iOS target. `WKRunsIndependentlyOfCompanionApp` is set, so it can be
installed from the Watch App Store on its own — which is what the pages below
exist for.

**This is dual distribution, not a watch-only app.** Independence is purely
additive: the watch app is still embedded in the iOS app
(`Fastino.app/Watch/…`) and still declares
`WKCompanionAppBundleIdentifier = com.baleware.fastino`, so a user who installs
Fastino on their iPhone gets it on their paired watch automatically, exactly as
before. One App Store listing serves both audiences. The only reason a phone
user would install it by hand is having turned *Automatic App Install* off in
the Watch app, which is a user setting and predates all of this.

Three keys, easily confused, so: **don't remove
`WKCompanionAppBundleIdentifier`** on the reasoning that independence made it
redundant — that would break auto-install for every phone user, and it's the
kind of tidy-up that looks correct. `WKRunsIndependentlyOfCompanionApp` adds
standalone installation without removing anything. `WKWatchOnly` is
deliberately **unset**: that one means no iOS app at all, which is a different
product.

`WatchRootView` is a three-page `TabView(.page)`, timer in the middle and
selected at launch:

- `WatchTimerView` — ring, mascot, elapsed time, zone, one button.
- `WatchSettingsView` — plan, start-reminder toggle and time, goal and milestone
  toggles. A deliberate subset: no appearance (`Theme.dynamic` resolves
  statically to dark on watchOS), no sync status, no export.
- `WatchProgressView` — current streak, seven-day bar strip, then the fast in
  progress (if any) above the ten most recent finished ones. Tapping any row
  opens `WatchFastDetailView`.

`WatchFastDetailView` is the repair hub for one fast: duration, a Start row, an
End row (replaced by "In progress" while it runs), and a destructive Discard
behind a confirmation. Each time row pushes `WatchTimeEditView`, which edits a
single instant with six bidirectional offset chips (±15m/30m/1h) and an
hour-and-minute picker. Bounds come from the caller — an end can't precede its
start or land in the future, a start can't follow its end — and out-of-range
chips disable rather than clamp. Overlap with neighbouring fasts is left to
`FastValidation`, which is the only thing that knows the other records.
Everything writes through `FastStore.update`.

**The open fast is editable, and that's the point.** On iPhone the same repair
lives in History → `EditFastView`, which lists the open fast and can edit its
start; a standalone watch has no such fallback. Tapping Start twenty minutes
after actually stopping eating puts every zone boundary and the goal alert out
by that much, and `FastStore.update` re-arms the notifications when it's fixed.
Ending a fast is deliberately *not* offered here — that stays the timer page's
single End button.

Neither editor touches the date. Same-day is what these corrections are, and a
date wheel at 41mm is worse at saying "yesterday" than the chips are.

The watch originally only **read** the plan. Standalone installation ended that:
a watch with no iPhone app has no other way to choose a protocol or repair a
record. Edits stamp `AppSettings.touch()` so `SettingsElection` orders them
against the phone's correctly.

**Notification ownership is decided at runtime** (`NotificationOwnership` +
`CompanionProbe`). iOS forwards the phone's local notifications to a paired
watch and there is no API to opt out — identifiers are per-device, so matching
ids don't dedupe. The watch therefore schedules only when `WCSession`
reports no companion app. `isCompanionAppInstalled` reads `false` before
activation completes, so the pre-activation default is "defer": an invisible
gap on a standalone watch's first launch beats duplicate alerts on every paired
one. Cancelling is ungated. In DEBUG, `-forceWatchNotifications` and
`-deferWatchNotifications` force either branch, which is the only way to reach
the standalone path on a paired watch.

**The watch tells the phone directly when a fast starts or ends**
(`CompanionRelay` in `Shared/Notifications/`, `CompanionRelayTransport` on the
watch, `CompanionListener` on the phone). It is the one thing that doesn't
travel through CloudKit, because cancelling a notification isn't something
CloudKit can carry: the start reminder is a repeating calendar trigger armed on
the *phone*, `removePendingNotificationRequests` is device-local, and a
suspended phone runs no code. Start a fast on the watch at 19:45 with the phone
in a pocket and the 20:00 reminder to start a fast fires anyway — mirroring's
silent push is best-effort and budget-throttled, and this is the case where it
doesn't arrive in time. `transferUserInfo` does wake a suspended counterpart, so
that is the transport; the iOS session is activated from an `AppDelegate`,
because a background launch may never bring the scene up.

What crosses is **scheduling state, not the record of truth** — the open fast's
id, start and goal, or nothing — and the phone writes none of it: the fast still
arrives as a CloudKit import, and the next `reconcileNotifications()` reads the
store and overwrites what the relay armed. The phone cancels every pending
`goal-`/`milestone-` request and re-arms from the payload, since the watch may
have discarded the fast the phone armed for and started another. One direction
only (the watch schedules nothing while a phone app exists), payloads older than
the last applied are dropped, outstanding transfers are cancelled before a new
one is queued, and a send raised before `WCSession` activation is held and
flushed by `CompanionProbe`. Both ends drop a `Watch relay` marker in `SyncLog`,
so "was the phone actually woken?" is answerable from the diagnostics screen.
The wire format and the staleness rule are unit-tested in
`FastinoTests/CompanionRelayTests.swift`; the transport is not, and no mock
session stands in for it.

## Built: the watch complication (§4.7)

Target `Fastino Watch WidgetsExtension` in `Fastino Watch Widgets/`, embedded in
the watch app. Circular, corner, inline and rectangular families; tapping opens
the watch app, which watchOS does by default (no `widgetURL`, which would do
nothing without a registered URL scheme).

**The store lives in an app group** (`group.com.baleware.fastino`) because an
extension is a separate process and can't read the app's sandbox. All three
targets declare it; a target missing it doesn't error, it silently gets its own
empty container and shows "Not fasting" forever. The extension opens the store
**read-only with mirroring off** — the app process owns CloudKit, and a second
mirror inside a short-lived extension would be wasteful and a source of
conflicting writes. App groups are app↔extension on one device; CloudKit is
phone↔watch. Both are needed, for different problems.

Two things that are easy to get wrong here:

- **The timeline must schedule every instant the display changes.** The label is
  a whole-hour count, so hour marks matter as much as the zone boundaries and
  the goal. All are known in advance, so nothing polls.
- **Colour depends on the rendering mode.** Watch faces render complications
  accented or vibrant and discard colour; Smart Stack widgets get `.fullColor`.
  The view branches on `widgetRenderingMode` rather than designing for the
  monochrome floor everywhere. For the same reason the mascot's face is punched
  *through* the body — ink drawn on it would be flame-on-flame once flattened.

`FlameRing` is deliberately not reused: its gold→orange→pink sweep plus glow
turns to mud at 30pt and is discarded by accented rendering anyway.

Still unverified: **sync between a real Watch and iPhone.** The watch simulator
inherits iCloud from its paired phone simulator inconsistently, so the
CloudKit round-trip needs hardware. Everything else — build, layout at 40/42mm,
fonts, the merge logic — is verified.

**CloudKit live sync (§3) is now on**, since the watch can only share a store
with the phone through it — app groups don't cross the iPhone/Watch boundary.
See "Sync" below.

## Sync (§3, §6)

`Store/AppContainer.swift` mirrors to the CloudKit private database, naming the
container explicitly rather than using `.automatic` (which picks the first
container in the entitlement, so a mis-provisioned build would sync to a
different database and silently never converge). It falls back to a local store
rather than trapping when mirroring can't be configured at all.

Two invariants the app relied on don't survive sync, and both are handled in
`Shared/Sync/` with pure, unit-tested rules (`FastinoTests/SyncMergeTests.swift`):

- **`AppSettings` is a singleton by convention only** — CloudKit forbids unique
  constraints, so two devices first launched offline each create a row.
  `SettingsElection` picks the same survivor on every device (newest
  `updatedAt`, ties on lowest `id`); `FastStore.settings()` deletes the losers.
  Views must query it **sorted** — an unsorted `@Query` has no defined order, so
  two screens could otherwise read different rows on the same launch.
- **Two devices can each start a fast offline.** `OpenFastMerge` implements §6's
  "later start wins, other closed at that instant", plus two cases §6 doesn't
  cover: identical starts (closing at the winner's start gives `end == start`,
  which `FastValidation` rejects) and fasts abandoned beyond the 7-day cap.
  `SyncReconciler` applies it after a settle delay, because CloudKit delivers in
  batches and a device can import a `start` before the matching `end` for the
  *same* fast — acting immediately would truncate an already-closed fast.

**An import is not a write, and nothing used to notice it.** `FastStore` runs its
two side effects — reconciling notifications and reloading the widget timeline —
on the local write path, so a change that arrived from the *other* device ran
neither. `@Query` republished, so the open screen healed itself and the bug hid
behind that. The complication did not: `WidgetCenter` reloads are device-local
(the phone reloading timelines never touches a watch face) and `FastingProvider`
returns `policy: .never`, so a fast ended on the phone left the watch face
counting up until the watch itself started or ended one. `Sync/RemoteChangeRefresher`
closes it — it watches for a completed, successful `.import` event and re-runs
both side effects — and both app entry points also call it on foreground, for
imports that finished while no observer was alive.

`CloudSyncStatus` reports whether sync actually works. It runs on the **watch**
too, and `WatchSettingsView` shows the warning: the local-store fallback above
is silent by design, which on a watch means one that looks entirely healthy while
nothing it records ever leaves it — and a standalone install has no phone screen
to carry the warning instead. Note that
`ModelContainer.init` **succeeds even when the container is unprovisioned** —
mirroring is configured asynchronously afterwards — so a launch-time flag proves
nothing. It watches `NSPersistentCloudKitContainer.eventChangedNotification`
and the iCloud account status instead, from app launch rather than when Settings
appears (mirroring fails within a second of the store opening, so a later
observer misses the event).

Extracting `Shared/` into a Swift package (as §7 envisions) is still possible
but was judged not worth it yet: the targets set
`SWIFT_DEFAULT_ACTOR_ISOLATION = MainActor` and the code leans on it, so a
package means replicating that default and making ~1,900 lines `public`.

## Changing plan mid-fast asks about the running fast

Switching protocol while a fast is running used to show a one-button dialog
announcing that the running fast kept its old goal. That is the wrong shape:
someone who changes plan mid-fast usually means *this* fast, and the goal is
what the ring fills towards, what the alert fires on and what the fast is
judged against when it ends. The dialog now offers both outcomes, each naming
its hours — "Change this fast to 20h too" / "Keep this fast at 16h" — over a
line of context ("You're 10h 3m into a 16-hour fast"). Both change the plan;
they differ only in whether the fast in progress comes along. On the watch
too, where it matters more: a standalone install has no phone screen to correct
a goal from.

The alert is skipped when it would have nothing to ask: if the running fast is
already on the plan being chosen, both buttons would offer the same hours.
That state is one move away — switch away, choose "keep this fast", switch
back — so `wouldRegoalFastInProgress` gates the dialog on whether applying
would actually change the fast, rather than merely on whether one is running.

`FastStore.applyProtocol(_:to:)` is the only path by which a running fast's
goal moves, and nothing but the dialog may call it. It reconciles, which is the
whole job — the goal alert and both milestones are derived from `goalHours` and
would otherwise stay armed for the goal the user just replaced. A new goal
already behind the fast is accepted and simply arms nothing.
`FastinoTests/PlanChangeTests.swift` covers the four cases that matter: the
open fast moves, history doesn't, a goal already passed is legal, and ending
afterwards is judged against the new goal.

Two SwiftUI traps surfaced while verifying this on the simulator, both
pre-existing and both now fixed:

- **`isPresented: .constant(x != nil)` cannot be dismissed.** The binding is
  write-to-nowhere, so every dismissal SwiftUI attempts is dropped — an outside
  tap and a downward swipe both left the dialog standing. `Binding.presented()`
  in `Shared/Support/OptionalPresentation.swift` is the real binding to use.
- **`confirmationDialog` drew no cancel button at all** in the card
  presentation these screens get, so with the constant binding the user was
  genuinely trapped, forced to commit to one of the choices. The plan dialogs
  are `.alert`s now; an alert draws every button it is given, Cancel included.
  Verified by tapping through all three branches with XCUITest: cancel and
  "keep" leave the running fast at 16h, "too" moves it to 18h.

## App Store readiness

Four things were settled here rather than left to the submission:

- **iPhone only.** `TARGETED_DEVICE_FAMILY` was `1,2` with both orientation
  keys set to portrait, which is the `All interface orientations must be
  supported unless the app requires full screen` warning the archive emitted —
  a real problem under iPadOS windowing, and a promise of an iPad layout
  nothing had ever laid out or screenshotted. The family is now `1` and
  `UISupportedInterfaceOrientations_iPad` is gone. Adding iPad later is an
  update; taking it away later is not.
- **`Shared/PrivacyInfo.xcprivacy`** — the required-reason declaration for
  `NotificationOwnership`'s app-group `UserDefaults` (`CA92.1`), plus the
  no-tracking / no-collection answers. It sits in `Shared/` because all three
  shipping targets include that folder, so one file lands at the Resources root
  of the app, the watch app *and* the complication extension — the extension
  links the same code and would otherwise be rejected on its own
  (ITMS-91053). `UserDefaults` is the only required-reason API the app touches;
  a new call to one (file timestamps, disk space, boot time, active keyboards)
  has to be declared there or the upload fails.
- **`ITSAppUsesNonExemptEncryption` is `false`**, in the iOS *and* the watch
  `Info.plist` — the two bundles App Store Connect assesses separately. The app
  ships no cryptography of its own; the only encryption it touches is the HTTPS
  the system performs inside CloudKit, which is exempt. Unanswered, the question
  is asked by hand on every upload and holds the build at "Missing Compliance",
  out of testers' hands, until someone answers it. Adding encryption that isn't
  the platform's own makes this `true` and the answer stops being free.

- **Both Health purpose strings**, though the app only reads. Upload validation
  demands `NSHealthUpdateUsageDescription` from any binary that *links*
  HealthKit and never checks whether a write API is called, so the read-only
  key alone is rejected. The string says the app never writes, which is true —
  `toShare: []` at both `HealthKitProvider` call sites — and iOS never presents
  it, since it only appears on a share request. The watch needs neither string:
  it has no HealthKit entitlement and never links the framework.

Still outstanding before submission, and none of them live in this repo:

1. **Deploy the CloudKit schema to Production.** SwiftData creates record types
   in the *Development* environment only; an App Store build talks to
   Production. Ship without this and sync silently fails for everyone. **This
   gates the first TestFlight upload, not just the submission** — a TestFlight
   build is an App Store distribution build and uses Production too.
   Only the two optional attributes are at risk of being missed, since Core Data
   encodes an attribute into a `CKRecord` only when it has a value and every
   other attribute is defaulted: `Fast.end` needs a *completed* fast and
   `Fast.note` a fast *with a note*, both of which `-seedDemo` writes. Verify
   with `xcrun cktool export-schema` rather than by eye, and confirm the
   Settings sync row before trusting any of it — `AppContainer` falls back to a
   local store silently, which pushes no schema at all. Production schema
   changes are additive-only and irreversible.
2. **HealthKit capability on the App ID** in the developer portal (see §4.8
   above).
3. **A privacy policy URL** — mandatory in App Store Connect, and scrutinised
   for a HealthKit app. Nothing in Settings links to one yet. It gates
   *external* TestFlight too, since that goes through Beta App Review; internal
   testers need neither the policy nor a review.
4. **Confirm `aps-environment` becomes `production`** in the exported ipa; both
   entitlements files say `development` and rely on Xcode's export step
   rewriting it.
5. Verify on hardware what a simulator can't: phone↔watch sync,
   `HealthKitProvider` against a real Health store, and notification ownership
   on a genuinely paired watch.

## Running

- App: `xcodebuild build -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17'`
- Tests: `xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FastinoTests`
- Demo data: launch with `-seedDemo` (DEBUG only) to populate a streak + an
  active fast for screenshots. `-seedEating` seeds the same streak but with the
  last fast closed 2h ago, so the timer shows the eating window instead.
  `-tab stats` / `-tab settings` (DEBUG only) opens straight onto another tab,
  which is what makes the other screens screenshot-able from `simctl`.
- Splash: `-noSplash` (DEBUG only) skips it. The screenshot pass shoots about a
  second after `simctl launch` and would otherwise photograph the splash.
