extends Camera3D
## Rock-solid rail camera. The rail path is perfectly straight (-Z), so
## the camera never rotates or sways. It sits at a fixed offset behind and
## above the path center, always looking straight down -Z.
##
## The player can move freely inside a center dead zone without the camera
## shifting. Once the player pushes past the dead zone edges, the camera
## smoothly pans laterally to keep them in frame.

var pole_length: float = 7.0    # distance behind path center
var pole_height: float = 2.8    # height above path

# Dead zone — fraction of player move_bounds where camera doesn't pan
var dead_zone_ratio: float = 0.5

# How fast the camera catches up when the player exits the dead zone
var follow_speed: float = 4.0

var _cam_offset: Vector2 = Vector2.ZERO
var _initialized: bool = false


func _process(delta):
	var gw = GameManager.game_world
	if gw == null or gw.path_follow == null:
		return

	var pf: PathFollow3D = gw.path_follow
	var player = GameManager.player

	# Path is straight down -Z, so forward is always (0,0,-1)
	var path_pos := pf.global_position

	# ── Compute desired lateral offset based on player position ──
	var target_offset := Vector2.ZERO
	if player != null and not player.is_dead:
		var px: float = player.position.x  # local offset from rail center
		var py: float = player.position.y
		var bounds_x: float = player.move_bounds.x
		var bounds_y: float = player.move_bounds.y

		var dz_x: float = bounds_x * dead_zone_ratio
		var dz_y: float = bounds_y * dead_zone_ratio

		if abs(px) > dz_x:
			var excess: float = abs(px) - dz_x
			var max_excess: float = bounds_x - dz_x
			if max_excess > 0:
				target_offset.x = sign(px) * (excess / max_excess) * (bounds_x * 0.5)

		if abs(py) > dz_y:
			var excess: float = abs(py) - dz_y
			var max_excess: float = bounds_y - dz_y
			if max_excess > 0:
				target_offset.y = sign(py) * (excess / max_excess) * (bounds_y * 0.35)

	_cam_offset = _cam_offset.lerp(target_offset, follow_speed * delta)

	# Position: behind path center, offset laterally
	var cam_pos := Vector3(
		path_pos.x + _cam_offset.x,
		path_pos.y + pole_height + _cam_offset.y,
		path_pos.z + pole_length
	)

	if not _initialized:
		global_position = cam_pos
		_cam_offset = target_offset
		_initialized = true
	else:
		global_position = cam_pos

	# Look straight ahead — fixed direction, never rotates
	var look_target := Vector3(cam_pos.x, cam_pos.y, cam_pos.z - 20.0)
	look_at(look_target, Vector3.UP)
