---
name: audio-implement
description: Put approved audio from audio_library/ into the game as creator overrides (convert, trim, normalise, place, verify). Use only for files approved in the latest /audio-review report, and only those the user names (or "all approved").
disable-model-invocation: true
---

# Audio implement — approved files into the game

Input: file paths, cue ids, or "all approved". Source of truth: the latest
`audio_library/_reports/review-*.md`. **Only implement files with verdict
`approve` (or `approve-new` after the user confirms the code hook).** If a file
was not reviewed, run `/audio-review` first — never implement unreviewed audio.

## For each file

1. Re-check it: run `python3 tools/audio/audio_inventory.py` on its folder and
   confirm the numbers still match the report.
2. Find its target in `scripts/core/audio_catalog.gd` (`CUES`): the creator
   path `assets/creator/audio/<path>.<fmt>`. Several takes for one cue →
   `<path>_01`, `<path>_02`, … (max 8) — the game picks one at random per play.
3. Prepare a game-ready copy with ffmpeg (never modify the original in
   `audio_library/`):
   - oneshots → `.wav`, 16-bit PCM, 44 100 Hz, mono for positional cues
     (stereo for UI/music): `ffmpeg -i in -ac 1 -ar 44100 -c:a pcm_s16le out.wav`
   - loops/ambience/music → `.ogg` (Vorbis q≈6), keep stereo.
   - Apply only the fixes the report listed: trim silence
     (`silenceremove`), short fades (`afade`, oneshots only — never fade a loop's
     seam), normalise peak to about −1 dBFS (`loudnorm` or `volume`), and keep
     the overall level close to the placeholder it replaces (compare RMS with the
     matching `assets/audio/<id>.wav` using the inventory tool).
4. Save it at the creator path. Don't overwrite an existing creator file without
   asking.
5. `approve-new` (a sound with no cue yet): propose the smallest hook — a new
   `CUES` entry + one `Sfx.play`/`sound_at` call where the event happens — and
   ask the user before adding code.

## Verify and record

- `tools/dev.sh import` (Godot imports the new files), then
  `tools/dev.sh test test_audio_overrides test_audio_export` — must pass.
- Update `docs/AUDIO_CATALOG.md`: the "Cues with creator (original) audio"
  count, and a note in each implemented cue's row.
- Append an "Implemented" section to the review report: file → creator path,
  fixes applied.
- Commit (sources stay in `audio_library/`, game copies in `assets/creator/audio/`)
  and tell the user which cues now use their audio and which approved files are left.
