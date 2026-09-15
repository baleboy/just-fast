# App Store copy

The agreed text for the App Store listing and the five promotional screenshot panels.
Panels are assembled in **AppScreens** from simulator captures; this file is the source of
truth for what each one says and why, so a re-capture doesn't quietly re-write the pitch.

Tone: plain and confident. No cutesy copy, no flame metaphors, no exclamation marks. The
mascot carries the warmth; the words carry the argument.

## The five panels

Headlines sit above the device, ≤ 6 words. Sublines are one sentence, ≤ 14 words.

### 1 — The timer, mid-fast · iPhone + Watch · light

> **Track a fast in one tap**
> Start it on your phone, end it on your watch. The ring shows exactly where you are.

Establishes what the app is and that it spans two devices, immediately. A 16-hour fast at
10h puts the ring about two-thirds filled in the gold "Burning" band, with the zone beads
and the "ends 15.07" line under the readout — the screen carries the product on its own.

Capture: `-seedDemo -noSplash`, light. The watch inset is `WatchTimerView`'s
"Fasting — 10h, store hero" preview, which exists so both devices show the same fast.

### 2 — The watch story · Watch large, iPhone behind · light

> **The watch app stands alone**
> Install it without the iPhone app, or use both — iCloud keeps them in step.

The differentiator. Most fasting apps' watch apps are remote controls; this one carries
its own settings, history and editing, and starts a fast with the phone out of range.

Sync was confirmed working on hardware before this copy was signed off, so the subline's
second half stands as written.

Capture: `2-progress-watch.png` large — the watch's own streak and week strip, which is
the standalone claim made visually — with `1-timer-iphone.png` smaller behind it.

### 3 — Stats and streaks · iPhone · light

> **See the streak you're building**
> Current and longest fasts, goal rate, and the last seven days at a glance.

The retention hook, and proof the app is more than a stopwatch. The 2×2 bento plus the
week strip is dense and attractive and needs no explanation.

Capture: `-seedDemo -seedHistory -fixtureHealth -tab stats -noSplash`, light.

### 4 — Apple Health · iPhone · **dark**

> **Your fasts, next to your sleep**
> Weight against the hours you fasted; your last meal against the night that followed.

The depth claim, and the one panel where dark mode does double duty: it shows the app has
a fully designed night appearance without spending a panel on it.

Capture: `-seedDemo -seedHistory -fixtureHealth -healthPanelsFirst -tab stats -noSplash`,
dark. The panels normally sit below the fold and `simctl` can't scroll, so
`-healthPanelsFirst` reorders the screen for this one shot — a launch argument rather than
an edit someone has to remember to undo.

### 5 — Free and private · iPhone · light

> **Free. No account. No ads.**
> No subscription, no sign-up, no tracking. Your data stays on your devices.

The reason to tap Get. Accurate in every clause: the CloudKit private database is the
user's own iCloud, there is no backend and no analytics, and Health data is never stored
at all. A settings screen with no paywall row on it is itself part of the argument.

Capture: `-seedDemo -noSyncWarning -tab settings -noSplash`, light. `-noSyncWarning`
suppresses the "iCloud sync is off" row: a simulator is never signed in to iCloud, so the
row is always shown there, always wrong about the shipping app, and lands directly under a
headline about your data being safe.

## Listing text

**Name:** Fastino — Fasting Tracker

**Subtitle (30):** Fasting timer for iPhone+Watch

**Promotional text:** A free intermittent fasting tracker with a real Apple Watch app that
works on its own. No account, no subscription, no ads.

**Keywords (100):**
`intermittent,fasting,fast,timer,16:8,OMAD,tracker,streak,watch,autophagy,ketosis,window,log`

### Description

Fastino tracks intermittent fasting and gets out of the way. Start a fast with one tap —
from the app, the Lock Screen, Control Center, your watch, Siri, or a double-tap on the
back of your phone — and the app handles the rest.

**A watch app that works on its own**
The Apple Watch app installs with the iPhone app or entirely without it. Start and end
fasts, fix a start time you tapped late, change your plan, and see your streak — all with
the phone out of range. Everything syncs through your own iCloud.

**Your schedule doesn't drift**
You choose the time you start fasting, and your eating window closes at that time every
day. Fast two hours longer than planned and you've spent two hours of today's eating
window — you haven't pushed tomorrow's start two hours later.

**Plans**
14:10, 16:8, 18:6, 20:4 and OMAD. Your goal is fixed when a fast starts, so changing plans
never rewrites your history.

**Stats worth checking**
Current and longest streak, current and longest fast, a seven-day chart, and 30-day
averages. Streaks are strict — no freezes, no rest days — and every number is recomputed
from your fasts, so an edit is always reflected correctly.

**Apple Health, read-only**
See your weight against the hours you fasted, and how long you slept against when you
stopped eating, one dot a night. Fastino reads from Health and never writes to
it, and Health data is never stored or synced.

**On your Lock Screen and in Control Center**
A Lock Screen widget counts your fast without draining anything, a Control Center toggle
starts and ends one from anywhere, and a watch complication keeps it on your face.

**History you can fix**
Every fast, grouped by month. Edit a time, add a fast you forgot, attach a note, or export
everything as CSV. It's your data.

**Free, and staying free**
No subscription, no in-app purchases, no ads, no account, no analytics, no backend. Your
fasts live on your devices and in your private iCloud.

## Capturing

Raw captures live in `docs/store/panels/` at 1320×2868 (the 6.9" App Store size, from the
**iPhone 17 Pro Max** simulator on iOS 26.5) and 416×496 for the watch renders. AppScreens
takes these as input; re-run the recipe below to regenerate them.

```bash
DEV=$(xcrun simctl list devices available | grep -A20 "iOS 26.5" \
      | grep "iPhone 17 Pro Max" | sed -E 's/.*\(([0-9A-F-]{36})\).*/\1/')
xcrun simctl boot "$DEV"
xcodebuild build -scheme Fastino -destination "platform=iOS Simulator,id=$DEV" \
  -derivedDataPath build/store
APP=build/store/Build/Products/Debug-iphonesimulator/Fastino.app

# The seed only runs on an empty store, so reinstall between shots or the first
# capture's open fast is still running — and still counting — during the rest.
shot() { name=$1; shift
  xcrun simctl terminate "$DEV" com.baleware.fastino 2>/dev/null
  xcrun simctl uninstall "$DEV" com.baleware.fastino 2>/dev/null
  xcrun simctl install "$DEV" "$APP"
  xcrun simctl launch "$DEV" com.baleware.fastino "$@" >/dev/null
  sleep 5
  xcrun simctl io "$DEV" screenshot "docs/store/panels/$name.png"
}

# A clean status bar — but deliberately NOT a pinned time. Overriding the clock to
# 9:41 contradicts the app's own content: a fast 10h in, ending at 22.26, cannot be
# on screen at 9:41. Let the host clock show, and take the whole set in one run so
# every panel agrees to the minute.
xcrun simctl status_bar "$DEV" override --batteryState discharging --batteryLevel 100 \
  --cellularMode active --cellularBars 4 --wifiMode active --wifiBars 3 --dataNetwork wifi

xcrun simctl ui "$DEV" appearance light
shot 1-timer-iphone   -seedDemo -noSplash
shot 3-stats-iphone   -seedDemo -seedHistory -fixtureHealth -tab stats -noSplash
shot 5-settings-iphone -seedDemo -noSyncWarning -tab settings -noSplash

xcrun simctl ui "$DEV" appearance dark
shot 4-health-iphone-dark -seedDemo -seedHistory -fixtureHealth -healthPanelsFirst \
                          -tab stats -noSplash
```

The two watch shots can't come from `simctl` — there's no way to tap Start on a booted
watch sim, so the active-fast state is unreachable. Render them from Xcode instead
(`RenderPreview`, or the canvas):

| File | Preview | Output |
|---|---|---|
| `Fastino Watch App Watch App/WatchTimerView.swift` | index 3, "Fasting — 10h, store hero" | `1-timer-watch.png` |
| `Fastino Watch App Watch App/WatchProgressView.swift` | index 0 | `2-progress-watch.png` |

The watch renders come out at 416×496, close enough to the 410×502 the store wants.

`WatchSettingsView`'s preview is the alternate for panel 2 — it proves the standalone
claim more directly (the plan picker lives on the watch) but renders as a plain dark list,
where Progress has the mascot and the week strip. Progress was chosen on looks.

### Screenshot-only launch flags

`-noSyncWarning` and `-healthPanelsFirst` live in `Shared/Support/ScreenshotFlags.swift`
and are DEBUG-only. They exist so this pass needs no temporary source edits. The rest
(`-seedDemo`, `-seedHistory`, `-fixtureHealth`, `-tab`, `-noSplash`) are the existing
development flags in `DebugLaunch` and `DemoSeeder`.

### Why the demo data looks the way it does

`DemoSeeder` keeps the **most recent 21 days as a clean run** — no missed days, and enough
slack above the goal that the wobble can't pull a fast under it — which is what gives panel
3 its 21-day streak, 86% goal rate and a full week strip. Beyond that window the record
stays mixed, so the under-goal badges, the history gaps and the empty week-strip stubs are
still exercised in development.

The slack is the whole mechanism: the wobble spans ±1h, so the original 15 minutes put
roughly two days in five under a 16h goal (a 4-day streak and a 61% rate, which undersold
the headline), while 1h15m puts none of them there. `WatchProgressView`'s preview seeds the
same 21 days, so the watch in panel 2 and the phone in panel 3 agree about the streak.

A side effect worth knowing: longer fasts mean earlier stop-eating times, so the dots on
panel 4's sleep scatter sit at or left of the 20:00 anchor rather than straddling it. That
reads as on-plan, which is the better picture anyway. And because the seeder's stop wobble
and the fixture's sleep wobble are the same sine, an earlier stop comes with a longer
sleep — the cloud slopes down to the right, which is the shape the panel is for. It's
mild, and it should stay mild: the screenshot must not oversell what a month of real data
will show. The two tiles under it split 22 nights against 3 for the same reason — the seeded
stops sit mostly before the anchor — which is honest about the demo data and fine for the
shot; the levels either side of the rule are what the eye reads.

### Still to do

- The **watchOS listing needs its own set** (410×502, 45/49mm class) — the watch app is
  independently installable, so that set is what a Watch App Store visitor sees. Three
  panels: Timer, Progress, Settings, in the same voice as these.
