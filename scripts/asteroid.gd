extends Area3D
## Destructible asteroid hazard. Misshapen, slowly tumbles and drifts.
## Has a chance to drop a Double Shot powerup when destroyed.

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
	pickup.add_to_group("powerups")
	pickup.position = global_position

	# Glowing rotating icon
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = Vector3(0.8, 0.8, 0.8)
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.2, 1.0, 0.5, 0.9)
	mat.emission_enabled = true
	mat.emission = Color(0.1, 1.0, 0.4)
	mat.emission_energy_multiplier = 4.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mi.material_override = mat
	pickup.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5  # generous pickup radius
	col.shape = shape
	pickup.add_child(col)

	# Label
	var label_node := MeshInstance3D.new()
	var label_mesh := QuadMesh.new()
	label_mesh.size = Vector2(2.0, 0.6)
	label_node.mesh = label_mesh
	label_node.position.y = 1.2
	label_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var label_mat := StandardMaterial3D.new()
	label_mat.albedo_color = Color(0.2, 1.0, 0.5)
	label_mat.emission_enabled = true
	label_mat.emission = Color(0.1, 1.0, 0.4)
	label_mat.emission_energy_multiplier = 2.0
	label_mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	label_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	label_node.material_override = label_mat
	pickup.add_child(label_node)

	gw.add_child(pickup)

	# Connect pickup detection
	pickup.area_entered.connect(func(area: Area3D):
		if area.is_in_group("player"):
			var p = GameManager.player
			if p and p.has_method("activate_double_shot"):
				p.activate_double_shot()
			pickup.queue_free()
	)

	# Rotate and bob the pickup
	pickup.set_meta("_time", 0.0)
	pickup.set_process(true)
	var orig_y: float = global_position.y
	pickup.set_meta("_orig_y", orig_y)
	# Use a simple script-like approach via the tree
	var timer := Timer.new()
	timer.wait_time = 8.0
	timer.one_shot = true
	timer.timeout.connect(pickup.queue_free)
	pickup.add_child(timer)
	timer.start()


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
