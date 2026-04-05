extends Camera3D
## Rigid rail camera — locked behind the path center, no lateral sway.
## The ship moves within the frame but the camera stays fixed on the rail.
## Feels like a steady chase cam on invisible tracks.

var pole_length: float = 10.0   # distance behind path center
var pole_height: float = 3.5    # height above path
var look_ahead: float = 10.0    # how far ahead to look
var _initialized: bool = false


func _process(_delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	var pf: PathFollow3D = gw.path_follow

	# Path orientation — camera follows the RAIL, not the ship
	var forward := -pf.global_transform.basis.z
	var up := pf.global_transform.basis.y

	# Position: directly behind the path center point
	var target_pos := pf.global_position - forward * pole_length + up * pole_height

	# Rigid — no lerp, no sway, no smoothing
	if not _initialized:
		global_position = target_pos
		_initialized = true
	else:
		global_position = target_pos

	# Look straight ahead along the path
	var look_target := pf.global_position + forward * look_ahead
	look_at(look_target, up)
