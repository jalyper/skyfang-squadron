extends Node3D
## Title screen: V formation of ships facing the camera, gentle bob,
## streaking stars in the background, stylized title overlay.

const ShipModel = preload("res://assets/models/Meshy_AI_space_ship_starfox__0410213457_texture.glb")

var ships: Array = []
var star_particles: GPUParticles3D
var _time: float = 0.0
var _started: bool = false

# V formation — leader at front, wingmen spread back (+Z = away from camera)
var formation := [
	Vector3(0, 0, 0),
	Vector3(-3.0, 0.3, 3.5),
	Vector3(3.0, 0.3, 3.5),
	Vector3(-6.0, 0.6, 7.0),
	Vector3(6.0, 0.6, 7.0),
]


func _ready():
	_build_environment()
	_build_stars()
	_build_ships()
	_build_camera()
	_build_ui()


func _process(delta):
	_time += delta
	for i in ships.size():
		var ship: Node3D = ships[i]
		var base_pos: Vector3 = formation[i]
		var phase := i * 0.7
		ship.position.y = base_pos.y + sin(_time * 1.2 + phase) * 0.15
		ship.rotation.z = sin(_time * 0.8 + phase * 1.3) * deg_to_rad(3.0)

	if not _started:
		if Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("ui_select") or Input.is_action_just_pressed("boost"):
			_started = true
			get_tree().change_scene_to_file("res://scenes/solar_map.tscn")


func _build_environment():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.005, 0.02)
	env.ambient_light_color = Color(0.15, 0.15, 0.2)
	env.ambient_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.6
	env.glow_bloom = 0.15

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Key light — cool blue from upper-right
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.7, 0.8, 1.0)
	key_light.light_energy = 1.5
	key_light.rotation_degrees = Vector3(-30, -20, 0)
	add_child(key_light)

	# Rim light — warm from below
	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color(1.0, 0.7, 0.4)
	rim_light.light_energy = 0.5
	rim_light.rotation_degrees = Vector3(20, 40, 0)
	add_child(rim_light)


func _build_stars():
	star_particles = GPUParticles3D.new()
	star_particles.amount = 300
	star_particles.lifetime = 2.5
	star_particles.explosiveness = 0.0
	star_particles.randomness = 0.5
	star_particles.fixed_fps = 60
	star_particles.local_coords = true
	star_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star_particles.position = Vector3(0, 0, 40)  # spawn far behind ships

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 0, -1)  # fly toward camera (-Z)
	proc.spread = 3.0
	proc.initial_velocity_min = 20.0
	proc.initial_velocity_max = 35.0
	proc.gravity = Vector3.ZERO
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(30, 20, 3)
	proc.scale_min = 0.3
	proc.scale_max = 0.8

	var color_ramp := GradientTexture1D.new()
	var grad := Gradient.new()
	grad.colors = PackedColorArray([
		Color(0.6, 0.7, 1.0, 0.0),
		Color(0.8, 0.85, 1.0, 0.7),
		Color(1.0, 1.0, 1.0, 0.9),
		Color(0.7, 0.8, 1.0, 0.0),
	])
	grad.offsets = PackedFloat32Array([0.0, 0.1, 0.6, 1.0])
	color_ramp.gradient = grad
	proc.color_ramp = color_ramp
	star_particles.process_material = proc

	var quad := QuadMesh.new()
	quad.size = Vector2(0.06, 0.06)
	star_particles.draw_pass_1 = quad

	var mat := StandardMaterial3D.new()
	mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	mat.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
	mat.vertex_color_use_as_albedo = true
	mat.albedo_color = Color.WHITE
	mat.no_depth_test = true
	quad.material = mat
	add_child(star_particles)


func _build_ships():
	for i in formation.size():
		var pos: Vector3 = formation[i]
		var ship := Node3D.new()
		ship.position = pos

		if ShipModel:
			var model := ShipModel.instantiate()
			model.scale = Vector3(1.2, 1.2, 1.2)
			# Ships face TOWARD camera (-Z), same as in-game but flipped
			model.rotation_degrees.y = 90
			ship.add_child(model)

		add_child(ship)
		ships.append(ship)


func _build_camera():
	var cam := Camera3D.new()
	# Camera in front of and slightly above the formation, looking back at them
	cam.position = Vector3(0, 2.5, -10)
	cam.fov = 50
	add_child(cam)
	# Look at the center of the formation
	cam.look_at(Vector3(0, 0, 3), Vector3.UP)


func _build_ui():
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui)

	# ── Stylized title with glow layers ──

	# Outer glow layer (large, blurred, colored)
	var glow2 := Label.new()
	glow2.text = "SKYFANG SQUADRON"
	glow2.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow2.offset_top = 68
	glow2.add_theme_font_size_override("font_size", 62)
	glow2.add_theme_color_override("font_color", Color(0.1, 0.4, 1.0, 0.25))
	glow2.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(glow2)

	# Mid glow layer
	var glow1 := Label.new()
	glow1.text = "SKYFANG SQUADRON"
	glow1.set_anchors_preset(Control.PRESET_TOP_WIDE)
	glow1.offset_top = 72
	glow1.add_theme_font_size_override("font_size", 56)
	glow1.add_theme_color_override("font_color", Color(0.2, 0.6, 1.0, 0.4))
	glow1.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	glow1.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(glow1)

	# Main title — bright with outline
	var title := Label.new()
	title.text = "SKYFANG SQUADRON"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 76

	var title_settings := LabelSettings.new()
	title_settings.font_size = 52
	title_settings.font_color = Color(0.85, 0.95, 1.0)
	title_settings.outline_size = 4
	title_settings.outline_color = Color(0.1, 0.3, 0.8)
	title_settings.shadow_size = 8
	title_settings.shadow_color = Color(0.0, 0.2, 0.7, 0.5)
	title_settings.shadow_offset = Vector2(0, 4)
	title.label_settings = title_settings

	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title)

	# Hot inner highlight — slightly smaller, brighter, offset up
	var highlight := Label.new()
	highlight.text = "SKYFANG SQUADRON"
	highlight.set_anchors_preset(Control.PRESET_TOP_WIDE)
	highlight.offset_top = 75
	highlight.add_theme_font_size_override("font_size", 52)
	highlight.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0, 0.3))
	highlight.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	highlight.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(highlight)

	# ── Divider line ──
	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = 140
	line.offset_left = 500
	line.offset_right = -500
	line.custom_minimum_size = Vector2(0, 2)
	line.color = Color(0.3, 0.6, 1.0, 0.4)
	line.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(line)

	# ── Subtitle ──
	var subtitle := Label.new()
	subtitle.text = "D E F E N D   T H E   S K I E S"
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 150

	var sub_settings := LabelSettings.new()
	sub_settings.font_size = 16
	sub_settings.font_color = Color(0.5, 0.6, 0.7)
	sub_settings.shadow_size = 4
	sub_settings.shadow_color = Color(0.0, 0.15, 0.4, 0.4)
	sub_settings.shadow_offset = Vector2(0, 2)
	subtitle.label_settings = sub_settings

	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(subtitle)

	# ── Press Start prompt ──
	var prompt := Label.new()
	prompt.text = "P R E S S   S T A R T"
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_bottom = -50

	var prompt_settings := LabelSettings.new()
	prompt_settings.font_size = 22
	prompt_settings.font_color = Color(1.0, 0.85, 0.2)
	prompt_settings.outline_size = 2
	prompt_settings.outline_color = Color(0.5, 0.3, 0.0)
	prompt_settings.shadow_size = 6
	prompt_settings.shadow_color = Color(0.4, 0.25, 0.0, 0.4)
	prompt_settings.shadow_offset = Vector2(0, 3)
	prompt.label_settings = prompt_settings

	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(prompt)

	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.3, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
