extends Area3D
## Enemy fighter that weaves in a pattern and shoots at the player when in range.

const TurretBulletScript = preload("res://scripts/turret_bullet.gd")
const ShipModel = preload("res://assets/models/ship.glb")

var health: float = 30.0
var is_dying: bool = false
var shoot_interval: float = 0.8   # fires much faster
var shoot_timer: float = 0.5
var activation_dist: float = 70.0  # activates sooner
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

	var player = GameManager.player
	pattern_time += delta

	# Smart movement: strafe toward player's lateral position, weave unpredictably
	if player and is_instance_valid(player):
		var player_x: float = player.global_position.x
		var player_y: float = player.global_position.y
		# Drift toward player's lane but weave around it
		var target_x := player_x + sin(pattern_time * 3.0 + origin_pos.x) * 5.0
		var target_y := player_y + cos(pattern_time * 2.0 + origin_pos.y) * 3.0
		position.x = lerpf(position.x, target_x, 1.5 * delta)
		position.y = lerpf(position.y, target_y, 1.5 * delta)
	else:
		position.x = origin_pos.x + sin(pattern_time * 2.0) * 3.0
		position.y = origin_pos.y + cos(pattern_time * 1.5) * 1.5

	# Shoot — lead the target slightly
	shoot_timer -= delta
	if shoot_timer <= 0 and dist < 50.0:
		_fire()
		shoot_timer = randf_range(shoot_interval * 0.7, shoot_interval * 1.3)

	# Cleanup if far behind camera
	if gw.path_follow.global_position.z < global_position.z - 30:
		queue_free()


func take_damage(amount: float):
	if is_dying:
		return
	health -= amount
	if health <= 0:
		is_dying = true
		var p = GameManager.player
		if p and p.has_method("add_score"):
			p.add_score(100)
			p.add_hit()
		_explode_and_chain()


func _explode_and_chain():
	var blast_radius := 6.0
	var my_pos := global_position

	# Spawn explosion visual in game world
	var gw = GameManager.game_world
	if gw:
		# Fireball
		var fireball := MeshInstance3D.new()
		var mesh := SphereMesh.new()
		mesh.radius = 1.0
		mesh.height = 2.0
		fireball.mesh = mesh
		fireball.position = my_pos
		fireball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(1.0, 0.5, 0.1, 0.9)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.3, 0.0)
		mat.emission_energy_multiplier = 6.0
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		fireball.material_override = mat
		gw.add_child(fireball)

		# Flash light
		var light := OmniLight3D.new()
		light.position = my_pos
		light.light_color = Color(1.0, 0.5, 0.1)
		light.light_energy = 5.0
		light.omni_range = 10.0
		gw.add_child(light)

		# Animate
		var tween := gw.create_tween()
		tween.set_parallel(true)
		tween.tween_property(fireball, "scale", Vector3(5, 5, 5), 0.4).set_ease(Tween.EASE_OUT)
		tween.tween_property(mat, "albedo_color", Color(1.0, 0.2, 0.0, 0.0), 0.4)
		tween.tween_property(light, "light_energy", 0.0, 0.4)
		tween.set_parallel(false)
		tween.tween_callback(func():
			fireball.queue_free()
			light.queue_free()
		)

	# Chain reaction — damage nearby enemies
	for enemy in get_tree().get_nodes_in_group("enemies"):
		if enemy == self or not is_instance_valid(enemy):
			continue
		if my_pos.distance_to(enemy.global_position) < blast_radius:
			if enemy.has_method("take_damage"):
				enemy.take_damage(50.0)

	queue_free()


func _fire():
	# 3-shot burst with slight spread
	var player = GameManager.player
	if player == null or GameManager.projectiles_container == null:
		return

	var base_dir: Vector3 = (player.global_position - global_position).normalized()
	for i in 3:
		var bullet := Area3D.new()
		bullet.set_script(TurretBulletScript)
		# Add slight spread to each shot in the burst
		var spread := Vector3(
			randf_range(-0.08, 0.08),
			randf_range(-0.08, 0.08),
			0
		)
		var dir: Vector3 = (base_dir + spread).normalized()
		bullet.set_meta("direction", dir)
		GameManager.projectiles_container.add_child(bullet)
		bullet.global_position = global_position + base_dir * (i * 0.5)


func _build_mesh():
	if ShipModel:
		var model := ShipModel.instantiate()
		model.scale = Vector3(0.8, 0.8, 0.8)
		model.rotation_degrees.y = 90  # face toward player
		_tint_meshes(model, Color(1.0, 0.4, 0.15))
		add_child(model)
	else:
		var mi := MeshInstance3D.new()
		var mesh := PrismMesh.new()
		mesh.size = Vector3(1.0, 0.2, 1.2)
		mi.mesh = mesh
		mi.rotation_degrees.x = -90
		var mat := StandardMaterial3D.new()
		mat.albedo_color = Color(0.8, 0.2, 0.2)
		mi.material_override = mat
		add_child(mi)


func _tint_meshes(node: Node, color: Color):
	if node is MeshInstance3D:
		var mat := StandardMaterial3D.new()
		mat.albedo_color = color
		mat.metallic = 0.5
		mat.roughness = 0.4
		mat.emission_enabled = true
		mat.emission = color * 0.6
		mat.emission_energy_multiplier = 1.5
		node.material_override = mat
	for child in node.get_children():
		_tint_meshes(child, color)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(1.2, 0.4, 1.5)
	col.shape = shape
	add_child(col)
