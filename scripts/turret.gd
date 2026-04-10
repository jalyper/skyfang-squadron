extends Area3D
## Stationary turret that aims and fires at the player when in range.

const TurretBulletScript = preload("res://scripts/turret_bullet.gd")

var health: float = 50.0
var shoot_interval: float = 0.7   # rapid fire
var shoot_timer: float = 0.5
var activation_dist: float = 60.0
var is_active: bool = false
var gun_pivot: Node3D


func _ready():
	add_to_group("enemies")
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

	# Aim at player
	var player = GameManager.player
	if player and gun_pivot:
		var target_pos: Vector3 = player.global_position
		gun_pivot.look_at(target_pos, Vector3.UP)

	# Shoot
	shoot_timer -= delta
	if shoot_timer <= 0 and dist < 45.0:
		_fire()
		shoot_timer = shoot_interval


func take_damage(amount: float):
	health -= amount
	if health <= 0:
		var p = GameManager.player
		if p and p.has_method("add_score"):
			p.add_score(150)
			p.add_hit()
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
	bullet.global_position = global_position + Vector3(0, 0.8, 0)


func _build_mesh():
	# Base cylinder
	var base := MeshInstance3D.new()
	var bmesh := CylinderMesh.new()
	bmesh.top_radius = 0.8
	bmesh.bottom_radius = 1.0
	bmesh.height = 1.0
	base.mesh = bmesh

	var bmat := StandardMaterial3D.new()
	bmat.albedo_color = Color(0.4, 0.4, 0.4)
	bmat.metallic = 0.8
	base.material_override = bmat
	add_child(base)

	# Gun barrel (on pivot)
	gun_pivot = Node3D.new()
	gun_pivot.position.y = 0.6
	add_child(gun_pivot)

	var barrel := MeshInstance3D.new()
	var gmesh := CylinderMesh.new()
	gmesh.top_radius = 0.12
	gmesh.bottom_radius = 0.18
	gmesh.height = 1.4
	barrel.mesh = gmesh
	barrel.rotation_degrees.x = 90
	barrel.position.z = -0.7

	var gmat := StandardMaterial3D.new()
	gmat.albedo_color = Color(0.6, 0.2, 0.2)
	gmat.metallic = 0.7
	barrel.material_override = gmat
	gun_pivot.add_child(barrel)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := CylinderShape3D.new()
	shape.radius = 1.0
	shape.height = 1.5
	col.shape = shape
	add_child(col)
