# Handoff: Fastino — "Ember" redesign (timer, stats, settings · dark + light)

## Overview
Redesign of Fastino, an intermittent-fasting timer app (iOS). The chosen direction is **"Ember"**: a warm, glowing aesthetic where the fast is visualized as a fire burning through metabolic zones. Three screens (Timer, Stats, Settings), each in dark and light mode.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to ship. Recreate these designs in the target codebase's existing environment (SwiftUI, React Native, Flutter, etc.) using its established patterns and libraries. If no codebase exists yet, choose the platform-appropriate framework and implement the designs there.

- `Fastino Explorations.dc.html` — the design document. **Turn 2 (top section) is the approved system**: options 2c (Timer dark), 2d (Timer light), 2a (Stats dark), 2e (Stats light), 2b (Settings dark), 2f (Settings light). Turn 1 (bottom) contains rejected explorations — ignore except 1c which is the ancestor of 2c.
- `ios-frame.jsx` — device-frame scaffolding only, not part of the design.

## Fidelity
**High-fidelity.** Colors, type, spacing, and copy are final; recreate pixel-perfectly. Screens are designed at 402×874 (iPhone). All px values below are at that scale.

## Design Tokens

### Dark mode
- Screen background: `radial-gradient(120% 80% at 50% 0%, #2a1a3e 0%, #181022 55%, #120b1a 100%)`
- Text primary: `#f3ecff`; secondary: `rgba(243,236,255,.55)`; tertiary: `rgba(243,236,255,.4)`
- Card background: `rgba(255,255,255,.05)`; card border: `rgba(255,255,255,.12)`; card radius: 20px (16–18px for small cards/rows)
- Accent highlight text: `#ffbe8f`; accent chip bg: `rgba(255,138,61,.14–.18)`; accent border: `#ff8a3d`
- Accent glow: `box-shadow: 0 0 20–24px rgba(255,138,61,.15–.3)`
- Success/green: `#7fe8c3`
- Primary button: `linear-gradient(90deg,#ffd066,#ff8a3d)`, text `#2a1206`, radius 99px, `box-shadow: 0 6px 30px rgba(255,138,61,.4)`

### Light mode
- Screen background: `radial-gradient(120% 80% at 50% 0%, #fdf3e3 0%, #f8f1e8 55%, #f3ece2 100%)` (warm paper)
- Text primary: `#2a1a3e` (plum); secondary: `rgba(42,26,62,.5)`
- Card background: `#fff`; border: `rgba(42,26,62,.1)`; shadow: `0 4px 14px rgba(42,26,62,.05)`
- Accent text: `#c1500f`; gold text: `#d98a12`; orange text: `#e0570f`; accent chip bg: `rgba(255,111,30,.08–.12)`; accent border: `#ff8f2e`
- Success/green: `#1f8a63`
- Primary button: `linear-gradient(90deg,#ffb23d,#ff6f1e)`, text `#3a1a05`, `box-shadow: 0 6px 26px rgba(255,111,30,.35)`

### Typography
- Family: **Space Grotesk** (Google Fonts), weights 400–700. Numerals use `font-variant-numeric: tabular-nums` on the live timer.
- Scale: screen title 16px/700/`.22em` tracking, uppercase · timer 44px/700/-0.02em · stat value 30px/700 · card label 11px/600/`.14em` uppercase · body row 15px/600 · caption 12–13px · tab label 13px.

### Spacing & shape
- Screen padding: 72–74px top (status bar clearance), 22–24px sides, 26px bottom.
- Grid gap: 10px (stats bento), 8–9px (chip rows).
- Radii: cards 20px, small cards 16–18px, pills/buttons/bars 99px.

## Screens / Views

### 1. Timer (2c dark / 2d light)
Purpose: live view of the current fast.
Layout: vertical flex, centered. Wordmark "FASTINO" top-center → progress ring (312×312, 48px top margin) → 3 zone cards (34px top margin) → pushed to bottom: End-fast button + tab bar (14px gap).

**Progress ring** — the signature element. A 312×312 donut (conic-gradient masked with `radial-gradient(closest-side, transparent 74%, #000 75%)`, i.e. ~28px stroke). The ring encodes **metabolic zones as color bands with gradients inside each zone and a hard color jump at zone boundaries**. For a 16h fast, 1h = 22.5°, from 12 o'clock clockwise:
- Zone 1, 0–12h (0–270°): pale gold → amber (dark: `#ffe9a0→#ffc24d`; light: `#ffd98a→#ffb23d`)
- Zone 2, 12–14h fat burn (270–315°): orange (dark: `#ff9a3d→#ff7a2e`; light: `#ff8f2e→#ff6f1e`)
- Zone 3, 14–16h ketosis (315–360°): pink (`rgba(255,84,112,…)→rgba(255,68,104,…)`)
- **Elapsed portion is full opacity; the not-yet-reached portion of the ring shows the same zone colors dimmed** (alpha ~.16–.36 dark, ~.22–.36 light). Mock shows 12h50m elapsed = 288°, so the fill ends 18° into zone 2. No dot/marker at the progress tip — the opacity edge is the indicator.
- Behind the ring, a duplicate of the elapsed-only gradient with `blur(26px)` at opacity .5 (dark) / .35 (light) creates the ember glow.
- Zone boundary jumps use ~4° soft transitions (e.g. stops at 268° and 272°) to avoid aliasing.

**Ring center** (stacked, 4px gap): "16H FAST" label · elapsed time `12:50:48` (44px, tabular) · "ends 12.34" · current-zone chip ("Fat-burn zone", flame-colored 8px dot with a subtle 1.6s scale/rotate flicker animation, pill with accent bg/border).

**Zone cards** (3 equal-width, 8px gap): "0–12H / Burning ✓" (gold), "12–14H / Fat burn" (orange, active: accent border + glow shadow), "14H+ / Ketosis" (muted until reached). These double as the legend for the ring colors. Active card follows the current zone.

**End fast button**: full-width gradient pill, 17px vertical padding, 18px/700 label.

**Tab bar**: floating pill (translucent card bg + border), three items Timer/Stats/Settings; active item gets accent chip bg + accent text (700), inactive 600 secondary.

### 2. Stats (2a dark / 2e light)
Purpose: streaks, records, weekly progress.
Layout: title "STATS" → 2×2 bento grid (10px gap) → Last-7-days card → History row → tab bar at bottom.
- Bento cards: label (11px caps) + value (30px/700) + caption. **Current fast** card is highlighted: accent bg/border + glow; its value uses the gradient as text fill (`background-clip: text`). **Goal rate** value in green. Streak shows `0` with "best 2" beside it, caption "finish today to relight".
- Values in mock: Current fast 12h 50m (80% of 16h) · Longest 17h 2m · Streak 0 (best 2) · Goal rate 50%, avg 14h 43m over 30 days.
- **Last 7 days**: 7 equal-width vertical bars (74px track, pill-shaped, aligned bottom). Completed days: vertical gold→orange gradient + glow, height ∝ fast length vs 16h goal; missed days: 8–10% white/plum tint, low heights; **today**: same gradient at ~50% alpha with a 1px dashed accent border ("still burning"). Day letters under bars; completed/today letters accented + bold. Footnote: "Dashed bar = today, still burning".
- History row: card-style row, "History" + → affordance, navigates to full history (not designed).

### 3. Settings (2b dark / 2f light)
Purpose: fast plan + preferences.
Layout: title "SETTINGS" → section "YOUR FAST PLAN" → 4 plan cards → "NOTIFICATIONS" group → "GENERAL" group → tab bar.
- Plan cards (equal width, 9px gap): ratio (24px/700) + nickname (11px): 14:10 gentle · **16:8 current** (selected: accent bg/border/glow, gradient text fill, "current" in accent 700) · 18:6 deep · 20:4 warrior. Selecting a plan changes the fast goal.
- Notification rows (grouped card, 1px separators): title (15px/600) + subtitle (12px secondary) + toggle. Toggle: 46×28 pill, on = accent gradient with white 22px knob right, off = neutral tint with knob left. Rows: Fast complete (on) · Milestones "Fat burn, ketosis" (on) · Time to start "Daily reminder, 20.30" (off).
- General rows: Appearance ("Dark →"/"Light →") · Apple Health ("Connected →" in green) · Export data ("→").

## Interactions & Behavior
- Timer ticks every second (HH:MM:SS). Ring fill angle = elapsed/goal × 360°, updating continuously; zone chip and active zone card switch at 12h and 14h boundaries.
- Zone-chip dot: gentle infinite flicker (scale 1→1.06, ±2° rotate, 1.6s ease-in-out) — subtle, decorative.
- End fast: confirm, then record the fast, reset ring, switch CTA to "Start fast".
- Fast completion (goal reached): notify (if enabled); today's stats bar becomes solid.
- Tab bar switches Timer/Stats/Settings; active state as described.
- Plan card tap: select (moves accent treatment); should confirm if a fast is running.
- Appearance row cycles Dark/Light/System; both palettes specified above.
- Hover/press states weren't designed for touch beyond active/selected treatments; use platform-standard press feedback (e.g. 0.97 scale or highlight).

## State Management
- Current fast: startTime, goalHours (from selected plan), derived elapsed/remaining/percent/zone.
- History: array of completed fasts (start, end, goal, met-goal flag) → drives streaks, longest, avg, goal rate, 7-day bars.
- Settings: selected plan, notification toggles, reminder time, appearance mode, health-sync status.
- Zones for a 16:8 plan: 0–12h "Burning", 12–14h "Fat burn", 14h+ "Ketosis". If plans have different zone science, keep the three-band ring pattern and adjust boundaries.

## Assets
No raster assets. Space Grotesk from Google Fonts. All graphics (ring, glow, bars, toggles) are pure gradients/shapes — no SVG illustrations. Status bar/home indicator in the mocks come from the device frame, not the app.

## Files
- `Fastino Explorations.dc.html` — open in a browser; the top section ("Ember as a system") holds the six approved screens: 2c, 2d (Timer), 2a, 2e (Stats), 2b, 2f (Settings).
- `ios-frame.jsx` — scaffolding for the device bezel; ignore for implementation.
