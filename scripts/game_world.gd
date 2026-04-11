extends Node3D
## Main level orchestrator. Builds the entire PoC level procedurally:
## rail path, player, camera, hazards, enemies, HUD, and squad comms.

const PlayerShipScript = preload("res://scripts/player_ship.gd")
const RailCameraScript = preload("res://scripts/rail_camera.gd")
const AsteroidScript = preload("res://scripts/asteroid.gd")
const EnemyFighterScript = preload("res://scripts/enemy_fighter.gd")
const TurretScript = preload("res://scripts/turret.gd")
const HudScript = preload("res://scripts/hud.gd")
const SquadCommsScript = preload("res://scripts/squad_comms.gd")
const PickupScript = preload("res://scripts/pickup.gd")
const SkyscraperModel = preload("res://assets/models/Meshy_AI_massive_skyscraper_0411002834_texture.glb")
const WreckModel = preload("res://assets/models/Meshy_AI_a_half_destroyed_star_0411002802_texture.glb")

# Rail
var rail_speed: float = 16.0
var current_speed: float = 16.0
var path: Path3D
var path_follow: PathFollow3D

# References
var player: Area3D
var rail_camera: Camera3D
var enemies_container: Node3D
var hazards_container: Node3D
var projectiles_container: Node3D
var hud: Control
var squad_comms: Control
var level_complete: bool = false
var player_dead: bool = false
var game_over_ui: Control = null

# Shockwave pursuit — boost to outrun
var shockwave: MeshInstance3D = null
var shockwave_mat: StandardMaterial3D = null
var shockwave_active: bool = false
var shockwave_progress: float = 0.0  # 0-1 along the path
var shockwave_speed: float = 14.0    # slightly slower than rail_speed — must boost to gain distance
var shockwave_damage_dist: float = 8.0
var shockwave_zones: Array = [
	# [start_ratio, end_ratio] — sections where shockwave activates
	[0.15, 0.35],   # Act 1-2: chase through city
	[0.55, 0.72],   # Act 3: trench pursuit
]

# Comms
var comms_triggers: Array = []
var comms_fired: Dictionary = {}


func _ready():
	GameManager.game_world = self
	current_speed = rail_speed

	_create_environment()
	_create_starfield()
	_create_nebula()
	_create_rail_path()
	_create_path_visuals()
	_create_containers()
	_create_buildings()
	_create_phase_walls()
	_create_player()
	_create_camera()
	_create_hazards()
	_create_enemies()
	_create_pickups()
	_create_ui()
	_setup_comms_triggers()


func _process(delta):
	if level_complete or player_dead:
		return
	path_follow.progress += current_speed * delta
	if path_follow.progress_ratio >= 1.0:
		level_complete = true
		_on_level_complete()
	_check_comms_triggers()
	_update_shockwave(delta)


# ── Environment ───────────────────────────────────────────────

func _create_environment():
	var env = WorldEnvironment.new()
	var environment = Environment.new()
	environment.background_mode = Environment.BG_COLOR
	environment.background_color = Color(0.01, 0.01, 0.06)
	environment.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	environment.ambient_light_color = Color(0.15, 0.15, 0.25)
	environment.ambient_light_energy = 0.5
	env.environment = environment
	add_child(env)

	var light = DirectionalLight3D.new()
	light.rotation_degrees = Vector3(-40, -30, 0)
	light.light_energy = 1.0
	light.light_color = Color(0.9, 0.9, 1.0)
	light.shadow_enabled = true
	add_child(light)


# ── Starfield (parallax white dots) ───────────────────────────

func _create_starfield():
	# Three layers of stars at different distances for parallax effect
	# Closer layers move faster relative to camera, giving depth
	var layers = [
		{"count": 300, "range": 80,  "depth": 400, "size": 0.08, "brightness": 0.6},   # near stars
		{"count": 400, "range": 150, "depth": 600, "size": 0.05, "brightness": 0.4},   # mid stars
		{"count": 500, "range": 250, "depth": 800, "size": 0.03, "brightness": 0.25},  # far stars
	]

	for layer in layers:
		var star_container := Node3D.new()
		star_container.name = "Stars"
		# Parent to path_follow for parallax — closer stars move more with camera
		add_child(star_container)

		for i in layer["count"]:
			var star := MeshInstance3D.new()
			var mesh := QuadMesh.new()
			mesh.size = Vector2(layer["size"], layer["size"])
			star.mesh = mesh
			star.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			var mat := StandardMaterial3D.new()
			var b: float = layer["brightness"] * randf_range(0.5, 1.5)
			# Slight color variation — some warm, some cool
			var tint := randf()
			if tint < 0.3:
				mat.albedo_color = Color(b, b * 0.9, b * 0.7)  # warm
			elif tint < 0.6:
				mat.albedo_color = Color(b * 0.8, b * 0.9, b)  # cool
			else:
				mat.albedo_color = Color(b, b, b)  # white
			mat.emission_enabled = true
			mat.emission = mat.albedo_color
			mat.emission_energy_multiplier = 2.0
			mat.billboard_mode = BaseMaterial3D.BILLBOARD_ENABLED
			mat.no_depth_test = true
			star.material_override = mat

			var r: float = layer["range"]
			var d: float = layer["depth"]
			star.position = Vector3(
				randf_range(-r, r),
				randf_range(-r * 0.6, r * 0.6),
				randf_range(-d, 0)  # spread along the path length
			)
			star_container.add_child(star)


# ── Nebula (distant gas clouds) ───────────────────────────────

func _create_nebula():
	# Large semi-transparent colored spheres far from the path to simulate gas clouds
	var nebula_data = [
		# [position, radius, color]
		[Vector3(120, 40, -150),  40, Color(0.15, 0.05, 0.25, 0.08)],   # purple haze
		[Vector3(-150, -20, -300), 55, Color(0.05, 0.1, 0.25, 0.06)],   # blue nebula
		[Vector3(80, 60, -450),   45, Color(0.2, 0.05, 0.1, 0.07)],     # red/pink cloud
		[Vector3(-100, 30, -200), 35, Color(0.1, 0.15, 0.2, 0.09)],     # teal wisp
		[Vector3(60, -40, -520),  50, Color(0.08, 0.05, 0.2, 0.06)],    # deep violet
		[Vector3(-80, 50, -100),  30, Color(0.15, 0.1, 0.05, 0.08)],    # amber glow
		[Vector3(140, 10, -550),  60, Color(0.05, 0.08, 0.2, 0.05)],    # distant blue
	]

	for data in nebula_data:
		var pos: Vector3 = data[0]
		var radius: float = data[1]
		var color: Color = data[2]

		# Each nebula is 2-3 overlapping spheres for organic shape
		var num_blobs := randi_range(2, 4)
		for i in num_blobs:
			var blob := MeshInstance3D.new()
			var mesh := SphereMesh.new()
			var blob_r := radius * randf_range(0.6, 1.2)
			mesh.radius = blob_r
			mesh.height = blob_r * 2.0
			blob.mesh = mesh
			blob.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

			var mat := StandardMaterial3D.new()
			# Slight color shift per blob
			mat.albedo_color = Color(
				color.r + randf_range(-0.03, 0.03),
				color.g + randf_range(-0.03, 0.03),
				color.b + randf_range(-0.03, 0.03),
				color.a * randf_range(0.7, 1.3)
			)
			mat.emission_enabled = true
			mat.emission = Color(color.r * 2, color.g * 2, color.b * 2)
			mat.emission_energy_multiplier = 0.5
			mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			mat.cull_mode = BaseMaterial3D.CULL_DISABLED
			mat.no_depth_test = true
			blob.material_override = mat

			blob.position = pos + Vector3(
				randf_range(-radius * 0.4, radius * 0.4),
				randf_range(-radius * 0.3, radius * 0.3),
				randf_range(-radius * 0.3, radius * 0.3)
			)
			blob.scale = Vector3(
				randf_range(0.8, 1.3),
				randf_range(0.6, 1.0),
				randf_range(0.8, 1.3)
			)
			add_child(blob)


# ── Rail Path ─────────────────────────────────────────────────

func _create_rail_path():
	path = Path3D.new()
	var curve = Curve3D.new()

	# Straight rail down -Z — no lateral or vertical curves.
	# The camera derives its orientation from the PathFollow3D, so any X/Y
	# offsets in the path cause visible sway. Keep the rail perfectly straight
	# and place level content around the corridor instead.
	# ~600 units total, evenly spaced control points.
	var pts = [
		[Vector3(0, 0, 0),       Vector3(),           Vector3(0, 0, -30)],
		[Vector3(0, 0, -100),    Vector3(0, 0, 30),   Vector3(0, 0, -30)],
		[Vector3(0, 0, -200),    Vector3(0, 0, 30),   Vector3(0, 0, -30)],
		[Vector3(0, 0, -300),    Vector3(0, 0, 30),   Vector3(0, 0, -30)],
		[Vector3(0, 0, -400),    Vector3(0, 0, 30),   Vector3(0, 0, -30)],
		[Vector3(0, 0, -500),    Vector3(0, 0, 30),   Vector3(0, 0, -30)],
		[Vector3(0, 0, -600),    Vector3(0, 0, 30),   Vector3()],
	]
	for p in pts:
		curve.add_point(p[0], p[1], p[2])

	path.curve = curve
	add_child(path)

	path_follow = PathFollow3D.new()
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_follow.loop = false
	path.add_child(path_follow)


# ── Path Visuals (tunnel feel + end glow) ─────────────────────

func _create_path_visuals():
	var curve: Curve3D = path.curve
	var total_len := curve.get_baked_length()

	# Ring markers along the rail every ~25 units
	var ring_spacing := 25.0
	var num_rings := int(total_len / ring_spacing)
	for i in range(1, num_rings + 1):
		var offset_dist := i * ring_spacing
		var ratio := offset_dist / total_len
		var pos: Vector3 = curve.sample_baked(offset_dist)

		var ring_node := MeshInstance3D.new()
		var ring := TorusMesh.new()
		ring.inner_radius = 4.0
		ring.outer_radius = 4.4
		ring.rings = 16
		ring.ring_segments = 24
		ring_node.mesh = ring

		var mat := StandardMaterial3D.new()
		# Rings get brighter toward the end
		var brightness := lerpf(0.15, 0.6, ratio)
		mat.albedo_color = Color(0.2 * brightness, 0.4 * brightness, 1.0 * brightness, 0.4)
		mat.emission_enabled = true
		mat.emission = Color(0.2, 0.4, 1.0) * brightness
		mat.emission_energy_multiplier = lerpf(0.5, 2.5, ratio)
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.no_depth_test = false
		ring_node.material_override = mat
		ring_node.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		ring_node.position = pos
		# Orient ring to face along path direction
		var next_pos: Vector3 = curve.sample_baked(minf(offset_dist + 1.0, total_len))
		var forward := (next_pos - pos).normalized()
		if forward.length() > 0.01:
			ring_node.look_at(pos + forward, Vector3.UP)
		add_child(ring_node)

	# End-of-tunnel glow: bright light + emissive sphere at path end
	var end_pos: Vector3 = curve.sample_baked(total_len)

	var glow_light := OmniLight3D.new()
	glow_light.position = end_pos
	glow_light.light_energy = 4.0
	glow_light.light_color = Color(0.5, 0.7, 1.0)
	glow_light.omni_range = 60.0
	glow_light.omni_attenuation = 1.5
	add_child(glow_light)

	var glow_sphere := MeshInstance3D.new()
	var sphere := SphereMesh.new()
	sphere.radius = 8.0
	sphere.height = 16.0
	glow_sphere.mesh = sphere
	glow_sphere.position = end_pos
	glow_sphere.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	var glow_mat := StandardMaterial3D.new()
	glow_mat.albedo_color = Color(0.4, 0.6, 1.0, 0.2)
	glow_mat.emission_enabled = true
	glow_mat.emission = Color(0.4, 0.6, 1.0)
	glow_mat.emission_energy_multiplier = 4.0
	glow_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	glow_sphere.material_override = glow_mat
	add_child(glow_sphere)


# ── Containers ────────────────────────────────────────────────

func _create_containers():
	enemies_container = Node3D.new()
	enemies_container.name = "Enemies"
	add_child(enemies_container)

	hazards_container = Node3D.new()
	hazards_container.name = "Hazards"
	add_child(hazards_container)

	projectiles_container = Node3D.new()
	projectiles_container.name = "Projectiles"
	add_child(projectiles_container)

	GameManager.projectiles_container = projectiles_container


# ── Player ────────────────────────────────────────────────────

func _create_player():
	player = Area3D.new()
	player.name = "PlayerShip"
	player.set_script(PlayerShipScript)
	path_follow.add_child(player)
	GameManager.player = player
	player.ship_destroyed.connect(_on_player_destroyed)


# ── Camera ────────────────────────────────────────────────────

func _create_camera():
	rail_camera = Camera3D.new()
	rail_camera.name = "RailCamera"
	rail_camera.set_script(RailCameraScript)
	rail_camera.current = true
	rail_camera.fov = 70.0
	add_child(rail_camera)


# ── Buildings & obstacles ─────────────────────────────────────
# "skyscraper" = textured skyscraper model, "wreck" = destroyed starship,
# "box" = plain box (corridor walls, beams).
# Format: [position, type, scale, rotation_y]

func _create_buildings():
	var obstacles = [
		# === ACT 1: City outskirts (Z=-30 to -55) ===
		[Vector3(15, 0, -35),   "skyscraper", 18.0, 0.0],
		[Vector3(-14, 0, -45),  "skyscraper", 25.0, 45.0],
		[Vector3(18, 0, -55),   "skyscraper", 15.0, -30.0],

		# === City proper (Z=-60 to -95) ===
		[Vector3(10, 0, -65),   "skyscraper", 20.0, 10.0],
		[Vector3(-10, 0, -70),  "skyscraper", 28.0, -20.0],
		[Vector3(12, 0, -85),   "skyscraper", 16.0, 60.0],
		[Vector3(-12, 0, -90),  "skyscraper", 24.0, -45.0],
		# Crashed ship in the street
		[Vector3(4, 1, -80),    "wreck", 6.0, 15.0],

		# === Narrow corridor walls (Z=-105 to -135) ===
		[Vector3(7, 8, -120),   "box", Vector3(3, 18, 35), 0.0],
		[Vector3(-7, 8, -120),  "box", Vector3(3, 18, 35), 0.0],

		# === ACT 2: Dense combat (Z=-185 to -240) ===
		[Vector3(14, 0, -185),  "skyscraper", 20.0, 25.0],
		[Vector3(-13, 0, -195), "skyscraper", 22.0, -15.0],
		[Vector3(-5, 2, -205),  "wreck", 8.0, 40.0],
		[Vector3(10, 0, -210),  "skyscraper", 17.0, -50.0],
		[Vector3(-11, 0, -225), "skyscraper", 26.0, 30.0],
		[Vector3(6, 3, -232),   "wreck", 5.0, -60.0],
		[Vector3(16, 0, -235),  "skyscraper", 14.0, 0.0],
		[Vector3(-15, 0, -240), "skyscraper", 19.0, 70.0],

		# === Transition zone (Z=-260 to -300) ===
		[Vector3(12, 0, -265),  "skyscraper", 22.0, -10.0],
		[Vector3(-13, 0, -275), "skyscraper", 18.0, 35.0],
		[Vector3(3, 4, -285),   "wreck", 10.0, 20.0],
		[Vector3(8, 0, -290),   "skyscraper", 30.0, -40.0],

		# === ACT 3: Trench dive (Z=-300 to -420) ===
		[Vector3(6, -4, -330),  "box", Vector3(3, 12, 40), 0.0],
		[Vector3(-6, -4, -330), "box", Vector3(3, 12, 40), 0.0],
		# Overhanging beams
		[Vector3(4, 2, -350),   "box", Vector3(8, 2, 4), 0.0],
		[Vector3(-3, 3, -380),  "box", Vector3(6, 2, 4), 0.0],
		# Wrecks lodged in the trench
		[Vector3(3, -3, -365),  "wreck", 4.0, 90.0],
		[Vector3(-4, -2, -400), "wreck", 5.0, -70.0],
		# Trench exit pillars
		[Vector3(5, -2, -410),  "box", Vector3(3, 8, 3), 0.0],
		[Vector3(-5, -2, -415), "box", Vector3(3, 8, 3), 0.0],

		# === ACT 4: Open space debris field (Z=-430 to -580) ===
		# Massive wreck — fly through the cavity, collectible inside
		[Vector3(0, 0, -440),   "megawreck", 45.0, 0.0],
		[Vector3(-12, 5, -475), "wreck", 15.0, -45.0],
		[Vector3(8, -2, -490),  "wreck", 10.0, 60.0],
		[Vector3(-16, 2, -510), "wreck", 18.0, -20.0],
		[Vector3(18, 1, -530),  "wreck", 8.0, 110.0],
		[Vector3(-10, 6, -550), "wreck", 14.0, -80.0],
		[Vector3(6, 3, -570),   "wreck", 11.0, 45.0],
		[Vector3(-14, -1, -580), "wreck", 16.0, -30.0],
	]

	for obs in obstacles:
		match obs[1]:
			"skyscraper":
				_spawn_model_obstacle(obs[0], SkyscraperModel, obs[2], obs[3])
			"wreck":
				_spawn_model_obstacle(obs[0], WreckModel, obs[2], obs[3])
			"megawreck":
				_spawn_megawreck(obs[0], obs[2], obs[3])
			"box":
				_spawn_box_obstacle(obs[0], obs[2])


func _spawn_model_obstacle(pos: Vector3, model_scene: PackedScene, scl: float, rot_y: float):
	var body := StaticBody3D.new()
	body.position = pos

	var model := model_scene.instantiate()
	model.scale = Vector3(scl, scl, scl)
	model.rotation_degrees.y = rot_y
	body.add_child(model)

	# Approximate collision box based on scaled model bounds
	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = Vector3(scl * 0.6, scl * 1.2, scl * 0.6)
	col.shape = shape
	body.add_child(col)

	hazards_container.add_child(body)


func _spawn_megawreck(pos: Vector3, scl: float, rot_y: float):
	# Massive destroyed starship — no collision on the center so the player
	# can boost through the cavity. Collision rings around the outer hull only.
	var container := Node3D.new()
	container.position = pos

	var model := WreckModel.instantiate()
	model.scale = Vector3(scl, scl, scl)
	model.rotation_degrees.y = rot_y
	container.add_child(model)

	# Outer hull collision — two walls on either side of the cavity
	# The wreck model is ~1.9 wide at scale 1, so at 45x it's ~85 units wide.
	# Leave a gap in the center (~15 units) for the player to fly through.
	var half_width: float = scl * 0.45
	var gap: float = 8.0  # clear space for the player
	var wall_width: float = half_width - gap

	# Left hull wall
	var col_l := StaticBody3D.new()
	col_l.position = Vector3(-(gap + wall_width / 2.0), 0, 0)
	var shape_l := CollisionShape3D.new()
	var box_l := BoxShape3D.new()
	box_l.size = Vector3(wall_width, scl * 0.5, scl * 0.5)
	shape_l.shape = box_l
	col_l.add_child(shape_l)
	container.add_child(col_l)

	# Right hull wall
	var col_r := StaticBody3D.new()
	col_r.position = Vector3(gap + wall_width / 2.0, 0, 0)
	var shape_r := CollisionShape3D.new()
	var box_r := BoxShape3D.new()
	box_r.size = Vector3(wall_width, scl * 0.5, scl * 0.5)
	shape_r.shape = box_r
	col_r.add_child(shape_r)
	container.add_child(col_r)

	# Collectible inside the cavity — double shot powerup
	var pickup := Area3D.new()
	pickup.set_script(PickupScript)
	pickup.pickup_type = PickupScript.PickupType.DOUBLE_SHOT
	pickup.position = Vector3(0, 0, 0)  # dead center of the wreck
	pickup.lifetime = 999.0
	container.add_child(pickup)

	# Atmospheric light inside the cavity
	var inner_light := OmniLight3D.new()
	inner_light.position = Vector3(0, 0, 0)
	inner_light.light_color = Color(0.3, 0.8, 0.4)
	inner_light.light_energy = 4.0
	inner_light.omni_range = 12.0
	container.add_child(inner_light)

	hazards_container.add_child(container)


func _spawn_box_obstacle(pos: Vector3, size: Vector3):
	var building := StaticBody3D.new()
	building.position = pos

	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh

	var mat := StandardMaterial3D.new()
	var shade := randf_range(0.12, 0.22)
	mat.albedo_color = Color(shade, shade, shade * 1.3)
	mat.metallic = 0.6
	mat.roughness = 0.5
	mat.emission_enabled = true
	mat.emission = Color(0.1, 0.15, 0.3)
	mat.emission_energy_multiplier = 0.3
	mi.material_override = mat
	building.add_child(mi)

	var col := CollisionShape3D.new()
	var shape := BoxShape3D.new()
	shape.size = size
	col.shape = shape
	building.add_child(col)

	hazards_container.add_child(building)


# ── Phase Walls (must phase through) ─────────────────────────

func _create_phase_walls():
	var wall_positions = [
		# Act 2 phase gauntlet
		Vector3(0, 1, -148),
		Vector3(0, 1, -158),
		Vector3(0, 1, -168),
		# Trench phase barriers (must phase while diving)
		Vector3(0, -6, -345),
		Vector3(0, -7, -390),
		# Final approach barrier
		Vector3(0, 0, -540),
	]

	for pos in wall_positions:
		var wall := Area3D.new()
		wall.add_to_group("phase_walls")
		wall.add_to_group("hazards")
		wall.position = pos

		var mi := MeshInstance3D.new()
		var mesh := BoxMesh.new()
		mesh.size = Vector3(20, 14, 0.4)
		mi.mesh = mesh
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

		var mat := StandardMaterial3D.new()
		mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		mat.albedo_color = Color(0.8, 0.2, 0.3, 0.25)
		mat.emission_enabled = true
		mat.emission = Color(1.0, 0.2, 0.3)
		mat.emission_energy_multiplier = 1.5
		mat.cull_mode = BaseMaterial3D.CULL_DISABLED
		mi.material_override = mat
		wall.add_child(mi)

		var col := CollisionShape3D.new()
		var shape := BoxShape3D.new()
		shape.size = Vector3(20, 14, 0.6)
		col.shape = shape
		wall.add_child(col)

		hazards_container.add_child(wall)


# ── Hazards (asteroids + debris) ──────────────────────────────

func _create_hazards():
	var data = [
		# Act 1: Scattered debris
		[Vector3(3, 0, -25), 2.0],
		[Vector3(-5, 1, -30), 1.5],
		[Vector3(6, -1, -180), 2.0],
		[Vector3(-4, 2, -250), 1.8],
		[Vector3(3, -1, -255), 2.2],
		[Vector3(-2, 3, -280), 1.5],
		# Act 3: Trench debris
		[Vector3(2, -6, -335), 1.5],
		[Vector3(-3, -5, -355), 2.0],
		[Vector3(1, -7, -375), 1.8],
		[Vector3(-2, -4, -400), 2.5],
		# Act 4: Asteroid field
		[Vector3(5, 1, -435), 3.0],
		[Vector3(-6, -1, -445), 2.5],
		[Vector3(3, 3, -455), 2.0],
		[Vector3(-8, 0, -470), 3.5],
		[Vector3(7, -2, -485), 2.0],
		[Vector3(-3, 4, -500), 2.8],
		[Vector3(0, -1, -515), 3.0],
		[Vector3(6, 2, -525), 2.0],
		[Vector3(-5, -2, -545), 2.5],
		[Vector3(4, 1, -560), 1.8],
		[Vector3(-7, 3, -575), 3.0],
		[Vector3(2, -1, -590), 2.2],
	]
	for d in data:
		var asteroid = Area3D.new()
		asteroid.set_script(AsteroidScript)
		asteroid.position = d[0]
		asteroid.set_meta("size", d[1])
		hazards_container.add_child(asteroid)


# ── Enemies ───────────────────────────────────────────────────

func _create_enemies():
	# Turrets on buildings and structures
	for pos in [
		# Act 1: City turrets
		Vector3(10, 14, -65),
		Vector3(-10, 16, -70),
		Vector3(12, 12, -85),
		# Act 2: Combat zone turrets
		Vector3(-7, 14, -210),
		Vector3(10, 12, -210),
		Vector3(14, 12, -235),
		# Act 3: Trench turrets (on walls)
		Vector3(5, 2, -340),
		Vector3(-5, 1, -365),
		Vector3(4, 3, -400),
		# Act 4: Ruin turrets
		Vector3(-14, 11, -460),
		Vector3(12, 4, -490),
		Vector3(-10, 10, -530),
	]:
		var turret = Area3D.new()
		turret.set_script(TurretScript)
		turret.position = pos
		enemies_container.add_child(turret)

	# Fighter waves
	var waves = [
		# Act 1: City
		[Vector3(0, 2, -55), 3],
		[Vector3(0, 2, -140), 3],
		[Vector3(0, 3, -200), 4],
		[Vector3(0, 2, -260), 3],
		# Act 3: Trench ambush
		[Vector3(0, -5, -335), 2],
		[Vector3(0, -6, -370), 3],
		# Act 4: Asteroid field fighters
		[Vector3(0, 2, -450), 4],
		[Vector3(0, 0, -500), 3],
		[Vector3(0, 1, -550), 5],  # big final wave
		[Vector3(0, 0, -580), 3],
	]
	for wave in waves:
		var center: Vector3 = wave[0]
		var count: int = wave[1]
		for i in count:
			var offset = Vector3(
				(i - count / 2.0) * 4.0,
				sin(i * 1.5) * 2.0,
				i * 3.0
			)
			var fighter = Area3D.new()
			fighter.set_script(EnemyFighterScript)
			fighter.position = center + offset
			enemies_container.add_child(fighter)


# ── Pickups (guaranteed shield recharges at key points) ──────

func _create_pickups():
	# Place two shield pickups at strategic locations:
	# one mid-level after heavy combat, one in the asteroid field
	var shield_positions := [
		Vector3(0, 1, -295),   # after Act 2 combat gauntlet
		Vector3(-2, 0, -505),  # mid asteroid field, Act 4
	]
	for pos in shield_positions:
		var pickup := Area3D.new()
		pickup.set_script(PickupScript)
		pickup.pickup_type = PickupScript.PickupType.SHIELD
		pickup.position = pos
		pickup.lifetime = 999.0  # static pickups don't expire
		hazards_container.add_child(pickup)


# ── UI ────────────────────────────────────────────────────────

func _create_ui():
	var canvas = CanvasLayer.new()
	canvas.name = "UI"
	add_child(canvas)

	hud = Control.new()
	hud.name = "HUD"
	hud.set_anchors_preset(Control.PRESET_FULL_RECT)
	hud.set_script(HudScript)
	canvas.add_child(hud)

	squad_comms = Control.new()
	squad_comms.name = "SquadComms"
	squad_comms.set_anchors_preset(Control.PRESET_FULL_RECT)
	squad_comms.mouse_filter = Control.MOUSE_FILTER_IGNORE
	squad_comms.set_script(SquadCommsScript)
	canvas.add_child(squad_comms)


# ── Squad Comms Triggers ──────────────────────────────────────

func _setup_comms_triggers():
	comms_triggers = [
		# Act 1: City
		{"at": 0.01, "who": "Nyx",   "say": "City ahead. Stay low between the buildings.",          "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.08, "who": "Kiro",  "say": "Fighters! Let's see who drops more.",                   "clr": Color(0.6, 0.6, 0.7)},
		{"at": 0.15, "who": "Bront", "say": "Narrow gap ahead. Tilt to squeeze through.",           "clr": Color(0.6, 0.4, 0.2)},
		# Act 2: Phase gauntlet
		{"at": 0.25, "who": "Nyx",   "say": "Phase barriers! Ghost through them.",                  "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.35, "who": "Kiro",  "say": "Heavy resistance. Lock on and let missiles fly.",      "clr": Color(0.6, 0.6, 0.7)},
		# Act 3: Trench dive
		{"at": 0.48, "who": "Bront", "say": "We're diving into the trench. Hold steady.",           "clr": Color(0.6, 0.4, 0.2)},
		{"at": 0.55, "who": "Nyx",   "say": "Watch the overhangs! Phase if you need to.",           "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.62, "who": "Kiro",  "say": "Ambush! They were waiting for us down here.",          "clr": Color(0.6, 0.6, 0.7)},
		# Act 4: Asteroid field
		{"at": 0.72, "who": "Bront", "say": "Open space... but it's full of debris.",               "clr": Color(0.6, 0.4, 0.2)},
		{"at": 0.80, "who": "Nyx",   "say": "Massive wave incoming. Shoot the asteroids for drops.", "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.88, "who": "Kiro",  "say": "This is it. Everything they've got.",                  "clr": Color(0.6, 0.6, 0.7)},
		{"at": 0.95, "who": "Bront", "say": "Almost through. We've got this, pack.",                "clr": Color(0.6, 0.4, 0.2)},
	]


func _check_comms_triggers():
	for t in comms_triggers:
		var key = str(t["at"])
		if not comms_fired.has(key) and path_follow.progress_ratio >= t["at"]:
			comms_fired[key] = true
			if squad_comms and squad_comms.has_method("show_message"):
				squad_comms.show_message(t["who"], t["say"], t["clr"])


func _on_level_complete():
	if squad_comms and squad_comms.has_method("show_message"):
		squad_comms.show_message("Raze", "Area clear. Good work, pack.", Color(0.3, 0.5, 0.9))
	_despawn_shockwave()

	# Record result and return to solar map after a delay
	var level_id: String = GameManager.current_level_id
	var hits: int = player.hit_count if player else 0
	var score_val: int = player.score if player else 0
	if level_id != "":
		GameManager.mark_level_beaten(level_id, hits, score_val)

	await get_tree().create_timer(3.0).timeout
	_show_level_clear(hits, score_val)


# ── Shockwave Pursuit ─────────────────────────────────────────

func _update_shockwave(delta):
	var player_ratio := path_follow.progress_ratio

	# Check if we're in a shockwave zone
	var in_zone := false
	for zone in shockwave_zones:
		if player_ratio >= zone[0] and player_ratio <= zone[1]:
			in_zone = true
			if not shockwave_active:
				# Start the shockwave behind the player
				shockwave_progress = player_ratio - 0.03
				_spawn_shockwave()
			break

	if not in_zone and shockwave_active:
		_despawn_shockwave()
		return

	if not shockwave_active:
		return

	# Advance shockwave along the path
	var curve_len := path.curve.get_baked_length()
	shockwave_progress += (shockwave_speed / curve_len) * delta

	# Position the shockwave on the path
	var sw_dist := shockwave_progress * curve_len
	var sw_pos: Vector3 = path.curve.sample_baked(clampf(sw_dist, 0, curve_len))
	if shockwave:
		shockwave.global_position = sw_pos
		# Pulse effect
		var pulse := 1.0 + sin(Time.get_ticks_msec() * 0.01) * 0.15
		shockwave.scale = Vector3(pulse, pulse, pulse)
		if shockwave_mat:
			var urgency := clampf(1.0 - (player_ratio - shockwave_progress) * 20.0, 0.0, 1.0)
			shockwave_mat.albedo_color.a = 0.2 + urgency * 0.4
			shockwave_mat.emission_energy_multiplier = 2.0 + urgency * 4.0

	# Check if shockwave caught the player
	if player and is_instance_valid(player):
		var dist_behind := (player_ratio - shockwave_progress) * curve_len
		# Emit proximity for HUD
		if hud and hud.has_method("update_threat"):
			hud.update_threat(dist_behind, shockwave_active)
		if dist_behind < shockwave_damage_dist:
			if player.has_method("take_damage"):
				player.take_damage(8.0 * delta)  # continuous damage when close


func _spawn_shockwave():
	shockwave_active = true

	shockwave = MeshInstance3D.new()
	var mesh := SphereMesh.new()
	mesh.radius = 12.0
	mesh.height = 24.0
	shockwave.mesh = mesh
	shockwave.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	shockwave_mat = StandardMaterial3D.new()
	shockwave_mat.albedo_color = Color(1.0, 0.3, 0.1, 0.3)
	shockwave_mat.emission_enabled = true
	shockwave_mat.emission = Color(1.0, 0.2, 0.05)
	shockwave_mat.emission_energy_multiplier = 3.0
	shockwave_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	shockwave_mat.cull_mode = BaseMaterial3D.CULL_DISABLED
	shockwave.material_override = shockwave_mat
	add_child(shockwave)

	# Warning comm
	if squad_comms and squad_comms.has_method("show_message"):
		squad_comms.show_message("Kiro", "Shockwave behind us! BOOST NOW!", Color(1.0, 0.3, 0.2))


func _despawn_shockwave():
	shockwave_active = false
	if shockwave:
		shockwave.queue_free()
		shockwave = null
		shockwave_mat = null
	if hud and hud.has_method("update_threat"):
		hud.update_threat(0.0, false)


# ── Game Over ─────────────────────────────────────────────────

func _on_player_destroyed():
	player_dead = true
	current_speed = 0.0

	# Wait a moment for the explosion to play, then show menu
	await get_tree().create_timer(1.5).timeout
	_show_game_over()


func _show_level_clear(hits: int, score_val: int):
	var canvas = CanvasLayer.new()
	canvas.layer = 10
	add_child(canvas)

	var ui := Control.new()
	ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(ui)

	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.5)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	ui.add_child(overlay)

	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -250
	vbox.offset_top = -120
	vbox.offset_right = 250
	vbox.offset_bottom = 120
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 16)
	ui.add_child(vbox)

	var title := Label.new()
	title.text = "MISSION COMPLETE"
	title.add_theme_font_size_override("font_size", 44)
	title.add_theme_color_override("font_color", Color(0.3, 1.0, 0.4))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	var hits_lbl := Label.new()
	hits_lbl.text = "TOTAL HITS: %d" % hits
	hits_lbl.add_theme_font_size_override("font_size", 24)
	hits_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.3))
	hits_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(hits_lbl)

	var score_lbl := Label.new()
	score_lbl.text = "SCORE: %d" % score_val
	score_lbl.add_theme_font_size_override("font_size", 20)
	score_lbl.add_theme_color_override("font_color", Color.WHITE)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(score_lbl)

	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 10)
	vbox.add_child(spacer)

	var cont_btn := Button.new()
	cont_btn.text = "CONTINUE"
	cont_btn.custom_minimum_size = Vector2(250, 50)
	cont_btn.add_theme_font_size_override("font_size", 22)
	cont_btn.focus_mode = Control.FOCUS_ALL
	cont_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/solar_map.tscn"))
	vbox.add_child(cont_btn)

	await get_tree().process_frame
	cont_btn.grab_focus()


func _show_game_over():
	var canvas = CanvasLayer.new()
	canvas.layer = 10  # on top of everything
	add_child(canvas)

	game_over_ui = Control.new()
	game_over_ui.set_anchors_preset(Control.PRESET_FULL_RECT)
	canvas.add_child(game_over_ui)

	# Dim overlay
	var overlay := ColorRect.new()
	overlay.set_anchors_preset(Control.PRESET_FULL_RECT)
	overlay.color = Color(0, 0, 0, 0.6)
	overlay.mouse_filter = Control.MOUSE_FILTER_IGNORE
	game_over_ui.add_child(overlay)

	# Center container
	var vbox := VBoxContainer.new()
	vbox.set_anchors_preset(Control.PRESET_CENTER)
	vbox.offset_left = -200
	vbox.offset_top = -100
	vbox.offset_right = 200
	vbox.offset_bottom = 100
	vbox.alignment = BoxContainer.ALIGNMENT_CENTER
	vbox.add_theme_constant_override("separation", 20)
	game_over_ui.add_child(vbox)

	# Title
	var title := Label.new()
	title.text = "MISSION FAILED"
	title.add_theme_font_size_override("font_size", 48)
	title.add_theme_color_override("font_color", Color(1.0, 0.3, 0.2))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(title)

	# Spacer
	var spacer := Control.new()
	spacer.custom_minimum_size = Vector2(0, 20)
	vbox.add_child(spacer)

	# Deduct a life
	GameManager.lives -= 1

	var lives_lbl := Label.new()
	lives_lbl.text = "LIVES: %d" % maxi(GameManager.lives, 0)
	lives_lbl.add_theme_font_size_override("font_size", 20)
	lives_lbl.add_theme_color_override("font_color", Color(0.8, 0.8, 0.8))
	lives_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	vbox.add_child(lives_lbl)

	# Try Again button (if lives remain)
	var retry_btn := Button.new()
	retry_btn.text = "TRY AGAIN"
	retry_btn.custom_minimum_size = Vector2(250, 50)
	retry_btn.add_theme_font_size_override("font_size", 22)
	retry_btn.focus_mode = Control.FOCUS_ALL
	retry_btn.pressed.connect(_on_retry)
	vbox.add_child(retry_btn)

	if GameManager.lives <= 0:
		retry_btn.disabled = true
		retry_btn.text = "NO LIVES LEFT"

	# Return to Map button
	var map_btn := Button.new()
	map_btn.text = "SOLAR MAP"
	map_btn.custom_minimum_size = Vector2(250, 50)
	map_btn.add_theme_font_size_override("font_size", 22)
	map_btn.focus_mode = Control.FOCUS_ALL
	map_btn.pressed.connect(func(): get_tree().change_scene_to_file("res://scenes/solar_map.tscn"))
	vbox.add_child(map_btn)

	# Quit button
	var quit_btn := Button.new()
	quit_btn.text = "QUIT"
	quit_btn.custom_minimum_size = Vector2(250, 50)
	quit_btn.add_theme_font_size_override("font_size", 22)
	quit_btn.focus_mode = Control.FOCUS_ALL
	quit_btn.pressed.connect(_on_quit)
	vbox.add_child(quit_btn)

	# Set focus neighbors for D-pad navigation
	retry_btn.focus_neighbor_bottom = retry_btn.get_path_to(map_btn)
	map_btn.focus_neighbor_top = map_btn.get_path_to(retry_btn)
	map_btn.focus_neighbor_bottom = map_btn.get_path_to(quit_btn)
	quit_btn.focus_neighbor_top = quit_btn.get_path_to(map_btn)

	# Grab focus after a frame so the layout is finalized
	await get_tree().process_frame
	if GameManager.lives > 0:
		retry_btn.grab_focus()
	else:
		map_btn.grab_focus()

	# Gamepad A button may conflict with our "boost" action, so handle it manually
	set_process_input(true)


func _input(event: InputEvent):
	if not player_dead or game_over_ui == null:
		return
	# Accept with gamepad A button or ui_accept
	if event is InputEventJoypadButton and event.button_index == JOY_BUTTON_A and event.pressed:
		var focused := get_viewport().gui_get_focus_owner()
		if focused is Button:
			focused.emit_signal("pressed")


func _on_retry():
	get_tree().reload_current_scene()


func _on_quit():
	get_tree().quit()
