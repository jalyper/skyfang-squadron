extends Area3D
## Homing missile that tracks a locked target. Curves toward its target and
## explodes on contact for heavy damage.

var speed: float = 40.0
var turn_speed: float = 5.0
var lifetime: float = 4.0
var damage: float = 50.0
var target: Node3D = null


func _ready():
	add_to_group("player_projectiles")
	_build_mesh()
	_build_collision()
	area_entered.connect(_on_hit)


func _process(delta):
	if is_instance_valid(target):
		var to_target := (target.global_position - global_position).normalized()
		var cur_fwd := -global_transform.basis.z
		var new_dir := cur_fwd.lerp(to_target, turn_speed * delta).normalized()
		look_at(global_position + new_dir, Vector3.UP)

	global_position += -global_transform.basis.z * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()


func _on_hit(area: Area3D):
	if area.is_in_group("enemies"):
		if area.has_method("take_damage"):
			area.take_damage(damage)
		queue_free()


func _build_mesh():
	# Body
	var mi := MeshInstance3D.new()
	var mesh := CapsuleMesh.new()
	mesh.radius = 0.15
	mesh.height = 0.8
	mi.mesh = mesh
	mi.rotation_degrees.x = 90

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.6, 0.1)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.4, 0.0)
	mat.emission_energy_multiplier = 2.0
	mi.material_override = mat
	add_child(mi)

	# Exhaust trail
	var trail := MeshInstance3D.new()
	var tmesh := CylinderMesh.new()
	tmesh.top_radius = 0.08
	tmesh.bottom_radius = 0.02
	tmesh.height = 0.6
	trail.mesh = tmesh
	trail.rotation_degrees.x = 90
	trail.position.z = 0.5

	var tmat := StandardMaterial3D.new()
	tmat.albedo_color = Color(1.0, 0.3, 0.0, 0.7)
	tmat.emission_enabled = true
	tmat.emission = Color(1.0, 0.2, 0.0)
	tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	trail.material_override = tmat
	add_child(trail)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.3
	col.shape = shape
	add_child(col)
