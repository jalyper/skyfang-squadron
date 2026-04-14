extends Area3D
## Player ship controller. Child of PathFollow3D — local position is the
## screen-space offset from the rail centre.
##
## Controls (Xbox):
##   Left stick  – move ship
##   R2          – fire normal shots
##   X           – fire tracking missiles at locked targets
##   A           – boost
##   L2          – brake
##   R1 / L1     – tilt ship 90° right / left (for narrow corridors)
##   B           – phase (semi-transparent, pass through obstacles 1 sec)

const LaserScript = preload("res://scripts/laser.gd")
const TrackingMissileScript = preload("res://scripts/tracking_missile.gd")
const ShipModel = preload("res://assets/models/Meshy_AI_space_ship_starfox__0410213457_texture.glb")

# ── Movement ──
var move_speed: float = 9.0
var move_bounds: Vector2 = Vector2(12.0, 5.0)
var bank_angle: float = 25.0
var bank_lerp: float = 6.0

# ── Gimbal aim (ship rotates to face joystick / locked target) ──
var aim_yaw_limit_deg: float = 20.0
var aim_pitch_limit_deg: float = 45.0
var aim_lerp: float = 18.0

# ── Right-stick reticle ──
# Right stick drives a virtual reticle in path-local space sitting at a
# fixed distance ahead of the ship. Lasers fire toward the reticle's
# world position; the HUD crosshair reads it and projects to the screen.
var reticle_offset: Vector2 = Vector2.ZERO
var reticle_offset_max: Vector2 = Vector2(18.0, 10.0)
var reticle_distance: float = 35.0
var reticle_move_speed: float = 26.0   # peak speed once the ramp completes
var reticle_accel_time: float = 0.0    # how long the stick has been held
var reticle_accel_ramp: float = 0.0    # seconds from start to peak speed (0 = instant)
var reticle_recenter_speed: float = 55.0  # drift-to-center when stick idle
# Short delay before drift kicks in, so briefly crossing zero while the
# player is changing aim direction doesn't snap the reticle toward center.
var reticle_idle_time: float = 0.0
var reticle_idle_threshold: float = 0.15

# ── Shooting ──
var fire_rate: float = 0.1
var fire_timer: float = 0.0
var total_shots_fired: int = 0
var double_shot: bool = false
var double_shot_timer: float = 0.0
var double_shot_duration: float = 15.0
var laser_energy: float = 100.0
var max_laser_energy: float = 100.0
var laser_drain_rate: float = 33.33    # depletes full bar in ~3 sec of continuous fire
var laser_recharge_rate: float = 33.33 # recharges full bar in ~3 sec
var laser_recharging: bool = false     # true when empty, blocks fire until partial refill

# ── Boost / brake ──
var boost_multiplier: float = 1.75
var brake_multiplier: float = 0.5
var boost_energy: float = 100.0
var max_boost_energy: float = 100.0
var is_boosting: bool = false
# Visual push-forward during boost (ship surges ahead of the rail, eases back)
var boost_visual_offset: float = 0.0
var boost_visual_target: float = -4.5
var boost_visual_lerp: float = 3.5

# ── Tilt (R1 / L1) + Barrel Roll (double-tap) ──
var tilt_current: float = 0.0
var tilt_speed: float = 18.0
var barrel_rolling: bool = false
var barrel_roll_timer: float = 0.0
var barrel_roll_duration: float = 0.4
var barrel_roll_direction: float = 0.0
var last_tilt_right_time: float = 0.0
var last_tilt_left_time: float = 0.0
var double_tap_window: float = 0.3

# ── Phase (B) ──
var is_phasing: bool = false
var phase_timer: float = 0.0
var phase_duration: float = 1.0
var phase_cooldown: float = 3.0
var phase_cd_timer: float = 0.0

# ── Lock-on ──
var max_locks: int = 1
var lock_range: float = 60.0
var lock_time_required: float = 0.4
var lock_candidate: Node3D = null
var lock_timer: float = 0.0
var locked_targets: Array = []
var missiles: int = 8

# ── Health ──
var health: float = 100.0
var max_health: float = 100.0
var invuln_timer: float = 0.0
var is_dead: bool = false

# ── Damage flash ──
var flash_timer: float = 0.0
var flash_duration: float = 0.25
var is_flashing: bool = false

# ── Score / Hits / Lives ──
var score: int = 0
var hit_count: int = 0
var lives: int = 3

# ── Node refs ──
var ship_visual: Node3D
var shoot_point: Marker3D

# ── Engine lights ──
var engine_lights: Array = []  # [{light, glow, glow_mat, trail_mesh, trail_points}]
var trail_fade_time: float = 0.5  # seconds before trail fully disappears

# ── Signals ──
signal health_changed(hp: float, hp_max: float)
signal boost_changed(val: float, val_max: float)
signal missiles_changed(count: int)
signal score_changed(pts: int)
signal hits_changed(count: int)
signal lives_changed(count: int)
signal laser_energy_changed(val: float, val_max: float)
signal phase_changed(is_active: bool, cooldown_ratio: float)
signal ship_destroyed


func _ready():
	add_to_group("player")
	_build_visuals()
	_build_collision()
	# shoot_point is parented to ship_visual so it rotates with the gimbal
	# and lasers fire from the ship's actual facing, not the rail direction.
	shoot_point = Marker3D.new()
	shoot_point.position = Vector3(0, 0, -2.5)
	ship_visual.add_child(shoot_point)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _process(delta):
	if is_dead:
		return
	_check_obstacle_collision()
	_handle_movement(delta)
	_handle_snap_target()
	_handle_shooting(delta)
	_handle_boost_brake(delta)
	_handle_tilt(delta)
	_handle_phase(delta)
	_handle_lock_on(delta)
	_handle_missile_fire()
	_handle_flash(delta)
	_update_engine_lights()
	if fire_timer > 0:
		fire_timer -= delta
	if invuln_timer > 0:
		invuln_timer -= delta
	if double_shot and double_shot_timer > 0:
		double_shot_timer -= delta
		if double_shot_timer <= 0:
			double_shot = false
	# Clean up locked targets that have been destroyed
	var valid: Array = []
	for t in locked_targets:
		if is_instance_valid(t):
			valid.append(t)
	locked_targets = valid


# ── Movement ──────────────────────────────────────────────────

func _handle_movement(delta):
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	position.x += input.x * move_speed * delta
	position.y -= input.y * move_speed * delta
	position.x = clampf(position.x, -move_bounds.x, move_bounds.x)
	position.y = clampf(position.y, -move_bounds.y, move_bounds.y)

	# Right stick integrates into the reticle offset. Drift-to-center only
	# kicks in once the stick is effectively at rest. Action deadzones are
	# set to 0 in game_manager so we get raw values; we use a tiny 0.05
	# threshold here to ignore hardware drift (Xbox sticks typically idle
	# around 0.01-0.02) while still responding to any intentional tilt.
	var aim_input := Input.get_vector("aim_left", "aim_right", "aim_up", "aim_down", 0.0)
	if aim_input.length() > 0.05:
		reticle_accel_time += delta
		reticle_idle_time = 0.0
		var ramp: float = 1.0
		if reticle_accel_ramp > 0.0:
			ramp = clampf(reticle_accel_time / reticle_accel_ramp, 0.0, 1.0)
		var current_speed: float = reticle_move_speed * ramp
		# X range is ~1.8× the Y range, so scale X velocity so both axes
		# take the same time to traverse from center to edge.
		var x_scale: float = reticle_offset_max.x / reticle_offset_max.y
		reticle_offset.x += aim_input.x * current_speed * x_scale * delta
		reticle_offset.y -= aim_input.y * current_speed * delta
	else:
		reticle_accel_time = 0.0
		# Delay the drift: brief zero-crossings while the player swings the
		# stick from one direction to another won't trigger recentering.
		reticle_idle_time += delta
		if reticle_idle_time >= reticle_idle_threshold:
			reticle_offset = reticle_offset.move_toward(Vector2.ZERO, reticle_recenter_speed * delta)
	reticle_offset.x = clampf(reticle_offset.x, -reticle_offset_max.x, reticle_offset_max.x)
	reticle_offset.y = clampf(reticle_offset.y, -reticle_offset_max.y, reticle_offset_max.y)

	# Wing dip from strafe (left stick) — bank only, no nose rotation.
	var strafe_bank := -input.x * deg_to_rad(bank_angle)

	# Ship's nose always tracks the reticle. When reticle drifts back to
	# center, the nose follows it home with the same easing.
	var aim_yaw := -(reticle_offset.x / reticle_offset_max.x) * deg_to_rad(aim_yaw_limit_deg)
	var aim_pitch := (reticle_offset.y / reticle_offset_max.y) * deg_to_rad(aim_pitch_limit_deg)

	# Combine tilt + strafe banking with aim. Pitch/yaw are set directly
	# (reticle movement already provides the smoothing). Z keeps its lerp
	# so wing-dip banking reads smoothly during strafe.
	var target_z := tilt_current + strafe_bank
	ship_visual.rotation.z = lerpf(ship_visual.rotation.z, target_z, bank_lerp * delta)
	ship_visual.rotation.x = aim_pitch
	ship_visual.rotation.y = aim_yaw


func get_reticle_world_position() -> Vector3:
	# Reticle is projected along the ship's actual forward direction so the
	# HUD crosshair always sits exactly where a laser shot would travel.
	# (Right stick drives the reticle_offset which drives the ship's nose
	# rotation; here we read the resulting nose forward and project out.)
	var forward: Vector3 = -ship_visual.global_transform.basis.z
	if forward.length_squared() < 0.0001:
		return shoot_point.global_position + Vector3(0, 0, -reticle_distance)
	return shoot_point.global_position + forward.normalized() * reticle_distance


func _nearest_locked_target() -> Node3D:
	var nearest: Node3D = null
	var nearest_dist := 9999.0
	for t in locked_targets:
		if is_instance_valid(t):
			var d: float = global_position.distance_to(t.global_position)
			if d < nearest_dist:
				nearest_dist = d
				nearest = t
	return nearest


# ── Snap to nearest enemy (Y) ─────────────────────────────────

var _snap_index: int = -1  # tracks position in the cycle

func _handle_snap_target():
	if not Input.is_action_just_pressed("snap_target"):
		return
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var screen_center := get_viewport().get_visible_rect().size / 2.0

	# Collect all visible enemies sorted by distance
	var candidates: Array = []
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy):
			continue
		var to_e: Vector3 = enemy.global_position - cam.global_position
		if to_e.dot(-cam.global_transform.basis.z) < 0:
			continue
		var world_dist: float = global_position.distance_to(enemy.global_position)
		candidates.append({"enemy": enemy, "dist": world_dist})

	if candidates.is_empty():
		return

	# Sort by distance (nearest first)
	candidates.sort_custom(func(a, b): return a["dist"] < b["dist"])

	# Cycle through candidates
	_snap_index = (_snap_index + 1) % candidates.size()
	var chosen: Node3D = candidates[_snap_index]["enemy"]

	# Instantly lock — no hover wait needed
	locked_targets.clear()
	locked_targets.append(chosen)
	lock_candidate = null
	lock_timer = 0.0


# ── Shooting (R2) ────────────────────────────────────────────

func _handle_shooting(delta):
	var trigger_held := Input.is_action_pressed("shoot")
	var can_fire := trigger_held and fire_timer <= 0 and not laser_recharging and laser_energy > 0

	if can_fire:
		_fire_laser()
		fire_timer = fire_rate

	# Drain continuously while trigger is held (not just per-shot)
	if trigger_held and laser_energy > 0 and not laser_recharging:
		laser_energy = maxf(laser_energy - laser_drain_rate * delta, 0.0)
		if laser_energy <= 0:
			laser_recharging = true
		laser_energy_changed.emit(laser_energy, max_laser_energy)
	elif not trigger_held and laser_energy < max_laser_energy:
		# Recharge only when trigger is released
		laser_energy = minf(laser_energy + laser_recharge_rate * delta, max_laser_energy)
		if laser_recharging and laser_energy >= max_laser_energy * 0.25:
			laser_recharging = false
		laser_energy_changed.emit(laser_energy, max_laser_energy)


func _fire_laser():
	if GameManager.projectiles_container == null:
		return
	# Laser is physically locked to the ship: it fires in the ship's own
	# forward direction (ship_visual -Z), from the shoot_point which is
	# parented to ship_visual and positioned on the model's centerline.
	# This guarantees the bolt always leaves straight out the nose no
	# matter how the ship is rotated or rolled.
	var forward: Vector3 = -ship_visual.global_transform.basis.z
	if forward.length_squared() < 0.0001:
		forward = Vector3(0, 0, -1)
	forward = forward.normalized()
	# Double-shot offsets use the ship's local right axis so the muzzles
	# sit on the wings and roll with the ship.
	var right: Vector3 = ship_visual.global_transform.basis.x.normalized()
	if right.length_squared() < 0.0001:
		right = Vector3(1, 0, 0)
	total_shots_fired += 1

	# IMPORTANT: assign direction BEFORE add_child. The laser's _ready runs
	# inside add_child and calls look_at based on direction — if we set
	# direction afterward, the visual stays locked to the default -Z and
	# every shot appears to fly along the rails.
	if double_shot:
		for offset in [-0.32, 0.32]:
			var laser := Area3D.new()
			laser.set_script(LaserScript)
			laser.direction = forward
			GameManager.projectiles_container.add_child(laser)
			laser.global_position = shoot_point.global_position + right * offset
			laser.look_at(laser.global_position + forward, _safe_up(forward))
	else:
		var laser := Area3D.new()
		laser.set_script(LaserScript)
		laser.direction = forward
		GameManager.projectiles_container.add_child(laser)
		laser.global_position = shoot_point.global_position
		laser.look_at(laser.global_position + forward, _safe_up(forward))


func _safe_up(dir: Vector3) -> Vector3:
	if absf(dir.dot(Vector3.UP)) > 0.99:
		return Vector3(0, 0, 1)
	return Vector3.UP


func activate_double_shot():
	double_shot = true
	double_shot_timer = double_shot_duration


func heal(amount: float):
	health = minf(health + amount, max_health)
	health_changed.emit(health, max_health)


# ── Boost / Brake ─────────────────────────────────────────────

func _handle_boost_brake(delta):
	var gw = GameManager.game_world
	if gw == null:
		return
	if Input.is_action_pressed("boost") and boost_energy > 0:
		gw.current_speed = gw.rail_speed * boost_multiplier
		boost_energy = maxf(boost_energy - 30.0 * delta, 0.0)
		is_boosting = true
	elif Input.is_action_pressed("brake"):
		gw.current_speed = gw.rail_speed * brake_multiplier
		is_boosting = false
	else:
		gw.current_speed = gw.rail_speed
		boost_energy = minf(boost_energy + 15.0 * delta, max_boost_energy)
		is_boosting = false
	boost_changed.emit(boost_energy, max_boost_energy)

	# Visual surge: push ship_visual forward along its own -Z when boosting,
	# ease back to 0 when the boost ends.
	var target_offset: float = boost_visual_target if is_boosting else 0.0
	boost_visual_offset = lerpf(boost_visual_offset, target_offset, boost_visual_lerp * delta)
	ship_visual.position.z = boost_visual_offset


# ── Tilt (R1 / L1) + Barrel Roll (double-tap) ────────────────

func _handle_tilt(delta):
	var now := Time.get_ticks_msec() / 1000.0

	# Detect double-tap for barrel roll (direction matches tilt direction)
	if Input.is_action_just_pressed("tilt_right"):
		if now - last_tilt_right_time < double_tap_window and not barrel_rolling:
			_start_barrel_roll(-1.0)  # R1 = tilt right = roll right (negative Z)
		last_tilt_right_time = now
	if Input.is_action_just_pressed("tilt_left"):
		if now - last_tilt_left_time < double_tap_window and not barrel_rolling:
			_start_barrel_roll(1.0)  # L1 = tilt left = roll left (positive Z)
		last_tilt_left_time = now

	# Handle barrel roll animation — 3 full rotations in 0.6 sec (fidget spinner)
	if barrel_rolling:
		barrel_roll_timer -= delta
		# 5 full rotations (10*PI) in barrel_roll_duration — spinning fan
		var roll_speed := (10.0 * PI) / barrel_roll_duration
		ship_visual.rotation.z += barrel_roll_direction * roll_speed * delta
		_deflect_nearby_projectiles()
		_update_barrel_roll_trail(delta)
		if barrel_roll_timer <= 0:
			barrel_rolling = false
			_clear_barrel_roll_trail()
			# Snap rotation to nearest upright so there's no unwinding animation
			ship_visual.rotation.z = 0.0
		return  # skip normal tilt during roll

	# Normal tilt
	var target := 0.0
	if Input.is_action_pressed("tilt_right"):
		target = deg_to_rad(-90.0)
	elif Input.is_action_pressed("tilt_left"):
		target = deg_to_rad(90.0)
	tilt_current = lerpf(tilt_current, target, tilt_speed * delta)


func _start_barrel_roll(dir: float):
	barrel_rolling = true
	barrel_roll_timer = barrel_roll_duration
	barrel_roll_direction = dir
	_create_barrel_roll_trail()


func _deflect_nearby_projectiles():
	var deflect_range := 5.0
	for proj in get_tree().get_nodes_in_group("enemy_projectiles"):
		if not is_instance_valid(proj):
			continue
		if global_position.distance_to(proj.global_position) < deflect_range:
			if proj.has_method("deflect"):
				proj.deflect()


# ── Barrel Roll Spin Trail (tapering ring) ────────────────────

var roll_trail: MeshInstance3D = null
var roll_trail_mat: StandardMaterial3D = null
var roll_trail_mesh: TorusMesh = null

func _create_barrel_roll_trail():
	roll_trail = MeshInstance3D.new()
	roll_trail_mesh = TorusMesh.new()
	roll_trail_mesh.inner_radius = 1.05  # thin ring
	roll_trail_mesh.outer_radius = 1.15
	roll_trail_mesh.rings = 20
	roll_trail_mesh.ring_segments = 32
	roll_trail.mesh = roll_trail_mesh
	roll_trail.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	roll_trail_mat = StandardMaterial3D.new()
	roll_trail_mat.albedo_color = Color(0.3, 0.7, 1.0, 0.7)
	roll_trail_mat.emission_enabled = true
	roll_trail_mat.emission = Color(0.3, 0.6, 1.0)
	roll_trail_mat.emission_energy_multiplier = 5.0
	roll_trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	roll_trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	roll_trail.material_override = roll_trail_mat

	roll_trail.rotation_degrees.x = 90
	roll_trail.position = Vector3(0, 0, 0)
	add_child(roll_trail)


func _update_barrel_roll_trail(_delta):
	if roll_trail == null or roll_trail_mat == null or roll_trail_mesh == null:
		return
	# Taper: ring gets thinner as the roll progresses
	var progress := 1.0 - (barrel_roll_timer / barrel_roll_duration)  # 0 at start → 1 at end
	# Thickness tapers from 0.10 down to 0.02
	var thickness := lerpf(0.10, 0.02, progress)
	roll_trail_mesh.inner_radius = 1.05
	roll_trail_mesh.outer_radius = 1.05 + thickness
	# Alpha also fades out
	var alpha := lerpf(0.7, 0.1, progress)
	roll_trail_mat.albedo_color.a = alpha
	roll_trail_mat.emission_energy_multiplier = lerpf(5.0, 1.0, progress)


func _clear_barrel_roll_trail():
	if roll_trail:
		roll_trail.queue_free()
		roll_trail = null
		roll_trail_mat = null
		roll_trail_mesh = null


# ── Phase (B) ────────────────────────────────────────────────

func _handle_phase(delta):
	if phase_cd_timer > 0:
		phase_cd_timer -= delta

	if is_phasing:
		phase_timer -= delta
		# Pulsing effect while phasing
		var pulse := 0.15 + sin(Time.get_ticks_msec() * 0.01) * 0.12
		_update_phase_pulse(pulse)
		if phase_timer <= 0:
			_end_phase()
	elif Input.is_action_just_pressed("phase") and phase_cd_timer <= 0:
		_start_phase()

	var cd_ratio := 0.0
	if is_phasing:
		cd_ratio = phase_timer / phase_duration
	elif phase_cd_timer > 0:
		cd_ratio = -(phase_cd_timer / phase_cooldown)
	phase_changed.emit(is_phasing, cd_ratio)


func _start_phase():
	is_phasing = true
	phase_timer = phase_duration
	monitoring = false
	monitorable = false


func _end_phase():
	is_phasing = false
	phase_cd_timer = phase_cooldown
	monitoring = true
	monitorable = true
	_clear_material_overrides(ship_visual)


func _update_phase_pulse(alpha: float):
	_apply_phase_recursive(ship_visual, alpha)


func _apply_phase_recursive(node: Node, alpha: float):
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.3, 0.6, 1.0, alpha)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.5, 1.0)
		# Pulse the emission energy
		var pulse_energy := 1.0 + sin(Time.get_ticks_msec() * 0.012) * 0.8
		mat.emission_energy_multiplier = pulse_energy
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		node.material_override = mat
	for child in node.get_children():
		_apply_phase_recursive(child, alpha)


func _clear_material_overrides(node: Node):
	if node is MeshInstance3D:
		node.material_override = null
	for child in node.get_children():
		_clear_material_overrides(child)


# ── Lock-on (enemies near screen center auto-lock) ───────────

func _handle_lock_on(delta):
	# Lock-on only runs while the player is actively holding the tracking
	# missile button (X). Releasing clears the candidate and accumulator so
	# the tutorial "HOLD X TO LOCK ON / RELEASE TO FIRE" matches reality.
	if not Input.is_action_pressed("tracking_missile"):
		lock_candidate = null
		lock_timer = 0.0
		return

	# Clean up invalid candidate
	if lock_candidate != null and not is_instance_valid(lock_candidate):
		lock_candidate = null
		lock_timer = 0.0

	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return

	var screen_center := get_viewport().get_visible_rect().size / 2.0

	# Find enemy closest to screen center
	var best_enemy: Node3D = null
	var best_screen_dist := 120.0  # pixel radius from center

	for enemy in get_tree().get_nodes_in_group("enemies"):
		if not is_instance_valid(enemy) or enemy in locked_targets:
			continue
		var to_e: Vector3 = enemy.global_position - cam.global_position
		if to_e.dot(-cam.global_transform.basis.z) < 0:
			continue
		var world_dist: float = global_position.distance_to(enemy.global_position)
		if world_dist > lock_range:
			continue
		var spos := cam.unproject_position(enemy.global_position)
		var d := spos.distance_to(screen_center)
		if d < best_screen_dist:
			best_screen_dist = d
			best_enemy = enemy

	if best_enemy != null and best_enemy == lock_candidate:
		lock_timer += delta
		if lock_timer >= lock_time_required and locked_targets.size() < max_locks:
			locked_targets.append(best_enemy)
			lock_timer = 0.0
			lock_candidate = null
	elif best_enemy != null:
		lock_candidate = best_enemy
		lock_timer = 0.0
	else:
		if lock_timer > 0:
			lock_timer = maxf(lock_timer - delta * 2.0, 0.0)  # decay slowly
		if lock_timer <= 0:
			lock_candidate = null


# ── Fire tracking missiles (X) ───────────────────────────────

func _handle_missile_fire():
	# Match the tutorial: hold X to build locks, release to fire them.
	if Input.is_action_just_released("tracking_missile"):
		if locked_targets.size() > 0 and missiles > 0:
			_fire_tracking_missiles()


func _fire_tracking_missiles():
	if GameManager.projectiles_container == null:
		return
	var fired := 0
	for t in locked_targets:
		if not is_instance_valid(t) or missiles <= 0:
			continue
		var missile := Area3D.new()
		missile.set_script(TrackingMissileScript)
		GameManager.projectiles_container.add_child(missile)
		missile.global_position = shoot_point.global_position
		missile.target = t
		missiles -= 1
		fired += 1
	locked_targets.clear()
	if fired > 0:
		missiles_changed.emit(missiles)


# ── Damage ────────────────────────────────────────────────────

func _check_obstacle_collision():
	if is_phasing or invuln_timer > 0 or is_dead:
		return
	var p := global_position
	# Player half-extents depend on roll. Flat: wide + thin (1.2 x 0.4 x 1.5).
	# Rolled to ±90° (holding L1/R1): tall + narrow (0.4 x 1.2 x 1.5) — this is
	# what lets the ship fit through vertical slot gates.
	var roll_norm: float = clampf(absf(tilt_current) / (PI / 2.0), 0.0, 1.0)
	var ph := Vector3(
		lerpf(0.6, 0.2, roll_norm),
		lerpf(0.2, 0.6, roll_norm),
		0.75,
	)
	for obs in GameManager.obstacle_aabbs:
		var o: Vector3 = obs["pos"]
		var h: Vector3 = obs["half"]
		if absf(p.x - o.x) < (ph.x + h.x) and absf(p.y - o.y) < (ph.y + h.y) and absf(p.z - o.z) < (ph.z + h.z):
			_die_explosion()
			return

	# Slot gates use path-local collision so they stay correct on curves.
	var parent := get_parent()
	if parent is PathFollow3D and GameManager.slot_gates.size() > 0:
		var pf: PathFollow3D = parent
		var rail_dist: float = pf.progress
		var lx: float = position.x
		var ly: float = position.y
		for slot in GameManager.slot_gates:
			var d_diff: float = absf(rail_dist - slot.dist)
			if d_diff > (slot.wall_half_thick + ph.z):
				continue
			var gap_half: float = slot.gap_half
			var ww: float = slot.wall_half_width
			var wh: float = slot.wall_half_height
			var left_center: float = -(gap_half + ww)
			var right_center: float = gap_half + ww
			var hit_left := absf(lx - left_center) < (ph.x + ww) and absf(ly) < (ph.y + wh)
			var hit_right := absf(lx - right_center) < (ph.x + ww) and absf(ly) < (ph.y + wh)
			if hit_left or hit_right:
				_die_explosion()
				return


func _on_area_entered(area: Area3D):
	if is_phasing:
		return
	if area.is_in_group("enemy_projectiles"):
		take_damage(15.0)
	elif area.is_in_group("phase_walls"):
		take_damage(25.0)
	elif area.is_in_group("hazards"):
		_die_explosion()
	elif area.is_in_group("enemies"):
		take_damage(30.0)


func _on_body_entered(_body: Node3D):
	# Hit a solid wall (StaticBody3D building) — instant death unless phasing
	if is_phasing:
		return
	_die_explosion()


func take_damage(amount: float):
	if is_phasing or invuln_timer > 0 or is_dead:
		return
	health -= amount
	invuln_timer = 0.5
	health_changed.emit(health, max_health)
	_start_flash()
	if health <= 0:
		_die_explosion()


func add_score(points: int):
	score += points
	score_changed.emit(score)


func add_hit():
	hit_count += 1
	hits_changed.emit(hit_count)


# ── Damage Flash (blink red) ─────────────────────────────────

func _start_flash():
	is_flashing = true
	flash_timer = flash_duration
	_apply_flash(ship_visual, true)


func _handle_flash(delta):
	if not is_flashing:
		return
	flash_timer -= delta
	# Blink: alternate red / normal every 0.05s
	var blink_on := fmod(flash_timer, 0.1) > 0.05
	_apply_flash(ship_visual, blink_on)
	if flash_timer <= 0:
		is_flashing = false
		if not is_phasing:
			_clear_material_overrides(ship_visual)


func _apply_flash(node: Node, red: bool):
	if node is MeshInstance3D:
		if red:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = Color(1.0, 0.15, 0.1)
			mat.emission_enabled = true
			mat.emission = Color(1.0, 0.1, 0.05)
			mat.emission_energy_multiplier = 3.0
			node.material_override = mat
		else:
			node.material_override = null
	for child in node.get_children():
		_apply_flash(child, red)


# ── Death Explosion ───────────────────────────────────────────

func _die_explosion():
	if is_dead:
		return
	is_dead = true
	health = 0
	health_changed.emit(0, max_health)
	ship_destroyed.emit()

	# Hide ship
	ship_visual.visible = false

	# Spawn explosion — large radiating orange/red sphere
	# Add to game world (not player) so it stays in world space
	var world_pos := global_position
	var game_root: Node3D = GameManager.game_world
	if game_root == null:
		return

	# Inner bright core
	var core := MeshInstance3D.new()
	var core_mesh := SphereMesh.new()
	core_mesh.radius = 1.0
	core_mesh.height = 2.0
	core.mesh = core_mesh
	core.position = world_pos
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(1.0, 1.0, 0.8)
	core_mat.emission_enabled = true
	core_mat.emission = Color(1.0, 0.9, 0.5)
	core_mat.emission_energy_multiplier = 12.0
	core_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = core_mat
	game_root.add_child(core)

	# Outer fireball
	var fireball := MeshInstance3D.new()
	var fb_mesh := SphereMesh.new()
	fb_mesh.radius = 2.0
	fb_mesh.height = 4.0
	fireball.mesh = fb_mesh
	fireball.position = world_pos
	fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fb_mat := StandardMaterial3D.new()
	fb_mat.albedo_color = Color(1.0, 0.4, 0.05, 0.8)
	fb_mat.emission_enabled = true
	fb_mat.emission = Color(1.0, 0.3, 0.0)
	fb_mat.emission_energy_multiplier = 6.0
	fb_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fb_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	fireball.material_override = fb_mat
	game_root.add_child(fireball)

	# Explosion light
	var light := OmniLight3D.new()
	light.position = world_pos
	light.light_color = Color(1.0, 0.5, 0.1)
	light.light_energy = 10.0
	light.omni_range = 30.0
	game_root.add_child(light)

	# Animate: expand + fade over 1 second
	var tween := game_root.create_tween()
	tween.set_parallel(true)
	# Core expands fast, fades
	tween.tween_property(core, "scale", Vector3(8, 8, 8), 0.6).set_ease(Tween.EASE_OUT)
	tween.tween_property(core_mat, "albedo_color", Color(1.0, 1.0, 0.8, 0.0), 0.6)
	# Fireball expands slower, fades slower
	tween.tween_property(fireball, "scale", Vector3(12, 12, 12), 1.0).set_ease(Tween.EASE_OUT)
	tween.tween_property(fb_mat, "albedo_color", Color(1.0, 0.2, 0.0, 0.0), 1.0)
	# Light fades
	tween.tween_property(light, "light_energy", 0.0, 0.8)
	tween.set_parallel(false)
	tween.tween_callback(func():
		core.queue_free()
		fireball.queue_free()
		light.queue_free()
	)


# ── Visual Construction ───────────────────────────────────────

func _build_visuals():
	ship_visual = Node3D.new()
	add_child(ship_visual)

	if ShipModel:
		var model := ShipModel.instantiate()
		model.scale = Vector3(1.0, 1.0, 1.0)
		model.rotation_degrees.y = -90
		ship_visual.add_child(model)
		_build_engine_lights()
	else:
		var mi := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(2.0, 0.4, 2.5)
		mi.mesh = mesh
		mi.rotation_degrees.x = -90
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.3, 0.5, 0.9)
		mi.material_override = mat
		ship_visual.add_child(mi)


func _build_engine_lights():
	var positions := [
		Vector3(-0.55, 0.0, 0.45),  # left engine
		Vector3(0.55, 0.0, 0.45),   # right engine
	]
	for pos in positions:
		# Engine nozzle glow
		var glow := MeshInstance3D.new()
		var glow_mesh := BoxMesh.new()
		glow_mesh.size = Vector3(0.06, 0.04, 0.02)
		glow.mesh = glow_mesh
		glow.position = pos
		glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var glow_mat := StandardMaterial3D.new()
		glow_mat.albedo_color = Color(0.85, 0.93, 1.0)
		glow_mat.emission_enabled = true
		glow_mat.emission = Color(0.8, 0.9, 1.0)
		glow_mat.emission_energy_multiplier = 15.0
		glow_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		glow.material_override = glow_mat
		ship_visual.add_child(glow)

		var light := OmniLight3D.new()
		light.position = pos
		light.light_color = Color(0.4, 0.65, 1.0)
		light.light_energy = 3.0
		light.omni_range = 3.0
		light.omni_attenuation = 1.5
		ship_visual.add_child(light)

		# Trail ribbon — ImmediateMesh drawn in world space
		var trail_mi := MeshInstance3D.new()
		trail_mi.mesh = ImmediateMesh.new()
		trail_mi.top_level = true  # ignore parent transform — vertices are world-space
		trail_mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var trail_mat := StandardMaterial3D.new()
		trail_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		trail_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
		trail_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		trail_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		trail_mat.vertex_color_use_as_albedo = true
		trail_mat.no_depth_test = true
		trail_mi.material_override = trail_mat
		# Add to game world root so it's in world space, not ship-local
		add_child(trail_mi)

		engine_lights.append({
			"light": light, "glow": glow, "glow_mat": glow_mat,
			"local_pos": pos, "trail_mesh": trail_mi,
			"trail_points": [],  # [{pos: Vector3, time: float}]
		})


func _update_engine_lights():
	var t := Time.get_ticks_msec() / 1000.0
	var now := Time.get_ticks_msec() / 1000.0
	var flicker := 0.95 + sin(t * 30.0) * 0.05
	var half_width := 0.015  # ribbon half-thickness — very thin flat stroke

	for entry in engine_lights:
		var light: OmniLight3D = entry["light"]
		var glow_mat: StandardMaterial3D = entry["glow_mat"]
		var trail_points: Array = entry["trail_points"]
		var trail_mi: MeshInstance3D = entry["trail_mesh"]
		var imesh: ImmediateMesh = trail_mi.mesh

		if is_boosting:
			light.light_color = Color(0.7, 0.85, 1.0)
			light.light_energy = 6.0 * flicker
			light.omni_range = 4.0
			glow_mat.albedo_color = Color(1.0, 1.0, 1.0)
			glow_mat.emission = Color(0.95, 0.97, 1.0)
			glow_mat.emission_energy_multiplier = 25.0 * flicker

			# Record current engine world position
			var local_pos: Vector3 = entry["local_pos"]
			var world_pos: Vector3 = ship_visual.global_transform * local_pos
			trail_points.append({"pos": world_pos, "time": now})
		else:
			light.light_color = Color(0.4, 0.65, 1.0)
			light.light_energy = 3.0 * flicker
			light.omni_range = 3.0
			glow_mat.albedo_color = Color(0.85, 0.93, 1.0)
			glow_mat.emission = Color(0.8, 0.9, 1.0)
			glow_mat.emission_energy_multiplier = 15.0 * flicker

		# Expire old points
		while trail_points.size() > 0 and (now - trail_points[0]["time"]) > trail_fade_time:
			trail_points.pop_front()

		# Rebuild ribbon mesh
		imesh.clear_surfaces()
		if trail_points.size() < 2:
			continue

		imesh.surface_begin(Mesh.PRIMITIVE_TRIANGLE_STRIP)
		for i in trail_points.size():
			var pt = trail_points[i]
			var age: float = now - pt["time"]
			var alpha: float = 1.0 - (age / trail_fade_time)
			alpha = clampf(alpha, 0.0, 1.0)

			# Color: bright white-blue near ship, fading out
			var col := Color(
				lerpf(0.5, 0.95, alpha),
				lerpf(0.7, 0.97, alpha),
				1.0,
				alpha * 0.8
			)

			var p: Vector3 = pt["pos"]
			# Flat horizontal ribbon — offset on Y axis
			imesh.surface_set_color(col)
			imesh.surface_add_vertex(p + Vector3(0, half_width, 0))
			imesh.surface_set_color(col)
			imesh.surface_add_vertex(p + Vector3(0, -half_width, 0))

		imesh.surface_end()


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 0.4, 1.5)
	col.shape = shape
	add_child(col)
