# Footstep library review — 2026-10-31

Library: `audio_library/player/Footsteps/` (uploaded; originals untouched).
Tools: `tools/audio/audio_inventory.py` (measurements → `_reports/inventory.json`),
extra clipping/truncation/stereo checks, and `tools/audio/prepare_footsteps.py`
(builds the game-ready copies; rerun it to regenerate them).

## Summary

- **130 files reviewed**: 13 surfaces × 10 takes, all 44.1 kHz / 16-bit stereo WAV
  (mostly dual-mono), 0.16–1.11 s, none silent, none truncated (tails end below −44 dBFS).
- **Verdicts:** approve 40 · approve-new 10 · maybe 50 · remove-candidate 30 · reject-tech 0.
- **Copied into the game:** 40 source recordings → **48 game-ready files** in
  `assets/creator/audio/player/footsteps/`: 8 takes each for wood, stone, dirt, grass
  and gravel, plus 8 carpet takes **derived** from the wood takes.
- **Connected to working triggers:** all 48. The local hunter's footsteps pick the
  surface of the room underfoot (`Defs.FLOOR_SURFACE`); the first step after the stairs
  and the phantom footsteps also use the surface at their position.
- **Technical issues:** Stone (9/10) and Concrete (10/10) are hard-clipped (flat-topped
  runs up to 73 samples). Stone was repaired (attenuate 8 dB, then ffmpeg `adeclip`:
  longest flat run 73 → 1 sample). Concrete was not needed. A few Grass/Gravel/Mud/Wood
  takes touch full scale for 4–8 samples (negligible).
- **Needs human listening:** the de-clipped Stone takes (the repair is an estimate), the
  derived Carpet takes (synthetic muffling), and the level balance between surfaces
  (matched by measurement to the old generic step, not by ear).

## Mapping to the game

| Surface (recordings) | Game floor textures | Rooms using them (7 locations) |
|---|---|---|
| Wood | wood_dark, wood_light, parquet | 56 rooms: halls, studies, bedrooms; the harbour quay and boat deck |
| Stone | stone, tile_white, tile_checker | 58 rooms: basements and cellars, kitchens, bathrooms, chapels |
| Dirt | dirt | 19 rooms: sheds, stables, earthen cellars |
| Grass | grass | 6 rooms: gardens (Ashgrove, Blackwood, St. Evangeline, Hollow Lane) |
| Gravel | gravel | 8 rooms: paths, drives, the harbour road and rope walk |
| Carpet (derived from Wood) | carpet_red, carpet_blue, carpet_green | 35 rooms: parlours, bedrooms, guest rooms |

Unknown floors (none today) and any surface whose files are missing fall back to the
generic `footstep` cue.

## Per-file table

Peak / RMS in dBFS; "Clip" = longest run of consecutive full-scale samples in the source.

| File | Length | Peak / RMS | Clip | Game use | Verdict | Status | Fixes applied | Reason |
|---|---|---|---|---|---|---|---|---|
| `Concrete footsteps/Concrete footstep 1.wav` | 0.5 s | 0.0 / -19.1 | 23 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 2.wav` | 0.43 s | 0.0 / -17.6 | 37 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 3.wav` | 0.48 s | 0.0 / -17.4 | 31 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 4.wav` | 0.46 s | 0.0 / -17.2 | 40 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 5.wav` | 0.22 s | 0.0 / -14.1 | 26 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 6.wav` | 0.26 s | 0.0 / -14.4 | 43 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 7.wav` | 0.2 s | 0.0 / -14.1 | 30 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 8.wav` | 0.19 s | 0.0 / -12.5 | 37 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 9.wav` | 0.2 s | 0.0 / -13.9 | 37 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Concrete footsteps/Concrete footstep 10.wav` | 0.26 s | 0.0 / -15.4 | 28 | — (no concrete floors; stone covers masonry) | **maybe** | reviewed only | — | Hard-clipped (flat runs 23–43 samples) and a modern-sounding material; stone already covers masonry. |
| `Dirt footsteps/Dirt footstep 1.wav` | 0.37 s | -3.9 / -25.7 | 0 | dirt | **approve** | **copied + connected** → `dirt_01.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 2.wav` | 0.45 s | -2.3 / -27.0 | 0 | dirt | **approve** | **copied + connected** → `dirt_02.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 3.wav` | 0.46 s | -8.9 / -27.7 | 0 | dirt | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier). |
| `Dirt footsteps/Dirt footstep 4.wav` | 0.48 s | -4.3 / -25.5 | 0 | dirt | **approve** | **copied + connected** → `dirt_03.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 5.wav` | 0.38 s | -7.4 / -25.8 | 0 | dirt | **approve** | **copied + connected** → `dirt_04.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 6.wav` | 0.52 s | -5.6 / -26.4 | 0 | dirt | **approve** | **copied + connected** → `dirt_05.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 7.wav` | 0.36 s | -6.4 / -25.1 | 0 | dirt | **approve** | **copied + connected** → `dirt_06.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 8.wav` | 0.27 s | -4.3 / -24.6 | 0 | dirt | **approve** | **copied + connected** → `dirt_07.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Dirt footsteps/Dirt footstep 9.wav` | 0.25 s | -3.1 / -24.1 | 0 | dirt | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier). |
| `Dirt footsteps/Dirt footstep 10.wav` | 0.37 s | -6.8 / -25.1 | 0 | dirt | **approve** | **copied + connected** → `dirt_08.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Glass footsteps/Glass footstep 1.wav` | 0.31 s | -7.0 / -22.7 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 2.wav` | 0.27 s | -7.5 / -20.8 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 3.wav` | 0.19 s | -5.0 / -19.9 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 4.wav` | 0.29 s | -6.4 / -21.3 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 5.wav` | 0.25 s | -1.9 / -23.4 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 6.wav` | 0.3 s | -6.3 / -22.7 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 7.wav` | 0.31 s | -7.8 / -23.3 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 8.wav` | 0.28 s | -9.9 / -23.2 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 9.wav` | 0.24 s | -6.1 / -21.8 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Glass footsteps/Glass footstep 10.wav` | 0.28 s | -8.3 / -21.8 | 0 | — (no glass floor) | **maybe** | reviewed only | — | Clean, but no glass floor exists; possible future broken-glass effect. |
| `Grass footsteps/Grass footstep 1.wav` | 0.5 s | -0.1 / -27.0 | 4 | grass | **approve** | **copied + connected** → `grass_01.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 2.wav` | 0.65 s | -3.3 / -26.2 | 0 | grass | **approve** | **copied + connected** → `grass_02.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 3.wav` | 0.68 s | 0.0 / -25.8 | 2 | grass | **approve** | **copied + connected** → `grass_03.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 4.wav` | 0.67 s | -2.7 / -26.3 | 1 | grass | **approve** | **copied + connected** → `grass_04.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 5.wav` | 0.52 s | 0.0 / -25.6 | 1 | grass | **approve** | **copied + connected** → `grass_05.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 6.wav` | 0.5 s | -4.8 / -24.8 | 0 | grass | **approve** | **copied + connected** → `grass_06.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 7.wav` | 0.36 s | 0.0 / -26.5 | 1 | grass | **approve** | **copied + connected** → `grass_07.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Grass footsteps/Grass footstep 8.wav` | 0.35 s | -3.6 / -24.4 | 0 | grass | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier). |
| `Grass footsteps/Grass footstep 9.wav` | 0.42 s | 0.0 / -28.2 | 4 | grass | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier, clipped). |
| `Grass footsteps/Grass footstep 10.wav` | 0.38 s | 0.0 / -27.3 | 1 | grass | **approve** | **copied + connected** → `grass_08.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 1.wav` | 0.34 s | 0.0 / -21.8 | 6 | gravel | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier, clipped). |
| `Gravel Footsteps/Gravel Footstep 2.wav` | 0.37 s | 0.0 / -24.3 | 4 | gravel | **approve** | **copied + connected** → `gravel_01.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 3.wav` | 0.38 s | 0.0 / -24.5 | 3 | gravel | **approve** | **copied + connected** → `gravel_02.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 4.wav` | 0.33 s | -2.1 / -24.4 | 0 | gravel | **approve** | **copied + connected** → `gravel_03.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 5.wav` | 0.48 s | -5.2 / -26.8 | 0 | gravel | **approve** | **copied + connected** → `gravel_04.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 6.wav` | 0.56 s | -3.0 / -25.3 | 0 | gravel | **approve** | **copied + connected** → `gravel_05.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 7.wav` | 0.45 s | 0.0 / -25.5 | 3 | gravel | **approve** | **copied + connected** → `gravel_06.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 8.wav` | 0.49 s | 0.0 / -22.7 | 5 | gravel | **approve** | **copied + connected** → `gravel_07.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Gravel Footsteps/Gravel Footstep 9.wav` | 0.58 s | 0.0 / -23.5 | 8 | gravel | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier, clipped). |
| `Gravel Footsteps/Gravel Footstep 10.wav` | 0.51 s | -0.3 / -24.3 | 0 | gravel | **approve** | **copied + connected** → `gravel_08.wav` | mono, 2/12 ms fades, level-match | Clear surface match; typical length and level. |
| `Ice Footsteps/Ice footstep 1.wav` | 0.65 s | -6.1 / -33.4 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 2.wav` | 0.8 s | -1.3 / -33.6 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 3.wav` | 0.94 s | -3.6 / -33.9 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 4.wav` | 0.79 s | -1.9 / -33.3 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 5.wav` | 0.56 s | -0.7 / -32.1 | 1 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 6.wav` | 0.54 s | -4.6 / -31.4 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 7.wav` | 0.83 s | -6.2 / -33.3 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 8.wav` | 0.71 s | -2.0 / -32.8 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 9.wav` | 1.11 s | -4.4 / -35.1 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Ice Footsteps/Ice footstep 10.wav` | 0.74 s | -4.1 / -33.4 | 0 | — (no ice in any location) | **remove** | reviewed only | — | No ice anywhere; very quiet (RMS ≈ −33 dBFS) with long tails. |
| `Metal footsteps/Metal footstep 1.wav` | 0.26 s | -3.0 / -23.2 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 2.wav` | 0.34 s | -3.7 / -25.1 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 3.wav` | 0.26 s | -2.8 / -24.4 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 4.wav` | 0.35 s | -2.0 / -24.3 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 5.wav` | 0.36 s | -5.6 / -27.3 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 6.wav` | 0.29 s | -3.9 / -24.9 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 7.wav` | 0.41 s | -3.6 / -25.6 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 8.wav` | 0.25 s | -3.8 / -23.2 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 9.wav` | 0.24 s | -6.2 / -24.4 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Metal footsteps/Metal footstep 10.wav` | 0.33 s | -3.6 / -24.1 | 0 | — (no metal floors) | **maybe** | reviewed only | — | Clean, but no metal floors; possible future iron grate / ship hatch. |
| `Mud footsteps/Mud footstep 1.wav` | 0.51 s | -2.2 / -27.7 | 0 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 2.wav` | 0.56 s | -0.0 / -27.8 | 4 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 3.wav` | 0.35 s | -3.2 / -26.6 | 0 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 4.wav` | 0.33 s | -0.7 / -26.0 | 0 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 5.wav` | 0.34 s | -2.1 / -26.8 | 0 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 6.wav` | 0.41 s | 0.0 / -26.3 | 3 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 7.wav` | 0.58 s | -1.4 / -27.3 | 0 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 8.wav` | 0.24 s | 0.0 / -22.4 | 2 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 9.wav` | 0.35 s | -5.3 / -26.0 | 0 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Mud footsteps/Mud footstep 10.wav` | 0.51 s | 0.0 / -26.8 | 1 | — (no wet ground / weather) | **maybe** | reviewed only | — | Clean, but no wet-ground surface; possible future rain variant. |
| `Sand footsteps/Sand footstep 1.wav` | 0.61 s | -0.5 / -19.8 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 2.wav` | 0.51 s | -4.7 / -19.5 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 3.wav` | 0.4 s | -0.3 / -19.3 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 4.wav` | 0.45 s | -4.9 / -19.8 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 5.wav` | 0.44 s | -1.2 / -19.4 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 6.wav` | 0.48 s | -2.9 / -20.2 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 7.wav` | 0.44 s | -1.7 / -18.8 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 8.wav` | 0.4 s | -1.2 / -18.4 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 9.wav` | 0.54 s | 0.0 / -20.2 | 1 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Sand footsteps/Sand footstep 10.wav` | 0.54 s | -4.3 / -20.0 | 0 | — (no sand in any location) | **remove** | reviewed only | — | No sand anywhere in the game. |
| `Snow footsteps/Snow footstep 1.wav` | 0.48 s | -8.9 / -25.9 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 2.wav` | 0.52 s | -8.1 / -27.3 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 3.wav` | 0.57 s | -8.1 / -27.8 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 4.wav` | 0.66 s | -10.4 / -27.6 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 5.wav` | 0.47 s | -12.4 / -27.6 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 6.wav` | 0.4 s | -9.0 / -24.6 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 7.wav` | 0.3 s | -8.2 / -24.1 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 8.wav` | 0.4 s | -9.6 / -25.6 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 9.wav` | 0.26 s | -8.3 / -25.9 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Snow footsteps/Snow footstep 10.wav` | 0.34 s | -8.6 / -25.4 | 0 | — (no snow / winter setting) | **remove** | reviewed only | — | No snow / winter setting in the game. |
| `Stone footsteps/Stone footstep 1.wav` | 0.25 s | 0.0 / -13.6 | 64 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_01.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 2.wav` | 0.31 s | 0.0 / -14.6 | 43 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_02.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 3.wav` | 0.17 s | 0.0 / -13.4 | 39 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_03.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 4.wav` | 0.16 s | 0.0 / -12.7 | 48 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_04.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 5.wav` | 0.21 s | 0.0 / -12.6 | 62 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_05.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 6.wav` | 0.18 s | 0.0 / -14.3 | 44 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_06.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 7.wav` | 0.31 s | 0.0 / -15.9 | 21 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_07.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 8.wav` | 0.22 s | 0.0 / -12.8 | 73 | stone, tile_white, tile_checker | **approve** | **copied + connected** → `stone_08.wav` | mono, 2/12 ms fades, level-match, de-clip (−8 dB + adeclip) | Clear surface match; typical length and level. |
| `Stone footsteps/Stone footstep 9.wav` | 0.37 s | 0.0 / -16.2 | 58 | stone, tile_white, tile_checker | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier, clipped). |
| `Stone footsteps/Stone footstep 10.wav` | 0.23 s | -1.8 / -20.2 | 0 | stone, tile_white, tile_checker | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier). |
| `Water footsteps/Water footstep 1.wav` | 0.49 s | -0.0 / -27.8 | 1 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 2.wav` | 0.45 s | -6.6 / -28.4 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 3.wav` | 0.57 s | -0.0 / -27.9 | 1 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 4.wav` | 0.45 s | -3.2 / -28.8 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 5.wav` | 0.6 s | -3.8 / -29.0 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 6.wav` | 0.47 s | -3.1 / -27.8 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 7.wav` | 0.67 s | -0.9 / -28.3 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 8.wav` | 0.69 s | -6.6 / -28.8 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 9.wav` | 0.5 s | -0.0 / -27.6 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Water footsteps/Water footstep 10.wav` | 0.51 s | -4.1 / -28.2 | 0 | — (water is not walkable; puddles would need a new hook) | **approve-new** | reviewed only | — | Would suit wading through the Drowned Sailor's puddles, but that needs a new detection hook — not implemented. |
| `Wood footsteps/Wood footstep 1.wav` | 0.51 s | -0.0 / -27.3 | 4 | wood_dark, wood_light, parquet (+ carpet, derived) | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier, clipped). |
| `Wood footsteps/Wood footstep 2.wav` | 0.52 s | -4.5 / -26.0 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_01.wav`, `carpet_01.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 3.wav` | 0.46 s | -4.4 / -25.8 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_02.wav`, `carpet_02.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 4.wav` | 0.36 s | -4.3 / -25.1 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_03.wav`, `carpet_03.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 5.wav` | 0.49 s | -4.4 / -25.6 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_04.wav`, `carpet_04.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 6.wav` | 0.47 s | -2.8 / -24.9 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_05.wav`, `carpet_05.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 7.wav` | 0.46 s | -4.7 / -25.4 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_06.wav`, `carpet_06.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 8.wav` | 0.51 s | -3.6 / -26.7 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_07.wav`, `carpet_07.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 9.wav` | 0.36 s | -4.6 / -25.3 | 0 | wood_dark, wood_light, parquet (+ carpet, derived) | **approve** | **copied + connected** → `wood_08.wav`, `carpet_08.wav` | mono, 2/12 ms fades, level-match; carpet copy also low-passed | Clear surface match; typical length and level. |
| `Wood footsteps/Wood footstep 10.wav` | 0.27 s | 0.0 / -25.1 | 4 | wood_dark, wood_light, parquet (+ carpet, derived) | **maybe** | reviewed only | — | Redundant: 8 takes per surface are used; this was a least typical take (length/level outlier, clipped). |

## Surface detection — what exists and what is missing

- **Exists:** the floor texture of the room you stand in (doorways take a neighbouring
  room's floor). Works on every level, including upper floors and basements.
- **Missing / approximations:**
  - Rugs are furniture, not floors: a rug on wood still sounds like wood.
  - No carpet recordings; carpet steps are muffled wood.
  - No wet-surface or weather detection: Water and Mud have nowhere to go; the Drowned
    Sailor's puddles are decals with no footstep hook.
  - No stair-specific step sound (taking the stairs plays one surface step).
  - Only the local hunter's own steps are heard; rivals, occupants and the entity have no
    footsteps (unchanged). The catalog's `rival_footstep` suggestion remains open.

## Cue coverage

New cues with creator audio: `footstep_wood`, `footstep_stone`, `footstep_dirt`,
`footstep_grass`, `footstep_gravel`, `footstep_carpet`. The generic `footstep`
placeholder remains as the fallback, and for the Nightmare noises and the Forest Tavern hub.

## Next steps (optional)

- Listen to `assets/creator/audio/player/footsteps/stone_*.wav` and `carpet_*.wav`.
- Water footsteps would need an approved puddle-wading hook before `/audio-implement`.
- `/audio-clean` would propose the remove-candidates (Ice, Sand, Snow). You asked to keep
  the library intact, so nothing has been deleted.
