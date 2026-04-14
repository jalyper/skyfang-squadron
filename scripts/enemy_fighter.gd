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
# When set, the fighter chases and fires at this node instead of the player.
# Used for the escort section where chasers target Kiro, not Raze.
var custom_target: Node3D = null
# Escort chasers are parented to path_follow alongside the ally, so they
# can track the ally's local position exactly (including Z along the rail).
# When tracking_mode is true, movement uses the target's LOCAL position
# plus tracking_offset and ignores the world-space activation check.
var tracking_mode: bool = false
var tracking_offset: Vector3 = Vector3.ZERO


func _ready():
	add_to_group("enemies")
	origin_pos = position
	_build_mesh()
	_build_collision()


func _process(delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	# Escort chaser path: parented to path_follow alongside the ally, so we
	# track the target's LOCAL position plus a configured offset. This keeps
	# chasers glued to the ally in all three axes regardless of rail motion.
	if tracking_mode:
		pattern_time += delta
		if custom_target and is_instance_valid(custom_target):
			var desired := custom_target.position + tracking_offset
			# Add a gentle weave so they feel alive
			desired += Vector3(
				sin(pattern_time * 3.0 + origin_pos.x) * 0.8,
				cos(pattern_time * 2.0 + origin_pos.y) * 0.5,
				0,
			)
			position = position.lerp(desired, 3.0 * delta)

			shoot_timer -= delta
			if shoot_timer <= 0 and global_position.distance_to(custom_target.global_position) < 50.0:
				_fire()
				shoot_timer = randf_range(shoot_interval * 0.7, shoot_interval * 1.3)
		return

	var dist := global_position.distance_to(gw.path_follow.global_position)

	if not is_active:
		if dist < activation_dist:
			is_active = true
		return

	var focus := _get_focus()
	pattern_time += delta

	# Smart movement: strafe toward focus target's world position, weave
	if focus and is_instance_valid(focus):
		var fx: float = focus.global_position.x
		var fy: float = focus.global_position.y
		var target_x := fx + sin(pattern_time * 3.0 + origin_pos.x) * 5.0
		var target_y := fy + cos(pattern_time * 2.0 + origin_pos.y) * 3.0
		position.x = lerpf(position.x, target_x, 1.5 * delta)
		position.y = lerpf(position.y, target_y, 1.5 * delta)
	else:
		position.x = origin_pos.x + sin(pattern_time * 2.0) * 3.0
		position.y = origin_pos.y + cos(pattern_time * 1.5) * 1.5

	# Shoot — lead the focus target
	shoot_timer -= delta
	if shoot_timer <= 0 and focus and is_instance_valid(focus) and global_position.distance_to(focus.global_position) < 50.0:
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


func _get_focus() -> Node3D:
	if custom_target != null and is_instance_valid(custom_target):
		return custom_target
	return GameManager.player


func _fire():
	# 3-shot burst with slight spread, aimed at the current focus target
	var focus := _get_focus()
	if focus == null or not is_instance_valid(focus) or GameManager.projectiles_container == null:
		return

	var base_dir: Vector3 = (focus.global_position - global_position).normalized()
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
