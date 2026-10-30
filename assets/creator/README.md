# Creator artwork overrides

Drop creator-produced PNGs here using the same relative paths as
`assets/provisional/` (see `docs/ASSET_MANIFEST.md`), e.g.
`assets/creator/tokens/werewolf.png`. The game prefers files in this folder and
falls back to the provisional art automatically — no code changes needed.
Open the project in the Godot editor once so the new files are imported.

# Creator audio overrides

Sound replacements go in `assets/creator/audio/<group>/<name>.wav|.ogg` — the
exact path for every sound is listed in `docs/AUDIO_CATALOG.md`. A file there
replaces the generated placeholder from `assets/audio/`; delete it to get the
placeholder back. Optional variants: `<name>_01.wav` … `<name>_08.wav`.
