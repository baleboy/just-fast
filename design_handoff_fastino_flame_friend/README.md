# Handoff: Fastino — "Flame Friend" redesign (light + dark · timer, eating window, stats, settings)

## Overview
Redesign of Fastino, an intermittent-fasting timer app (iOS). The chosen direction is **"Flame Friend"**: a warm, cute, peach-toned aesthetic built around a small flame mascot who lives inside the progress ring and changes color/expression with the metabolic zone. Screens: Timer (fasting), Timer (eating window), Stats, Settings — with a full light and dark scheme.

## About the Design Files
The files in this bundle are **design references created in HTML** — prototypes showing intended look and behavior, not production code to ship. Recreate these designs in the target codebase's existing environment (SwiftUI, React Native, Flutter, etc.) using its established patterns and libraries. If no codebase exists yet, choose the platform-appropriate framework and implement the designs there.

- `Fastino Explorations.dc.html` — the design document. **Approved screens:**
  - Light: `4a` Timer fasting · `6a` Timer eating-window · `5a` Stats · `5b` Settings
  - Dark: `7a` Timer fasting · `7b` Stats · `7c` Settings (dark eating-window not designed — derive from 6a with the dark tokens)
  - `3a` (turn 3) holds approved **motion specs** (launch fill, ignite, zone crossing, completion celebration) demonstrated in an earlier skin — port the timings/choreography to Flame Friend's colors.
  - Everything else (turns 1–2, 4b, 4c) is rejected exploration — ignore.
- `ios-frame.jsx` — device-frame scaffolding only, not part of the design.

## Fidelity
**High-fidelity.** Colors, type, spacing, copy, and the mascot construction are final; recreate faithfully. Screens are designed at 402×874 (iPhone). All px values below are at that scale. The mascot should be rebuilt as a vector asset (or drawn shapes) matching the construction spec below.

## Design Tokens

### Light scheme
- Background: vertical gradient `#fff3e4 → #ffe8d1`; eating window uses calmer `#fff8ef → #fdeede`
- Ink: `#4a2a1e` (headings, numbers); body `#5a3a2e`; muted `#b07a5a`; accent text `#c9502e`; wordmark `#c96f4a` (lowercase "fastino")
- Card: `#fff`, radius 24px (22px rows, 20px small), shadow `0 4px 14px rgba(201,111,74,.12)`
- Accent surface `#ffe0c2`; accent border `#ff9e7d` (2.5px); success green `#2a8a6b` on `#e3f5ec`
- Muted/unlit flame: `#e8cdb8` (faced) / `#d9b8a5` (plain); face ink on muted flames `#8a5a42`
- Primary button: gradient `#ff9e7d → #f27a52`, white text, radius 26px, hard 3D press shadow `0 6px 0 #d95f3a` (eating window: `#ffb36b → #f2905c`, shadow `0 6px 0 #d97a42`)
- Chart neutral bar: `rgba(90,58,46,.1)`

### Dark scheme ("cozy campfire night")
- Background: `#2b1a12 → #211107`
- Ink: `#fff3e4` (headings/numbers); body `#f5dfc8`; muted `#c99a7d`; accent text `#ffb98a`; unlit flame `#6b4a38` (face ink `#2b1a12`); dim `#a87e68`
- Card: `rgba(255,220,180,.07)` (tab bar/chips `.08`), same radii, no drop shadow; row dividers `2px dashed rgba(255,220,180,.12)`
- Accent surface `rgba(255,125,82,.16–.2)`; accent border `#ff9e7d`
- **Glow**: mascot and lit elements get `drop-shadow(0 0 8–18px rgba(255,125,82,.45–.6))`; ring adds a blurred duplicate of the elapsed arc (blur 24px, opacity .35)
- Primary button: same gradient, text `#3a1505`, press shadow `0 6px 0 #a8431f`
- Toggle off: `rgba(255,220,180,.14)` with `#c9a88a` knob; chart neutral bar `rgba(255,220,180,.1)`
- Face ink on lit flames: `#3a1c10`

### Zone colors (ring, mascot, beads — both schemes)
- Burning (0–12h): gold `#ffd88a → #ffb36b`
- Fat burn (12–14h): deep orange `#ff9068 → #ff7d52` (boundary jump stops at 268°/272°)
- Ketosis (14h+): pink (dim preview `#f7c3cf` light / `rgba(247,138,168,.2)` dark)
- Dimmed unreached segments: light `#ffd9c2` (fat burn) + `#f7c3cf` (ketosis); dark `rgba(255,180,130,.18)` + `rgba(247,138,168,.2)`

### Typography
- **Baloo 2** (Google Fonts), weights 600–800.
- Scale: wordmark 20px/800 · timer 40px/800 · stat value 32px/800 · screen title 26px/800 · section label 12–13px/800/`.06em` caps · row title 16px/800 · captions 12.5–14px/600–700 · tab label 13px.

## Screens / Views

### 1. Timer — fasting (4a light, 7a dark)
Vertical flex, centered: wordmark → ring (310×310, 40px top margin) → zone beads (30px margin) → bottom: End-fast button + tab bar (14px gap).

**Ring**: donut via conic-gradient masked `transparent 78% / solid 79%` (~32px stroke). Zone bands with in-zone gradients and a hard jump at boundaries (1h = 22.5° from 12 o'clock): gold 0–268°, fat-burn orange 272°–fill edge (mock: 288° = 12h50m of 16h), dimmed unreached segments beyond. Progress dot: 32px circle (white in light, `#3a2418` in dark) with 4px border in the active zone color, centered on the ring at the fill angle; dark adds an orange glow shadow.

**Mascot (inside ring, above the time)** — 74×86, bobbing (3s ease-in-out, ±6px; dark adds glow). Construction: teardrop body `border-radius: 50% 50% 46% 46% / 62% 62% 40% 40%` filled with the **active zone gradient** (mock: `#ff9068→#ff7d52`); flame tip (26×30) on top in the zone's lighter color (`#ffb36b`); face: two oval eyes (9×12), open smile (16×8 bottom-arc, 3px stroke), blush ovals `rgba(255,120,90,.55)`. **Expression + color follow the zone**: Burning = gold, plain happy; Fat burn = deep orange, determined (13×4 brow bars, ±14°); Ketosis = pink, proud (bigger smile). Face ink `#4a2a1e` light / `#3a1c10` dark.

**Center text**: time `12:50:27` (40px/800) · "16h fast · ends 12.34" (14px/600 muted).

**Zone beads** (3 pills, 10px gap): color dot + label. Completed "Burning ✓" (gold dot); active "Fat burn!" (accent surface + 2px accent border, accent text 800); upcoming "Ketosis" at 55% opacity.

**CTA**: "End fast".

### 2. Timer — eating window (6a; dark variant not drawn — apply dark tokens)
Same skeleton, calmer background. Ring = 8px dashed `#f3ddc8` circle, no fill, no dot. Mascot = 58×68 "pilot light" (paler `#ffd3a8→#ffb98a`, closed happy eyes, slower 4.5s bob). Center: "EATING WINDOW" · countdown `5h 26m` · "until your next fast · 20.30". Below ring: last-fast recap card ("LAST FAST / 16h 4m · goal met" + green "Streak ×1" chip). CTA: "**Start fast**" (triggers ignite animation, ring transitions dashed→filled).

### 3. Stats (5a light, 7b dark)
Title "Your journey" + "Last 30 days" → 2×2 bento (12px gap) → Last-7-days card → History row → tab bar.
- Cards: label 12px/800 caps · value 32px/800 · caption 12.5px/600. Current-fast value in accent; caption "elapsed · 80% of 16h". Longest-fast card has a tiny 26×30 happy mascot top-right (glowing in dark). Goal-rate card on accent surface.
- Values: Current 12h 50m · Longest 17h 2m · Streak 0 (best 2, "finish today to relight") · Goal rate 50% (avg 14h 43m · 30 days).
- **Last 7 days = bar histogram**: 7 equal-width bars (flex, 9px gap) on a 64px track, bottom-aligned, `border-radius: 8px` (soft-cornered bars — NOT fully rounded pills, and no mascots/flames in the chart). Height ∝ fast length vs goal (mock: 26/34/88/100/30/22/80%). Goal-met days: `#ffb36b→#ff8a5c` vertical gradient (dark adds `0 0 12px rgba(255,138,92,.4)` glow); missed: neutral bar token; today: same gradient at ~45–50% alpha + 2px dashed accent border. Day letters below; lit/today letters accented 800. Footnote: "Bar height = fast length · dashed = today, in progress".
- History row: card with "History" + accent `→`.

### 4. Settings (5b light, 7c dark)
Title "Settings" → "YOUR FAST PLAN" → 4 plan cards → "NOTIFICATIONS" group → "GENERAL" group → tab bar.
- **Plan cards**: mascot flame **grows with intensity, each with its own expression** — 14:10 "gentle" (26×31, dozing: closed-eye bars + tiny mouth) · 16:8 "current" (30×36, happy, full color + flicker + glow in dark; card selected: accent surface + 2.5px accent border, accent text) · 18:6 "deep" (34×41, focused: angled brows + flat mouth) · 20:4 "warrior" (38×46, fierce: steeper brows + big grin). Unselected flames muted.
- Group cards with dashed dividers (`#ffe8d1` light / `rgba(255,220,180,.12)` dark). Toggle: 48×29 pill; on = `#ffb36b→#ff8a5c` gradient, white knob right; off = neutral, knob left.
- Rows: Fast complete (on) · Milestones "Fat burn, ketosis" (on) · Time to start "Daily reminder, 20.30" (off). General: Appearance ("Light →" / "Dark →") · Export data ("→"). **No health-platform integration** — deliberately removed.

## Interactions & Behavior
- Timer ticks every second; ring fill = elapsed/goal × 360°; mascot color/expression, beads, and dot border switch at 12h and 14h.
- Motion specs (live in `3a`, port colors): **launch fill** 0→current ~1.8s ease-out cubic · **ignite** on start: expanding ring flash ~0.9s · **zone crossing**: pulse flash + bead handoff at the boundary · **completion**: flare + rising ember particles (~1.4–2s staggered), CTA flips to green "Log this fast".
- Mascot idle bob 3s (4.5s resting); flicker (scale 1→1.06, ±2°, 1.6–1.8s) on the selected plan flame and today's contexts.
- End fast: confirm → record → eating-window state. Start fast: ignite → fasting state.
- Buttons: hard-shadow press (translate down 2–3px, shadow shrinks). Copy is matter-of-fact — no first-person mascot speech.
- Appearance cycles Light/Dark/System using the two token sets above.

## State Management
- Current fast: startTime, goalHours (selected plan), derived elapsed/percent/zone; app mode: fasting | eating-window (countdown to next scheduled fast from reminder time).
- History: completed fasts (start, end, goal, met flag) → streaks, longest, avg, goal rate, 7-day bars, last-fast recap.
- Settings: plan, notification toggles, reminder time, appearance.
- Zones (16:8): 0–12h Burning · 12–14h Fat burn · 14h+ Ketosis; keep the three-zone pattern if plans differ.

## Assets
No raster assets. Baloo 2 from Google Fonts. Mascot and flame glyphs are CSS shapes in the reference — rebuild as a reusable mascot component with props: size, zoneColor, expression (happy | dozing | determined | focused | fierce | proud), animated, glow (dark).

## Files
- `Fastino Explorations.dc.html` — open in a browser; approved screens 4a, 6a, 5a, 5b (light) and 7a, 7b, 7c (dark); 3a for motion.
- `ios-frame.jsx` — device bezel scaffolding; ignore for implementation.
