# Skyfang Squadron

An on-rails 3D arcade shooter inspired by Star Fox 64, built in **Godot 4.6**.

Pilot Raze and his squadmates through four acts of city skylines, dense combat
zones, trench runs, and a debris field studded with a flyable megawreck.

## The Squad

- **Raze** (eagle) — player character
- **Kiro** (wolf) — rival
- **Nyx** (fox) — mediator
- **Bront** (bear) — protector

## Gameplay

- Fly a fixed rail from start to boss on a straight `Path3D` corridor
- Strafe within a screen-space window (±12 X, ±8 Y) to dodge hazards
- Shoot lasers, lock tracking missiles, boost, and phase through danger
- Destroy asteroids for powerups, dodge turret fire, and break fighter waves

## Level Layout

| Act | Theme           | Hazards                                      |
|-----|-----------------|----------------------------------------------|
| 1   | City            | Skyscrapers, narrow corridor walls           |
| 2   | Dense combat    | Skyscrapers, wrecks, transition zone         |
| 3   | Trench dive     | Box walls, overhanging beams, lodged wrecks  |
| 4   | Debris field    | Megawreck (flyable cavity), asteroids        |

## Architecture

Everything is built procedurally in code — no complex `.tscn` trees. The world
is assembled by `game_world.gd` at runtime.

```
GameWorld (Node3D)
├── WorldEnvironment, DirectionalLight3D
├── Stars (3 parallax layers) + Nebula
├── Path3D
│   └── PathFollow3D          (advances progress += speed * delta)
│       └── PlayerShip        (Area3D, local offset = screen-space position)
├── RailCamera
├── Enemies    (turrets, fighters, asteroids)
├── Hazards    (buildings, wrecks, walls, pickups)
└── Projectiles
```

### Key scripts

| Script               | Role                                            |
|----------------------|-------------------------------------------------|
| `game_world.gd`      | Main orchestrator — builds the level in code    |
| `player_ship.gd`     | Movement, shooting, boost, phase, collision     |
| `game_manager.gd`    | Autoload — global state, obstacle AABB registry |
| `turret.gd`          | Stationary turret enemy                         |
| `enemy_fighter.gd`   | Flying enemy                                    |
| `asteroid.gd`        | Destructible hazard                             |
| `hud.gd`             | UI overlay                                      |

## Running

1. Install [Godot 4.6](https://godotengine.org/download) (Forward+ renderer)
2. Open `project.godot` in the editor
3. Press F5 — main scene is `scenes/title_screen.tscn`

## Status

Prototype. See `SUMMARY.md` for current session notes and known issues.
