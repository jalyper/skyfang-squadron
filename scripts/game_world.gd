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
	[0.15, 0.30],   # Act 2 banking descent — boost through
	[0.80, 0.93],   # Final approach asteroid field — boost out
]

# Comms
var comms_triggers: Array = []
var comms_fired: Dictionary = {}

# ── Tutorial State ──
# Tutorials pause the game (rail slowdown) and show a prompt until the
# player performs the taught action. One tutorial at a time.
var tutorial_speed_mult: float = 1.0
var tutorial_slow_factor: float = 0.05  # 5% rail speed while prompt is up
var tutorial_panel: PanelContainer = null
var tutorial_label: Label = null
var tutorial_tween: Tween = null
var tutorials: Array = []
var tutorial_index: int = 0
var active_tutorial: Dictionary = {}
# Enemies tracked for the "enemies_cleared" tutorial trigger
var tutorial_enemies: Array = []
var tutorial_enemies_cleared: bool = false

# ── Escort Section State ──
# Kiro flies in from off-screen right, arcs across the player's view, and
# holds a position ahead-center while chasers try to shred him. Player
# clears the chasers; Kiro says thanks and peels off left.
const AllyShipModel := preload("res://assets/models/Meshy_AI_space_ship_starfox__0410213457_texture.glb")
enum EscortPhase { IDLE, ENTERING, HOLDING, EXITING, DONE }
var escort_start_ratio: float = 0.55
var escort_phase: int = EscortPhase.IDLE
var escort_phase_time: float = 0.0
var escort_complete: bool = false
var escort_help_shown: bool = false
var escort_thanks_shown: bool = false
var escort_ally: Node3D = null
var escort_ally_hp: float = 100.0
var escort_ally_max_hp: float = 100.0
var escort_chasers: Array = []
var escort_damage_range: float = 18.0
var escort_dps_per_chaser: float = 5.0

# Animation waypoints (all in path_follow-local space)
var escort_entrance_duration: float = 3.5
var escort_exit_duration: float = 2.5
var escort_entry_start: Vector3 = Vector3(28.0, 3.0, -8.0)    # off-screen right
var escort_entry_end: Vector3 = Vector3(0.0, 2.0, -42.0)      # settled ahead
var escort_exit_end: Vector3 = Vector3(-32.0, 6.0, -95.0)     # off-screen left


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
	_setup_tutorials()


func _process(delta):
	if level_complete or player_dead:
		return
	path_follow.progress += current_speed * tutorial_speed_mult * delta
	if path_follow.progress_ratio >= 1.0:
		level_complete = true
		_on_level_complete()
	_update_tutorials()
	_check_comms_triggers()
	_update_shockwave(delta)
	_update_escort(delta)


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
	# Roller-coaster style rail: gentle intro → banking right descent →
	# straight slot-gate run → climbing left turn → escort straight → final
	# climb. No loops. The rail camera follows the rail's basis, so tilts
	# and curves produce a roller-coaster feel.
	path = Path3D.new()
	var curve = Curve3D.new()
	curve.up_vector_enabled = true

	# [position, tilt_degrees]
	var pts := [
		[Vector3(0, 0, 0),        0.0],   # intro start
		[Vector3(0, 0, -90),      0.0],   # intro straight
		[Vector3(20, -10, -160),  12.0],  # begin banking right + descent
		[Vector3(50, -25, -230),  20.0],  # mid banked dive
		[Vector3(55, -30, -300),  10.0],  # pull out, entering slot run
		[Vector3(55, -30, -370),  0.0],   # slot run straight
		[Vector3(35, -20, -440),  -15.0], # climbing left-banked turn
		[Vector3(5, -5, -510),    -8.0],  # turn exit
		[Vector3(0, 0, -590),     0.0],   # escort section straight
		[Vector3(0, 5, -680),     0.0],   # final gentle climb
		[Vector3(0, 5, -770),     0.0],   # finish
	]

	for i in pts.size():
		var p: Vector3 = pts[i][0]
		var tilt: float = pts[i][1]
		# Smooth Catmull-Rom-ish tangents computed from neighbors
		var prev_p: Vector3 = (pts[i - 1][0] if i > 0 else p)
		var next_p: Vector3 = (pts[i + 1][0] if i < pts.size() - 1 else p)
		var out_t := (next_p - prev_p) * 0.25
		var in_t := -out_t
		curve.add_point(p, in_t, out_t)
		curve.set_point_tilt(i, deg_to_rad(tilt))

	path.curve = curve
	add_child(path)

	path_follow = PathFollow3D.new()
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_follow.loop = false
	path.add_child(path_follow)


# ── Rail-local helpers ───────────────────────────────────────
# The curved rail means obstacles, enemies, and effects must be placed
# relative to a distance along the rail plus a local offset, not in raw
# world coordinates. These helpers convert rail-local coords to world.

func _rail_transform(dist: float) -> Transform3D:
	var curve: Curve3D = path.curve
	var total := curve.get_baked_length()
	var d := clampf(dist, 0.0, total)
	return curve.sample_baked_with_rotation(d, false, true)


func _rail_pos(dist: float, lx: float, ly: float, lz: float = 0.0) -> Vector3:
	return _rail_transform(dist) * Vector3(lx, ly, lz)


func _rail_forward(dist: float) -> Vector3:
	var curve: Curve3D = path.curve
	var total := curve.get_baked_length()
	var d := clampf(dist, 0.0, total)
	var a := curve.sample_baked(d)
	var b := curve.sample_baked(minf(d + 1.0, total))
	var f := (b - a)
	if f.length_squared() < 0.0001:
		return Vector3(0, 0, -1)
	return f.normalized()


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

		# Orient ring to face along path direction
		var next_pos: Vector3 = curve.sample_baked(minf(offset_dist + 1.0, total_len))
		var forward := (next_pos - pos).normalized()
		add_child(ring_node)
		if forward.length() > 0.01 and not forward.is_equal_approx(Vector3.UP) and not forward.is_equal_approx(-Vector3.UP):
			ring_node.look_at_from_position(pos, pos + forward, Vector3.UP)
		else:
			ring_node.position = pos

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
	# Content is defined in rail-local space: (distance_along_rail, local_x,
	# local_y, type, payload...). Helpers convert these into world positions
	# so content follows the curved rail automatically.
	var obstacles := [
		# === ACT 1: Intro city (dist 25-110) ===
		[ 30,  14,  0, "skyscraper", 18.0, 0.0],
		[ 45, -14,  0, "skyscraper", 24.0, 30.0],
		[ 60,  12,  0, "skyscraper", 16.0, -20.0],
		[ 75, -12,  0, "skyscraper", 22.0, 45.0],
		[ 90,  14,  0, "skyscraper", 18.0, 10.0],
		[105,  -6,  1, "wreck", 6.0, 15.0],

		# === ACT 2: Banking descent (dist 140-220) ===
		[150,  10,  0, "wreck", 10.0, 60.0],
		[180, -10,  0, "wreck", 12.0, -30.0],
		[210,   8, -2, "wreck", 8.0, 20.0],

		# === ACT 3: Slot-run straight (dist 260-360) — slot gates added
		#   by _create_slot_gates() below. A handful of flanking wrecks. ===
		[250,  16,  0, "skyscraper", 14.0, -15.0],
		[280, -16,  0, "skyscraper", 12.0, 30.0],
		[310,  16,  2, "wreck", 9.0, 45.0],
		[340, -16, -1, "wreck", 10.0, -60.0],

		# === ACT 4: Climbing left turn (dist 380-460) ===
		[400,  10,  2, "wreck", 12.0, 20.0],
		[430, -12, -2, "wreck", 14.0, -40.0],
		[455,   8,  3, "wreck", 10.0, 80.0],

		# === ACT 5: Escort-section lane (dist 480-620) — sparse flanking
		#   obstacles so the chase feels open but not empty ===
		[500,  14,  0, "wreck", 12.0, 35.0],
		[540, -14,  0, "wreck", 14.0, -25.0],
		[580,  12,  2, "wreck", 10.0, 55.0],

		# === Final approach (dist 640-740) ===
		[660,   0,  0, "megawreck", 45.0, 0.0],
		[710,  10,  3, "wreck", 10.0, 45.0],
		[730, -10, -2, "wreck", 12.0, -30.0],
	]

	for obs in obstacles:
		var d: float = obs[0]
		var lx: float = obs[1]
		var ly: float = obs[2]
		var kind: String = obs[3]
		var world_pos: Vector3 = _rail_pos(d, lx, ly)
		match kind:
			"skyscraper":
				_spawn_model_obstacle(world_pos, SkyscraperModel, obs[4], obs[5])
			"wreck":
				_spawn_model_obstacle(world_pos, WreckModel, obs[4], obs[5])
			"megawreck":
				_spawn_megawreck(world_pos, obs[4], obs[5])

	_create_slot_gates()


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
	var half := Vector3(scl * 0.35, scl * 0.8, scl * 0.35) * 0.5
	shape.size = half * 2.0
	col.shape = shape
	body.add_child(col)

	hazards_container.add_child(body)
	GameManager.obstacle_aabbs.append({"pos": pos, "half": half})


func _spawn_megawreck(pos: Vector3, scl: float, rot_y: float):
	# Massive destroyed starship — only the outer hull has collision, leaving
	# the central cavity clear for the player to fly through.
	var container := Node3D.new()
	container.position = pos

	var model := WreckModel.instantiate()
	model.scale = Vector3(scl, scl, scl)
	model.rotation_degrees.y = rot_y
	container.add_child(model)

	# The wreck is ~1.9 wide at scale 1, so at 45x it's ~85 units wide.
	# Leave a gap in the center (~16 units) for the player to fly through.
	var half_width: float = scl * 0.45
	var gap: float = 8.0
	var wall_width: float = half_width - gap
	var wall_height: float = scl * 0.5
	var wall_depth: float = scl * 0.5

	# Left hull wall
	var l_pos := pos + Vector3(-(gap + wall_width / 2.0), 0, 0)
	var body_l := StaticBody3D.new()
	body_l.position = l_pos
	var shape_l := CollisionShape3D.new()
	var box_l := BoxShape3D.new()
	box_l.size = Vector3(wall_width, wall_height, wall_depth)
	shape_l.shape = box_l
	body_l.add_child(shape_l)
	container.add_child(body_l)
	GameManager.obstacle_aabbs.append({"pos": l_pos, "half": Vector3(wall_width, wall_height, wall_depth) * 0.5})

	# Right hull wall
	var r_pos := pos + Vector3(gap + wall_width / 2.0, 0, 0)
	var body_r := StaticBody3D.new()
	body_r.position = r_pos
	var shape_r := CollisionShape3D.new()
	var box_r := BoxShape3D.new()
	box_r.size = Vector3(wall_width, wall_height, wall_depth)
	shape_r.shape = box_r
	body_r.add_child(shape_r)
	container.add_child(body_r)
	GameManager.obstacle_aabbs.append({"pos": r_pos, "half": Vector3(wall_width, wall_height, wall_depth) * 0.5})

	# Collectible inside the cavity — double shot powerup
	var pickup := Area3D.new()
	pickup.set_script(PickupScript)
	pickup.pickup_type = PickupScript.PickupType.DOUBLE_SHOT
	pickup.position = Vector3(0, 0, 0)
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
	GameManager.obstacle_aabbs.append({"pos": pos, "half": size * 0.5})


# ── Phase Walls (must phase through) ─────────────────────────

func _create_phase_walls():
	# Phase walls removed in the level 1 redesign — the slot-gate mechanic
	# replaces them as the "hold L1/R1 to fit through" moment. Phase is still
	# available as a general-purpose survival tool; it just isn't required
	# for any scripted obstacle in this level.
	pass


# ── Slot Gates ───────────────────────────────────────────────
# Two hull plates with a narrow vertical gap between them. The player must
# roll their ship (hold L1 or R1) so its profile is tall-and-narrow to slip
# through. A head-on flat ship hits both plates.

func _create_slot_gates():
	# Gates are only placed on rail sections where the tilt is guaranteed
	# zero at both neighboring control points — otherwise the Catmull-Rom
	# tangent smoothing bleeds a slight roll into the straightaway and
	# makes threading the gap much harder. Currently that's only the intro
	# straight (P0→P1) and the final approach (P8→P10).
	var gates := [
		60,   # intro straight — introduces the mechanic
		700,  # final approach — skill check
	]
	for d in gates:
		_spawn_slot_gate(float(d))


func _spawn_slot_gate(dist: float):
	var t: Transform3D = _rail_transform(dist)

	# Walls must fully cover the player's move_bounds (±12 x, ±5 y) so the
	# only way past is through the narrow vertical slit in the middle. Gap
	# is ~0.8 wide horizontally but spans the full playable height.
	var gap_half: float = 0.4
	var wall_width: float = 14.0   # each plate reaches past the x=±12 bounds
	var wall_height: float = 12.0  # taller than the y=±5 bounds
	var wall_thick: float = 1.0

	# Register the slot gate for LOCAL-space collision. Player checks its
	# own path-local position against these parameters in _check_obstacle_collision.
	GameManager.slot_gates.append({
		"dist": dist,
		"gap_half": gap_half,
		"wall_half_width": wall_width * 0.5,
		"wall_half_height": wall_height * 0.5,
		"wall_half_thick": wall_thick * 0.5,
	})

	# Visual walls — oriented to the rail basis so they bracket the path
	var left_local := Vector3(-(gap_half + wall_width / 2.0), 0, 0)
	var left_pos: Vector3 = t * left_local
	_spawn_slot_visual(Transform3D(t.basis, left_pos), Vector3(wall_width, wall_height, wall_thick))

	var right_local := Vector3(gap_half + wall_width / 2.0, 0, 0)
	var right_pos: Vector3 = t * right_local
	_spawn_slot_visual(Transform3D(t.basis, right_pos), Vector3(wall_width, wall_height, wall_thick))


func _spawn_slot_visual(xform: Transform3D, size: Vector3):
	var mi := MeshInstance3D.new()
	var mesh := BoxMesh.new()
	mesh.size = size
	mi.mesh = mesh
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.material_override = _slot_wall_material()
	hazards_container.add_child(mi)
	mi.global_transform = xform


func _slot_wall_material() -> StandardMaterial3D:
	var mat := StandardMaterial3D.new()
	mat.albedo_color = Color(0.25, 0.3, 0.45)
	mat.metallic = 0.7
	mat.roughness = 0.4
	mat.emission_enabled = true
	mat.emission = Color(0.4, 0.2, 0.1)
	mat.emission_energy_multiplier = 0.6
	return mat


# ── Hazards (asteroids + debris) ──────────────────────────────

func _create_hazards():
	# (distance_along_rail, local_x, local_y, size)
	var data := [
		# Act 1 intro
		[ 25,  4,  0, 2.0],
		[ 40, -5,  1, 1.5],
		# Act 2 banked descent
		[170,  6, -1, 2.0],
		[200, -4,  2, 1.8],
		# Final approach asteroid field
		[640,  5,  1, 3.0],
		[680, -6, -1, 2.5],
		[700,  3,  3, 2.0],
		[720, -5,  0, 3.5],
		[740,  7, -2, 2.0],
	]
	for d in data:
		var world_pos: Vector3 = _rail_pos(d[0], d[1], d[2])
		var asteroid = Area3D.new()
		asteroid.set_script(AsteroidScript)
		asteroid.position = world_pos
		asteroid.set_meta("size", d[3])
		hazards_container.add_child(asteroid)


# ── Enemies ───────────────────────────────────────────────────

func _create_enemies():
	# Turrets placed via rail distance. (dist, lx, ly)
	var turret_points := [
		[ 70, -10,  16],  # Act 1 city
		[180,  12,   6],  # Act 2 descent
		[430, -12,   4],  # Act 4 climbing turn
	]
	for tp in turret_points:
		var turret = Area3D.new()
		turret.set_script(TurretScript)
		turret.position = _rail_pos(tp[0], tp[1], tp[2])
		enemies_container.add_child(turret)

	# Fighter waves (dist, count, spread_scale)
	var waves := [
		[ 60, 2, 4.0],  # Act 1 intro ambush
		[170, 2, 4.0],  # descent wave
		[420, 3, 4.0],  # post-climbing turn
	]
	for wave in waves:
		var dist: float = float(wave[0])
		var count: int = wave[1]
		var spread: float = wave[2]
		for i in count:
			var lx: float = (i - count / 2.0) * spread
			var ly: float = sin(i * 1.5) * 2.0
			var lz: float = -float(i) * 3.0  # stagger behind the spawn point
			var world_pos: Vector3 = _rail_pos(dist, lx, ly, lz)
			var fighter = Area3D.new()
			fighter.set_script(EnemyFighterScript)
			fighter.position = world_pos
			enemies_container.add_child(fighter)

	# Escort section (Act 5) — ally + chasers spawned as a unit
	_create_escort_section()


# ── Pickups (guaranteed shield recharges at key points) ──────

func _create_pickups():
	# (distance_along_rail, local_x, local_y)
	var shield_points := [
		[240,  0,  1],  # reward for surviving the descent, before the slot run
		[470, -2,  0],  # reward for clearing the climbing turn
	]
	for sp in shield_points:
		var pickup := Area3D.new()
		pickup.set_script(PickupScript)
		pickup.pickup_type = PickupScript.PickupType.SHIELD
		pickup.position = _rail_pos(sp[0], sp[1], sp[2])
		pickup.lifetime = 999.0
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
		# Act 1: Intro city
		{"at": 0.02, "who": "Nyx",   "say": "City ahead. Stay tight through the skyline.",                 "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.09, "who": "Kiro",  "say": "Fighters! Let's see who drops more.",                          "clr": Color(0.6, 0.6, 0.7)},
		# Act 2: Banked descent
		{"at": 0.18, "who": "Bront", "say": "Bank right and dive — I've got your six.",                     "clr": Color(0.6, 0.4, 0.2)},
		# Act 3: Slot gates
		{"at": 0.32, "who": "Nyx",   "say": "Slot gates! Roll your ship sideways to thread them.",          "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.42, "who": "Kiro",  "say": "Nice flying. Try not to get too comfortable.",                 "clr": Color(0.6, 0.6, 0.7)},
		# Act 4: Climbing turn
		{"at": 0.52, "who": "Bront", "say": "Climbing out. Watch the wrecks on the turn.",                  "clr": Color(0.6, 0.4, 0.2)},
		# (Escort section comms are event-driven from _update_escort,
		#  triggered when Kiro enters view and when chasers are cleared.)
		# Final approach
		{"at": 0.85, "who": "Bront", "say": "Final stretch. Asteroid field — stay sharp.",                  "clr": Color(0.6, 0.4, 0.2)},
		{"at": 0.95, "who": "Nyx",   "say": "Almost through. We've got this, pack.",                        "clr": Color(0.9, 0.5, 0.2)},
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


# ── Escort Section ───────────────────────────────────────────

func _create_escort_section():
	# Ally is a child of path_follow so it rides the rail alongside the
	# player; its local position is animated each frame from a state
	# machine (entrance arc → hold → exit arc).
	escort_ally = Node3D.new()
	escort_ally.name = "AllyKiro"

	var model := AllyShipModel.instantiate()
	model.scale = Vector3(1.2, 1.2, 1.2)
	model.rotation_degrees.y = -90
	escort_ally.add_child(model)

	# Friendly rim glow so he reads as an ally
	var ally_light := OmniLight3D.new()
	ally_light.light_color = Color(0.4, 0.9, 1.0)
	ally_light.light_energy = 2.0
	ally_light.omni_range = 8.0
	escort_ally.add_child(ally_light)

	escort_ally.visible = false
	path_follow.add_child(escort_ally)


func _update_escort(delta):
	if escort_complete or path_follow == null or escort_ally == null:
		return

	match escort_phase:
		EscortPhase.IDLE:
			if path_follow.progress_ratio >= escort_start_ratio:
				_escort_begin_entrance()

		EscortPhase.ENTERING:
			escort_phase_time += delta
			var t := clampf(escort_phase_time / escort_entrance_duration, 0.0, 1.0)
			var t_eased := _ease_in_out(t)
			var arc_y := sin(t * PI) * 2.0  # peaks at midpoint
			escort_ally.position = escort_entry_start.lerp(escort_entry_end, t_eased) + Vector3(0, arc_y, 0)
			# Slow barrel roll while dodging
			escort_ally.rotation.z += delta * deg_to_rad(180.0)

			# "Help!" comms once he's actually on screen
			if not escort_help_shown and t > 0.25 and squad_comms and squad_comms.has_method("show_message"):
				escort_help_shown = true
				squad_comms.show_message("Kiro", "Help! I can't shake them!", Color(0.6, 0.6, 0.7))

			if t >= 1.0:
				_escort_begin_holding()

		EscortPhase.HOLDING:
			# Idle bob
			var bob := sin(Time.get_ticks_msec() / 400.0) * 0.15
			escort_ally.position = Vector3(escort_entry_end.x, escort_entry_end.y + bob, escort_entry_end.z)
			# Straighten out of the roll
			escort_ally.rotation.z = lerp_angle(escort_ally.rotation.z, 0.0, 4.0 * delta)

			# Chaser damage
			var live_in_range := 0
			var any_alive := false
			var i := escort_chasers.size() - 1
			while i >= 0:
				var c = escort_chasers[i]
				if not is_instance_valid(c):
					escort_chasers.remove_at(i)
				else:
					any_alive = true
					if escort_ally.global_position.distance_to(c.global_position) < escort_damage_range:
						live_in_range += 1
				i -= 1

			if live_in_range > 0 and escort_ally_hp > 0:
				escort_ally_hp -= delta * escort_dps_per_chaser * live_in_range
				if escort_ally_hp <= 0:
					_escort_ally_destroyed()
					return

			# Success when all chasers down
			if not any_alive:
				if not escort_thanks_shown and squad_comms and squad_comms.has_method("show_message"):
					escort_thanks_shown = true
					squad_comms.show_message("Kiro", "Thanks! I owe you one.", Color(0.6, 0.6, 0.7))
				_escort_begin_exit()

		EscortPhase.EXITING:
			escort_phase_time += delta
			var t2 := clampf(escort_phase_time / escort_exit_duration, 0.0, 1.0)
			var t2_eased := _ease_out(t2)
			var arc_y2 := sin(t2 * PI) * 1.5
			escort_ally.position = escort_entry_end.lerp(escort_exit_end, t2_eased) + Vector3(0, arc_y2, 0)
			escort_ally.rotation.z += delta * deg_to_rad(120.0)
			if t2 >= 1.0:
				escort_phase = EscortPhase.DONE
				escort_complete = true
				escort_ally.visible = false

		EscortPhase.DONE:
			pass


func _escort_begin_entrance():
	escort_phase = EscortPhase.ENTERING
	escort_phase_time = 0.0
	escort_ally_hp = escort_ally_max_hp
	escort_ally.position = escort_entry_start
	escort_ally.rotation = Vector3.ZERO
	escort_ally.visible = true


func _escort_begin_holding():
	escort_phase = EscortPhase.HOLDING
	escort_phase_time = 0.0
	escort_ally.rotation.z = 0.0

	# Spawn 5 chasers as children of path_follow alongside the ally so
	# they can track Kiro's local position (x/y/z) exactly as the rail
	# advances. Each gets a distinct offset behind/around the ally.
	for n in 5:
		var fighter = Area3D.new()
		fighter.set_script(EnemyFighterScript)
		fighter.tracking_mode = true
		fighter.custom_target = escort_ally
		fighter.tracking_offset = Vector3(
			(n - 2) * 3.5,
			1.5 + sin(n * 1.1) * 1.5,
			4.0 + n * 2.0,  # positive Z = behind the ally in path-local
		)
		# Seed local position near the offset so they don't lerp from 0
		fighter.position = escort_ally.position + fighter.tracking_offset
		path_follow.add_child(fighter)
		escort_chasers.append(fighter)


func _escort_begin_exit():
	escort_phase = EscortPhase.EXITING
	escort_phase_time = 0.0


func _escort_ally_destroyed():
	escort_phase = EscortPhase.DONE
	escort_complete = true
	if escort_ally:
		escort_ally.visible = false
	GameManager.set("ally_kiro_lost", true)
	if squad_comms and squad_comms.has_method("show_message"):
		squad_comms.show_message("Raze", "KIRO! ...dammit.", Color(0.3, 0.5, 0.9))


func _ease_in_out(t: float) -> float:
	return t * t * (3.0 - 2.0 * t)


func _ease_out(t: float) -> float:
	return 1.0 - (1.0 - t) * (1.0 - t)


# ── Tutorial System ──────────────────────────────────────────

func _setup_tutorials():
	tutorials = [
		{
			"id": "fire",
			"trigger_ratio": 0.0,  # immediately on level start
			"message": "HOLD RT / SPACE\nTO FIRE YOUR WEAPONS",
		},
		{
			"id": "tilt",
			"trigger": "enemies_cleared",  # fires after tutorial enemies destroyed
			"message": "HOLD L1 OR R1\nTO FLY SIDEWAYS",
		},
		{
			"id": "missile",
			"trigger": "escort_holding",  # fires once Kiro is under attack
			"message": "HOLD X TO LOCK ON\nPRESS Y TO CYCLE TARGETS\nRELEASE X TO FIRE",
		},
	]
	_spawn_tutorial_enemies()
	_build_tutorial_ui()


func _spawn_tutorial_enemies():
	# Two fighters ahead of the player at level start — first shots the
	# player takes should go into these. Tracked so the "tilt" tutorial
	# fires when they're cleared.
	var spawn_points := [
		[35, -4, 1],
		[35,  4, 1],
	]
	for sp in spawn_points:
		var fighter = Area3D.new()
		fighter.set_script(EnemyFighterScript)
		fighter.position = _rail_pos(sp[0], sp[1], sp[2])
		enemies_container.add_child(fighter)
		tutorial_enemies.append(fighter)


func _build_tutorial_ui():
	# Reuse the HUD canvas layer so it renders above the 3D world
	var canvas: CanvasLayer = hud.get_parent() as CanvasLayer
	if canvas == null:
		return

	tutorial_panel = PanelContainer.new()
	tutorial_panel.name = "TutorialPanel"
	tutorial_panel.set_anchors_preset(Control.PRESET_CENTER_TOP)
	tutorial_panel.offset_left = -380
	tutorial_panel.offset_right = 380
	tutorial_panel.offset_top = 360
	tutorial_panel.offset_bottom = 500
	tutorial_panel.mouse_filter = Control.MOUSE_FILTER_IGNORE

	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.02, 0.05, 0.15, 0.88)
	style.border_color = Color(0.4, 0.75, 1.0, 0.95)
	style.set_border_width_all(3)
	style.set_corner_radius_all(8)
	style.set_content_margin_all(24)
	tutorial_panel.add_theme_stylebox_override("panel", style)

	tutorial_label = Label.new()
	tutorial_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	tutorial_label.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var label_settings := LabelSettings.new()
	label_settings.font_size = 42
	label_settings.font_color = Color(0.95, 0.98, 1.0)
	label_settings.outline_size = 4
	label_settings.outline_color = Color(0.1, 0.2, 0.5)
	label_settings.shadow_size = 6
	label_settings.shadow_color = Color(0.0, 0.3, 0.7, 0.6)
	label_settings.shadow_offset = Vector2(0, 3)
	tutorial_label.label_settings = label_settings
	tutorial_panel.add_child(tutorial_label)

	tutorial_panel.visible = false
	tutorial_panel.modulate = Color(1, 1, 1, 0)
	canvas.add_child(tutorial_panel)


func _update_tutorials():
	if tutorial_panel == null:
		return

	# Track whether the starter enemies are all down — used as a trigger
	# for the tilt tutorial.
	if not tutorial_enemies_cleared and tutorial_enemies.size() > 0:
		var any_alive := false
		for e in tutorial_enemies:
			if is_instance_valid(e):
				any_alive = true
				break
		if not any_alive:
			tutorial_enemies_cleared = true

	if active_tutorial.is_empty():
		if tutorial_index < tutorials.size():
			var next_tut: Dictionary = tutorials[tutorial_index]
			var can_trigger := false
			if next_tut.has("trigger_ratio"):
				can_trigger = path_follow.progress_ratio >= float(next_tut.trigger_ratio)
			elif next_tut.get("trigger", "") == "enemies_cleared":
				can_trigger = tutorial_enemies_cleared
			elif next_tut.get("trigger", "") == "escort_holding":
				can_trigger = escort_phase == EscortPhase.HOLDING
			if can_trigger:
				_start_tutorial(next_tut)
	else:
		if _is_tutorial_done(active_tutorial.id):
			_complete_tutorial()


func _start_tutorial(tut: Dictionary):
	active_tutorial = tut
	tutorial_speed_mult = tutorial_slow_factor
	tutorial_label.text = tut.message
	tutorial_panel.visible = true
	if tutorial_tween and tutorial_tween.is_valid():
		tutorial_tween.kill()
	tutorial_tween = create_tween()
	tutorial_tween.tween_property(tutorial_panel, "modulate:a", 1.0, 0.3)


func _complete_tutorial():
	tutorial_speed_mult = 1.0
	active_tutorial = {}
	tutorial_index += 1
	if tutorial_tween and tutorial_tween.is_valid():
		tutorial_tween.kill()
	tutorial_tween = create_tween()
	tutorial_tween.tween_property(tutorial_panel, "modulate:a", 0.0, 0.3)
	tutorial_tween.tween_callback(func():
		if tutorial_panel:
			tutorial_panel.visible = false
	)


func _is_tutorial_done(id: String) -> bool:
	match id:
		"fire":
			return player != null and player.total_shots_fired > 0
		"tilt":
			# Player must push the ship into a clear sideways roll
			return player != null and absf(player.tilt_current) > deg_to_rad(60.0)
		"missile":
			# Clear as soon as the player starts holding X so the lock-on
			# animation actually plays — otherwise the tutorial slowdown
			# would make the player think the mechanic is stuck.
			return player != null and Input.is_action_pressed("tracking_missile")
		_:
			return true
