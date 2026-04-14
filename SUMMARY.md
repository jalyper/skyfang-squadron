# Skyfang Squadron — Session Summary

## Project Overview
Star Fox 64 clone — on-rails 3D arcade shooter built entirely in **Godot 4.6** with procedural scene construction (no complex .tscn files). Everything is built in code via `game_world.gd`.

- **Repo**: `C:\Users\keato\repos\skyfang-squadron`
- **Engine**: Godot 4.6 (`D:\Godot`)
- **Game docs**: `C:\Users\keato\.gamedev\` (CONCEPT.md, PROTOTYPE-LOG.md)

## Architecture

### Scene Tree (runtime)
```
GameWorld (Node3D, game_world.gd)
├── WorldEnvironment, DirectionalLight3D
├── Stars (3 parallax layers)
├── Nebula (mesh blobs)
├── Path3D
│   └── PathFollow3D          ← moves along rail via progress += speed * delta
│       └── PlayerShip (Area3D, player_ship.gd)
│           ├── ship_visual (Node3D + GLB model)
│           ├── CollisionShape3D (BoxShape3D: 1.2 x 0.4 x 1.5)
│           └── Marker3D (shoot_point)
├── RailCamera (Camera3D)
├── Enemies (Node3D container — turrets, fighters, asteroids)
├── Hazards (Node3D container — buildings, wrecks, walls, pickups)
└── Projectiles (Node3D container — lasers, missiles, bullets)
```

### Rail System
- `Path3D` with straight `Curve3D` from `(0,0,0)` to `(0,0,-600)`
- `PathFollow3D` with `ROTATION_ORIENTED`, advances `progress += current_speed * delta` each frame
- Player is **child of PathFollow3D** — local position is screen-space offset (X ±12, Y ±8)
- Player `global_position` = PathFollow3D world pos + local offset

### Key Scripts

| Script | Lines | Role |
|--------|-------|------|
| `game_world.gd` | ~1064 | Main orchestrator — builds everything procedurally in `_ready()` |
| `player_ship.gd` | ~876 | Player controller — movement, shooting, boost, phase, collision |
| `game_manager.gd` | ~122 | Autoload singleton — global state, input config, obstacle_aabbs |
| `turret.gd` | ~117 | Stationary turret enemy |
| `enemy_fighter.gd` | ~192 | Flying enemy |
| `asteroid.gd` | ~135 | Destructible hazard |
| `hud.gd` | ~666 | UI overlay |

### Obstacle Spawning (game_world.gd)
All obstacles defined in `_create_buildings()` as arrays: `[position, type, scale, rotation]`

Three spawn functions:
1. **`_spawn_model_obstacle(pos, scene, scale, rot)`** — skyscrapers and small wrecks. Creates `StaticBody3D` with `CollisionShape3D(BoxShape3D)`. Registers AABB in `GameManager.obstacle_aabbs`.
2. **`_spawn_megawreck(pos, scale, rot)`** — large destroyed starship with flyable cavity. Creates 4 separate `StaticBody3D` nodes (front hull, back hull, left wall, right wall) with gap for player to fly through. Registers 4 AABBs.
3. **`_spawn_box_obstacle(pos, size)`** — corridor walls, trench walls, beams. Creates `StaticBody3D` with exact-size box. Registers AABB.

### Collision Detection — Three Layers
1. **`area_entered` signal** — player Area3D detects other Area3Ds (enemies, projectiles, asteroids in "hazards" group)
2. **`body_entered` signal** — player Area3D detects StaticBody3D (buildings, walls)
3. **Manual AABB check** — `_check_obstacle_collision()` in `_process()` polls `GameManager.obstacle_aabbs` array every frame, compares player `global_position` against registered obstacle boxes

### Enemy Behavior
- **Turrets**: activate within 60 units, fire within 45 units, now stops firing once player passes (Z check)
- **Fighters**: 6 waves, 13 total fighters (reduced from 10 waves / 33 fighters)
- **Asteroids**: destructible, drop powerups

## Changes Made This Session

### 1. Hitbox Size Reduction
- Building/wreck collision boxes: `0.6/1.2/0.6` → `0.35/0.8/0.35` multipliers
- Applied in `_spawn_model_obstacle()`

### 2. Enemy Count Reduction
- Turrets: 12 → 4 (one per act)
- Fighter waves: 10 waves / 33 fighters → 6 waves / 13 fighters

### 3. Turret Firing Fix
- Turrets now check `player_z < global_position.z - 5.0` to stop firing after player passes
- In `turret.gd` `_process()`

### 4. Megawreck U-shaped Collision
- Replaced single collision box with 4 separate StaticBody3D nodes:
  - Front hull (solid, full-width)
  - Back hull (solid, full-width)
  - Left wall (cavity edge)
  - Right wall (cavity edge)
  - 8-unit gap in center for player to fly through
- All added directly to `hazards_container` (not nested in Node3D container)

### 5. Manual AABB Collision System
- Added `obstacle_aabbs: Array` to `GameManager`
- All spawn functions register `{"pos": Vector3, "half": Vector3}` entries
- Player calls `_check_obstacle_collision()` every frame in `_process()`
- Compares `global_position` against all registered AABBs

## ACTIVE BLOCKER: Collision Detection Not Working

**The player can fly through ALL obstacles without dying.** This is the primary issue.

### What We've Tried (all failed)
1. **StaticBody3D + `body_entered` signal** — doesn't fire, likely because PathFollow3D teleports the player each frame (sets `progress` directly) so physics overlap detection misses
2. **Area3D in "hazards" group + `area_entered` signal** — same teleportation issue
3. **Nested StaticBody3D in Node3D container** — tried un-nesting to add directly to hazards_container, no change
4. **Manual AABB collision checking** — added `_check_obstacle_collision()` that polls every frame with pure math (no physics engine). Player `global_position` vs obstacle `pos + half-extents`. **This should work but doesn't.**

### What Has NOT Been Tried Yet
1. **Debug prints** — Add `print()` statements to `_check_obstacle_collision()` to verify:
   - Is `GameManager.obstacle_aabbs` populated? (check `.size()`)
   - What is `global_position` returning for the player?
   - What are the actual distances between player and obstacles?
   - Is the function even being called?
2. **Verify coordinate spaces** — PathFollow3D with `ROTATION_ORIENTED` might transform the player's local offset in unexpected ways for a straight -Z path
3. **Check if obstacle_aabbs is cleared** — something might reset the array between creation and gameplay
4. **Test with a hardcoded obstacle** — bypass the spawn system entirely, add a test AABB at a known position (e.g., `Vector3(0, 0, -50)` with huge half-extents) and see if it triggers

### Recommended Next Step
Add debug prints to `_check_obstacle_collision()` in `player_ship.gd`:
```gdscript
func _check_obstacle_collision():
    if is_phasing or invuln_timer > 0 or is_dead:
        return
    var p := global_position
    print("COLLISION CHECK: player_pos=", p, " aabb_count=", GameManager.obstacle_aabbs.size())
    # ... rest of function
```
Run the game, check the Godot output console, and verify the values make sense.

## Level Layout
The level is a straight rail from Z=0 to Z=-600, divided into 4 acts:

| Act | Z Range | Theme | Key Obstacles |
|-----|---------|-------|---------------|
| 1 | -30 to -135 | City | Skyscrapers, narrow corridor walls |
| 2 | -185 to -300 | Dense combat | Skyscrapers, wrecks, transition zone |
| 3 | -300 to -420 | Trench dive | Box walls, overhanging beams, lodged wrecks |
| 4 | -430 to -600 | Debris field | Megawreck (flyable cavity), scattered wrecks, asteroids |

## Squad
- **Raze** (eagle) — player character
- **Kiro** (wolf) — rival
- **Nyx** (fox) — mediator
- **Bront** (bear) — protector
