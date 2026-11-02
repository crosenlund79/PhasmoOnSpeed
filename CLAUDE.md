# THE WITCHENING TALES — instructions for Claude

## Standing rule: mandatory repository verification

This is a permanent project safety requirement for every development task, not a
one-time instruction. It applies again at the start of every new implementation
task, including after context compaction, a new session or a change of machine.

**Before modifying any file:**

1. Verify the local repository, project identity, Git remote, active branch and the
   relevant project files against the intended game. Expected identity:
   - Git remote `origin`: `https://github.com/crosenlund79/PhasmoOnSpeed` (GitHub
     `crosenlund79/PhasmoOnSpeed`).
   - `project.godot` → `config/name="THE WITCHENING TALES"` (formerly SPECTRAL RUN) and
     `config/custom_user_dir_name="godot/app_userdata/SPECTRAL RUN"`.
   - `README.md` begins with `# THE WITCHENING TALES`.
   - A Godot 4.3 / GDScript project: `scripts/game/run.gd`, `scripts/data/defs.gd`,
     `data/houses/`, `tools/art/`, `tools/installer/`.
   - Active branch: the branch designated for the session (check `git branch
     --show-current` and that it tracks the matching `origin/` branch).
   Quick check:
   `git rev-parse --show-toplevel && git remote -v && git branch --show-current && git status -sb && grep -n "config/name" project.godot`
2. If the repository is incorrect, ambiguous, or cannot be verified: **stop and ask
   the user for clarification.** Do not guess.
3. Never modify files belonging to another project (another repository, a different
   Godot project, a different checkout or worktree that isn't the intended one).
4. Repeat this verification at the beginning of every new implementation task.
