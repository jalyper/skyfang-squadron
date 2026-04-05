extends Camera3D
## Chase camera that follows the PathFollow3D with smooth interpolation.
## Offsets slightly toward the player ship for responsive feel.

var offset := Vector3(0.0, 3.5, 8.0)   # behind & above
var follow_speed: float = 5.0
var look_ahead: float = 6.0
var _initialized: bool = false


func _process(delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	var pf: PathFollow3D = gw.path_follow
	var forward := -pf.global_transform.basis.z
	var up := pf.global_transform.basis.y
	var right := pf.global_transform.basis.x

	# Target position: behind the rail point
	var target_pos := pf.global_position + up * offset.y - forward * offset.z

	# Shift toward player for responsive framing
	var player = GameManager.player
	if player:
		target_pos += right * player.position.x * 0.3
		target_pos += up * player.position.y * 0.2

	# Snap on first frame, smooth after
	if not _initialized:
		global_position = target_pos
		_initialized = true
	else:
		global_position = global_position.lerp(target_pos, follow_speed * delta)

	# Look at a point ahead of the rail
	var look_target := pf.global_position + forward * look_ahead
	if player:
		look_target += right * player.position.x * 0.5
		look_target += up * player.position.y * 0.3
	look_at(look_target, up)
