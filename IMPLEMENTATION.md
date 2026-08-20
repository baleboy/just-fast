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
- Three tabs — Timer / Stats / Settings — each with its own `NavigationStack`,
  behind a custom floating pill tab bar (`RootView`); the three main screens
  carry no navigation bar
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
- History (grouped by month, reverse-chron), edit/retro-entry/delete with
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
foreground. Foreground alerts stay suppressed on purpose (no
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

Read-only, iOS-only. `TrendsView` is pushed from the Stats tab, alongside
History: fasting hours, an eating-stop/sleep overlay, and weight, stacked over
one shared 30-day date axis. The only screen in the app using Swift
Charts, styled entirely from `Theme`.

The middle panel is the one the screen is built around: `FastingEngine.eatingStops`
(our own data, not Health's) as dots, overlaid on each night's sleep drawn as a
bar from asleep to awake. Both sit on one clock axis in signed hours from
midnight, so there is no second scale. Covered by
`EatingStopTests` in `FastingEngineTests.swift`: the signed-hours scale staying
continuous across midnight, the longest-fast-per-day rule matching `lastDays`,
the open fast landing on today, DST, and time-zone bucketing.

**Patterns** sits below the timelines: two scatter plots (eating stop vs hours
asleep, weekly average fast vs weekly weight change) built by
`Shared/Engine/Correlation.swift` and `Shared/Health/HealthCorrelation.swift`,
covered by `FastinoTests/CorrelationTests.swift` — the fit, both pairings, and
every branch of the wording. The weight pairing is weekly over 90 days, which is
why `HealthProvider.series` takes a separate `weightDays` window.

`-seedHistory` seeds three months of fasts, which the Patterns cards need before
they can say anything; its stop times deliberately track the same wobble
`FixtureHealthProvider` uses, so the cards show a finding rather than noise.
Both sides are invented data — making them agree is what makes the screen
reviewable at all.

`DemoSeeder`'s completed fasts now end at noon rather than at whatever time the
seed runs, so the seeded schedule reads like a real 16:8 (stop just before 20:00,
break at midday) instead of starting in the small hours. Calendar days — and so
the streak and the week strip — are unchanged.

The pure half lives in `Shared/Health/` (`HealthSample`, `SleepAggregator`,
`WeightSeries`, `HealthProvider` + `FixtureHealthProvider`) and is covered by
`FastinoTests/SleepAggregatorTests.swift` — overlapping multi-source samples,
`inBed`/`awake` exclusion, naps, DST, and time-zone bucketing. The one file that
imports HealthKit is `Fastino/Health/HealthKitProvider.swift`.

Wiring: `com.apple.developer.healthkit` in `Fastino/Fastino.entitlements` and
`NSHealthShareUsageDescription` in `Fastino/Info.plist` (the project's first
privacy usage string). **Device builds also need the HealthKit capability
enabled on the App ID in the developer portal** — a manual step outside the
repo. Simulator builds work as-is.

Not done, deliberately:

- **Writing fasts to Health.** There is no fasting sample type in the SDK
  (checked against `iPhoneOS26.5.sdk`); Mindful Minutes is the only thing other
  apps use and it's a meditation type. Still a non-goal (§1).
- **Background delivery / `HKObserverQuery`.** The screen fetches when it opens,
  which is enough for a screen you visit.
- **Watch.** No health data on the wrist (§4.7 — phone-sized screens stay on the
  phone).

Verified on the iPhone 17 simulator via `-tab stats -screen trends` (populated,
light and dark) and `-noHealthData` (empty states). **The real HealthKit query
path is not verifiable headlessly**: a simulator's Health store is empty and its
permission sheet can't be tapped by `simctl`, so `-screen trends` uses
`FixtureHealthProvider`. `HealthKitProvider` itself needs a device or a manual
simulator session with sample data.

## Deferred (need additional Xcode targets — not added here)

These require new build targets in `project.pbxproj`, which can't be added
reliably by editing the file by hand or verified headlessly.

1. **Widget extension (§4.5)** — Lock Screen circular/rectangular + Home Screen
   widgets using `Text(timerInterval:)` and the interactive Start intent. Add a
   Widget Extension target and tick `Shared/` for it.
(The watch complication is built — see below.)

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

`CloudSyncStatus` reports whether sync actually works. Note that
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

## Running

- App: `xcodebuild build -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17'`
- Tests: `xcodebuild test -scheme Fastino -destination 'platform=iOS Simulator,name=iPhone 17' -only-testing:FastinoTests`
- Demo data: launch with `-seedDemo` (DEBUG only) to populate a streak + an
  active fast for screenshots. `-seedEating` seeds the same streak but with the
  last fast closed 2h ago, so the timer shows the eating window instead.
  `-tab stats` / `-tab settings` (DEBUG only) opens straight onto another tab,
  which is what makes the other screens screenshot-able from `simctl`.
