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

# Rail
var rail_speed: float = 20.0
var current_speed: float = 20.0
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

# Comms
var comms_triggers: Array = []
var comms_fired: Dictionary = {}


func _ready():
	GameManager.game_world = self
	current_speed = rail_speed

	_create_environment()
	_create_rail_path()
	_create_containers()
	_create_player()
	_create_camera()
	_create_hazards()
	_create_enemies()
	_create_ui()
	_setup_comms_triggers()


func _process(delta):
	if level_complete:
		return
	path_follow.progress += current_speed * delta
	if path_follow.progress_ratio >= 1.0:
		level_complete = true
		_on_level_complete()
	_check_comms_triggers()


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


# ── Rail Path ─────────────────────────────────────────────────

func _create_rail_path():
	path = Path3D.new()
	var curve = Curve3D.new()

	# Gentle S-curves going forward (-Z), ~300 units total
	var pts = [
		[Vector3(0, 0, 0),       Vector3(),            Vector3(0, 0, -20)],
		[Vector3(5, 2, -50),     Vector3(0, 0, -20),   Vector3(0, 0, -20)],
		[Vector3(-5, 0, -100),   Vector3(0, 0, -20),   Vector3(0, 0, -20)],
		[Vector3(8, -1, -150),   Vector3(0, 0, -20),   Vector3(0, 0, -20)],
		[Vector3(-3, 3, -200),   Vector3(0, 0, -20),   Vector3(0, 0, -20)],
		[Vector3(2, 1, -250),    Vector3(0, 0, -20),   Vector3(0, 0, -20)],
		[Vector3(0, 0, -300),    Vector3(0, 0, -20),   Vector3()],
	]
	for p in pts:
		curve.add_point(p[0], p[1], p[2])

	path.curve = curve
	add_child(path)

	path_follow = PathFollow3D.new()
	path_follow.rotation_mode = PathFollow3D.ROTATION_ORIENTED
	path_follow.loop = false
	path.add_child(path_follow)


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


# ── Camera ────────────────────────────────────────────────────

func _create_camera():
	rail_camera = Camera3D.new()
	rail_camera.name = "RailCamera"
	rail_camera.set_script(RailCameraScript)
	rail_camera.current = true
	rail_camera.fov = 70.0
	add_child(rail_camera)


# ── Hazards ───────────────────────────────────────────────────

func _create_hazards():
	var data = [
		# [position, size]
		[Vector3(3, 0, -40), 2.0],
		[Vector3(-4, 1, -45), 1.5],
		[Vector3(0, -1, -50), 2.5],
		[Vector3(-6, 0, -80), 4.0],
		[Vector3(7, 2, -110), 1.5],
		[Vector3(-7, -1, -120), 1.8],
		[Vector3(2, 3, -180), 2.0],
		[Vector3(-2, -2, -185), 2.2],
		[Vector3(4, 0, -260), 1.5],
		[Vector3(-3, 1, -265), 2.0],
	]
	for d in data:
		var asteroid = Area3D.new()
		asteroid.set_script(AsteroidScript)
		asteroid.position = d[0]
		asteroid.set_meta("size", d[1])
		hazards_container.add_child(asteroid)


# ── Enemies ───────────────────────────────────────────────────

func _create_enemies():
	# Turrets
	for pos in [
		Vector3(8, -2, -60),
		Vector3(-8, -2, -65),
		Vector3(6, 3, -140),
		Vector3(-7, 2, -210),
		Vector3(9, -1, -215),
	]:
		var turret = Area3D.new()
		turret.set_script(TurretScript)
		turret.position = pos
		enemies_container.add_child(turret)

	# Fighter waves
	var waves = [
		[Vector3(0, 0, -95), 3],
		[Vector3(0, 0, -165), 3],
		[Vector3(0, 2, -245), 4],
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
		{"at": 0.02, "who": "Nyx",   "say": "All clear ahead... for now.",              "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.15, "who": "Kiro",  "say": "Asteroids! Try to keep up, Raze.",         "clr": Color(0.6, 0.6, 0.7)},
		{"at": 0.30, "who": "Bront", "say": "Fighters incoming. I've got your six.",    "clr": Color(0.6, 0.4, 0.2)},
		{"at": 0.50, "who": "Nyx",   "say": "Heads up -- more debris. Stay sharp.",     "clr": Color(0.9, 0.5, 0.2)},
		{"at": 0.70, "who": "Kiro",  "say": "I'd thread that gap faster. Just saying.", "clr": Color(0.6, 0.6, 0.7)},
		{"at": 0.90, "who": "Bront", "say": "Almost through. We've got this, pack.",    "clr": Color(0.6, 0.4, 0.2)},
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
