extends Area3D
## Destructible asteroid hazard. Misshapen, slowly tumbles and drifts.
## Drops Double Shot or Shield pickups when destroyed.

const PickupScript = preload("res://scripts/pickup.gd")

var health: float = 40.0
var rot_speed: Vector3
var drift_speed: Vector3
var size: float = 2.0
var drop_chance: float = 0.4  # 40% chance to drop powerup


func _ready():
	add_to_group("hazards")
	add_to_group("enemies")  # targetable by lock-on and seeking lasers
	size = get_meta("size") if has_meta("size") else 2.0
	rot_speed = Vector3(
		randf_range(-0.8, 0.8),
		randf_range(-0.8, 0.8),
		randf_range(-0.5, 0.5)
	)
	drift_speed = Vector3(
		randf_range(-0.5, 0.5),
		randf_range(-0.3, 0.3),
		randf_range(-0.2, 0.2)
	)
	_build_mesh()
	_build_collision()


func _process(delta):
	rotation += rot_speed * delta
	position += drift_speed * delta


func take_damage(amount: float):
	health -= amount
	if health <= 0:
		var p = GameManager.player
		if p and p.has_method("add_score"):
			p.add_score(25)
			p.add_hit()
		# Chance to drop powerup
		if randf() < drop_chance:
			_spawn_powerup()
		_explode()
		queue_free()


func _explode():
	var gw = GameManager.game_world
	if gw == null:
		return
	# Small rocky explosion
	var debris := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.4
	debris.mesh = mesh
	debris.position = global_position
	debris.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.6, 0.4, 0.2, 0.8)
	mat.emission_enabled = true
	mat.emission = Color(0.8, 0.4, 0.1)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	debris.material_override = mat
	gw.add_child(debris)

	var tween := gw.create_tween()
	tween.set_parallel(true)
	tween.tween_property(debris, "scale", Vector3(4, 4, 4), 0.5).set_ease(Tween.EASE_OUT)
	tween.tween_property(mat, "albedo_color", Color(0.6, 0.4, 0.2, 0.0), 0.5)
	tween.set_parallel(false)
	tween.tween_callback(debris.queue_free)


func _spawn_powerup():
	var gw = GameManager.game_world
	if gw == null:
		return

	var pickup := Area3D.new()
	pickup.set_script(PickupScript)

	# 30% chance of shield, 70% double shot
	if randf() < 0.3:
		pickup.pickup_type = PickupScript.PickupType.SHIELD
	else:
		pickup.pickup_type = PickupScript.PickupType.DOUBLE_SHOT

	pickup.position = global_position
	gw.add_child(pickup)


func _build_mesh():
	# Create misshapen asteroid using multiple overlapping deformed spheres
	var num_lumps := randi_range(3, 5)
	for i in num_lumps:
		var mi := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		var lump_size := size * randf_range(0.3, 0.6)
		mesh.radius = lump_size
		mesh.height = lump_size * 2.0
		mi.mesh = mesh
		mi.position = Vector3(
			randf_range(-size * 0.2, size * 0.2),
			randf_range(-size * 0.15, size * 0.15),
			randf_range(-size * 0.2, size * 0.2)
		)
		mi.scale = Vector3(
			randf_range(0.6, 1.4),
			randf_range(0.5, 1.0),
			randf_range(0.6, 1.4)
		)

		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(
			randf_range(0.25, 0.5),
			randf_range(0.2, 0.4),
			randf_range(0.15, 0.3)
		)
		mat.roughness = 0.95
		mat.metallic = 0.1
		mi.material_override = mat
		add_child(mi)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = size * 0.5
	col.shape = shape
	add_child(col)
