# Handoff: Fastino — "Flame Friend" redesign (timer, eating window, stats, settings)

## Overview
Redesign of Fastino, an intermittent-fasting timer app (iOS). The chosen direction is **"Flame Friend"**: a warm, cute, peach-toned aesthetic built around a small flame mascot who lives inside the progress ring and changes color/expression with the metabolic zone. Four screens: Timer (fasting), Timer (eating window), Stats, Settings.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to ship. Recreate these designs in the target codebase's existing environment (SwiftUI, React Native, Flutter, etc.) using its established patterns and libraries. If no codebase exists yet, choose the platform-appropriate framework and implement the designs there.

- `Fastino Explorations.dc.html` — the design document. **The approved screens are:**
  - `4a` — Timer, fasting state (turn 4 section)
  - `6a` — Timer, eating-window state (turn 6, top)
  - `5a` — Stats, `5b` — Settings (turn 5)
  - Turn 3 (`3a`) holds approved **motion specs** (launch fill, ignite, zone crossing, completion celebration) demonstrated in the earlier "Ember" skin — port the timings/choreography to Flame Friend's colors.
  - Everything else (turns 1–2, 4b, 4c) is rejected exploration — ignore.
- `ios-frame.jsx` — device-frame scaffolding only, not part of the design.

## Fidelity
**High-fidelity.** Colors, type, spacing, copy, and the mascot construction are final; recreate faithfully. Screens are designed at 402×874 (iPhone). All px values below are at that scale. The mascot should be rebuilt as a vector asset (or drawn shapes) matching the construction spec below.

## Design Tokens
- Background: vertical gradient `#fff3e4 → #ffe8d1` (timer-fasting, stats, settings); eating window uses a calmer `#fff8ef → #fdeede`
- Text ink: `#4a2a1e` (headings, numbers); body/labels: `#5a3a2e`; muted: `#b07a5a`; accent text: `#c9502e`; wordmark/brand: `#c96f4a` (lowercase "fastino")
- Card: `#fff`, radius 24px (22px rows, 20px small), shadow `0 4px 14px rgba(201,111,74,.12)`
- Accent surface: `#ffe0c2`; accent border: `#ff9e7d` (2.5px); success green: `#2a8a6b` on `#e3f5ec`
- Muted/unlit flame fill: `#e8cdb8` (with face) or `#d9b8a5` (plain); face ink on muted flames: `#8a5a42`
- Zone colors — used by the ring, the mascot, and the zone beads:
  - Burning (0–12h): gold `#ffd88a → #ffb36b`
  - Fat burn (12–14h): deep orange `#ff9068 → #ff7d52` (mid-jump stops `#ff9068` at 272°, `#ff7d52` at fill edge)
  - Ketosis (14h+): pink; dimmed preview `#f7c3cf`, active ~`#f78aa8` range
  - Dimmed/unreached ring segments: `#ffd9c2` (fat burn), `#f7c3cf` (ketosis)
- Primary button: gradient `#ff9e7d → #f27a52`, white text, radius 26px, **hard 3D press shadow** `0 6px 0 #d95f3a` (eating window variant: `#ffb36b → #f2905c`, shadow `0 6px 0 #d97a42`). Press = translate down 2–3px, shadow shrinks.
- Tab bar: white floating pill, shadow `0 4px 16px rgba(201,111,74,.15)`; active tab: `#ffe0c2` chip, text `#c9502e` 800; inactive `#b07a5a` 700.

### Typography
- Family: **Baloo 2** (Google Fonts), weights 600–800. Everything is rounded and chunky.
- Scale: wordmark 20px/800 · timer 40px/800 · stat value 32px/800 · screen title 26px/800 · section label 12–13px/800/`.06em` uppercase · row title 16px/800 · captions 12.5–14px/600–700 · tab label 13px.

## Screens / Views

### 1. Timer — fasting (4a)
Vertical flex, centered: wordmark → ring (310×310, 40px top margin) → zone beads (30px margin) → bottom: End-fast button + tab bar (14px gap).

**Ring**: donut via conic-gradient masked at `transparent 78% / solid 79%` (~32px stroke). Zone bands with in-zone gradients and a hard jump at boundaries (1h = 22.5°, from 12 o'clock clockwise): gold `#ffd88a→#ffb36b` 0–268°, jump, fat-burn `#ff9068→#ff7d52` 272°–fill edge (mock: 288° = 12h50m of 16h), then **dimmed unreached segments**: `#ffd9c2` to 313°, `#f7c3cf` 317–360°. Progress dot: 32px white circle, 4px border in the active zone color (`#ff7d52`), soft shadow, centered on the ring at the fill angle.

**Mascot (inside ring, above the time)** — 74×86, gently bobbing (3s ease-in-out float, ±6px). Construction: teardrop body `border-radius: 50% 50% 46% 46% / 62% 62% 40% 40%` filled with the **active zone gradient** (mock: fat-burn `#ff9068→#ff7d52`); small flame tip (26×30, same shape family) rising from the top in the zone's lighter color (`#ffb36b`); face in `#4a2a1e`: two oval eyes (9×12), open smile (16×8 bottom-half arc, 3px stroke), blush ovals `rgba(255,120,90,.55)`. **Expression + color follow the zone**: Burning = gold body, plain happy; Fat burn = deep orange, determined (13×4 angled brow bars, rotate ±14°, above the eyes); Ketosis = pink, proud (same brows, bigger smile). Eating window = see screen 2.

**Center text** under mascot: time `12:50:27` (40px/800) · "16h fast · ends 12.34" (14px/600 muted).

**Zone beads** (3 pills, 10px gap): white pill + 10px color dot + label. Completed: "Burning ✓" (gold dot). Active: accent surface `#ffe0c2`, 2px `#ff9e7d` border, "Fat burn!" in `#c9502e` 800, dot `#ff8a5c`. Upcoming: white at 55% opacity, dot `#d9b8a5`.

**CTA**: "End fast".

### 2. Timer — eating window (6a)
Same skeleton; calmer background. Ring becomes a **waiting ring**: 8px dashed `#f3ddc8` circle, no fill, no dot. Mascot shrinks to 58×68 "pilot light" (paler `#ffd3a8→#ffb98a`, closed happy eyes = 10×3 curved bars, small smile, slower 4.5s bob). Center: "EATING WINDOW" (16px/800 muted) · countdown `5h 26m` (40px/800) · "until your next fast · 20.30". Below the ring: **last-fast recap card** (white, full width): "LAST FAST / 16h 4m · goal met" + green "Streak ×1" chip. CTA: "**Start fast**" (starting a fast triggers the ignite animation and the ring transitions dashed→filled).

### 3. Stats (5a)
Title "Your journey" + subtitle "Last 30 days" → 2×2 bento (12px gap) → Last-7-days card → History row → tab bar.
- Cards: label 12px/800 caps muted · value 32px/800 · caption 12.5px/600. Current fast value in `#c9502e`; caption "elapsed · 80% of 16h". Longest fast card has a tiny 26×30 mascot in the top-right corner. Goal-rate card sits on accent surface `#ffe0c2` (label/caption `#a8623e`).
- Values: Current 12h 50m · Longest 17h 2m · Streak 0 (best 2, "finish today to relight") · Goal rate 50% (avg 14h 43m · 30 days).
- **Last 7 days = a row of 7 little flames** (30×34 teardrops): goal-met days are lit (gold-orange gradient + happy face), missed days unlit (`#d9b8a5`, 30% opacity, no face), today is a dashed-outline gold flame (2px dashed `#c9502e`) with a gentle flicker. Day letters under each; lit/today letters `#c9502e` 800. Footnote: "Dashed flame = today, in progress".
- History row: white card, "History" + `→` in accent.

### 4. Settings (5b)
Title "Settings" → "YOUR FAST PLAN" → 4 plan cards → "NOTIFICATIONS" group → "GENERAL" group → tab bar.
- **Plan cards**: each shows a mascot flame that **grows with plan intensity** and has its own expression — 14:10 "gentle" (26×31, dozing: closed-eye bars + tiny mouth) · 16:8 "current" (30×36, happy, full color + flicker, card selected: `#ffe0c2` + 2.5px `#ff9e7d` border, text `#c9502e`) · 18:6 "deep" (34×41, focused: angled brows + flat mouth) · 20:4 "warrior" (38×46, fierce: steeper brows + big grin). Unselected flames use muted `#e8cdb8` with `#8a5a42` faces.
- Group cards: white, radius 24px, rows split by **2px dashed `#ffe8d1` dividers**. Row: title 16px/800 + subtitle 12.5px/600 muted + toggle (48×29 pill; on = `#ffb36b→#ff8a5c` gradient, white knob right; off = `#e8d5c5`, knob left).
- Rows: Fast complete (on) · Milestones "Fat burn, ketosis" (on) · Time to start "Daily reminder, 20.30" (off). General: Appearance ("Light →") · Export data ("→"). **No health-platform integration** — deliberately removed.

## Interactions & Behavior
- Timer ticks every second; ring fill angle = elapsed/goal × 360°; mascot color/expression, zone beads, and dot border color switch at 12h and 14h.
- Motion specs (see live `3a` demo, port colors): **launch fill** ring sweeps 0→current, ~1.8s ease-out cubic · **ignite** on start-fast: expanding ring flash ~0.9s · **zone crossing**: pulse flash + bead handoff at the boundary · **completion**: flare + rising ember particles (~1.4–2s staggered), CTA flips to a green "Log this fast".
- Mascot idle bob: translateY 0→−6px→0, 3s ease-in-out infinite (4.5s when resting). Today-flame flicker: scale 1→1.06 with ±2° rotate, 1.6–1.8s.
- End fast: confirm → record → transition to eating-window state. Start fast: ignite → fasting state.
- Buttons use the hard-shadow press (translate down, shadow shrinks). Copy is matter-of-fact — no first-person mascot speech.

## State Management
- Current fast: startTime, goalHours (selected plan), derived elapsed/percent/zone; app mode: fasting | eating-window (eating window shows countdown to next scheduled fast from the daily reminder time).
- History: completed fasts (start, end, goal, met flag) → streaks, longest, avg, goal rate, 7-day flames, last-fast recap.
- Settings: plan, notification toggles, reminder time, appearance.
- Zones (16:8): 0–12h Burning, 12–14h Fat burn, 14h+ Ketosis; keep the three-zone pattern if plans differ.

## Assets
No raster assets. Baloo 2 from Google Fonts. The mascot and flame glyphs are built from CSS shapes in the reference — rebuild as a reusable vector/mascot component with props: size, zoneColor, expression (happy | dozing | determined | focused | fierce | proud), animated.

## Files
- `Fastino Explorations.dc.html` — open in a browser; approved screens are 4a, 6a, 5a, 5b (+ 3a for motion).
- `ios-frame.jsx` — device bezel scaffolding; ignore for implementation.
