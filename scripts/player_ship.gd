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
const ShipModel = preload("res://assets/models/ship.glb")

# ── Movement ──
var move_speed: float = 15.0
var move_bounds: Vector2 = Vector2(12.0, 8.0)
var bank_angle: float = 25.0
var bank_lerp: float = 6.0

# ── Shooting ──
var fire_rate: float = 0.1
var fire_timer: float = 0.0
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

# ── Tilt (R1 / L1) + Barrel Roll (double-tap) ──
var tilt_current: float = 0.0
var tilt_speed: float = 8.0
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

# ── Engine burn ──
var engine_particles: GPUParticles3D
var engine_particle_mat: ParticleProcessMaterial
var engine_draw_mat: StandardMaterial3D
var engine_glow: MeshInstance3D
var engine_glow_mat: StandardMaterial3D
var engine_light: OmniLight3D

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
	_build_engine()
	_build_collision()
	shoot_point = Marker3D.new()
	shoot_point.position = Vector3(0, 0, -1.5)
	add_child(shoot_point)
	area_entered.connect(_on_area_entered)
	body_entered.connect(_on_body_entered)


func _process(delta):
	if is_dead:
		return
	_handle_movement(delta)
	_handle_snap_target()
	_handle_shooting(delta)
	_handle_boost_brake(delta)
	_handle_tilt(delta)
	_handle_phase(delta)
	_handle_lock_on(delta)
	_handle_missile_fire()
	_handle_flash(delta)
	_update_engine(delta)
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

	# Wing dip — bank toward strafe direction
	var strafe_bank := -input.x * deg_to_rad(bank_angle)
	var pitch_adj := input.y * deg_to_rad(10.0)

	# Combine tilt + strafe banking
	var target_z := tilt_current + strafe_bank
	ship_visual.rotation.z = lerpf(ship_visual.rotation.z, target_z, bank_lerp * delta)
	ship_visual.rotation.x = lerpf(ship_visual.rotation.x, pitch_adj, bank_lerp * delta)
	ship_visual.rotation.y = lerpf(ship_visual.rotation.y, 0.0, bank_lerp * delta)


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
	var forward: Vector3 = -get_parent().global_transform.basis.z
	var right: Vector3 = get_parent().global_transform.basis.x

	# Find nearest locked target for seeking
	var seek_target: Node3D = null
	if locked_targets.size() > 0:
		var nearest_dist := 9999.0
		for t in locked_targets:
			if is_instance_valid(t):
				var d: float = global_position.distance_to(t.global_position)
				if d < nearest_dist:
					nearest_dist = d
					seek_target = t

	if double_shot:
		# Two parallel streams offset left and right
		for offset in [-0.6, 0.6]:
			var laser := Area3D.new()
			laser.set_script(LaserScript)
			GameManager.projectiles_container.add_child(laser)
			laser.global_position = shoot_point.global_position + right * offset
			laser.direction = forward
			if seek_target:
				laser.target = seek_target
	else:
		var laser := Area3D.new()
		laser.set_script(LaserScript)
		GameManager.projectiles_container.add_child(laser)
		laser.global_position = shoot_point.global_position
		laser.direction = forward
		if seek_target:
			laser.target = seek_target


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
	if Input.is_action_just_pressed("tracking_missile"):
		print("X pressed — locks: ", locked_targets.size(), " missiles: ", missiles)
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


# ── Engine Burn Effect ────────────────────────────────────────
# GPUParticles3D exhaust: particles stream backward from the nozzle,
# fading from hot white-blue to transparent. Nozzle glow sphere + light.

func _build_engine():
	# ── Particle emitter ──
	engine_particles = GPUParticles3D.new()
	engine_particles.amount = 40
	engine_particles.lifetime = 0.4
	engine_particles.explosiveness = 0.0
	engine_particles.randomness = 0.2
	engine_particles.fixed_fps = 60
	engine_particles.local_coords = true
	engine_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	engine_particles.position = Vector3(0, 0, 0.7)  # nozzle exit

	# Process material — controls particle physics
	engine_particle_mat = ParticleProcessMaterial.new()
	engine_particle_mat.direction = Vector3(0, 0, 1)  # emit backward (+Z in local)
	engine_particle_mat.spread = 5.0
	engine_particle_mat.initial_velocity_min = 4.0
	engine_particle_mat.initial_velocity_max = 6.0
	engine_particle_mat.gravity = Vector3.ZERO
	engine_particle_mat.damping_min = 1.0
	engine_particle_mat.damping_max = 2.0

	# Scale: start small, shrink to nothing
	engine_particle_mat.scale_min = 0.8
	engine_particle_mat.scale_max = 1.2
	var scale_curve := CurveTexture.new()
	var sc := Curve.new()
	sc.add_point(Vector2(0.0, 1.0))
	sc.add_point(Vector2(0.4, 0.6))
	sc.add_point(Vector2(1.0, 0.0))
	scale_curve.curve = sc
	engine_particle_mat.scale_curve = scale_curve

	# Color: hot white-blue at start → blue → transparent
	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.85, 0.92, 1.0, 0.9),   # bright white-blue at nozzle
		Color(0.4, 0.6, 1.0, 0.6),     # blue mid-life
		Color(0.2, 0.4, 0.9, 0.0),     # fade to transparent
	])
	grad.offsets = PackedFloat32Array([0.0, 0.4, 1.0])
	color_ramp.gradient = grad
	engine_particle_mat.color_ramp = color_ramp

	engine_particles.process_material = engine_particle_mat

	# Draw pass — small billboard quad per particle
	var draw_mesh := QuadMesh.new()
	draw_mesh.size = Vector2(0.3, 0.3)
	engine_particles.draw_pass_1 = draw_mesh

	# Soft radial gradient texture — white center fading to transparent edges
	var soft_dot := GradientTexture2D.new()
	soft_dot.width = 64
	soft_dot.height = 64
	soft_dot.fill = GradientTexture2D.FILL_RADIAL
	soft_dot.fill_from = Vector2(0.5, 0.5)
	soft_dot.fill_to = Vector2(0.5, 0.0)
	var dot_grad := Gradient.new()
	dot_grad.colors = PackedColorArray([
		Color(1.0, 1.0, 1.0, 1.0),
		Color(1.0, 1.0, 1.0, 0.4),
		Color(1.0, 1.0, 1.0, 0.0),
	])
	dot_grad.offsets = PackedFloat32Array([0.0, 0.5, 1.0])
	soft_dot.gradient = dot_grad

	# Draw material — additive blending, billboard, soft texture
	engine_draw_mat = StandardMaterial3D.new()
	engine_draw_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	engine_draw_mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	engine_draw_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	engine_draw_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	engine_draw_mat.vertex_color_use_as_albedo = true
	engine_draw_mat.albedo_color = Color.WHITE
	engine_draw_mat.albedo_texture = soft_dot
	engine_draw_mat.no_depth_test = true
	draw_mesh.material = engine_draw_mat

	ship_visual.add_child(engine_particles)

	# ── Nozzle glow sphere ──
	engine_glow = MeshInstance3D.new()
	var glow_mesh := SphereMesh.new()
	glow_mesh.radius = 0.2
	glow_mesh.height = 0.4
	engine_glow.mesh = glow_mesh
	engine_glow.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	engine_glow.position = Vector3(0, 0, 0.65)

	engine_glow_mat = StandardMaterial3D.new()
	engine_glow_mat.albedo_color = Color(0.8, 0.9, 1.0, 0.9)
	engine_glow_mat.emission_enabled = true
	engine_glow_mat.emission = Color(0.7, 0.85, 1.0)
	engine_glow_mat.emission_energy_multiplier = 6.0
	engine_glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	engine_glow.material_override = engine_glow_mat
	ship_visual.add_child(engine_glow)

	# ── Point light ──
	engine_light = OmniLight3D.new()
	engine_light.position = Vector3(0, 0, 1.0)
	engine_light.light_color = Color(0.4, 0.6, 1.0)
	engine_light.light_energy = 1.5
	engine_light.omni_range = 5.0
	ship_visual.add_child(engine_light)


func _update_engine(_delta):
	if engine_particles == null:
		return

	var t := Time.get_ticks_msec() / 1000.0
	var flicker := 0.9 + sin(t * 25.0) * 0.08 + sin(t * 41.0) * 0.05

	if is_boosting:
		# Boost: more particles, faster, bigger, brighter
		engine_particles.amount = 80
		engine_particles.lifetime = 0.5
		engine_particle_mat.initial_velocity_min = 8.0
		engine_particle_mat.initial_velocity_max = 12.0
		engine_particle_mat.scale_min = 1.2
		engine_particle_mat.scale_max = 1.8
		engine_particle_mat.spread = 8.0

		engine_glow.scale = Vector3(1.5, 1.5, 1.5)
		engine_glow_mat.albedo_color = Color(1.0, 0.97, 0.95, 1.0)
		engine_glow_mat.emission = Color(1.0, 0.95, 0.85)
		engine_glow_mat.emission_energy_multiplier = 14.0 * flicker

		engine_light.light_energy = 5.0 * flicker
		engine_light.light_color = Color(0.5, 0.7, 1.0)
	else:
		# Normal cruise
		engine_particles.amount = 40
		engine_particles.lifetime = 0.4
		engine_particle_mat.initial_velocity_min = 4.0
		engine_particle_mat.initial_velocity_max = 6.0
		engine_particle_mat.scale_min = 0.8
		engine_particle_mat.scale_max = 1.2
		engine_particle_mat.spread = 5.0

		engine_glow.scale = Vector3(1.0, 1.0, 1.0)
		engine_glow_mat.albedo_color = Color(0.8, 0.9, 1.0, 0.9)
		engine_glow_mat.emission = Color(0.7, 0.85, 1.0)
		engine_glow_mat.emission_energy_multiplier = 6.0 * flicker

		engine_light.light_energy = 1.5 * flicker
		engine_light.light_color = Color(0.4, 0.6, 1.0)


# ── Visual Construction ───────────────────────────────────────

func _build_visuals():
	ship_visual = Node3D.new()
	add_child(ship_visual)

	if ShipModel:
		var model := ShipModel.instantiate()
		model.scale = Vector3(1.0, 1.0, 1.0)
		model.rotation_degrees.y = -90
		ship_visual.add_child(model)
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


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 0.4, 1.5)
	col.shape = shape
	add_child(col)
