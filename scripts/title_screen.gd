extends Node3D
## Title screen: V formation of ships facing the camera, gentle bob,
## streaking stars in the background, stylized title overlay.

const ShipModel = preload("res://assets/models/Meshy_AI_space_ship_starfox__0410213457_texture.glb")
const TitleLogoModel = preload("res://assets/models/Meshy_AI_SKYFANG_SQUADRON_st_0413213505_texture.glb")

var ships: Array = []
var title_logo: Node3D
var _logo_base_y: float = 0.0
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
	_build_title_logo()
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

	if title_logo:
		title_logo.position.y = _logo_base_y + sin(_time * 1.0) * 0.2
		title_logo.rotation.z = sin(_time * 0.6) * deg_to_rad(2.0)

	# Menu input handled by buttons + focus system


func _build_environment():
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.005, 0.02)
	env.ambient_light_color = Color(0.15, 0.15, 0.2)
	env.ambient_light_energy = 0.3
	env.glow_enabled = true
	env.glow_intensity = 0.2
	env.glow_bloom = 0.0

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
			# Ships face TOWARD camera (-Z)
			model.rotation_degrees.y = -90
			ship.add_child(model)

		add_child(ship)
		ships.append(ship)


func _build_title_logo():
	if not TitleLogoModel:
		return
	title_logo = Node3D.new()
	# Hovering above and slightly in front of the ship formation so it reads
	# as the "title" in the upper portion of the camera view.
	_logo_base_y = 3.8
	title_logo.position = Vector3(0, _logo_base_y, 2.0)
	title_logo.scale = Vector3(2.8, 2.8, 2.8)

	var model := TitleLogoModel.instantiate()
	model.rotation_degrees.y = 180
	title_logo.add_child(model)

	# The GLB ships with strong baked emission that bloomed into an
	# unreadable haze. Crush the emission so real lights drive the look.
	_tone_down_emission(model)

	# Front-facing spot light to pop the logo against the dark background.
	var front_light := SpotLight3D.new()
	front_light.light_color = Color(1.0, 0.95, 1.0)
	front_light.light_energy = 10.0
	front_light.spot_range = 30.0
	front_light.spot_angle = 45.0
	front_light.spot_attenuation = 0.6
	front_light.position = Vector3(0, 0, -4)
	front_light.look_at_from_position(front_light.position, Vector3.ZERO, Vector3.UP)
	title_logo.add_child(front_light)

	# Warm fill from below for depth.
	var fill_light := OmniLight3D.new()
	fill_light.light_color = Color(1.0, 0.8, 0.6)
	fill_light.light_energy = 2.5
	fill_light.omni_range = 12.0
	fill_light.position = Vector3(0, -1.5, -2)
	title_logo.add_child(fill_light)

	add_child(title_logo)


func _tone_down_emission(node: Node) -> void:
	if node is MeshInstance3D:
		var mi := node as MeshInstance3D
		var mesh := mi.mesh
		if mesh:
			for i in mesh.get_surface_count():
				var mat := mi.get_active_material(i)
				if mat is StandardMaterial3D:
					var sm := mat.duplicate() as StandardMaterial3D
					sm.emission_enabled = true
					sm.emission = Color(0.15, 0.15, 0.2)
					sm.emission_energy_multiplier = 0.3
					mi.set_surface_override_material(i, sm)
				elif mat is ORMMaterial3D:
					var om := mat.duplicate() as ORMMaterial3D
					om.emission_enabled = true
					om.emission = Color(0.15, 0.15, 0.2)
					om.emission_energy_multiplier = 0.3
					mi.set_surface_override_material(i, om)
	for child in node.get_children():
		_tone_down_emission(child)


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

	# Title is now a 3D logo model built in _build_title_logo().

	# ── Divider line ──
	var line := ColorRect.new()
	line.set_anchors_preset(Control.PRESET_TOP_WIDE)
	line.offset_top = 340
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
	subtitle.offset_top = 350

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

	# ── Menu buttons ──
	var menu_container := VBoxContainer.new()
	menu_container.set_anchors_preset(Control.PRESET_CENTER)
	menu_container.offset_left = -140
	menu_container.offset_right = 140
	menu_container.offset_top = 188
	menu_container.offset_bottom = 328
	menu_container.add_theme_constant_override("separation", 12)
	menu_container.alignment = BoxContainer.ALIGNMENT_CENTER
	ui.add_child(menu_container)

	var buttons := ["S T A R T", "E X I T"]
	var actions := [_on_start, _on_exit]

	for i in buttons.size():
		var btn := Button.new()
		btn.text = buttons[i]
		btn.custom_minimum_size = Vector2(280, 50)
		btn.focus_mode = Control.FOCUS_ALL

		# Flat transparent style
		var normal_style := StyleBoxFlat.new()
		normal_style.bg_color = Color(0.05, 0.1, 0.2, 0.6)
		normal_style.border_color = Color(0.2, 0.45, 0.8, 0.5)
		normal_style.set_border_width_all(1)
		normal_style.set_corner_radius_all(2)
		normal_style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("normal", normal_style)

		# Hover — brighter border, subtle blue fill
		var hover_style := StyleBoxFlat.new()
		hover_style.bg_color = Color(0.1, 0.2, 0.4, 0.8)
		hover_style.border_color = Color(0.4, 0.7, 1.0, 0.9)
		hover_style.set_border_width_all(2)
		hover_style.set_corner_radius_all(2)
		hover_style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("hover", hover_style)

		# Focus — same as hover (for controller navigation)
		var focus_style := hover_style.duplicate()
		btn.add_theme_stylebox_override("focus", focus_style)

		# Pressed
		var pressed_style := StyleBoxFlat.new()
		pressed_style.bg_color = Color(0.15, 0.3, 0.6, 0.9)
		pressed_style.border_color = Color(0.5, 0.85, 1.0, 1.0)
		pressed_style.set_border_width_all(2)
		pressed_style.set_corner_radius_all(2)
		pressed_style.set_content_margin_all(8)
		btn.add_theme_stylebox_override("pressed", pressed_style)

		btn.add_theme_font_size_override("font_size", 20)
		btn.add_theme_color_override("font_color", Color(0.6, 0.75, 0.9))
		btn.add_theme_color_override("font_hover_color", Color(0.9, 0.95, 1.0))
		btn.add_theme_color_override("font_focus_color", Color(0.9, 0.95, 1.0))
		btn.add_theme_color_override("font_pressed_color", Color(1.0, 1.0, 1.0))

		btn.pressed.connect(actions[i])
		btn.mouse_entered.connect(_on_btn_hover.bind(btn))
		btn.focus_entered.connect(_on_btn_focus.bind(btn))
		btn.focus_exited.connect(_on_btn_unfocus.bind(btn))

		menu_container.add_child(btn)

	# Give first button focus after layout settles
	await get_tree().process_frame
	menu_container.get_child(0).grab_focus()


func _on_btn_hover(btn: Button):
	btn.grab_focus()


func _on_btn_focus(btn: Button):
	# Slide in from left + scale up
	var tween := create_tween()
	tween.set_parallel(true)
	btn.pivot_offset = btn.size / 2.0
	tween.tween_property(btn, "scale", Vector2(1.06, 1.06), 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_BACK)
	tween.tween_property(btn, "position:x", btn.position.x + 6, 0.15).set_ease(Tween.EASE_OUT).set_trans(Tween.TRANS_CUBIC)


func _on_btn_unfocus(btn: Button):
	var tween := create_tween()
	tween.set_parallel(true)
	tween.tween_property(btn, "scale", Vector2(1.0, 1.0), 0.12).set_ease(Tween.EASE_OUT)
	tween.tween_property(btn, "position:x", btn.position.x - 6, 0.12).set_ease(Tween.EASE_OUT)


func _on_start():
	if _started:
		return
	_started = true
	GameManager.reset_campaign()
	get_tree().change_scene_to_file("res://scenes/solar_map.tscn")


func _on_options():
	pass  # TODO: options menu


func _on_exit():
	get_tree().quit()
