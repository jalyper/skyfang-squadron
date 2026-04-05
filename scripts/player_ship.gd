extends Area3D
## Player ship controller. Child of PathFollow3D — local position is the
## screen-space offset from the rail centre. Handles movement, shooting,
## boost/brake, deflect-spin, and tracking-missile lock-on.

const LaserScript = preload("res://scripts/laser.gd")
const TrackingMissileScript = preload("res://scripts/tracking_missile.gd")

# Movement
var move_speed: float = 15.0
var move_bounds: Vector2 = Vector2(12.0, 8.0)
var bank_angle: float = 35.0
var bank_lerp: float = 5.0

# Shooting
var fire_rate: float = 0.1
var fire_timer: float = 0.0

# Boost / brake
var boost_multiplier: float = 1.75
var brake_multiplier: float = 0.5
var boost_energy: float = 100.0
var max_boost_energy: float = 100.0

# Deflect spin
var spin_duration: float = 0.5
var spin_cooldown: float = 1.0
var is_spinning: bool = false
var spin_timer: float = 0.0
var spin_cd_timer: float = 0.0

# Tracking missile
var max_locks: int = 4
var lock_range: float = 60.0
var missiles: int = 5
var locked_targets: Array = []
var is_locking: bool = false

# Health
var health: float = 100.0
var max_health: float = 100.0
var invuln_timer: float = 0.0

# Score
var score: int = 0

# Node refs
var ship_mesh: MeshInstance3D
var shoot_point: Marker3D

# Signals
signal health_changed(hp: float, hp_max: float)
signal boost_changed(val: float, val_max: float)
signal missiles_changed(count: int)
signal score_changed(pts: int)
signal ship_destroyed


func _ready():
	add_to_group("player")
	_build_visuals()
	_build_collision()
	shoot_point = Marker3D.new()
	shoot_point.position = Vector3(0, 0, -1.5)
	add_child(shoot_point)
	area_entered.connect(_on_area_entered)


func _process(delta):
	_handle_movement(delta)
	_handle_shooting(delta)
	_handle_boost_brake(delta)
	_handle_spin(delta)
	_handle_tracking_missile()
	if fire_timer > 0:
		fire_timer -= delta
	if invuln_timer > 0:
		invuln_timer -= delta


# ── Movement ──────────────────────────────────────────────────

func _handle_movement(delta):
	var input := Input.get_vector("move_left", "move_right", "move_up", "move_down")

	position.x += input.x * move_speed * delta
	position.y -= input.y * move_speed * delta
	position.x = clampf(position.x, -move_bounds.x, move_bounds.x)
	position.y = clampf(position.y, -move_bounds.y, move_bounds.y)

	if not is_spinning:
		var target_roll := -input.x * deg_to_rad(bank_angle)
		var base_pitch := deg_to_rad(-90.0)
		var target_pitch := base_pitch + input.y * deg_to_rad(15.0)
		ship_mesh.rotation.z = lerpf(ship_mesh.rotation.z, target_roll, bank_lerp * delta)
		ship_mesh.rotation.x = lerpf(ship_mesh.rotation.x, target_pitch, bank_lerp * delta)


# ── Shooting ──────────────────────────────────────────────────

func _handle_shooting(_delta):
	if Input.is_action_pressed("shoot") and fire_timer <= 0:
		_fire_laser()
		fire_timer = fire_rate


func _fire_laser():
	if GameManager.projectiles_container == null:
		return
	var laser := Area3D.new()
	laser.set_script(LaserScript)
	GameManager.projectiles_container.add_child(laser)
	laser.global_position = shoot_point.global_position
	laser.direction = -get_parent().global_transform.basis.z


# ── Boost / Brake ─────────────────────────────────────────────

func _handle_boost_brake(delta):
	var gw = GameManager.game_world
	if gw == null:
		return
	if Input.is_action_pressed("boost") and boost_energy > 0:
		gw.current_speed = gw.rail_speed * boost_multiplier
		boost_energy = maxf(boost_energy - 30.0 * delta, 0.0)
	elif Input.is_action_pressed("brake"):
		gw.current_speed = gw.rail_speed * brake_multiplier
	else:
		gw.current_speed = gw.rail_speed
		boost_energy = minf(boost_energy + 15.0 * delta, max_boost_energy)
	boost_changed.emit(boost_energy, max_boost_energy)


# ── Deflect Spin ──────────────────────────────────────────────

func _handle_spin(delta):
	if spin_cd_timer > 0:
		spin_cd_timer -= delta
	if is_spinning:
		spin_timer -= delta
		ship_mesh.rotation.z += 25.0 * delta
		if spin_timer <= 0:
			is_spinning = false
			spin_cd_timer = spin_cooldown
	elif Input.is_action_just_pressed("deflect_spin") and spin_cd_timer <= 0:
		is_spinning = true
		spin_timer = spin_duration


# ── Tracking Missile ──────────────────────────────────────────

func _handle_tracking_missile():
	if Input.is_action_just_pressed("tracking_missile") and missiles > 0:
		is_locking = true
		locked_targets.clear()
	if is_locking and Input.is_action_pressed("tracking_missile"):
		_scan_for_locks()
	if is_locking and Input.is_action_just_released("tracking_missile"):
		is_locking = false
		if locked_targets.size() > 0:
			_fire_tracking_missiles()


func _scan_for_locks():
	var cam := get_viewport().get_camera_3d()
	if cam == null:
		return
	var screen_center := get_viewport().get_visible_rect().size / 2.0
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if locked_targets.size() >= max_locks:
			break
		if enemy in locked_targets or not is_instance_valid(enemy):
			continue
		var spos := cam.unproject_position(enemy.global_position)
		if spos.distance_to(screen_center) < 150.0:
			if global_position.distance_to(enemy.global_position) < lock_range:
				locked_targets.append(enemy)


func _fire_tracking_missiles():
	if GameManager.projectiles_container == null:
		return
	for t in locked_targets:
		if not is_instance_valid(t) or missiles <= 0:
			continue
		var missile := Area3D.new()
		missile.set_script(TrackingMissileScript)
		GameManager.projectiles_container.add_child(missile)
		missile.global_position = shoot_point.global_position
		missile.target = t
		missiles -= 1
		missiles_changed.emit(missiles)
	locked_targets.clear()


# ── Damage ────────────────────────────────────────────────────

func _on_area_entered(area: Area3D):
	if is_spinning and area.is_in_group("enemy_projectiles"):
		area.queue_free()
		return
	if area.is_in_group("enemy_projectiles"):
		take_damage(15.0)
	elif area.is_in_group("hazards"):
		take_damage(20.0)
	elif area.is_in_group("enemies"):
		take_damage(30.0)


func take_damage(amount: float):
	if is_spinning or invuln_timer > 0:
		return
	health -= amount
	invuln_timer = 0.5
	health_changed.emit(health, max_health)
	if health <= 0:
		ship_destroyed.emit()


func add_score(points: int):
	score += points
	score_changed.emit(score)


# ── Visual Construction ───────────────────────────────────────

func _build_visuals():
	ship_mesh = MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(2.0, 0.4, 2.5)
	ship_mesh.mesh = mesh
	ship_mesh.rotation_degrees.x = -90  # apex points forward (-Z)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 0.5, 0.9)
	mat.metallic = 0.7
	mat.roughness = 0.3
	ship_mesh.material_override = mat
	add_child(ship_mesh)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.8, 0.5, 2.0)
	col.shape = shape
	add_child(col)
