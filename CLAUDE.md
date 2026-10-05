# Skyfang Squadron

On-rails 3D arcade shooter inspired by Star Fox 64. Godot 4.6, Forward+
renderer, GDScript. This repository is **public**.

## Start here

- Read `HANDOFF.md` (state and next step), then `README.md` (gameplay,
  architecture) and `BOSS-NOTES.md` (unbuilt Level 1 boss design).
- The world is built procedurally in code: `scripts/game_world.gd` assembles
  the level at runtime (rail `Path3D`, hazards, enemies, gates, pickups,
  comms). `scenes/main.tscn` runs it; the main scene is
  `scenes/title_screen.tscn`. `GameManager` (`scripts/autoload/game_manager.gd`)
  is the autoload for global state.

## Godot

- Local: `D:/Godot_v4.6.2-stable_win64.exe` (console build alongside).
- Cloud: download the Linux x86_64 build of 4.6.2-stable from
  https://github.com/godotengine/godot/releases/tag/4.6.2-stable.
- There are no automated tests. A headless smoke run of the gameplay scene
  catches script errors: `godot --headless --path . res://scenes/main.tscn --quit-after 600`.
  Judging how it plays needs a real window and a person.

## Local-only files

- `SUMMARY.md` (private dev notes) is gitignored; never commit it.
- The Godot MCP tooling (`addons/godot_mcp_enhanced/`, `.mcp.json`,
  `godot_mcp_config.json`) and `debug/` captures are excluded through
  `.git/info/exclude` on the user's PC; a full copy is in tag
  `archive/wip/uncommitted-2026-04-30`. Do not commit them or enable the
  plugin in `project.godot`.

<!-- cloud-sync:start -->
## The remote is the source of truth

- GitHub (`origin`) holds the truth. Local work may replace it only when it was made on top of its latest.
- Fetch before changing anything. If this copy is behind, bring it up to date first (fast-forward, or rebase your own commits onto origin). Never force-push, and never overwrite a remote change you have not seen.
- If the remote moved and the work cannot be brought on top of it cleanly, stop and ask.
- Push what you commit as soon as it is ready (in a cloud session: to your working branch).
<!-- cloud-sync:end -->
