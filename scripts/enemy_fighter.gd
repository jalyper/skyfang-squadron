extends Area3D
## Enemy fighter that weaves in a pattern and shoots at the player when in range.

const TurretBulletScript = preload("res://scripts/turret_bullet.gd")

var health: float = 30.0
var shoot_interval: float = 2.0
var shoot_timer: float = 1.5
var activation_dist: float = 60.0
var is_active: bool = false
var pattern_time: float = 0.0
var origin_pos: Vector3


func _ready():
	add_to_group("enemies")
	origin_pos = position
	_build_mesh()
	_build_collision()


func _process(delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	var dist := global_position.distance_to(gw.path_follow.global_position)

	if not is_active:
		if dist < activation_dist:
			is_active = true
		return

	# Weave pattern
	pattern_time += delta
	position.x = origin_pos.x + sin(pattern_time * 2.0) * 3.0
	position.y = origin_pos.y + cos(pattern_time * 1.5) * 1.5

	# Shoot
	shoot_timer -= delta
	if shoot_timer <= 0 and dist < 45.0:
		_fire()
		shoot_timer = shoot_interval

	# Cleanup if far behind camera
	if gw.path_follow.global_position.z < global_position.z - 30:
		queue_free()


func take_damage(amount: float):
	health -= amount
	if health <= 0:
		var p = GameManager.player
		if p and p.has_method("add_score"):
			p.add_score(100)
		queue_free()


func _fire():
	var player = GameManager.player
	if player == null or GameManager.projectiles_container == null:
		return

	var bullet := Area3D.new()
	bullet.set_script(TurretBulletScript)
	var dir: Vector3 = (player.global_position - global_position).normalized()
	bullet.set_meta("direction", dir)
	GameManager.projectiles_container.add_child(bullet)
	bullet.global_position = global_position


func _build_mesh():
	var mi := MeshInstance3D.new()
	var mesh := PrismMesh.new()
	mesh.size = Vector3(1.0, 0.2, 1.2)
	mi.mesh = mesh
	mi.rotation_degrees.x = -90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.8, 0.2, 0.2)
	mat.metallic = 0.5
	mat.roughness = 0.4
	mi.material_override = mat
	add_child(mi)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 0.4, 1.5)
	col.shape = shape
	add_child(col)
