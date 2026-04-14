extends Node
## Global game state and input configuration singleton.

var game_world: Node3D = null
var player: Area3D = null
var projectiles_container: Node3D = null
var obstacle_aabbs: Array = []  # [{pos: Vector3, half: Vector3}] for manual collision
# Slot gates require checking the player's rail-local offset, not world AABB,
# because the rail curves and the walls rotate with it. Entries:
#   {dist: float, gap_half: float, wall_half_width: float, wall_half_height: float}
var slot_gates: Array = []

# ── Persistent state across scenes (solar map progress) ──
var current_level_id: String = ""
var beaten_levels: Dictionary = {}   # level_id → {hits: int, score: int}
var total_score: int = 0
var lives: int = 3

# ── Squad state (persists into boss fight) ──
# Set to true if the player fails to save a teammate during an escort section;
# the lost teammate sits out the next boss encounter.
var ally_kiro_lost: bool = false
var ally_nyx_lost: bool = false
var ally_bront_lost: bool = false


func _ready():
	_setup_input_actions()
	_setup_ui_actions()


func mark_level_beaten(level_id: String, hits: int, score: int):
	beaten_levels[level_id] = {"hits": hits, "score": score}
	total_score += score


func is_level_beaten(level_id: String) -> bool:
	return beaten_levels.has(level_id)


func reset_campaign():
	beaten_levels.clear()
	total_score = 0
	lives = 3
	current_level_id = ""
	ally_kiro_lost = false
	ally_nyx_lost = false
	ally_bront_lost = false


func _setup_ui_actions():
	# Map navigation — reuse move actions but also add explicit ui actions
	_add_key_action("ui_select", KEY_ENTER)
	_add_joy_button("ui_select", JOY_BUTTON_A)
	_add_key_action("ui_back", KEY_ESCAPE)
	_add_joy_button("ui_back", JOY_BUTTON_B)


func _setup_input_actions():
	# ── Movement (left stick / WASD) ──
	_add_key_action("move_up", KEY_W)
	_add_key_action("move_down", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)

	# ── Right stick / arrow keys (used for solar map navigation) ──
	_add_key_action("aim_up", KEY_UP)
	_add_key_action("aim_down", KEY_DOWN)
	_add_key_action("aim_left", KEY_LEFT)
	_add_key_action("aim_right", KEY_RIGHT)
	_add_joy_axis("aim_up", JOY_AXIS_RIGHT_Y, -1.0)
	_add_joy_axis("aim_down", JOY_AXIS_RIGHT_Y, 1.0)
	_add_joy_axis("aim_left", JOY_AXIS_RIGHT_X, -1.0)
	_add_joy_axis("aim_right", JOY_AXIS_RIGHT_X, 1.0)

	# ── Shoot normal (R2 / Space) ──
	_add_key_action("shoot", KEY_SPACE)
	_add_joy_axis("shoot", JOY_AXIS_TRIGGER_RIGHT, 0.5)

	# ── Tracking missile (X / Q) ──
	_add_key_action("tracking_missile", KEY_Q)
	_add_joy_button("tracking_missile", JOY_BUTTON_X)

	# ── Boost (A / Shift) ──
	_add_key_action("boost", KEY_SHIFT)
	_add_joy_button("boost", JOY_BUTTON_A)

	# ── Brake (L2 / Ctrl) ──
	_add_key_action("brake", KEY_CTRL)
	_add_joy_axis("brake", JOY_AXIS_TRIGGER_LEFT, 0.5)

	# ── Tilt right – R1 / E ──
	_add_key_action("tilt_right", KEY_E)
	_add_joy_button("tilt_right", JOY_BUTTON_RIGHT_SHOULDER)

	# ── Tilt left – L1 / C ──
	_add_key_action("tilt_left", KEY_C)
	_add_joy_button("tilt_left", JOY_BUTTON_LEFT_SHOULDER)

	# ── Phase (B / F) ──
	_add_key_action("phase", KEY_F)
	_add_joy_button("phase", JOY_BUTTON_B)

	# ── Snap to next target (Y / Tab) ──
	_add_key_action("snap_target", KEY_TAB)
	_add_joy_button("snap_target", JOY_BUTTON_Y)


func _add_key_action(action: String, keycode: int):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev = InputEventKey.new()
	ev.physical_keycode = keycode
	InputMap.action_add_event(action, ev)


func _add_joy_button(action: String, button: int):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev = InputEventJoypadButton.new()
	ev.button_index = button
	InputMap.action_add_event(action, ev)


func _add_joy_axis(action: String, axis: int, value: float):
	if not InputMap.has_action(action):
		InputMap.add_action(action)
	var ev = InputEventJoypadMotion.new()
	ev.axis = axis
	ev.axis_value = value
	InputMap.action_add_event(action, ev)
