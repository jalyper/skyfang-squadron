extends Node3D
## Title screen: V formation of ships facing the camera, gentle bob,
## streaking stars in the background, title text overlay.

const ShipModel = preload("res://assets/models/Meshy_AI_space_ship_starfox__0410213457_texture.glb")

var ships: Array = []
var star_particles: GPUParticles3D
var _time: float = 0.0
var _started: bool = false

# V formation positions (leader at center-front, wingmen spread back)
var formation := [
	Vector3(0, 0, 0),        # leader
	Vector3(-2.5, 0.3, 3),   # left wing 1
	Vector3(2.5, 0.3, 3),    # right wing 1
	Vector3(-5.0, 0.6, 6),   # left wing 2
	Vector3(5.0, 0.6, 6),    # right wing 2
]


func _ready():
	_build_environment()
	_build_stars()
	_build_ships()
	_build_camera()
	_build_ui()


func _process(delta):
	_time += delta

	# Bob ships gently
	for i in ships.size():
		var ship: Node3D = ships[i]
		var base_pos: Vector3 = formation[i]
		# Each ship bobs at a slightly different phase
		var phase := i * 0.7
		ship.position.y = base_pos.y + sin(_time * 1.2 + phase) * 0.15
		# Subtle roll sway
		ship.rotation.z = sin(_time * 0.8 + phase * 1.3) * deg_to_rad(3.0)

	# Handle start input
	if not _started:
		if Input.is_action_just_pressed("shoot") or Input.is_action_just_pressed("ui_select") or Input.is_action_just_pressed("boost"):
			_started = true
			get_tree().change_scene_to_file("res://scenes/solar_map.tscn")


func _build_environment():
	# Dark space background
	var env := Environment.new()
	env.background_mode = Environment.BG_COLOR
	env.background_color = Color(0.005, 0.005, 0.02)
	env.ambient_light_color = Color(0.15, 0.15, 0.2)
	env.ambient_light_energy = 0.3

	# Subtle bloom for the glowing elements
	env.glow_enabled = true
	env.glow_intensity = 0.4
	env.glow_bloom = 0.1

	var world_env := WorldEnvironment.new()
	world_env.environment = env
	add_child(world_env)

	# Key light — slightly above and to the right, cool blue
	var key_light := DirectionalLight3D.new()
	key_light.light_color = Color(0.7, 0.8, 1.0)
	key_light.light_energy = 1.2
	key_light.rotation_degrees = Vector3(-30, -20, 0)
	add_child(key_light)

	# Rim light — warm from below-left for dramatic contrast
	var rim_light := DirectionalLight3D.new()
	rim_light.light_color = Color(1.0, 0.7, 0.4)
	rim_light.light_energy = 0.4
	rim_light.rotation_degrees = Vector3(20, 40, 0)
	add_child(rim_light)


func _build_stars():
	star_particles = GPUParticles3D.new()
	star_particles.amount = 300
	star_particles.lifetime = 3.0
	star_particles.explosiveness = 0.0
	star_particles.randomness = 0.5
	star_particles.fixed_fps = 60
	star_particles.local_coords = true
	star_particles.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	star_particles.position = Vector3(0, 0, -30)

	var proc := ParticleProcessMaterial.new()
	proc.direction = Vector3(0, 0, 1)  # fly toward camera
	proc.spread = 5.0
	proc.initial_velocity_min = 15.0
	proc.initial_velocity_max = 25.0
	proc.gravity = Vector3.ZERO

	# Spawn across a wide area in front
	proc.emission_shape = ParticleProcessMaterial.EMISSION_SHAPE_BOX
	proc.emission_box_extents = Vector3(25, 15, 2)

	# Tiny scale
	proc.scale_min = 0.3
	proc.scale_max = 0.8

	# Fade in and out
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

	# Small quad per star
	var quad := QuadMesh.new()
	quad.size = Vector2(0.05, 0.05)
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
			model.scale = Vector3(1.0, 1.0, 1.0)
			# Face toward camera (+Z)
			model.rotation_degrees.y = 90
			ship.add_child(model)

		add_child(ship)
		ships.append(ship)


func _build_camera():
	var cam := Camera3D.new()
	cam.position = Vector3(0, 1.5, -8)
	cam.rotation_degrees.x = -5
	cam.fov = 55
	add_child(cam)


func _build_ui():
	var canvas := CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui)

	# Title
	var title := Label.new()
	title.text = "SKYFANG SQUADRON"
	title.set_anchors_preset(Control.PRESET_TOP_WIDE)
	title.offset_top = 80
	title.add_theme_font_size_override("font_size", 52)
	title.add_theme_color_override("font_color", Color(0.4, 0.85, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(title)

	# Subtitle
	var subtitle := Label.new()
	subtitle.text = "DEFEND THE SKIES"
	subtitle.set_anchors_preset(Control.PRESET_TOP_WIDE)
	subtitle.offset_top = 145
	subtitle.add_theme_font_size_override("font_size", 18)
	subtitle.add_theme_color_override("font_color", Color(0.6, 0.65, 0.7))
	subtitle.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(subtitle)

	# "Press Start" prompt — pulses
	var prompt := Label.new()
	prompt.text = "PRESS START"
	prompt.name = "StartPrompt"
	prompt.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	prompt.offset_bottom = -60
	prompt.add_theme_font_size_override("font_size", 24)
	prompt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	prompt.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	prompt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(prompt)

	# Pulse the prompt
	var tween := create_tween().set_loops()
	tween.tween_property(prompt, "modulate:a", 0.3, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
	tween.tween_property(prompt, "modulate:a", 1.0, 0.8).set_ease(Tween.EASE_IN_OUT).set_trans(Tween.TRANS_SINE)
