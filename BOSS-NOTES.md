# Level 1 Boss — Design Notes

**Status:** Not yet implemented. Captured while redesigning Level 1's rail so
future work has context.

## Arena

- **Off-rails, free-flight arena** (Star Fox 64 "all-range mode" equivalent)
- Player leaves the rail at a set trigger and enters an open flight zone
- Large boundary box defines the play space; if the player crosses the boundary,
  the ship is forced into a **U-turn** back into the arena (same rebound feel as
  Star Fox 64 when you fly out of a boss area)
- Boss sits in the approximate **center of the arena**
- Surviving teammates join the player in the arena and attack alongside them

## Teammate Participation

- How many teammates are in the boss fight depends on earlier level events
- **Escort section consequence:** if the player fails to save their teammate
  during the chase/escort section of Level 1, that teammate is **absent** from
  the boss fight (one fewer ally helping attack)
- This is the main way the escort section creates a lasting stake

## Implementation Hooks (for future)

- `game_world.gd` already owns spawning; it will need a new "boss phase" that:
  1. Unparents the player from `PathFollow3D`
  2. Switches to free-flight movement (X/Y/Z, yaw + pitch)
  3. Instantiates a boundary box (probably 6 `Area3D` walls) that trigger U-turn
  4. Spawns the boss at arena center
  5. Spawns surviving teammates as ally ships circling the boss
- `player_ship.gd` will need a `free_flight_mode` branch in its movement code
- Boundary U-turn: when the player's Area3D overlaps a boundary wall, force a
  180° yaw and push the ship a few units back into the arena. Preserve velocity.

## Not Decided Yet

- Exact arena size
- Boss design (enemy, weak points, attack patterns)
- How free-flight camera behaves vs. the current chase cam
- Whether teammates are scripted attackers or have real combat AI
