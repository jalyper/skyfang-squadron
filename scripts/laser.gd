extends Area3D
## Player laser projectile. Travels forward and damages enemies/hazards.
## If a target is set (locked enemy), the laser aggressively homes toward it.

var speed: float = 140.0
var lifetime: float = 3.0
var damage: float = 25.0
var direction: Vector3 = Vector3(0, 0, -1)
var target: Node3D = null
var seek_strength: float = 12.0  # strong homing


func _ready():
	add_to_group("player_projectiles")
	_build_mesh()
	_build_collision()
	area_entered.connect(_on_hit)
	# Orient the whole laser node to face its travel direction so the
	# visual bolt aligns with the actual trajectory.
	if direction.length_squared() > 0.0001:
		var target_point := global_position + direction
		# Pick a stable up: world up unless direction is nearly vertical
		var up := Vector3.UP
		if absf(direction.dot(up)) > 0.99:
			up = Vector3(0, 0, 1)
		look_at(target_point, up)


func _process(delta):
	# Home toward locked target if set
	if target != null and is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		direction = direction.lerp(to_target, seek_strength * delta).normalized()
		# If very close, just aim directly
		var dist_to_target := global_position.distance_to(target.global_position)
		if dist_to_target < 5.0:
			direction = to_target

	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()


func _on_hit(area: Area3D):
	if area.is_in_group("enemies") or area.is_in_group("hazards"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()


func _build_mesh():
	# Main bolt — elongated tapered cylinder, bright cyan
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.035
	mesh.bottom_radius = 0.065
	mesh.height = 4.5
	mi.mesh = mesh
	mi.rotation_degrees.x = -90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.4, 0.9, 1.0)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 0.8, 1.0)
	mat.emission_energy_multiplier = 5.0
	mi.material_override = mat
	add_child(mi)

	# Inner core glow — brighter white-cyan center
	var core := MeshInstance3D.new()
	var core_mesh := CylinderMesh.new()
	core_mesh.top_radius = 0.018
	core_mesh.bottom_radius = 0.035
	core_mesh.height = 4.3
	core.mesh = core_mesh
	core.rotation_degrees.x = -90

	var core_mat := StandardMaterial3D.new()
	core_mat.albedo_color = Color(0.8, 0.95, 1.0)
	core_mat.emission_enabled = true
	core_mat.emission = Color(0.9, 1.0, 1.0)
	core_mat.emission_energy_multiplier = 8.0
	core.material_override = core_mat
	add_child(core)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8  # generous sphere for reliable hits
	col.shape = shape
	add_child(col)
