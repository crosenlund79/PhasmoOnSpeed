# Audio library (outside the game)

Raw and candidate audio for THE WITCHENING TALES. The `.gdignore` file in this
folder makes Godot skip it completely: nothing here is imported, loaded or
exported. Files only reach the game when Claude (or you) copies a finished
version into `assets/creator/audio/…` — see `docs/AUDIO_CATALOG.md`.

## How to organise it

Claude identifies content from the folder path and the file name, so make both say
what the sound is. Suggested layout (mirrors the game's audio categories):

```
audio_library/
  ambient/        house beds, weather, basement drones, music
  entities/       per entity: entities/weeper/sob_close_01.wav
  environment/    doors, flames, clocks, timbers, water, hellfire
  equipment/      lantern, Witch's Needle, Whisper Box, thermometer…
  evidence/       journal, writing, mimicked voices
  npc/            occupants: gasps, screams, footsteps, mutters
  player/         footsteps, hurt, death, pickups
  ui/             clicks, stings, results, menu
  _reports/       Claude's review reports (keep them)
```

File names: `<what>_<detail>[_NN].<ext>` in lowercase with underscores, e.g.
`door_creak_heavy_oak_02.wav`, `weeper_sob_distant.ogg`, `clock_toll_long.wav`.
Numbered takes (`_01`, `_02`…) become random variants in the game.
Optional notes: put a `notes.txt` (or `<file>.txt`) next to files to explain intent,
mood, or licence/source. Only add audio you made or have the rights to use.

Formats: `.wav` (16/24-bit PCM) or `.flac` preferred for effects; `.ogg` for long
loops and ambience; `.mp3` accepted. Any sample rate ≥ 22 050 Hz.

## Asking Claude

- `/audio-review` — inventory and judge everything here; writes a report in
  `_reports/`. Changes nothing in the game.
- `/audio-implement <files or "all approved">` — put approved files into the game.
- `/audio-clean` — propose removing files with no use under the current design;
  deletes only after you confirm the list.

## Size

GitHub rejects single files over 100 MB and the repository should stay well under a
few GB. Prefer shorter edits and `.ogg`/`.flac` for long material. For very large
collections, consider Git LFS (`git lfs track "audio_library/**/*.wav"`) or a
separate repository.
