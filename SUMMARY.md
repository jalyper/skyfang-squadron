# Skyfang Squadron — Session Summary (2026-04-13)

This document captures the findings, edits, bugs, and resolutions discussed
throughout the day's development session. It's organized by feature/system
rather than strictly chronological because several systems were iterated
multiple times.

---

## Project snapshot

- Star Fox 64 clone, on-rails 3D arcade shooter
- Engine: **Godot 4.6** (Forward+)
- Entirely procedural scene construction — `game_world.gd` builds the world
  in code, no complex `.tscn` files
- Repo: `C:\Users\keato\repos\skyfang-squadron`
- Game design docs: `C:\Users\keato\.gamedev\CONCEPT.md`, `PROTOTYPE-LOG.md`
- Boss design notes: `BOSS-NOTES.md` (off-rails arena, boundary U-turn,
  teammate participation affected by escort outcome)

---

## Title screen

### What changed
- 3D logo model replaces the stacked text labels (`title_screen.gd`)
- Model path: `assets/models/Meshy_AI_SKYFANG_SQUADRON_st_0413213505_texture.glb`
- Rotated and lit with front spotlight + warm omni fill + optional cool backlight
- Environment glow crushed (`glow_intensity 0.6 → 0.2`, `glow_bloom 0.15 → 0.0`)
  to stop emission bloom from smearing the logo into a pink haze
- `_tone_down_emission()` recursively overrides `MeshInstance3D` materials to
  dim Meshy-AI baked emission down to near-black
- Options button removed; Start and Exit buttons moved down ~10% of viewport
- Hover animation is now a centered symmetric scale (removed asymmetric
  `position:x += 6` slide)

### Bugs and fixes
- **Controller A button didn't select menu buttons** — caused by custom
  input map rebind of `ui_accept`. Added `_input()` handler that forwards
  `JOY_BUTTON_A` to the focused button's `pressed` signal.
- **"Cannot call set_input_as_handled on null"** after A-press → fixed by
  calling `set_input_as_handled()` **before** emitting the button signal,
  since the Start handler synchronously changes scenes and unparents the
  title screen.
- **README** created at `README.md` with premise, gameplay, squad, act
  breakdown, architecture, running instructions

---

## Rail system (roller coaster redesign)

### The big rewrite
- Curved `Curve3D` with 11 control points, smooth Catmull-Rom-ish tangents,
  and per-point tilt values for banking
- Five acts across ~810 units: intro city → banked descent → slot run →
  climbing left turn → escort → final approach
- New helpers: `_rail_transform(dist)`, `_rail_pos(dist, lx, ly, lz)`,
  `_rail_forward(dist)` — convert rail-local coordinates to world so all
  content placement follows the curved rail automatically
- Phase walls removed (replaced conceptually by slot gates)
- Megawreck reverted to the original 2-wall design (left + right hull plates
  with a central gap — no front/back blockers)

### Camera rewrite
- `rail_camera.gd` fully rewritten to follow the PathFollow3D's basis each
  frame — snaps position and orientation (no lerp) so the camera rides the
  curved rail like a second node
- `pole_length 10.0 → 8.5 → 7.25` (two rounds of "15% closer to the player")
- `pole_height = 1.5` (slightly above rail center)
- Dead zone / lateral pan **removed**: player requested the camera frustum
  cover the entire `move_bounds` rectangle so "what you see is always what
  the player can reach"

### Rail tree-membership bug
- `_create_path_visuals()` called `look_at()` on ring markers before adding
  them to the tree. Fixed with `look_at_from_position()` + parallel-axis
  guards.

### Gate positioning issue (ongoing)
- Gates are on "straight" sections, but Catmull-Rom tangents bend toward the
  first curved control point (`P2 = (20,-10,-160)`), so the "straight" P0→P1
  segment actually bends gently in its second half.
- **Attempted fix**: inserted an extra straight control point P1' at
  (0,0,-80) to get three collinear points and a fully-straight P0→P1 segment.
- **New bug**: caused a "weird camera snapping thing that rotates the view
  90° to the left and snaps back" — likely a `Curve3D` up-vector
  discontinuity when the three collinear points made Godot's internal
  reference-vector computation degenerate.
- **Current state**: rail reverted to original 11 points. Gate 1 at distance
  60 has a residual ~1° camera rotation from the P0→P1 tangent interpolation;
  gate 2 at distance 700 is in the P8→P9 near-straight finale. Still a TODO:
  find a clean way to give gate 1 a truly flat rail window (options: move
  the bent P2 further along, or move gate 1 to very early/very late).

---

## Player ship — movement, aim, and lasers

This was iterated **many times**. Current state at end of session:

### Movement (left stick)
- `move_speed: 15 → 12 → 9` (user wanted progressively slower strafing)
- `move_bounds: (12, 8) → (12, 5)` to keep the ship inside the camera frustum
- Wing-dip bank on strafe is `bank_lerp = 6.0` on `rotation.z`
- **Left stick strafes only** — no nose rotation from it

### Aim (right stick)
- **Right stick drives a virtual reticle** in path-local space
- Reticle state: `reticle_offset: Vector2`, bounded by
  `reticle_offset_max = (18, 10)`, living at `reticle_distance = 35` units
  ahead of the player along the rail
- Current tuned config:
  - `reticle_move_speed = 26.0`
  - `reticle_accel_ramp = 0.0` (instant)
  - `reticle_recenter_speed = 55.0`
  - X-axis velocity scaled by `reticle_offset_max.x / reticle_offset_max.y`
    so X and Y axes reach their respective maxes in the same time (the user
    originally said "X feels twice as slow")
- **Acceleration ramp was removed** after testing — instant felt best
- **Ship nose rotates directly** from the reticle (`rotation.x/y = aim_pitch/yaw`,
  no lerp). Previously used `aim_lerp`, removed because the reticle
  integration already smooths motion.
- `aim_yaw_limit_deg = 20`, `aim_pitch_limit_deg = 45` (side-to-side is
  narrower than up/down per user request)

### Drift-to-center behavior (hard-won, four iterations)
- Requirement: reticle drifts back to center **only when the stick is
  effectively at rest**. Any intentional tilt holds the reticle in place,
  AND brief zero-crossings (e.g. swinging from right to left) don't cause
  a recenter snap mid-gesture.
- **Attempt 1**: lowered threshold from `length > 0.1` to `length > 0.0`.
  Not enough — Godot's `Input.get_vector(...)` default deadzone zeroed the
  value before the stick physically returned home.
- **Attempt 2**: explicit `Input.get_vector(..., 0.0)`. Still didn't work
  because the individual **action** deadzones default to 0.5, so
  `get_action_strength` returned zero under that threshold.
- **Attempt 3**: `InputMap.action_set_deadzone("aim_*", 0.0)` in
  `game_manager.gd` so raw stick values propagate through the whole chain.
  This worked for hold-in-place but broke released-stick drift: hardware
  stick drift (~0.01–0.02 on typical Xbox controllers) kept `length() > 0`
  at rest, so the reticle never returned to center.
- **Attempt 4**: threshold bumped back to `> 0.05` — above drift noise,
  below any intentional tilt. Fixed resting behavior but introduced a new
  issue: swinging the stick from one direction to another crosses zero
  briefly, which triggered drift mid-gesture.
- **Final fix**: added `reticle_idle_time` accumulator with a
  `reticle_idle_threshold = 0.15s` grace window. The reticle only starts
  drifting once the stick has been below threshold for 150ms continuously.
  Brief zero-crossings (30–50ms typical) during direction changes don't
  count. Fully released stick still drifts after the 150ms delay.

### Laser firing
- `shoot_point` is a `Marker3D` child of `ship_visual` at local
  `Vector3(0, 0, -2.5)` — rotates with the ship's gimbal, on the centerline
- **Forward vector lock**: laser direction = `-ship_visual.global_transform.basis.z`
  (the ship's actual nose direction). *Not* toward the reticle — earlier
  that caused the laser to fire at a shallower angle than the ship was
  pitched, because the reticle sits 35u ahead while pitching moves the
  nose angle much more than the small world offset suggests.
- **Aim lerp raised to 18** so the nose tracks the reticle in ~50ms, keeping
  the visible nose direction and the crosshair in sync.
- `aim_lerp` is actually unused now because rotation is assigned directly
  — kept for a possible re-introduction
- Double-shot offsets use `ship_visual.global_transform.basis.x` (ship's
  own local right axis) so the two beams rotate with the ship through
  banking, sideways-flight tilt, and barrel rolls.
- Double-shot offset: `±0.6 → ±0.32` (beams closer to center to line up
  with the model's gun barrels)
- Laser mesh radii: main `0.05/0.09 → 0.035/0.065`, core `0.025/0.05 →
  0.018/0.035` (roughly 30% slimmer)
- `laser.speed: 70 → 140`
- Auto-seek removed from lasers entirely — missiles still track, lasers
  are skill shots

### Laser visual-alignment bugs
- Cylinder mesh was originally rotated `+90°` around X, which pointed the
  axis along world +Z regardless of direction. Fixed to `-90°` so it
  aligns with local -Z (Godot forward).
- **Laser `_ready` ran during `add_child` before `direction` was set**, so
  the in-`_ready` `look_at` was using the default `(0,0,-1)` and the
  trajectory was forever locked to rail forward. Fix: assign `laser.direction`
  *before* `add_child`, and also explicitly call `laser.look_at(...)` in
  `_fire_laser` after `global_position` is set.
- `_safe_up(dir)` helper returns `Vector3(0, 0, 1)` when `dir` is nearly
  parallel to world up, to avoid `look_at` gimbal lock.

### Boost visual
- While boosting, `ship_visual.position.z` lerps toward `-4.5` (forward
  along ship-local -Z). On release, lerps back to 0.
- `boost_visual_lerp = 3.5` (about 0.3s to reach target)
- Because `shoot_point` is a child of `ship_visual`, the muzzle moves
  with the ship during the surge so lasers stay attached visually.

### Yaw lock → re-enabled
- Originally the player asked to lock yaw entirely. Later they reversed
  course and asked for yaw back at ±20° (vs. ±45° pitch) so the ship has
  some horizontal wiggle for aiming.

### Auto-lock hijacking aim (big root-cause find)
- User reported "I couldn't move the nose up or down until halfway through
  the level". Traced to `_handle_lock_on` auto-accumulating a lock on any
  enemy that stays centered for 0.4s (no button required). Once a target
  was locked, the aim branch switched to target-driven pitch and ignored
  the stick.
- Fix: stick input is the primary source; target-lock aim only runs when
  the stick is idle. Later, target-lock was gated on **holding X** to match
  the missile tutorial.

### Missile controls
- `_handle_lock_on` now bails unless `Input.is_action_pressed("tracking_missile")`
- Missile firing moved from `is_action_just_pressed` to `is_action_just_released`
  (hold X to build locks, release to fire) to match the tutorial text
- Removed a leftover `print()` debug line

---

## Slot gates

- Registered in a new `GameManager.slot_gates: Array` (not `obstacle_aabbs`),
  so the player checks them in **path-local coordinates** — avoids the
  broken world-space AABB approximation of rotated box shapes on curved rails.
- Walls: `wall_width = 14`, `wall_height = 12`, `wall_thick = 1`,
  `gap_half = 0.4`. Fully covers the ±12 × ±5 `move_bounds` so the player
  **cannot** fly around or over.
- Player hitbox lerps from wide-flat `(0.6, 0.2, 0.75)` to tall-narrow
  `(0.2, 0.6, 0.75)` based on `abs(tilt_current) / (π/2)`. Rolling the ship
  is the only way through.
- Yellow warning bar removed (was cluttering the gap).
- Gate count iterated several times: `3 → 3 spread out → 2 spread out`.
  Current placement: distance 60 and 700.
- **Ongoing issue**: gate 1 at distance 60 still has a subtle camera bend
  because of the Catmull-Rom tangent toward the first curved control point.
  One attempted fix (inserting a straight collinear point) caused a 90°
  camera snap and was reverted. Still TODO.

---

## Escort section (Kiro cinematic entrance)

### Architecture
- State machine: `IDLE → ENTERING → HOLDING → EXITING → DONE`
- Ally is now a `Node3D` child of `path_follow` (not a separate `PathFollow3D`)
- Animation runs in path-local space

### ENTERING (3.5s)
- Ally arcs in from off-screen right: `(28, 3, -8) → (0, 2, -42)` with
  `sin(t*π) * 2.0` Y-arc peak
- Continuous 180°/s barrel roll to sell "dodging fire"
- Ease-in-out curve for organic motion
- `"Help! I can't shake them!"` comms fires at `t = 0.25` (when clearly on-screen)

### HOLDING
- Idle bob, roll straightens out
- **5 chasers spawn as children of `path_follow`** (not `enemies_container`)
  with `tracking_mode = true` and `custom_target = escort_ally`
- Chasers now follow Kiro's **full 3D position** (not just X/Y) because
  they share the path_follow parent and use path-local coordinates
- Chasers drain Kiro's HP at `5 DPS × N in range` while within 18 units
- Success: all chasers dead → `"Thanks! I owe you one."` + start EXITING

### EXITING (2.5s)
- Arcs to `(-32, 6, -95)` with another sine Y-arc
- Slower barrel roll

### DONE / failure
- HP hitting 0 → sets `GameManager.ally_kiro_lost = true` for boss phase,
  plays `"KIRO! ...dammit."` line

### Bug fixes along the way
- **First implementation: chasers never followed in Z** — they were world-space
  Area3Ds that only lerped `position.x/y`, and the ally's Z was advancing
  with the rail. Fixed by parenting chasers to `path_follow` and introducing
  `tracking_mode` that uses `position.lerp(target.position + offset, ...)`
  in local space.
- **Chasers were firing at the player instead of Kiro** — fixed by adding
  `custom_target` to `enemy_fighter.gd` and a `_get_focus()` helper that
  returns `custom_target` if set, else `GameManager.player`. Both the
  movement-toward target and the fire-at target now respect it.

---

## Tutorial system

- `game_world.gd` owns tutorial state: `tutorials: Array`,
  `tutorial_speed_mult`, `tutorial_slow_factor = 0.05`, `active_tutorial`,
  UI panel + label in a HUD canvas layer
- Rail advance is multiplied by `tutorial_speed_mult` so active tutorials
  crawl the game without freezing it
- Tutorials list (current):
  1. **`fire`** — `trigger_ratio = 0.0`, message `"HOLD RT / SPACE / TO FIRE
     YOUR WEAPONS"`, completes on first `player.total_shots_fired > 0`
  2. **`tilt`** — `trigger: "enemies_cleared"`, message `"HOLD L1 OR R1 /
     TO FLY SIDEWAYS"`, completes on `|tilt_current| > 60°`
  3. **`missile`** — `trigger: "escort_holding"`, message
     `"HOLD X TO LOCK ON / PRESS Y TO CYCLE TARGETS / RELEASE X TO FIRE"`,
     completes on `Input.is_action_pressed("tracking_missile")` (so the
     tutorial clears the moment the player starts holding, letting the
     lock-on animation play at normal speed)
- Two tutorial enemies spawned at rail distance 35 (flanking the player)
  so the fire tutorial has targets; they also gate the "enemies_cleared"
  trigger for the tilt tutorial
- New `player.total_shots_fired: int` counter, incremented in `_fire_laser`

---

## Enemies

- Added `custom_target: Node3D` for non-player targets
- Added `tracking_mode: bool` + `tracking_offset: Vector3` for escort chasers
  that are parented to path_follow and track targets in path-local space
- `_get_focus()` helper returns custom_target if set else `GameManager.player`;
  used by both movement and firing

---

## Boss notes (deferred)

Captured in `BOSS-NOTES.md`:

- Off-rails **free-flight arena** (Star Fox 64 "all-range mode" equivalent)
- Boundary box that **U-turns** the ship back into play
- Boss in arena center
- Surviving teammates help attack
- **Escort section consequence**: if Kiro is lost, he doesn't appear in the
  boss fight — `GameManager.ally_kiro_lost` is the hook

Implementation sketch (for future): unparent player from PathFollow3D,
switch to free-flight movement branch, spawn 6 `Area3D` boundary walls that
trigger a yaw flip + push-back on overlap, spawn boss + surviving teammates.

---

## HUD

- `hud.gd._update_crosshair()` now reads
  `player.get_reticle_world_position()` each frame and projects through
  `cam.unproject_position` so the crosshair tracks the actual aim point
  rather than sitting fixed at screen center
- Skips updates when the reticle is behind the camera to avoid projection
  wrap
- `get_reticle_world_position()` projects along the ship's actual forward
  direction (`-ship_visual.global_transform.basis.z * reticle_distance` from
  `shoot_point.global_position`), so the HUD reticle always sits exactly
  where a laser shot will go

---

## Input configuration changes

- **Aim action deadzones set to 0.0** (`game_manager.gd`) — critical for the
  reticle drift fix. Without this the default 0.5 action deadzone zeroed
  any stick input under 50% deflection, defeating the reticle's "hold in
  place until exactly zero" behavior.

---

## Project settings

- Suggested (not yet committed): enable fullscreen via `Project → Display
  → Window → Size → Mode = Fullscreen` or by adding `window/size/mode=3`
  to `[display]` in `project.godot`. User's complaint was the 1920×1080
  window was getting clipped by the screen.

---

## Still TODO / open issues

1. **Gate 1 camera tilt** — original problem still partially present. The
   Catmull-Rom tangent at `P1 = (0, 0, -90)` bends toward `P2 = (20, -10,
   -160)`, causing a subtle (~1°) camera yaw during gate 1's traversal.
   The clean fix is rail refactoring, but an inserted straight point caused
   a 90° up-vector snap. Open options:
   - Add an extra straight control point *and* manually set/disable up
     vectors in `Curve3D`
   - Move gate 1 very late or very early on the existing rail
   - Manually set point tangents instead of relying on Catmull-Rom
2. **Ally HP bar** — not yet added to the HUD during the escort section.
3. **Boss phase** — still just notes.
4. **Tutorial enemy damage during tutorial slow-mo** — noted earlier that
   Kiro's HP ticks at normal rate while the missile tutorial slows the
   game; could result in unfair losses. Not yet addressed.

---

## Notable commits

- `7dd82d6` — checkpoint before level 1 redesign
- `6b982c5` — feat: redesign level 1 as roller-coaster with slot gates and
  escort section

Subsequent iteration work is uncommitted and lives in the working tree.
