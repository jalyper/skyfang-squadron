extends Area3D
## Generic enemy projectile. Flies in a straight line and damages the player on contact.
## Direction is passed via metadata before entering the tree.

var speed: float = 30.0
var lifetime: float = 3.0
var direction: Vector3 = Vector3(0, 0, -1)


func _ready():
	add_to_group("enemy_projectiles")
	if has_meta("direction"):
		direction = get_meta("direction")
	_build_mesh()
	_build_collision()
	area_entered.connect(_on_hit)


func _process(delta):
	global_position += direction * speed * delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()


func _on_hit(area: Area3D):
	if area.is_in_group("player"):
		queue_free()


func _build_mesh():
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.15
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(1.0, 0.3, 0.2)
	mat.emission_enabled = true
	mat.emission = Color(1.0, 0.1, 0.1)
	mat.emission_energy_multiplier = 3.0
	mi.material_override = mat
	add_child(mi)


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 0.2
	col.shape = shape
	add_child(col)
