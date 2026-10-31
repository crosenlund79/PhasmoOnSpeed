---
name: audio-clean
description: Remove files from audio_library/ that have no use under the current game design and feel, based on the latest /audio-review report. Always lists the candidates and asks for confirmation before deleting anything.
disable-model-invocation: true
---

# Audio clean — prune the library, carefully

Goal: delete files the latest review marked **remove** (and, if the user asks,
**reject-tech**) so the library only holds usable material. Deleting is
destructive, so follow every step.

1. Use the newest `audio_library/_reports/review-*.md`. If there is none, or files
   were added since it was written (compare with a fresh
   `python3 tools/audio/audio_inventory.py`), run `/audio-review` first.
2. Build the deletion list: only verdict **remove** (plus **reject-tech** if the
   user said so). Never include `approve`, `approve-new` or `maybe` files, files
   already implemented in `assets/creator/audio/`, `notes.txt`/README files that
   belong to kept audio, `_reports/`, or anything outside the library folder.
3. Show the list to the user in chat — path, size, and the one-line reason from the
   report — plus the total size freed. Then ask for confirmation with the
   AskUserQuestion tool (options: delete all listed / let me pick / cancel).
   Delete nothing without an explicit yes.
4. On yes: `git rm` the confirmed files (and their now-orphaned `<file>.txt`
   notes), remove empty sub-folders (keep the category folders and their
   `.gitkeep`), and append a "Cleaned" section to the report listing what was
   removed and why.
5. Commit with a message listing the count and categories, and tell the user:
   the files are gone from the folder but still in git history (recoverable with
   `git checkout <commit>^ -- <path>`); fully purging them from history (to shrink
   the repository) is a separate, history-rewriting step — only on request.
