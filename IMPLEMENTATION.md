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
simulator session with sample data.

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

Two things were settled here rather than left to the submission:

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

Still outstanding before submission, and none of them live in this repo:

1. **Deploy the CloudKit schema to Production.** SwiftData creates record types
   in the *Development* environment only; an App Store build talks to
   Production. Ship without this and sync silently fails for everyone.
2. **HealthKit capability on the App ID** in the developer portal (see §4.8
   above).
3. **A privacy policy URL** — mandatory in App Store Connect, and scrutinised
   for a HealthKit app. Nothing in Settings links to one yet.
4. **Confirm `aps-environment` becomes `production`** in the exported ipa; both
   entitlements files say `development` and rely on Xcode's export step
   rewriting it.
5. **`ITSAppUsesNonExemptEncryption`** is unset, so every upload asks the
   export-compliance question by hand.
6. Verify on hardware what a simulator can't: phone↔watch sync,
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
