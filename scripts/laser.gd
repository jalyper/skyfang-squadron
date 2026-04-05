extends Area3D
## Player laser projectile. Travels forward and damages enemies/hazards.
## If a target is set (locked enemy), the laser aggressively homes toward it.

var speed: float = 70.0
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
	var mi := MeshInstance3D.new()
	var mesh := CylinderMesh.new()
	mesh.top_radius = 0.05
	mesh.bottom_radius = 0.05
	mesh.height = 1.2
	mi.mesh = mesh
	mi.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.3, 1.0, 0.4)
	mat.emission_enabled = true
	mat.emission = Color(0.3, 1.0, 0.4)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	add_child(mi)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.8  # generous sphere for reliable hits
	col.shape = shape
	add_child(col)
