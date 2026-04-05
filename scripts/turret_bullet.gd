extends Area3D
## Enemy energy bolt. Small glowing sphere with a short trail that always
## faces the camera. Looks like a plasma ball, not a metal pole.
## Can be deflected by a barrel roll — bounces off in a random direction.

var speed: float = 50.0
var lifetime: float = 3.0
var direction: Vector3 = Vector3(0, 0, -1)
var deflected: bool = false
var bolt_mesh: MeshInstance3D
var trail_mesh: MeshInstance3D
var trail_segments: Array = []


func _ready():
	add_to_group("enemy_projectiles")
	if has_meta("direction"):
		direction = get_meta("direction")
	_build_mesh()
	_build_collision()
	area_entered.connect(_on_hit)


func _process(delta):
	global_position += direction * speed * delta
	# Position trail segments behind the bolt along travel direction
	var behind := -direction.normalized()
	for i in trail_segments.size():
		if is_instance_valid(trail_segments[i]):
			trail_segments[i].position = behind * (i + 1) * 0.2
	lifetime -= delta
	if lifetime <= 0:
		queue_free()


func deflect():
	if deflected:
		return
	deflected = true
	direction = Vector3(
		randf_range(-1.0, 1.0),
		randf_range(-0.5, 0.5),
		randf_range(-1.0, 1.0)
	).normalized()
	speed *= 1.5
	remove_from_group("enemy_projectiles")
	add_to_group("player_projectiles")
	_set_color(Color(0.3, 1.0, 0.4))


func _on_hit(area: Area3D):
	if area.is_in_group("player") and not deflected:
		queue_free()
	elif area.is_in_group("enemies") and deflected:
		if area.has_method("take_damage"):
			area.take_damage(15.0)
		queue_free()


func _set_color(col: Color):
	# Recolor all mesh children (core + trail segments)
	for child in get_children():
		if child is MeshInstance3D:
			var mat := StandardMaterial3D.new()
			mat.albedo_color = col
			mat.emission_enabled = true
			mat.emission = col
			mat.emission_energy_multiplier = 5.0
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			child.material_override = mat


func _build_mesh():
	# Core: tiny bright hot point
	bolt_mesh = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.07
	mesh.height = 0.14
	bolt_mesh.mesh = mesh
	bolt_mesh.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.8, 0.5)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.5, 0.1)
	mat.emission_energy_multiplier = 8.0
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	bolt_mesh.material_override = mat
	add_child(bolt_mesh)

	# Trail: 3 fading segments that taper behind the bolt
	trail_segments.clear()
	for i in 3:
		var seg := MeshInstance3D.new()
		var smesh := SphereMesh.new()
		var seg_size := 0.05 - i * 0.012
		smesh.radius = maxf(seg_size, 0.02)
		smesh.height = maxf(seg_size * 2, 0.04)
		seg.mesh = smesh
		seg.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var smat := StandardMaterial3D.new()
		var alpha := 0.6 - i * 0.18
		smat.albedo_color = Color(1.0, 0.3, 0.1, alpha)
		smat.emission_enabled = true
		smat.emission = Color(1.0, 0.2, 0.05)
		smat.emission_energy_multiplier = 3.0 - i * 0.8
		smat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		smat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		seg.material_override = smat
		add_child(seg)
		trail_segments.append(seg)

	trail_mesh = null


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)
