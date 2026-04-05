extends Area3D
## Destructible asteroid hazard. Slowly tumbles in place.

var health: float = 40.0
var rot_speed: Vector3
var size: float = 2.0


func _ready():
	add_to_group("hazards")
	size = get_meta("size") if has_meta("size") else 2.0
	rot_speed = Vector3(
		randf_range(-0.5, 0.5),
		randf_range(-0.5, 0.5),
		randf_range(-0.3, 0.3)
	)
	_build_mesh()
	_build_collision()


func _process(delta):
	rotation += rot_speed * delta


func take_damage(amount: float):
	health -= amount
	if health <= 0:
		var p = GameManager.player
		if p and p.has_method("add_score"):
			p.add_score(25)
		queue_free()


func _build_mesh():
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = size * 0.5
	mesh.height = size
	mi.mesh = mesh
	mi.scale = Vector3(
		randf_range(0.8, 1.2),
		randf_range(0.7, 1.0),
		randf_range(0.8, 1.2)
	)

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(
		randf_range(0.3, 0.5),
		randf_range(0.25, 0.4),
		randf_range(0.2, 0.35)
	)
	mat.roughness = 0.9
	mi.material_override = mat
	add_child(mi)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = size * 0.5
	col.shape = shape
	add_child(col)
