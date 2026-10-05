# Skyfang Squadron - handoff

## Status / start here (2026-10-04)

- **State:** proof of concept, running. The last gameplay work (Apr 30) is
  committed on `master` as 6597902 but has **not been playtested**: slot
  gates on a level basis with straight approaches, an extended rail
  (barrel-roll section, second gate, new enemy wave), the megawreck as a
  full block to phase through with the double-shot pickup after it,
  double-shot wing pods, pickups that converge with the ship, a shield
  bubble and heal pulse, the rail/shockwave/escort stopping during tutorial
  prompts, and the title starfield's direction. The gameplay scene runs
  headless for 600 frames without script errors (checked 2026-10-04).
- **Next step:** playtest those changes in a real window (`scenes/title_screen.tscn`,
  F5 in the editor) and fix what does not feel right; feel calls are the
  user's.
- **Unbuilt:** the Level 1 boss (`BOSS-NOTES.md`).

## Local-only material (not in this repo)

- `SUMMARY.md`: private dev notes, gitignored (this repo is public).
- `C:\Users\keato\.gamedev\`: design docs (`CONCEPT.md`, `PROTOTYPE-LOG.md`).
- The Godot MCP addon, its configs and `debug/` captures (excluded locally;
  full copy in tag `archive/wip/uncommitted-2026-04-30`).
