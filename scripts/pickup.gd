extends Area3D
## Collectible pickup with spinning idle animation and a juicy collection
## effect: rapid spin + shrink onto player + flash + twinkle particles.
##
## Types: "double_shot", "shield"

enum PickupType { DOUBLE_SHOT, SHIELD }

var pickup_type: PickupType = PickupType.DOUBLE_SHOT
var lifetime: float = 10.0
var bob_speed: float = 2.5
var spin_speed: float = 1.8
var _time: float = 0.0
var _origin_y: float = 0.0
var _collected: bool = false

var visual: Node3D  # container for mesh(es)


func _ready():
	add_to_group("powerups")
	_origin_y = position.y
	_build_visual()
	_build_collision()
	area_entered.connect(_on_area_entered)


func _process(delta: float):
	if _collected:
		return
	_time += delta
	lifetime -= delta
	if lifetime <= 0:
		queue_free()
		return

	# Gentle spin + bob
	if visual:
		visual.rotation.y += spin_speed * delta
		visual.rotation.x = sin(_time * 0.7) * 0.15
	position.y = _origin_y + sin(_time * bob_speed) * 0.4

	# Fade out in last 2 seconds
	if lifetime < 2.0:
		var alpha: float = lifetime / 2.0
		_set_visual_alpha(alpha)


func _on_area_entered(area: Area3D):
	if _collected:
		return
	if not area.is_in_group("player"):
		return
	_collected = true

	var p = GameManager.player
	if p:
		match pickup_type:
			PickupType.DOUBLE_SHOT:
				if p.has_method("activate_double_shot"):
					p.activate_double_shot()
			PickupType.SHIELD:
				if p.has_method("heal"):
					p.heal(35.0)

	_play_collect_animation()


func _play_collect_animation():
	var gw = GameManager.game_world
	if gw == null:
		queue_free()
		return

	# Disable collision so we don't re-trigger
	set_deferred("monitoring", false)
	set_deferred("monitorable", false)

	var player = GameManager.player
	var target_pos: Vector3 = player.global_position if player and is_instance_valid(player) else global_position

	# Phase 1: Rapid spin + shrink toward player (0.35 sec)
	var tween := create_tween()
	tween.set_parallel(true)

	# Spin rapidly — 6 full rotations
	if visual:
		var spin_target: float = visual.rotation.y + TAU * 6.0
		tween.tween_property(visual, "rotation:y", spin_target, 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	# Shrink to nothing
	tween.tween_property(self, "scale", Vector3(0.05, 0.05, 0.05), 0.35).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_BACK)

	# Fly toward player position
	tween.tween_property(self, "global_position", target_pos, 0.3).set_ease(Tween.EASE_IN).set_trans(Tween.TRANS_QUAD)

	tween.set_parallel(false)
	tween.tween_callback(_spawn_collect_flash)
	tween.tween_interval(0.4)
	tween.tween_callback(queue_free)


func _spawn_collect_flash():
	var gw = GameManager.game_world
	if gw == null:
		return

	var flash_pos: Vector3 = global_position
	var flash_color: Color
	match pickup_type:
		PickupType.DOUBLE_SHOT:
			flash_color = Color(0.2, 1.0, 0.5)
		PickupType.SHIELD:
			flash_color = Color(0.5, 0.8, 1.0)

	# Bright flash sphere
	var flash := MeshInstance3D.new()
	var fmesh := SphereMesh.new()
	fmesh.radius = 0.8
	fmesh.height = 1.6
	flash.mesh = fmesh
	flash.position = flash_pos
	flash.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var fmat := StandardMaterial3D.new()
	fmat.albedo_color = Color(flash_color.r, flash_color.g, flash_color.b, 0.9)
	fmat.emission_enabled = true
	fmat.emission = flash_color
	fmat.emission_energy_multiplier = 10.0
	fmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	fmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	flash.material_override = fmat
	gw.add_child(flash)

	# Flash light
	var light := OmniLight3D.new()
	light.position = flash_pos
	light.light_color = flash_color
	light.light_energy = 6.0
	light.omni_range = 12.0
	gw.add_child(light)

	# Twinkle particles — small bright dots that scatter outward
	var twinkles: Array[MeshInstance3D] = []
	var twinkle_targets: Array[Vector3] = []
	for i in 8:
		var t := MeshInstance3D.new()
		var tmesh := SphereMesh.new()
		tmesh.radius = 0.06
		tmesh.height = 0.12
		t.mesh = tmesh
		t.position = flash_pos
		t.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var tmat := StandardMaterial3D.new()
		# Alternate white and colored twinkles
		var tcol: Color = Color.WHITE if i % 2 == 0 else flash_color
		tmat.albedo_color = Color(tcol.r, tcol.g, tcol.b, 1.0)
		tmat.emission_enabled = true
		tmat.emission = tcol
		tmat.emission_energy_multiplier = 8.0
		tmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		tmat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
		t.material_override = tmat
		gw.add_child(t)
		twinkles.append(t)
		# Random scatter direction
		var scatter := Vector3(
			randf_range(-1.0, 1.0),
			randf_range(-0.5, 1.0),
			randf_range(-1.0, 1.0)
		).normalized() * randf_range(2.0, 5.0)
		twinkle_targets.append(flash_pos + scatter)

	# Animate flash + twinkles
	var ft := gw.create_tween()
	ft.set_parallel(true)
	# Flash expands and fades
	ft.tween_property(flash, "scale", Vector3(5, 5, 5), 0.3).set_ease(Tween.EASE_OUT)
	ft.tween_property(fmat, "albedo_color:a", 0.0, 0.3)
	ft.tween_property(light, "light_energy", 0.0, 0.35)

	# Twinkles fly outward and fade
	for i in twinkles.size():
		ft.tween_property(twinkles[i], "position", twinkle_targets[i], 0.4).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)
		var tw_mat: StandardMaterial3D = twinkles[i].material_override
		ft.tween_property(tw_mat, "albedo_color:a", 0.0, 0.4).set_delay(0.1)
		# Twinkles shimmer by pulsing scale
		ft.tween_property(twinkles[i], "scale", Vector3(0.3, 0.3, 0.3), 0.15).set_ease(Tween.EASE_OUT)
		ft.tween_property(twinkles[i], "scale", Vector3(0.05, 0.05, 0.05), 0.25).set_delay(0.15)

	ft.set_parallel(false)
	ft.tween_callback(func():
		flash.queue_free()
		light.queue_free()
		for tw in twinkles:
			if is_instance_valid(tw):
				tw.queue_free()
	)


func _set_visual_alpha(alpha: float):
	if visual == null:
		return
	for child in visual.get_children():
		if child is MeshInstance3D and child.material_override:
			child.material_override.albedo_color.a = alpha


func _build_visual():
	visual = Node3D.new()
	add_child(visual)

	match pickup_type:
		PickupType.DOUBLE_SHOT:
			_build_double_shot_visual()
		PickupType.SHIELD:
			_build_shield_visual()


func _build_double_shot_visual():
	# Glowing green cube with inner energy
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
	visual.add_child(mi)

	# Inner bright core
	var core := MeshInstance3D.new()
	var cmesh := SphereMesh.new()
	cmesh.radius = 0.25
	cmesh.height = 0.5
	core.mesh = cmesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.6, 1.0, 0.8, 0.8)
	cmat.emission_enabled = true
	cmat.emission = Color(0.5, 1.0, 0.7)
	cmat.emission_energy_multiplier = 6.0
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = cmat
	visual.add_child(core)


func _build_shield_visual():
	# Whitish-blue sphere with honeycomb-like faceted appearance
	# Main sphere — low-poly for faceted/honeycomb look
	var mi := MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 0.55
	mesh.height = 1.1
	mesh.radial_segments = 8   # low poly = hexagonal facets
	mesh.rings = 5
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.75, 0.88, 1.0, 0.85)
	mat.emission_enabled = true
	mat.emission = Color(0.6, 0.8, 1.0)
	mat.emission_energy_multiplier = 3.0
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.metallic = 0.7
	mat.roughness = 0.15
	# Slight iridescence via rim/fresnel effect
	mat.rim_enabled = true
	mat.rim = 0.6
	mat.rim_tint = 0.3
	mi.material_override = mat
	visual.add_child(mi)

	# Outer wireframe shell for honeycomb texture illusion
	var wire := MeshInstance3D.new()
	var wmesh := SphereMesh.new()
	wmesh.radius = 0.6
	wmesh.height = 1.2
	wmesh.radial_segments = 6   # hexagonal wireframe
	wmesh.rings = 4
	wire.mesh = wmesh
	wire.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var wmat := StandardMaterial3D.new()
	wmat.albedo_color = Color(0.5, 0.75, 1.0, 0.3)
	wmat.emission_enabled = true
	wmat.emission = Color(0.4, 0.7, 1.0)
	wmat.emission_energy_multiplier = 2.0
	wmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	wmat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	wmat.cull_mode = BaseMaterial3D.CULL_FRONT  # shows inner wireframe edges
	wire.material_override = wmat
	visual.add_child(wire)

	# Inner bright core glow
	var core := MeshInstance3D.new()
	var cmesh := SphereMesh.new()
	cmesh.radius = 0.3
	cmesh.height = 0.6
	core.mesh = cmesh
	core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var cmat := StandardMaterial3D.new()
	cmat.albedo_color = Color(0.85, 0.95, 1.0, 0.6)
	cmat.emission_enabled = true
	cmat.emission = Color(0.8, 0.9, 1.0)
	cmat.emission_energy_multiplier = 5.0
	cmat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	core.material_override = cmat
	visual.add_child(core)

	# Slower, more majestic rotation for the shield
	spin_speed = 1.2


func _build_collision():
	var col := CollisionShape3D.new()
	var shape := SphereShape3D.new()
	shape.radius = 1.5
	col.shape = shape
	add_child(col)
