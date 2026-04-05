extends Node
## Global game state and input configuration singleton.

var game_world: Node3D = null
var player: Area3D = null
var projectiles_container: Node3D = null
var is_paused: bool = false


func _ready():
	_setup_input_actions()


func _setup_input_actions():
	# Movement (WASD + left stick)
	_add_key_action("move_up", KEY_W)
	_add_key_action("move_down", KEY_S)
	_add_key_action("move_left", KEY_A)
	_add_key_action("move_right", KEY_D)
	_add_joy_axis("move_up", JOY_AXIS_LEFT_Y, -1.0)
	_add_joy_axis("move_down", JOY_AXIS_LEFT_Y, 1.0)
	_add_joy_axis("move_left", JOY_AXIS_LEFT_X, -1.0)
	_add_joy_axis("move_right", JOY_AXIS_LEFT_X, 1.0)

	# Shoot (Space / A button)
	_add_key_action("shoot", KEY_SPACE)
	_add_joy_button("shoot", JOY_BUTTON_A)

	# Tracking missile (Q / X button)
	_add_key_action("tracking_missile", KEY_Q)
	_add_joy_button("tracking_missile", JOY_BUTTON_X)

	# Boost (Shift / RB)
	_add_key_action("boost", KEY_SHIFT)
	_add_joy_button("boost", JOY_BUTTON_RIGHT_SHOULDER)

	# Brake (Ctrl / LB)
	_add_key_action("brake", KEY_CTRL)
	_add_joy_button("brake", JOY_BUTTON_LEFT_SHOULDER)

	# Deflect spin (E / B button)
	_add_key_action("deflect_spin", KEY_E)
	_add_joy_button("deflect_spin", JOY_BUTTON_B)


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
