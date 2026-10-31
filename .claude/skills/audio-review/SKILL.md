---
name: audio-review
description: Inventory and judge the raw audio in audio_library/ against the game's sound list, design and Gothic Noir feel; writes a fit report. Use when the user has added audio files and wants them assessed. Never changes the game.
---

# Audio review — what fits THE WITCHENING TALES?

Goal: decide, file by file, whether audio in `audio_library/` (or the folder the
user names) fits the game, and where. **This skill only measures, listens by
numbers, and reports. It never copies files into the game, edits code, or deletes
anything.**

## 1. Gather facts

1. Run the inventory (never skip it):
   `python3 tools/audio/audio_inventory.py [folder] --json audio_library/_reports/inventory.json`
   It gives per file: category (first folder), duration, sample rate, channels,
   peak/RMS dBFS, clipping %, leading/trailing silence, loop-seam jump, and any
   `notes.txt` / `<file>.txt` text, plus the game's current cue ids.
2. Read what the game needs:
   - `docs/AUDIO_CATALOG.md` — every cue (id, purpose, creator path, priority) and
     the "Missing sounds worth adding" suggestions.
   - `scripts/core/audio_catalog.gd` (`CUES`) — the authoritative cue list.
   - `docs/DESIGN.md` and `scripts/data/defs.gd` (entities, equipment) when a file
     names an entity, item or event.
3. Identify each file from its **folder path and file name** (and notes). Do not
   guess beyond what they say; if a name is ambiguous, mark it "unclear" and say
   what name would make it clear.

## 2. Judge each file

**Fit (design & feel)** — the game is Gothic Noir, 19th-century, supernatural
investigation; short tense runs. Good: creaks, knocks, drips, wind, candle and
hearth fire, clocks, period equipment (glass, brass, wood, paper, chains), human
breath/whispers/screams, animals of the era, organs/strings/music boxes,
unnatural tones. Reject: modern technology (engines, phones, electronic beeps,
sirens, gunfire, modern UI blips), cartoon/comedic sounds, sci-fi, recognisable
copyrighted music or sound effects, voice lines with modern phrasing, anything
whose licence/source note says it may not be used.

**Match** — map to one of:
- an existing cue id (it would replace the generated placeholder; numbered takes
  `_01…_08` become random variants),
- a "missing sound" suggestion from the catalog (needs a small code hook later),
- a plausible new use you can name concretely (needs a code hook),
- nothing (no use under the current design).

**Technical** — oneshots ideally < 4 s (UI < 0.5 s), loops seamless (seam jump
small, no lead/trail silence) and ≥ 10 s; not silent; not clipped (clipping
> 0.01 %); peak between about −6 and −0.5 dBFS (louder/quieter is fixable by
normalising — say so); ≥ 22 050 Hz; mono preferred for positional effects
(stereo is fine for ambience/music/UI). Fixable issues (trim, normalise, mono,
fade, convert) do not disqualify a file — note the fix.

## 3. Write the report

Save `audio_library/_reports/review-YYYY-MM-DD.md` (keep older reports). Sections:

1. **Summary** — counts per verdict, notable gaps the library fills or misses.
2. **Table** — one row per file: path · identified as · verdict · target cue id /
   suggested use · fixes needed · reason (one line).
   Verdicts: **approve** (fits, ready after listed fixes) · **approve-new**
   (fits, needs a new cue/code hook) · **maybe** (fits the feel but no clear
   use yet, or unclear name) · **reject-tech** (unusable: silent, broken,
   undecodable, hopelessly clipped) · **remove** (definitely no use under the
   current design and feel, or not allowed to be used).
3. **Cue coverage** — which catalog cues now have candidates, which still have none.
4. **Next steps** — exact `/audio-implement …` and `/audio-clean` suggestions.

Then give the user a short summary in chat with the report's path. Be honest about
what numbers can't tell you (you cannot hear the files): judge mood from names,
notes, durations and levels, and say when the user should listen to confirm.
