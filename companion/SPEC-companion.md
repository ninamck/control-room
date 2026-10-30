# Spec change: the companion's face

Date: 30 Oct 2026. Replaces section 6 "Notch companion" face states, the companion row in section 7, and the icon folder.

## What changed

The companion was an 8×8 pixel-art face. It is now a geometric face in the style of a square with two round eyes and a flat mouth: small features, lots of empty ground, no pixel grid. The colour rules are unchanged.

## Drawing rules

Everything is drawn on a 100×100 unit square and scaled. No anti-aliasing tricks needed; these are plain shapes.

- Ground: a filled square. Yellow #F8C94A by default. Coral #E8604F for worried and blocked. Mint #BFE3C4 for pleased. Ink #111111 for inverted.
- Eyes: circles, radius 5.5, centred at (30,38) and (70,38). Alert uses radius 7 at y=36.
- Closed eyes: rectangles 16 wide, 4 tall, at (22,36) and (62,36).
- Mouth: a rectangle 4 tall at y=64. Width 40 (neutral) or 24 (asleep, alert). Talking is a 20×12 block at (40,60).
- Zero corner radius on the square. The only curves are the eyes.
- At sizes under 32px, enforce a minimum stroke of 1px so closed eyes and the mouth don't disappear.

Exact geometry for every face is in `faces/faces.json` and as individual SVGs in `faces/`. Use the SVGs directly or draw natively from the JSON; either is fine.

## The faces and when each shows

| # | File | State | Ground |
|---|---|---|---|
| 02 | 02-asleep | Nothing waiting | Yellow |
| 03 | 03-alert | At least one needs_you ticket | Yellow |
| 04 | 04-talking | Panel open | Yellow |
| 05 | 05-worried | Any needs_you ticket past 15 min | Coral |
| 08 | 08-quiet | Quiet mode on | Yellow |
| 09 | 09-blocked | Any blocked ticket | Coral |
| 06 | 06-pleased | Queue just cleared; show for 2 seconds then back to asleep | Mint |

Priority when several apply, highest first: blocked, worried, alert, talking (only while open), quiet, pleased (transient), asleep.

Not used in v1 but shipped: 01-neutral, 07-working, 10-inverted. 10-inverted is the candidate for the collapsed notch if yellow proves too loud against the black housing; Nina will decide after seeing it live.

## App icon

The app icon is 01-neutral (Nina chose it over 02-asleep on 30 Oct 2026). The full macOS set is in `icon/`, redrawn by `swift tools/make-icon.swift` (Xcode appiconset, Tauri folder, .icns, PNGs 16 to 1024). Replace the previous icon folder entirely.

## What does not change

Colour meanings, the 15 minute threshold, the rule that working agents and scheduled output never change the face, Quiet behaviour, accessibility (every face carries an aria-label naming the state, and colour is never the only signal because the eyes and mouth change too).
